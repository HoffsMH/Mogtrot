local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local LookCodec = ns.LookCodec or require("LookCodec")
local Library = ns.Library or require("Library")

-- How a library record reads: the lines on its card, its detail pane and
-- the snap confirmation. Pure, so what the window says is testable without a
-- window.
local LibraryText = {}

local SEXES = { [2] = "man", [3] = "woman" }

-- Race file names that do not read as the race's name once split at capitals.
local RACE_NAMES = { Scourge = "Undead", MagharOrc = "Mag'har Orc",
	EarthenDwarf = "Earthen", Harronir = "Haranir" }

function LibraryText.RaceName(raceFile)
	if type(raceFile) ~= "string" or raceFile == "" then return nil end
	return RACE_NAMES[raceFile] or (raceFile:gsub("(%l)(%u)", "%1 %2"))
end

-- Face value, never a guess: a record carrying no name was captured where the
-- client refused to give one.
function LibraryText.Title(record)
	if type(record) ~= "table" then return "" end
	if record.source == "mine"
		and (record.origin == "outfit" or record.origin == "customSet")
		and type(record.originName) == "string" and record.originName ~= "" then
		return record.originName
	end
	if type(record.name) == "string" and record.name ~= "" then
		if type(record.realm) == "string" and record.realm ~= "" then
			return record.name .. "-" .. record.realm
		end
		return record.name
	end
	if record.originName then return tostring(record.originName) end
	return ("Look #%s"):format(tostring(record.id or "?"))
end

-- The line on the snap confirmation. A repeat sighting says so rather than
-- implying something new was stored.
function LibraryText.Confirmation(record, isNew)
	if type(record) ~= "table" then return "" end
	local line = ("%s %s"):format(LibraryText.Title(record),
		isNew and "captured" or "seen again")
	if type(record.name) ~= "string" or record.name == "" then
		line = line .. ", no name given"
	end
	return line
end

function LibraryText.CardTitle(record, className, colorCode)
	local title = LibraryText.Title(record)
	if type(className) ~= "string" or className == "" then return title end
	if type(colorCode) ~= "string" or colorCode == "" then return title end
	return ("%s | |c%s%s|r"):format(title, colorCode, className)
end

function LibraryText.Pieces(record)
	if type(record) ~= "table" then return 0 end
	local look = LookCodec.Decode(record.look)
	if type(look) ~= "table" then return 0 end
	local n = 0
	for _ in pairs(look) do n = n + 1 end
	return n
end

-- Where a card's lines sit, in pixels up from its bottom edge, and where the
-- model scene ends.
function LibraryText.CardLayout()
	return { sub = 5, title = 17, scene = 33 }
end

-- The body the card is showing, plus how much of an outfit is on it.
-- className is injected because naming a class is a client lookup and this
-- module stays pure. Snapshots only: one of your own already wears its class
-- on the card title.
function LibraryText.Subtitle(record, className)
	if type(record) ~= "table" then return "" end
	if record.source == "mine"
		and (record.origin == "outfit" or record.origin == "customSet") then
		local owner = record.name or "Unknown character"
		if record.realm and record.realm ~= "" then owner = owner .. "-" .. record.realm end
		-- Both of these hold an empty look, and saying "0 pieces" for either
		-- hides the only difference that matters: whether there is anything to
		-- go and fetch.
		if Library.IsUnscanned(record) then
			return ("%s, not captured yet"):format(owner)
		end
		if Library.IsEmptyOutfit(record) then
			return ("%s, nothing set"):format(owner)
		end
		local pieces = LibraryText.Pieces(record)
		return ("%s, %d piece%s"):format(owner, pieces, pieces == 1 and "" or "s")
	end
	local race = LibraryText.RaceName(record.raceFile)
	local sex = SEXES[record.sex]
	local who
	if race and sex then
		who = ("%s %s"):format(race, sex)
	elseif race then
		who = race
	else
		who = "Unknown race"
	end
	if type(className) == "string" and className ~= "" then
		who = ("%s %s"):format(who, className)
	end
	local pieces = LibraryText.Pieces(record)
	return ("%s, %d piece%s"):format(who, pieces, pieces == 1 and "" or "s")
end

-- Pieces limited to one faction's races are dropped by a body of the other
-- faction. dropped is how many armour slots the body left empty. Short enough
-- to stand in for the card's subtitle.
local FACTIONS = { Alliance = true, Horde = true }

function LibraryText.FactionNote(record, bodyFaction, dropped)
	if type(record) ~= "table" or type(dropped) ~= "number" or dropped < 1 then
		return nil
	end
	local wanted = record.faction
	if not (FACTIONS[wanted] and FACTIONS[bodyFaction]) or wanted == bodyFaction then
		return nil
	end
	return ("%d of %d pieces %s %s only"):format(dropped, LibraryText.Pieces(record),
		dropped == 1 and "is" or "are", wanted)
end

-- Inventory slots a transmog can occupy, in the order a person reads a
-- character sheet: head down the body, then what is held.
LibraryText.SLOT_ORDER = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 19 }

-- The paperdoll arrangement: worn-on-the-body down the left, worn-on-the-limbs
-- down the right, weapons underneath. The same shape as the character sheet,
-- so it reads without being learned.
LibraryText.SLOT_COLUMNS = {
	left = { 1, 3, 15, 5, 4, 19, 9 },
	right = { 10, 6, 7, 8 },
	bottom = { 16, 17 },
}

local SLOT_NAMES = {
	[1] = "Head", [3] = "Shoulders", [4] = "Shirt", [5] = "Chest",
	[6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrists",
	[10] = "Hands", [15] = "Back", [16] = "Main hand", [17] = "Off hand",
	[19] = "Tabard",
}

function LibraryText.SlotName(slotID)
	return SLOT_NAMES[slotID] or ("Slot " .. tostring(slotID))
end

ns.LibraryText = LibraryText
return LibraryText
