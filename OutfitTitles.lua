local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Stores titles linked to outfits and chooses the least recently used one.
local OutfitTitles = {}

function OutfitTitles.Get(char, outfitID)
	return char.titles[outfitID] or {}
end

function OutfitTitles.Count(char, outfitID)
	local count = 0
	for _ in pairs(OutfitTitles.Get(char, outfitID)) do count = count + 1 end
	return count
end

function OutfitTitles.Replace(char, outfitID, titleIDs)
	local linked = {}
	for _, titleID in ipairs(titleIDs or {}) do linked[titleID] = true end
	char.titles[outfitID] = next(linked) and linked or nil

	local rotation = char.titleRotation[outfitID]
	if not next(linked) then
		char.titleRotation[outfitID] = nil
	elseif rotation and rotation.used then
		for titleID in pairs(rotation.used) do
			if not linked[titleID] then rotation.used[titleID] = nil end
		end
	end
end

function OutfitTitles.Copy(char, fromOutfitID, toOutfitID, merge)
	local linked = {}
	if merge then
		for titleID in pairs(OutfitTitles.Get(char, toOutfitID)) do linked[titleID] = true end
	end
	for titleID in pairs(OutfitTitles.Get(char, fromOutfitID)) do linked[titleID] = true end

	local titleIDs = {}
	for titleID in pairs(linked) do table.insert(titleIDs, titleID) end
	OutfitTitles.Replace(char, toOutfitID, titleIDs)
end

function OutfitTitles.Clear(char, outfitID)
	OutfitTitles.Replace(char, outfitID, {})
end

function OutfitTitles.Choose(char, outfitID, known, currentTitleID, random)
	local linked = char.titles[outfitID]
	if not linked then return nil end
	local rotation = char.titleRotation[outfitID] or {}
	local used = rotation.used or {}
	local least
	local eligible = {}
	for titleID in pairs(linked) do
		if known[titleID] then
			local serial = used[titleID] or 0
			if least == nil or serial < least then
				least = serial
				eligible = { titleID }
			elseif serial == least then
				table.insert(eligible, titleID)
			end
		end
	end
	if #eligible == 0 then return nil end
	if #eligible > 1 and currentTitleID then
		for i = #eligible, 1, -1 do
			if eligible[i] == currentTitleID then table.remove(eligible, i) end
		end
	end
	table.sort(eligible)
	random = random or math.random
	return eligible[random(#eligible)]
end

function OutfitTitles.Record(char, outfitID, titleID)
	local rotation = char.titleRotation[outfitID] or { serial = 0, used = {} }
	rotation.serial = (rotation.serial or 0) + 1
	rotation.used = rotation.used or {}
	rotation.used[titleID] = rotation.serial
	char.titleRotation[outfitID] = rotation
end

function OutfitTitles.Clean(char, liveOutfits)
	for outfitID in pairs(char.titles) do
		if not liveOutfits[outfitID] then char.titles[outfitID] = nil end
	end
	for outfitID in pairs(char.titleRotation) do
		if not liveOutfits[outfitID] then char.titleRotation[outfitID] = nil end
	end
end

ns.OutfitTitles = OutfitTitles
return OutfitTitles
