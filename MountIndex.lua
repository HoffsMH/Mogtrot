local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Finds every outfit linked to a mount. Mount cards use it to count links, and
-- the "Outfits using" window uses it to mark existing links.
local MountIndex = {}

function MountIndex.Build(db)
	local index = {}

	for outfitID, mounts in pairs(db.mounts or {}) do
		for mountID in pairs(mounts) do
			local outfits = index[mountID]
			if not outfits then
				outfits = {}
				index[mountID] = outfits
			end
			table.insert(outfits, outfitID)
		end
	end

	for _, outfits in pairs(index) do
		table.sort(outfits)
	end

	return index
end

ns.MountIndex = MountIndex
return MountIndex
