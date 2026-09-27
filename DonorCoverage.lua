local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Real-look coverage: whether a body drew a stored look whole, and what a
-- body would need to be for a look none of the tried ones drew.
--
-- Pure. The drawing and the tooltip reads stay in DonorCoverageUI and
-- DonorWatchUI; facts arrive as tables.
local DonorCoverage = {}

-- IsSlotVisible answers nothing useful for a weapon (LookRender).
local WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true }

local function Includes(list, value)
	if value == nil then return false end
	for _, item in ipairs(type(list) == "table" and list or {}) do
		if item == value then return true end
	end
	return false
end

-- The races a tooltip's "Races:" line names, or nil when text does not start
-- with prefix. Colour codes are stripped.
function DonorCoverage.ParseRaces(text, prefix)
	if type(text) ~= "string" or type(prefix) ~= "string" or prefix == "" then return nil end
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	if text:sub(1, #prefix) ~= prefix then return nil end
	local races = {}
	for name in text:sub(#prefix + 1):gmatch("[^,]+") do
		name = name:match("^%s*(.-)%s*$")
		if name ~= "" then races[#races + 1] = name end
	end
	return races
end

-- One (look, body) pair from what the actor showed.
--
-- slots: { slot, source, item, appearance, visible, held, hidden } per piece
-- the look asked for; hidden marks a "hide this slot" appearance.
-- heritage: source -> { races } for a piece its tooltip limits to some races,
-- false for one it does not, nil while unread.
-- donor: { race } with race the localized name the tooltip uses.
--
-- A piece neither visible nor held was dropped. A dropped piece limited to
-- races the body is not is excluded: transmog keeps such a piece on its own
-- race, so it says nothing about a body of another race. Any other drop is a
-- failure; unread marks one whose lock could not be read. A piece held but
-- not visible is counted as covered, not dropped.
function DonorCoverage.Classify(slots, heritage, donor)
	heritage = type(heritage) == "table" and heritage or {}
	donor = type(donor) == "table" and donor or {}
	local out = { drawn = 0, asked = 0, covered = 0, failures = {}, excluded = {} }
	for _, piece in ipairs(type(slots) == "table" and slots or {}) do
		if not WEAPON_SLOTS[piece.slot] and not piece.hidden then
			out.asked = out.asked + 1
			if piece.visible then
				out.drawn = out.drawn + 1
			elseif piece.held then
				out.covered = out.covered + 1
			else
				local lock = heritage[piece.source]
				local row = { slot = piece.slot, source = piece.source, item = piece.item,
					appearance = piece.appearance }
				if type(lock) == "table" and not Includes(lock.races, donor.race) then
					row.races = lock.races
					out.excluded[#out.excluded + 1] = row
				else
					if lock == nil then row.unread = true end
					if type(lock) == "table" then row.races = lock.races end
					out.failures[#out.failures + 1] = row
				end
			end
		end
	end
	out.full = #out.failures == 0
	return out
end

local SEX = { [2] = "man", [3] = "woman" }

local function SexWord(sex)
	return SEX[sex] or "unknown sex"
end
DonorCoverage.SexWord = SexWord

local function SameRace(look, donor)
	return look.raceFile ~= nil and look.raceFile == donor.raceFile
		and look.faction == donor.faction
end

-- What a body would need to be to draw a look no tried body drew, inferred
-- from the bodies of its sex that were tried and the pieces they dropped.
-- Returns { sex, faction, race, why }; race is set only when a body of the
-- look's sex and faction was tried and failed.
function DonorCoverage.Needs(look, tried)
	local needs = { sex = look.sex, faction = look.faction }
	local sameSex, sameFaction, sameRace = {}, {}, {}
	for _, pair in ipairs(tried or {}) do
		local donor = pair.donor
		if donor.sex == look.sex then
			sameSex[#sameSex + 1] = pair
			if donor.faction == look.faction then
				sameFaction[#sameFaction + 1] = pair
				if SameRace(look, donor) then sameRace[#sameRace + 1] = pair end
			end
		end
	end
	if #sameSex == 0 then
		needs.why = ("no %s body yet"):format(SexWord(look.sex))
	elseif #sameFaction == 0 then
		needs.why = ("only %s bodies of the other faction tried"):format(SexWord(look.sex))
	elseif #sameRace == 0 then
		needs.race = look.raceFile
		needs.why = "a body of its sex and faction dropped pieces"
	else
		needs.race = look.raceFile
		needs.why = "drops pieces even on a body of its own race"
	end
	return needs
end

-- The bodies worth ingesting next: the uncovered looks grouped by the
-- attributes they need, most looks first.
function DonorCoverage.Wanted(uncovered)
	local groups, byKey = {}, {}
	for _, entry in ipairs(uncovered or {}) do
		local needs = entry.needs or {}
		local key = ("%s|%s|%s"):format(tostring(needs.sex), tostring(needs.faction),
			tostring(needs.race))
		local group = byKey[key]
		if not group then
			group = { sex = needs.sex, faction = needs.faction, race = needs.race, looks = {} }
			byKey[key] = group
			groups[#groups + 1] = group
		end
		group.looks[#group.looks + 1] = entry.look
	end
	table.sort(groups, function(a, b)
		if #a.looks ~= #b.looks then return #a.looks > #b.looks end
		return ("%s|%s|%s"):format(tostring(a.sex), tostring(a.faction), tostring(a.race))
			< ("%s|%s|%s"):format(tostring(b.sex), tostring(b.faction), tostring(b.race))
	end)
	return groups
end

-- Playable races: file and faction (ChrRaces, 12.1).
local RACES = {
	[1] = { "Human", "Alliance" }, [2] = { "Orc", "Horde" },
	[3] = { "Dwarf", "Alliance" }, [4] = { "NightElf", "Alliance" },
	[5] = { "Scourge", "Horde" }, [6] = { "Tauren", "Horde" },
	[7] = { "Gnome", "Alliance" }, [8] = { "Troll", "Horde" },
	[9] = { "Goblin", "Horde" }, [10] = { "BloodElf", "Horde" },
	[11] = { "Draenei", "Alliance" }, [22] = { "Worgen", "Alliance" },
	[25] = { "Pandaren", "Alliance" }, [26] = { "Pandaren", "Horde" },
	[27] = { "Nightborne", "Horde" }, [28] = { "HighmountainTauren", "Horde" },
	[29] = { "VoidElf", "Alliance" }, [30] = { "LightforgedDraenei", "Alliance" },
	[31] = { "ZandalariTroll", "Horde" }, [32] = { "KulTiran", "Alliance" },
	[34] = { "DarkIronDwarf", "Alliance" }, [35] = { "Vulpera", "Horde" },
	[36] = { "MagharOrc", "Horde" }, [37] = { "Mechagnome", "Alliance" },
	[52] = { "Dracthyr", "Alliance" }, [70] = { "Dracthyr", "Horde" },
	[84] = { "EarthenDwarf", "Horde" }, [85] = { "EarthenDwarf", "Alliance" },
	[86] = { "Harronir", "Alliance" }, [91] = { "Harronir", "Horde" },
}

-- A playable race's faction, or nil for one not listed.
function DonorCoverage.RaceFaction(raceID)
	local race = RACES[raceID]
	return race and race[2] or nil
end

ns.DonorCoverage = DonorCoverage
return DonorCoverage
