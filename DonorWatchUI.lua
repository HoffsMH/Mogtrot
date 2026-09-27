local _, ns = ...

-- Passive donors and background coverage.
--
-- Target, mouseover, nameplates and group members of the other sex become
-- donors in passing when they meet one of DonorWatch.Needs; with no needs the
-- capture events are unregistered. A taken donor's bodies are built a few per
-- frame, each after checking a token still names that donor, and stay hidden
-- from cards, coverage and the offer until all are built. They last only the
-- session.
-- In the background every live look is drawn on the bodies at hand, a few at
-- a time, and read per slot as DonorCoverage reads a pair; DonorWatch.Status
-- turns the verdicts into whether the library offers original race.
local DonorWatchUI = {}

-- Seconds before units refused for a passing reason are asked about again.
local RETRY_AFTER = 3
-- Milliseconds of body building per frame; a step that starts inside it runs
-- to the end, so a frame can go over by one body.
local BUILD_BUDGET_MS = 16
local MAX_IN_FLIGHT = 3
local TICK = 0.25
-- A settled pass is read at READ_EARLY, one with a piece not drawn again at
-- READ_LATE, after the last dress retry.
local READ_EARLY, READ_LATE = 1.6, 6
local HERITAGE_TRIES, HERITAGE_WAIT = 3, 1.5
local SCAN_EVERY = 2

local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local state = {
	looks = {}, cache = {}, tried = {}, pending = {}, busy = {}, inFlight = {},
	selfBodies = {}, guids = {}, passive = 0, needs = {}, blocked = {}, capturing = false,
	dirty = true, lastScan = -math.huge, lastStart = -math.huge,
	cost = { ticks = 0, lastMs = 0, maxMs = 0, reads = 0, starts = 0, ingests = 0,
		lastIngestMs = 0, maxIngestMs = 0, abandoned = 0, lastFrames = 0,
		lastStepFrameMs = 0, maxStepFrameMs = 0, lastGapMs = 0, maxGapMs = 0 },
}
DonorWatchUI.state = state

local function Viewer()
	local ok, sex = pcall(UnitSex, "player")
	return ok and Plain(sex) or nil
end

-- Looks ------------------------------------------------------------------------

