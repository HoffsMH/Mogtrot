local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Passive donors and background coverage: which units become donors as the
-- player meets them, which (look, body) pairs are left to draw, and whether
-- every live look has a body known to draw it whole, which is when the
-- library offers original race.
--
-- Pure. Units, frames and draws stay in DonorWatchUI; facts arrive as tables.
local DonorWatch = {}

local function Coverage()
	return ns.DonorCoverage or (require and require("DonorCoverage"))
end

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

-- What makes two donors' bodies alike for coverage: a piece's lock follows
-- the donor's faction and, for heritage pieces, its race.
function DonorWatch.ClassKey(sex, faction, raceID)
	return ("%s|%s|%s"):format(tostring(sex), tostring(faction), tostring(raceID))
end

-- Whether a donor with these facts meets one need: the need's sex, and its
-- faction and race when it names them.
function DonorWatch.Meets(need, facts)
	if type(need) ~= "table" or type(facts) ~= "table" then return false end
	if need.sex ~= facts.sex then return false end
	if need.faction ~= nil and need.faction ~= facts.faction then return false end
	if need.race ~= nil and need.race ~= facts.raceFile then return false end
	return true
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

-- Whether a unit becomes a donor in passing. Returns ok, why, retry; retry
-- marks a refusal that may pass later for the same unit.
--
-- facts: exists, isPlayer, isSelf, secret, ready, combat, instance, sex,
-- viewerSex, guid, raceID, raceFile, faction.
-- held: guids and classes already held, needs (DonorWatch.Needs), building
-- (true while another donor's bodies are being built).
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
	if held.building then return false, "another body is being built", true end
	local meets = false
	for _, need in ipairs(held.needs or {}) do
		if DonorWatch.Meets(need, facts) then meets = true end
	end
	if not meets then return false, "no body like it is needed" end
	if not facts.ready then return false, "model not loaded", true end
	return true
end

local function Rank(body, look)
	local rank = 0
	if look.raceFile ~= nil and body.raceFile == look.raceFile then rank = rank + 2 end
	if look.faction ~= nil and body.faction == look.faction then rank = rank + 1 end
	return rank
end

local function HasKey(body, key)
	return body.keys == nil or (key ~= nil and body.keys[key] == true)
end

-- The bodies whose verdict counts for a look, best first. A card draws a look
-- of your sex on your own body, so only that body counts for it; any other
-- look needs a donor of its sex holding a body of its key.
function DonorWatch.Eligible(look, bodies, viewerSex)
	local list = {}
	for index, body in ipairs(bodies or {}) do
		if look.sex == viewerSex then
			if body.self then list[#list + 1] = { body = body, index = index } end
		elseif not body.self and body.sex == look.sex and HasKey(body, look.key) then
			list[#list + 1] = { body = body, index = index }
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Rank(a.body, look), Rank(b.body, look)
		if ra ~= rb then return ra > rb end
		return a.index < b.index
	end)
	for index, row in ipairs(list) do list[index] = row.body end
	return list
end

local function OwnRace(look, body)
	return body.sex == look.sex and look.raceFile ~= nil and body.raceFile == look.raceFile
		and body.faction == look.faction
end

-- One look's standing:
--   covered   a body that counts drew it whole (by: those bodies)
--   known     it dropped pieces on a body of its own race and sex: left out
--   noRoom    drawn whole only by donors with no card body of its key
--   checking  a pair is in flight or an eligible body is untried
--   onYou     a look of your sex that dropped pieces on your body
--   needs     no body at hand can draw it
local function LookState(look, input)
	local tried = (input.tried or {})[look.id] or {}
	local eligible = DonorWatch.Eligible(look, input.bodies, input.viewerSex)
	local by, wholeUnpooled = {}, false
	for _, body in ipairs(eligible) do
		local verdict = tried[body.id]
		if verdict and verdict.full then
			local pooled = body.self or ((input.pooled or {})[look.key] or {})[body.id]
			if pooled then by[#by + 1] = body.id else wholeUnpooled = true end
		end
	end
	if #by > 0 then return "covered", by end
	for _, body in ipairs(input.bodies or {}) do
		local verdict = tried[body.id]
		if verdict and not verdict.full and OwnRace(look, body) then return "known" end
	end
	if wholeUnpooled then return "noRoom" end
	if (input.pending or {})[look.id] then return "checking" end
	for _, body in ipairs(eligible) do
		if not tried[body.id] then return "checking" end
	end
	if look.sex == input.viewerSex and #eligible > 0 then return "onYou" end
	return "needs"
end

-- Up to limit pairs to draw next, one per look and one per body key, each
-- look with its best untried eligible body. busy holds "bodyID|key" for
-- bodies already dressing.
function DonorWatch.NextPairs(input)
	input = type(input) == "table" and input or {}
	local out, taken = {}, {}
	local limit = input.limit or 1
	for _, look in ipairs(input.looks or {}) do
		if #out >= limit then break end
		if not look.archived and not (input.pending or {})[look.id]
			and LookState(look, input) == "checking" then
			local tried = (input.tried or {})[look.id] or {}
			for _, body in ipairs(DonorWatch.Eligible(look, input.bodies, input.viewerSex)) do
				local slot = ("%s|%s"):format(tostring(body.id), tostring(look.key))
				if not tried[body.id] then
					if not (input.busy or {})[slot] and not taken[slot] then
						taken[slot] = true
						out[#out + 1] = { look = look.id, body = body.id }
					end
					break
				end
			end
		end
	end
	return out
end

local function TriedPairs(look, input, bodyByID)
	local tried = {}
	for id, verdict in pairs((input.tried or {})[look.id] or {}) do
		if bodyByID[id] then tried[#tried + 1] = { donor = bodyByID[id], verdict = verdict } end
	end
	table.sort(tried, function(a, b) return tostring(a.donor.id) < tostring(b.donor.id) end)
	return tried
end

-- Which donors are still wanted, as { sex, faction?, race? }, and blocked
-- (sex -> true) for the sexes taking nobody right now.
--
-- input is DonorWatch.Status's, plus building: donors whose bodies are still
-- being built. Only live looks of the other sex count. A sex with no donor
-- held needs any body of it. A sex with a donor building, or with a look
-- still to check on a held donor, needs nobody until that settles. After
-- that, each uncovered look needs what DonorCoverage.Needs says: its faction,
-- or its race where a body of its faction dropped pieces.
function DonorWatch.Needs(input)
	input = type(input) == "table" and input or {}
	local viewer = input.viewerSex
	local held, blocked, coarse, precise = {}, {}, {}, {}
	local bodyByID = {}
	for _, body in ipairs(input.bodies or {}) do
		bodyByID[body.id] = body
		if not body.self and body.sex ~= nil then held[body.sex] = true end
	end
	for _, donor in ipairs(input.building or {}) do
		if donor.sex ~= nil then blocked[donor.sex] = true end
	end
	for _, look in ipairs(input.looks or {}) do
		if not look.archived and look.sex ~= viewer and (look.sex == 2 or look.sex == 3) then
			local state = LookState(look, input)
			if state == "checking" then
				blocked[look.sex] = true
			elseif state == "needs" then
				if not held[look.sex] then
					coarse[look.sex] = true
				else
					local needs = Coverage().Needs(look, TriedPairs(look, input, bodyByID))
					precise[#precise + 1] = { sex = needs.sex, faction = needs.faction,
						race = needs.race }
				end
			end
		end
	end
	local out, seen = {}, {}
	for _, sex in ipairs({ 2, 3 }) do
		if not blocked[sex] then
			if coarse[sex] then out[#out + 1] = { sex = sex } end
			local mine = {}
			for _, need in ipairs(precise) do
				local key = ("%s|%s|%s"):format(tostring(need.sex), tostring(need.faction),
					tostring(need.race))
				if need.sex == sex and not coarse[sex] and not seen[key] then
					seen[key] = true
					mine[#mine + 1] = need
				end
			end
			table.sort(mine, function(a, b)
				return ("%s|%s"):format(tostring(a.faction), tostring(a.race))
					< ("%s|%s"):format(tostring(b.faction), tostring(b.race))
			end)
			for _, need in ipairs(mine) do out[#out + 1] = need end
		end
	end
	return out, blocked
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

local RACE_WORDS = { Scourge = "undead", MagharOrc = "mag'har orc",
	EarthenDwarf = "earthen", Harronir = "haranir", HighmountainTauren = "highmountain tauren" }

function DonorWatch.RaceWord(raceFile)
	if type(raceFile) ~= "string" then return nil end
	if RACE_WORDS[raceFile] then return RACE_WORDS[raceFile] end
	return (raceFile:gsub("(%l)(%u)", "%1 %2"):lower())
end

local SEX = { [2] = "man", [3] = "woman" }

local function Article(word)
	return word:match("^[AEIOUaeiou]") and "an " or "a "
end

local function Looks(count)
	return ("%d look%s"):format(count, count == 1 and "" or "s")
end

-- Whether original race is offered, and what the status line says while it
-- is not.
--
-- input: looks { id, sex, faction, raceFile, key, archived }, bodies (self
-- first, keys nil for a body that builds any key), tried (lookID -> bodyID ->
-- { full }), pending (lookID -> true), pooled (key -> bodyID -> true for
-- donors with a card body of that key), viewerSex, paused (why, or nil).
--
-- Archived looks and looks that drop pieces on their own race are left out.
-- Returns offered, coveredBy (lookID -> body IDs), known (look IDs),
-- checking, noRoom, dropsOnYou, groups (DonorCoverage.Wanted) and text.
function DonorWatch.Status(input)
	input = type(input) == "table" and input or {}
	local out = { coveredBy = {}, known = {}, checking = 0, noRoom = 0, dropsOnYou = 0,
		live = 0 }
	local uncovered = {}
	local bodyByID = {}
	for _, body in ipairs(input.bodies or {}) do bodyByID[body.id] = body end
	for _, look in ipairs(input.looks or {}) do
		if not look.archived then
			out.live = out.live + 1
			local state, by = LookState(look, input)
			if state == "covered" then
				out.coveredBy[look.id] = by
			elseif state == "known" then
				out.known[#out.known + 1] = look.id
			elseif state == "noRoom" then
				out.noRoom = out.noRoom + 1
			elseif state == "checking" then
				out.checking = out.checking + 1
			elseif state == "onYou" then
				out.dropsOnYou = out.dropsOnYou + 1
			else
				local tried = {}
				for id, verdict in pairs((input.tried or {})[look.id] or {}) do
					if bodyByID[id] then tried[#tried + 1] = { donor = bodyByID[id], verdict = verdict } end
				end
				uncovered[#uncovered + 1] = { look = look.id,
					needs = Coverage().Needs(look, tried) }
			end
		end
	end
	table.sort(out.known, function(a, b) return tostring(a) < tostring(b) end)
	out.groups = Coverage().Wanted(uncovered)
	out.offered = out.live > 0 and #uncovered == 0 and out.checking == 0
		and out.noRoom == 0 and out.dropsOnYou == 0

	local segments = {}
	if #out.groups > 0 then
		local wants = {}
		for _, group in ipairs(out.groups) do
			local who = SEX[group.sex] or "body"
			local race = DonorWatch.RaceWord(group.race)
			if race then
				who = race .. " " .. who
			elseif group.faction then
				who = group.faction .. " " .. who
			end
			wants[#wants + 1] = ("%s%s for %s"):format(Article(who), who, Looks(#group.looks))
		end
		local last = table.remove(wants)
		local joined = #wants > 0 and (table.concat(wants, ", ") .. " and " .. last) or last
		segments[#segments + 1] = "needs " .. joined
	end
	if out.checking > 0 then segments[#segments + 1] = "checking " .. Looks(out.checking) end
	if out.dropsOnYou > 0 then
		segments[#segments + 1] = ("%s drop%s pieces on your body"):format(
			Looks(out.dropsOnYou), out.dropsOnYou == 1 and "s" or "")
	end
	if out.noRoom > 0 then
		segments[#segments + 1] = ("%s %s no free body"):format(Looks(out.noRoom),
			out.noRoom == 1 and "has" or "have")
	end
	if #segments == 0 then
		out.text = out.offered and "" or "Original race: no looks yet"
	else
		local text = table.concat(segments, "; ")
		out.text = (text:match("^needs") and "Original race " or "Original race: ") .. text
		if input.paused then out.text = ("%s (checks paused %s)"):format(out.text, input.paused) end
	end
	return out
end

ns.DonorWatch = DonorWatch
return DonorWatch
