local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Passive donors: which units become donors as the player meets them, and
-- what a donor being built in steps does next.
--
-- Pure. Units, frames and bodies stay in DonorWatchUI; facts arrive as tables.
local DonorWatch = {}

local GROUP = {}
for index = 1, 4 do GROUP[#GROUP + 1] = "party" .. index end
for index = 1, 40 do GROUP[#GROUP + 1] = "raid" .. index end

-- The unit tokens an event asks about. "rescan" is target, mouseover and the
-- group, for when a pause ends.
function DonorWatch.EventUnits(event, arg)
	if event == "PLAYER_TARGET_CHANGED" then return { "target" } end
	if event == "UPDATE_MOUSEOVER_UNIT" then return { "mouseover" } end
	if event == "NAME_PLATE_UNIT_ADDED" then
		return type(arg) == "string" and { arg } or {}
	end
	local units = {}
	if event == "rescan" then units = { "target", "mouseover" } end
	if event == "GROUP_ROSTER_UPDATE" or event == "rescan" then
		for _, token in ipairs(GROUP) do units[#units + 1] = token end
	end
	return units
end

-- What makes two donors' bodies alike: the sex, the faction (a piece limited
-- to one faction's races drops on a body of the other) and the race.
function DonorWatch.ClassKey(sex, faction, raceID)
	return ("%s|%s|%s"):format(tostring(sex), tostring(faction), tostring(raceID))
end

-- Why a unit's donor facts cannot be taken, or nil when they can.
-- facts: exists, isPlayer, isSelf, secret, ready, combat.
function DonorWatch.Refusal(facts)
	facts = type(facts) == "table" and facts or {}
	if facts.combat then return "not in combat" end
	if not facts.exists then return "target a player first" end
	if not facts.isPlayer then return "your target is not a player" end
	if facts.isSelf then return "that is you" end
	if facts.secret then return "the client keeps your target's identity secret here" end
	if not facts.ready then return "their model is not loaded yet; try again in a moment" end
	return nil
end

-- Whether a unit becomes a donor in passing: any player of the other sex
-- whose sex, faction and race no donor held or queued has. Returns ok, why,
-- retry; retry marks a refusal that may pass later for the same unit.
--
-- facts: exists, isPlayer, isSelf, secret, ready, combat, instance, sex,
-- viewerSex, guid, raceID, raceFile, faction.
-- held: guids and classes (DonorWatch.ClassKey) held or queued, and full when
-- the body pool has no room for another donor's bodies.
function DonorWatch.Accepts(facts, held)
	facts = type(facts) == "table" and facts or {}
	held = type(held) == "table" and held or {}
	if facts.combat then return false, "in combat", true end
	if facts.instance then return false, "in an instance", true end
	if not facts.exists then return false, "no unit" end
	if not facts.isPlayer then return false, "not a player" end
	if facts.isSelf then return false, "that is you" end
	if facts.secret then return false, "identity kept secret" end
	if facts.sex ~= 2 and facts.sex ~= 3 then return false, "sex unknown" end
	if facts.sex == facts.viewerSex then return false, "your own body draws your sex" end
	if facts.guid == nil then return false, "no GUID to follow" end
	if (held.guids or {})[facts.guid] then return false, "already taken" end
	local class = DonorWatch.ClassKey(facts.sex, facts.faction, facts.raceID)
	if (held.classes or {})[class] then return false, "a body like it is held" end
	if held.full then return false, "no room for more bodies", true end
	if not facts.ready then return false, "model not loaded", true end
	return true
end

-- Every token that can name a player, the one a donor came in by first, for
-- finding that donor again between build steps.
function DonorWatch.SearchUnits(first)
	local units, seen = {}, {}
	local function Add(unit)
		if unit ~= nil and not seen[unit] then
			seen[unit] = true
			units[#units + 1] = unit
		end
	end
	Add(first)
	Add("target")
	Add("mouseover")
	Add("focus")
	for index = 1, 40 do Add("nameplate" .. index) end
	for _, token in ipairs(GROUP) do Add(token) end
	return units
end

-- Seconds a half-built donor may be out of every token's reach before it is
-- dropped.
DonorWatch.LOST_GRACE = 5

-- What a donor being built in steps does next: "build" (and the token to
-- build from), "wait", "finish" or "abandon" (and why). Records on build
-- when the donor went out of reach.
--
-- build: total steps, done so far. facts: now, token (the unit naming the
-- donor now, or nil), ready, combat, instance.
function DonorWatch.BuildStep(build, facts)
	facts = type(facts) == "table" and facts or {}
	if facts.instance then return "abandon", "entered an instance" end
	if (build.done or 0) >= (build.total or 0) then return "finish" end
	if not facts.token then
		build.lostAt = build.lostAt or facts.now
		if (facts.now or 0) - build.lostAt >= DonorWatch.LOST_GRACE then
			return "abandon", "they went out of reach"
		end
		return "wait", "out of reach"
	end
	build.lostAt = nil
	if facts.combat then return "wait", "in combat" end
	if not facts.ready then return "wait", "model not loaded" end
	return "build", facts.token
end

ns.DonorWatch = DonorWatch
return DonorWatch