-- Re-reads the library only where a record's look text changed, so a snap, a
-- sync or a deletion is picked up without decoding every record again.
local function Scan()
	local library = type(MogtrotDB) == "table" and MogtrotDB.library or nil
	local coverage = ns.DonorCoverageUI
	if not (coverage and type(library) == "table") then return end
	local seen, changed = {}, false
	local function Visit(record, archived)
		if type(record) ~= "table" or record.id == nil then return end
		seen[record.id] = true
		local cached = state.cache[record.id]
		if cached and cached.text == record.look and cached.archived == archived then return end
		state.cache[record.id] = { text = record.look, archived = archived,
			look = coverage.Look(record, archived) }
		state.tried[record.id] = nil
		changed = true
	end
	for _, record in pairs(type(library.records) == "table" and library.records or {}) do
		Visit(record, false)
	end
	for _, record in ipairs(type(library.archive) == "table" and library.archive or {}) do
		Visit(record, true)
	end
	for id in pairs(state.cache) do
		if not seen[id] then
			state.cache[id], state.tried[id] = nil, nil
			changed = true
		end
	end
	if not changed then return end
	local looks = {}
	for _, cached in pairs(state.cache) do
		if cached.look then looks[#looks + 1] = cached.look end
	end
	table.sort(looks, function(a, b) return (a.id or 0) > (b.id or 0) end)
	state.looks = looks
	state.dirty = true
end

-- Bodies -------------------------------------------------------------------------

local function SelfFacts()
	local race, raceFile, raceID = UnitRace("player")
	return { id = "self", self = true, sex = Viewer(), faction = Plain(UnitFactionGroup("player")),
		race = Plain(race), raceFile = Plain(raceFile), raceID = Plain(raceID) }
end

-- Your own body, then every kept donor of the other sex with the keys it holds.
local function Bodies()
	local bodies = { SelfFacts() }
	local viewer = bodies[1].sex
	local coverage = ns.DonorCoverageUI
	for _, entry in ipairs(coverage and coverage.Kept() or {}) do
		local donor = entry.donor
		if donor.id ~= nil and donor.sex ~= viewer then
			local keys = {}
			for key, group in pairs(entry.groups) do
				if group.actors and group.actors[1] then keys[key] = true end
			end
			bodies[#bodies + 1] = { id = donor.id, sex = donor.sex, faction = donor.faction,
				race = donor.race, raceFile = donor.raceFile, raceID = donor.raceID, keys = keys,
				entry = entry }
		end
	end
	return bodies
end

local function SelfActor(look)
	local built = state.selfBodies[look.key]
	if built and built.actor then return built.actor end
	local coverage = ns.DonorCoverageUI
	built = built or { scene = coverage.NewScene() }
	state.selfBodies[look.key] = built
	built.actor = coverage.Build(built.scene, "player", look.form)
	return built.actor
end

local function ActorFor(body, look)
	if body.self then return SelfActor(look) end
	local group = body.entry and body.entry.groups[look.key]
	return group and group.actors and group.actors[1] or nil
end

-- Pauses -------------------------------------------------------------------------

local function Paused()
	if InCombatLockdown and InCombatLockdown() then return "in combat" end
	if IsInInstance and IsInInstance() then return "in an instance" end
	return nil
end

-- Status -------------------------------------------------------------------------

local function Pooled()
	local lent = ns.LibraryBodies
	return lent and lent.PooledKeys and lent.PooledKeys() or {}
end

local lastStatus

local function Status(paused)
	local Watch = ns.DonorWatch
	return Watch.Status({ looks = state.looks, bodies = Bodies(), tried = state.tried,
		pending = state.pending, pooled = Pooled(), viewerSex = Viewer(), paused = paused })
end

local UpdateCapture

local function Building()
	local build = state.build
	return build and { build.donor } or {}
end

local function Publish(paused)
	state.needs, state.blocked = ns.DonorWatch.Needs({ looks = state.looks, bodies = Bodies(),
		tried = state.tried, pending = state.pending, pooled = Pooled(), viewerSex = Viewer(),
		building = Building() })
	if UpdateCapture then UpdateCapture() end
	local status = Status(paused)
	local before = lastStatus
	lastStatus = status
	local ui = ns.LibraryUI
	if ui then
		if not before or before.offered ~= status.offered then
			if ui.Soon then ui.Soon() end
		elseif before.text ~= status.text and ui.PaintStatus then
			ui.PaintStatus()
		end
	end
end

-- Draws ----------------------------------------------------------------------------

local function Classify(job)
	local coverage = ns.DonorCoverageUI
	local heritage, unread = {}, false
	for _, piece in ipairs(job.slots) do
		if not piece.visible and not piece.held and not piece.hidden then
			local lock = coverage.Heritage(piece.source)
			if lock == nil then
				unread = true
				coverage.RequestItem(piece.source)
			else
				heritage[piece.source] = lock
			end
		end
	end
	if unread and job.tries < HERITAGE_TRIES then
		job.tries = job.tries + 1
		C_Timer.After(HERITAGE_WAIT, function() Classify(job) end)
		return
	end
	local verdict = ns.DonorCoverage.Classify(job.slots, heritage, { race = job.body.race })
	state.tried[job.look.id] = state.tried[job.look.id] or {}
	state.tried[job.look.id][job.body.id] = { full = verdict.full, verdict = verdict }
	state.pending[job.look.id] = nil
	state.busy[job.slot] = nil
	state.dirty = true
end

local function Read(now)
	local coverage = ns.DonorCoverageUI
	for index = #state.inFlight, 1, -1 do
		local job = state.inFlight[index]
		local elapsed = now - job.at
		local settled = job.actor.mogtrotSettled == job.token
		if elapsed >= READ_LATE or (settled and elapsed >= READ_EARLY) then
			local slots = coverage.ReadSlots(job.actor, job.look)
			local whole = true
			for _, piece in ipairs(slots) do
				if not piece.hidden and not piece.visible then whole = false end
			end
			if elapsed >= READ_LATE or whole then
				table.remove(state.inFlight, index)
				state.cost.reads = state.cost.reads + 1
				job.slots, job.tries = slots, 0
				Classify(job)
			end
		end
	end
end

local function Start(now)
	if #state.inFlight >= MAX_IN_FLIGHT or now - state.lastStart < TICK then return end
	-- Nothing was left to draw, and nothing has changed since.
	if state.idle then return end
	local bodies = Bodies()
	local busy = {}
	for slot in pairs(state.busy) do busy[slot] = true end
	local pair = ns.DonorWatch.NextPairs({ looks = state.looks, bodies = bodies,
		tried = state.tried, pending = state.pending, busy = busy, viewerSex = Viewer(),
		limit = 1 })[1]
	if not pair then
		state.idle = true
		return
	end
	local look, body
	for _, row in ipairs(state.looks) do if row.id == pair.look then look = row end end
	for _, row in ipairs(bodies) do if row.id == pair.body then body = row end end
	local slot = ("%s|%s"):format(tostring(body.id), tostring(look.key))
	local actor = ActorFor(body, look)
	if not actor then
		-- Your model is not ready yet; try again in a moment.
		state.lastStart = now + 2
		return
	end
	state.busy[slot] = true
	state.pending[look.id] = true
	ns.LookRender.DressWhenLoaded(actor, look.list)
	state.inFlight[#state.inFlight + 1] = { look = look, body = body, actor = actor,
		slot = slot, token = actor.mogtrotPaint, at = now }
	state.lastStart = now
	state.cost.starts = state.cost.starts + 1
end

local function Tick()
	local clock = debugprofilestop
	local began = clock and clock()
	local now = GetTime()
	if now - state.lastScan >= SCAN_EVERY then
		state.lastScan = now
		Scan()
	end
	Read(now)
	local paused = Paused()
	if not paused then Start(now) end
	if state.dirty or paused ~= state.paused then
		state.dirty, state.idle = false, false
		state.paused = paused
		Publish(paused)
	end
	if began then
		local cost, spent = state.cost, clock() - began
		cost.ticks = cost.ticks + 1
		cost.lastMs = spent
		if spent > cost.maxMs then cost.maxMs = spent end
	end
end

-- Passive donors ----------------------------------------------------------------

local function Held()
	local guids, classes = {}, {}
	for guid in pairs(state.guids) do guids[guid] = true end
	local Watch = ns.DonorWatch
	for _, entry in ipairs(ns.DonorCoverageUI and ns.DonorCoverageUI.Kept() or {}) do
		local donor = entry.donor
		if donor.guid then guids[donor.guid] = true end
		classes[Watch.ClassKey(donor.sex, donor.faction, donor.raceID)] = true
	end
	return { guids = guids, classes = classes, needs = state.needs,
		building = state.build ~= nil }
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

-- Building a donor in steps ------------------------------------------------------

local builder = CreateFrame and CreateFrame("Frame") or nil

-- The token that names the donor now, trying the one it last answered to first.
local function FindDonor(build)
	for _, unit in ipairs(ns.DonorWatch.SearchUnits(build.token)) do
		if UnitExists(unit) and Plain(UnitGUID(unit)) == build.guid then return unit end
	end
	return nil
end

local function EndBuild()
	state.build = nil
	if builder then builder:SetScript("OnUpdate", nil) end
	state.dirty = true
end

local function Abandon(build)
	ns.LibraryBodies.DropDonor(build.guid)
	ns.DonorCoverageUI.DropDonor(build.entry)
	state.cost.abandoned = state.cost.abandoned + 1
	EndBuild()
end

local function Finish(build)
	local ui, coverage = ns.LibraryUI, ns.DonorCoverageUI
	ns.LibraryBodies.SettleDonor(build.guid)
	coverage.SettleDonor(build.entry)
	state.guids[build.guid] = true
	state.passive = state.passive + 1
	local cost = state.cost
	cost.ingests = cost.ingests + 1
	cost.lastIngestMs = build.spentMs
	if build.spentMs > cost.maxIngestMs then cost.maxIngestMs = build.spentMs end
	cost.lastFrames = build.frames
	cost.lastStepFrameMs = build.maxFrameMs
	cost.lastGapMs = build.maxGapMs
	EndBuild()
	if build.built > 0 then ui.Soon() end
end

local function BuildFrame(elapsed)
	local build = state.build
	if not build then return end
	local cost = state.cost
	local clock = debugprofilestop
	if build.frames > 0 and elapsed then
		local gap = elapsed * 1000
		if gap > build.maxGapMs then build.maxGapMs = gap end
		if gap > cost.maxGapMs then cost.maxGapMs = gap end
	end
	local began = clock()
	local Watch = ns.DonorWatch
	local built = false
	while true do
		local token = FindDonor(build)
		local facts = { now = GetTime(), token = token,
			combat = (InCombatLockdown and InCombatLockdown()) or false,
			instance = (IsInInstance and IsInInstance()) or false,
			ready = token ~= nil
				and (not IsUnitModelReadyForUI or IsUnitModelReadyForUI(token) == true) }
		local action, detail = Watch.BuildStep(build, facts)
		if action == "finish" then
			Finish(build)
			break
		elseif action == "abandon" then
			Abandon(build)
			break
		elseif action ~= "build" then
			break
		end
		build.token = detail
		build.done = build.done + 1
		build.steps[build.done](detail)
		built = true
		if clock() - began >= BUILD_BUDGET_MS then break end
	end
	local spent = clock() - began
	if built then
		build.frames = build.frames + 1
		build.spentMs = build.spentMs + spent
		if spent > build.maxFrameMs then build.maxFrameMs = spent end
		if spent > cost.maxStepFrameMs then cost.maxStepFrameMs = spent end
	end
end

-- Plans every body the donor lends as one step each, card bodies first, and
-- starts building them on the next frame.
local function StartBuild(unit, donor)
	local ui, lent, coverage = ns.LibraryUI, ns.LibraryBodies, ns.DonorCoverageUI
	local build = { donor = donor, guid = donor.guid, token = unit, steps = {}, done = 0,
		built = 0, frames = 0, spentMs = 0, maxFrameMs = 0, maxGapMs = 0 }
	for _, step in ipairs(ui.WarmPlan()) do
		build.steps[#build.steps + 1] = function(token)
			if lent.WarmBody(step.record, token, step.want, build.guid) then
				build.built = build.built + 1
			end
		end
	end
	local entry, keeps = coverage.KeepPlan(donor, 1, state.looks, true)
	build.entry = entry
	for _, step in ipairs(keeps) do
		build.steps[#build.steps + 1] = function(token) coverage.KeepStep(entry, step, token) end
	end
	build.total = #build.steps
	state.build = build
	state.dirty = true
	builder:SetScript("OnUpdate", function(_, elapsed) BuildFrame(elapsed) end)
end

Consider = function(unit)
	local Watch = ns.DonorWatch
	local facts = Facts(unit)
	-- Most units are nobody worth asking about; skip the rest for them.
	if not facts.isPlayer or facts.isSelf or facts.sex == facts.viewerSex then return end
	local ok, _, retry = Watch.Accepts(facts, Held())
	if not ok then
		if retry and not facts.combat and not facts.instance then RetryLater() end
		return
	end
	local donor = ns.LibraryBodies.DonorFacts(unit)
	if not donor or donor.guid == nil then return end
	StartBuild(unit, donor)
end

-- Capture events --------------------------------------------------------------------

local CAPTURE = { "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
	"GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }
local events = CreateFrame and CreateFrame("Frame", "MogtrotDonorWatch") or nil

-- Listens for players only while some donor is needed.
UpdateCapture = function()
	local want = #state.needs > 0
	if want == state.capturing or not events then return end
	state.capturing = want
	for _, event in ipairs(CAPTURE) do
		if want then events:RegisterEvent(event) else events:UnregisterEvent(event) end
	end
	if want then RetryLater(0) end
end

-- Public -----------------------------------------------------------------------------

function DonorWatchUI.Status()
	return lastStatus or Status(Paused())
end

function DonorWatchUI.Offered()
	return lastStatus ~= nil and lastStatus.offered == true
end

-- GUID -> true for the donors known to draw this look whole.
function DonorWatchUI.Covering(lookID)
	local set = {}
	for _, id in ipairs(lastStatus and lastStatus.coveredBy[lookID] or {}) do set[id] = true end
	return set
end

function DonorWatchUI.Cost()
	return state.cost
end

-- What donors are still wanted, which sexes are waiting on checks, whether
-- the capture events are registered, and the donor being built.
function DonorWatchUI.Needs()
	local build = state.build
	return { needs = state.needs, blocked = state.blocked, capturing = state.capturing,
		building = build and { name = build.donor.name, sex = build.donor.sex,
			done = build.done, total = build.total } or nil }
end

if CreateFrame then
	-- Named, and carrying the module, for the harness to read.
	events.watch = DonorWatchUI
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:SetScript("OnEvent", function(_, event, arg)
		if event == "PLAYER_ENTERING_WORLD" then
			if not state.ticker then state.ticker = C_Timer.NewTicker(TICK, Tick) end
			if state.capturing then RetryLater() end
			return
		end
		local name = event == "PLAYER_REGEN_ENABLED" and "rescan" or event
		for _, unit in ipairs(ns.DonorWatch.EventUnits(name, arg)) do Consider(unit) end
	end)
end

ns.DonorWatchUI = DonorWatchUI
return DonorWatchUI
