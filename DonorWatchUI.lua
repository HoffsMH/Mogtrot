local _, ns = ...

-- Passive donors.
--
-- From login, library open or not, target, mouseover, nameplates and group
-- members of the other sex become donors in passing whenever
-- DonorWatch.Accepts finds their sex, faction and race new. Each one taken is
-- queued at once, so a sweep of the pointer over a crowd takes all of them.
-- The queue is built a few body steps per frame, in the order taken among
-- the donors some token still names, each step after checking that token
-- names the donor's GUID. A donor's bodies stay hidden from cards until all
-- are built; one out of reach for DonorWatch.LOST_GRACE is dropped. Bodies
-- last only the session.
local DonorWatchUI = {}

-- Seconds before units refused for a passing reason are asked about again.
local RETRY_AFTER = 3
-- Milliseconds of body building per frame; a step that starts inside it runs
-- to the end, so a frame can go over by one step.
local BUILD_BUDGET_MS = 16

local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local state = {
	queue = {}, guids = {}, classes = {}, passive = 0,
	cost = { ingests = 0, lastIngestMs = 0, maxIngestMs = 0, abandoned = 0, lastFrames = 0,
		lastStepFrameMs = 0, maxStepFrameMs = 0 },
}

local function Viewer()
	local ok, sex = pcall(UnitSex, "player")
	return ok and Plain(sex) or nil
end

-- Taking donors ---------------------------------------------------------------------

local function Held()
	local guids, classes = {}, {}
	for guid in pairs(state.guids) do guids[guid] = true end
	for class in pairs(state.classes) do classes[class] = true end
	for _, build in ipairs(state.queue) do
		guids[build.guid] = true
		classes[build.class] = true
	end
	local lent = ns.LibraryBodies
	return { guids = guids, classes = classes,
		full = lent ~= nil and lent.PoolFull ~= nil and lent.PoolFull() == true }
end

local function Facts(unit)
	local facts = { combat = (InCombatLockdown and InCombatLockdown()) or false,
		instance = (IsInInstance and IsInInstance()) or false, viewerSex = Viewer() }
	facts.exists = UnitExists(unit) == true
	if not facts.exists then return facts end
	facts.isPlayer = UnitIsPlayer(unit) == true
	if not facts.isPlayer then return facts end
	local okSelf, same = pcall(UnitIsUnit, unit, "player")
	facts.isSelf = okSelf and same == true
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		local known, secret = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
		if known and secret then
			facts.secret = true
			return facts
		end
	end
	local okSex, sex = pcall(UnitSex, unit)
	facts.sex = okSex and Plain(sex) or nil
	local _, raceFile, raceID = UnitRace(unit)
	facts.raceID, facts.raceFile = Plain(raceID), Plain(raceFile)
	facts.faction = Plain(UnitFactionGroup(unit))
	facts.guid = Plain(UnitGUID(unit))
	facts.ready = not IsUnitModelReadyForUI or IsUnitModelReadyForUI(unit) == true
	return facts
end

local retryPending = false
local Consider

local function RetryLater(delay)
	if retryPending then return end
	retryPending = true
	C_Timer.After(delay or RETRY_AFTER, function()
		retryPending = false
		for _, unit in ipairs(ns.DonorWatch.EventUnits("rescan")) do Consider(unit) end
	end)
end

-- Building donors in steps -----------------------------------------------------------

local builder = CreateFrame and CreateFrame("Frame") or nil

-- The token that names the donor now, trying the one it last answered to first.
local function FindDonor(build)
	if build.searchFrom ~= build.token then
		build.searchFrom = build.token
		build.search = ns.DonorWatch.SearchUnits(build.token)
	end
	for _, unit in ipairs(build.search) do
		if UnitExists(unit) and Plain(UnitGUID(unit)) == build.guid then return unit end
	end
	return nil
end

local function Abandon(build)
	ns.LibraryBodies.DropDonor(build.guid)
	state.cost.abandoned = state.cost.abandoned + 1
end

