local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Pure half of capturing another player's appearance. The client hands back
-- an ItemTransmogInfo per slot; this turns that into the same look shape
-- Mogtrot already stores for its own outfits, so one renderer serves both.
--
-- A look is { [slotID] = { appearanceID, secondaryAppearanceID, illusionID } }.
-- Tables in, no frames, no C_ calls.
local InspectLook = {}

InspectLook.NO_TRANSMOG = 0

local function Number(value)
	local n = tonumber(value)
	return n or InspectLook.NO_TRANSMOG
end

-- Returns look, filled, empty. filled counts slots carrying a real
-- appearance, so a caller can tell "still loading" from "wearing nothing".
function InspectLook.FromTransmogList(list)
	local look, filled, empty = {}, 0, 0
	if type(list) ~= "table" then return look, 0, 0 end

	for slotID, info in pairs(list) do
		if type(slotID) == "number" and type(info) == "table" then
			local appearance = Number(info.appearanceID)
			look[slotID] = {
				appearance,
				Number(info.secondaryAppearanceID),
				Number(info.illusionID),
			}
			if appearance ~= InspectLook.NO_TRANSMOG then
				filled = filled + 1
			else
				empty = empty + 1
			end
		end
	end
	return look, filled, empty
end

-- Paste-ready lines in the shape MogtrotCharDB.looks already uses.
function InspectLook.Format(look, label)
	local slots = {}
	for slotID in pairs(look or {}) do
		if type(slotID) == "number" then slots[#slots + 1] = slotID end
	end
	table.sort(slots)

	local lines = { ("-- %s"):format(tostring(label or "captured look")) }
	lines[#lines + 1] = "{"
	for _, slotID in ipairs(slots) do
		local entry = look[slotID]
		lines[#lines + 1] = ("\t[%d] = { %d, %d, %d },")
			:format(slotID, entry[1], entry[2], entry[3])
	end
	lines[#lines + 1] = "}"
	return lines
end

ns.InspectLook = InspectLook
return InspectLook
