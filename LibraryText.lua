local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local LookCodec = ns.LookCodec or require("LookCodec")
local Library = ns.Library or require("Library")

-- How a library record reads: the two lines on its card, and the full dump
-- behind More info. Pure, so what the window says is testable without a
-- window. A field the client never answered prints as "-" rather than
-- vanishing, because "we did not get this" is itself the answer.
local LibraryText = {}

local SEXES = { [2] = "male", [3] = "female" }

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
	local body = record.raceFile or (record.raceID and ("race " .. record.raceID))
	local sex = SEXES[record.sex]
	local who
	if body and sex then
		who = ("%s %s"):format(body, sex)
	elseif body then
		who = tostring(body)
	else
		who = "body unknown"
	end
	if type(className) == "string" and className ~= "" then
		who = ("%s %s"):format(who, className)
	end
	local pieces = LibraryText.Pieces(record)
	return ("%s, %d piece%s"):format(who, pieces, pieces == 1 and "" or "s")
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

local function Value(value)
	if value == nil then return "-" end
	if type(value) == "boolean" then return value and "true" or "false" end
	return tostring(value)
end

local ORDER = {
	{ "id" }, { "source" },
	{ "origin" }, { "originID" }, { "originName" }, { "originIcon" },
	{ "name" }, { "realm" }, { "guid" }, { "title" },
	{ "faction" }, { "level" }, { "classID" }, { "specID" },
	{ "raceID" }, { "raceFile" }, { "sex" }, { "altRaceID" }, { "nativeForm" },
	{ "zone" }, { "subZone" }, { "mapID" }, { "x" }, { "y" }, { "mount" },
	{ "form" }, { "mythicPlus" }, { "itemLevel" },
	{ "seenAt" }, { "lastSeen" }, { "seenCount" },
	{ "savedAt" }, { "updatedAt" },
	{ "build" }, { "tocVersion" }, { "capturedBy" },
}

-- Every field the schema knows, in a fixed order, then the look one slot per
-- line. Fixed order so two dumps can be read side by side.
function LibraryText.Details(record)
	if type(record) ~= "table" then return {} end

	local lines = { LibraryText.Title(record), LibraryText.Subtitle(record), "" }
	for _, entry in ipairs(ORDER) do
		local field = entry[1]
		lines[#lines + 1] = ("%-12s %s"):format(field, Value(record[field]))
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = ("look         %s"):format(Value(record.look))

	local look = LookCodec.Decode(record.look)
	if type(look) ~= "table" then
		lines[#lines + 1] = "  (this look string does not parse)"
		return lines
	end

	local slots = {}
	for slot in pairs(look) do slots[#slots + 1] = slot end
	table.sort(slots)
	for _, slot in ipairs(slots) do
		local entry = look[slot]
		lines[#lines + 1] = ("  slot %-3d appearance %-8s secondary %-8s illusion %s")
			:format(slot, Value(entry[1]), Value(entry[2]), Value(entry[3]))
	end
	return lines
end

ns.LibraryText = LibraryText
return LibraryText