local function Finish(build)
	ns.LibraryBodies.SettleDonor(build.guid)
	state.guids[build.guid] = true
	state.classes[build.class] = true
	state.passive = state.passive + 1
	local cost = state.cost
	cost.ingests = cost.ingests + 1
	cost.lastIngestMs = build.spentMs
	if build.spentMs > cost.maxIngestMs then cost.maxIngestMs = build.spentMs end
	cost.lastFrames = build.frames
	cost.lastStepFrameMs = build.maxFrameMs
	local ui = ns.LibraryUI
	if build.built > 0 and ui and ui.BodiesArrived then ui.BodiesArrived(build.keys, build.donor) end
end

-- One frame of building: the first donor in the queue a token names takes
-- steps until the budget is spent, then the next.
local function BuildFrame()
	local clock = debugprofilestop
	local began = clock()
	local Watch = ns.DonorWatch
	local queue = state.queue
	local index = 1
	local spentOn = {}
	while index <= #queue do
		local build = queue[index]
		local token = FindDonor(build)
		local facts = { now = GetTime(), token = token,
			combat = (InCombatLockdown and InCombatLockdown()) or false,
			instance = (IsInInstance and IsInInstance()) or false,
			ready = token ~= nil
				and (not IsUnitModelReadyForUI or IsUnitModelReadyForUI(token) == true) }
		local action, detail = Watch.BuildStep(build, facts)
		if action == "finish" then
			table.remove(queue, index)
			Finish(build)
		elseif action == "abandon" then
			table.remove(queue, index)
			Abandon(build)
		elseif action ~= "build" then
			index = index + 1
		else
			local stepBegan = clock()
			build.token = detail
			build.done = build.done + 1
			build.steps[build.done](detail)
			spentOn[build] = (spentOn[build] or 0) + (clock() - stepBegan)
			if clock() - began >= BUILD_BUDGET_MS then break end
		end
	end
	local frameMs = clock() - began
	for build, spent in pairs(spentOn) do
		build.frames = build.frames + 1
		build.spentMs = build.spentMs + spent
		if spent > build.maxFrameMs then build.maxFrameMs = spent end
	end
	if frameMs > state.cost.maxStepFrameMs then state.cost.maxStepFrameMs = frameMs end
	if #queue == 0 and builder then builder:SetScript("OnUpdate", nil) end
end

-- Plans every card body the donor lends as one step each and queues it.
local function Enqueue(unit, donor)
	local lent = ns.LibraryBodies
	local build = { donor = donor, guid = donor.guid, token = unit, steps = {}, done = 0,
		built = 0, keys = {}, frames = 0, spentMs = 0, maxFrameMs = 0,
		class = ns.DonorWatch.ClassKey(donor.sex, donor.faction, donor.raceID) }
	for _, step in ipairs(ns.LibraryUI.WarmPlan()) do
		build.steps[#build.steps + 1] = function(token)
			local built, key = lent.WarmBody(step.record, token, step.want, build.guid)
			if built then
				build.built = build.built + 1
				if key ~= nil then build.keys[key] = true end
			end
		end
	end
	build.total = #build.steps
	state.queue[#state.queue + 1] = build
	if builder then builder:SetScript("OnUpdate", BuildFrame) end
end

Consider = function(unit)
	local facts = Facts(unit)
	-- Most units are nobody worth asking about; skip the rest for them.
	if not facts.isPlayer or facts.isSelf or facts.sex == facts.viewerSex then return end
	local ok, _, retry = ns.DonorWatch.Accepts(facts, Held())
	if not ok then
		if retry and not facts.combat and not facts.instance then RetryLater() end
		return
	end
	local donor = ns.LibraryBodies.DonorFacts(unit)
	if not donor or donor.guid == nil then return end
	Enqueue(unit, donor)
end

-- Public -------------------------------------------------------------------------------

function DonorWatchUI.Cost()
	return state.cost
end

-- Events -------------------------------------------------------------------------------

local CAPTURE = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
	"GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }

if CreateFrame then
	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	for _, event in ipairs(CAPTURE) do events:RegisterEvent(event) end
	events:SetScript("OnEvent", function(_, event, arg)
		if event == "PLAYER_ENTERING_WORLD" then
			RetryLater(0)
			return
		end
		local name = event == "PLAYER_REGEN_ENABLED" and "rescan" or event
		for _, unit in ipairs(ns.DonorWatch.EventUnits(name, arg)) do Consider(unit) end
	end)
end

ns.DonorWatchUI = DonorWatchUI
return DonorWatchUI
