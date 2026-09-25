local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Compact text form of a captured look, and the key the library dedupes on.
--
-- A look is { [inventorySlotID] = { appearanceID, secondaryAppearanceID,
-- illusionID } }. Stored as nested tables it costs roughly ten times the parse
-- and four times the heap of one string per record, measured over a thousand
-- records, so it is stored as text and decoded only for the rows on screen.
--
-- Grammar: slots joined by ";", each "slot:a,b,c". A slot holding nothing
-- positive is omitted, which drops the seven slots no character can ever
-- transmog. A slot carrying only an illusion is kept, because a weapon enchant
-- with no appearance is real.
--
-- Values can be negative: the client answers -1 for the secondary appearance of
-- a weapon slot with no second appearance, as a two-hander has. That is the
-- client's own answer, so it is stored rather than flattened, and "nothing
-- here" is any value at or below zero.
local LookCodec = {}

local SEP, FIELD = ";", ","

local function Number(value)
	local n = tonumber(value)
	return n or 0
end

local function Triple(entry)
	if type(entry) ~= "table" then return 0, 0, 0 end
	return Number(entry[1]), Number(entry[2]), Number(entry[3])
end

function LookCodec.Encode(look)
	if type(look) ~= "table" then return nil end

	local slots = {}
	for slot in pairs(look) do
		if type(slot) == "number" then slots[#slots + 1] = slot end
	end
	table.sort(slots)

	local parts = {}
	for _, slot in ipairs(slots) do
		local a, b, c = Triple(look[slot])
		if a > 0 or b > 0 or c > 0 then
			parts[#parts + 1] = ("%d:%d%s%d%s%d"):format(slot, a, FIELD, b, FIELD, c)
		end
	end
	return table.concat(parts, SEP)
end

-- nil for anything malformed, so a corrupted string is never read as a naked
-- character wearing nothing.
function LookCodec.Decode(text)
	if type(text) ~= "string" then return nil end
	if text == "" then return {} end

	local look = {}
	for part in text:gmatch("[^" .. SEP .. "]+") do
		local slot, a, b, c = part:match("^(%d+):(%-?%d+),(%-?%d+),(%-?%d+)$")
		if not slot then return nil end
		look[tonumber(slot)] = { tonumber(a), tonumber(b), tonumber(c) }
	end
	return look
end

-- An outfit's definition from the viewed outfit's slot infos. entries are
-- { slotID, primary, secondary, illusion }, each part a slot info or nil. A
-- part counts only when its displayType is assigned: an empty slot renders
-- equipped gear, which the outfit does not choose, so it is stored as 0.
function LookCodec.FromSlotInfos(entries, assigned)
	local function Part(info)
		if type(info) ~= "table" or info.displayType ~= assigned then return 0 end
		return tonumber(info.transmogID) or 0
	end

	local look = {}
	for _, entry in ipairs(entries or {}) do
		if type(entry) == "table" and type(entry.slotID) == "number" then
			look[entry.slotID] = {
				Part(entry.primary), Part(entry.secondary), Part(entry.illusion),
			}
		end
	end
	return look
end

-- What the library dedupes on: what they look like, not who they are. Two
-- characters with the same appearances, race and sex carry no new information.
-- Lua hashes a string key internally, so an index keyed on this is already the
-- hash map; no digest function exists in the API and none is needed.
function LookCodec.Key(lookOrText, raceID, sex)
	local text = type(lookOrText) == "string" and lookOrText
		or LookCodec.Encode(lookOrText)
	if type(text) ~= "string" then return nil end
	return ("%s|%s|%s"):format(text, tostring(raceID), tostring(sex))
end

ns.LookCodec = LookCodec
return LookCodec
