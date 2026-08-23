local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Prepares the title choices shown for an outfit and saves the chosen set.
local OutfitTitlePicker = {}

local function CleanName(name, playerName)
	name = name or ""
	playerName = playerName or ""
	if name:find("%%s") then
		return (name:gsub("%%s", playerName)):match("^%s*(.-)%s*$")
	end
	if playerName == "" then return name:match("^%s*(.-)%s*$") end
	if name:find("%s$") then return name .. playerName end
	if name:find("^[%s,]") then return playerName .. name end
	return playerName .. ", " .. name
end

OutfitTitlePicker.DisplayName = CleanName

function OutfitTitlePicker.BuildItems(count, isKnown, getName, linked, playerName)
	local items = {}
	for titleID = 1, count do
		if isKnown(titleID) then
			table.insert(items, {
				titleID = titleID,
				name = CleanName(getName(titleID), playerName),
				preselected = linked[titleID] == true,
			})
		end
	end
	table.sort(items, function(a, b)
		if a.preselected ~= b.preselected then return a.preselected end
		local aName, bName = a.name:lower(), b.name:lower()
		if aName == bName then return a.titleID < b.titleID end
		return aName < bName
	end)
	return items
end

function OutfitTitlePicker.Apply(model, char, outfitID, chosen)
	local titleIDs = {}
	for _, item in ipairs(chosen) do table.insert(titleIDs, item.titleID) end
	table.sort(titleIDs)
	model.Replace(char, outfitID, titleIDs)
end

ns.OutfitTitlePicker = OutfitTitlePicker
return OutfitTitlePicker
