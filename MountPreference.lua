local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = {} end

local MountPreference = {}

local function InType(types, mountID, mountType)
	local classified = types and types[mountID]
	return classified and classified[mountType] == true
end

local function Bucket(candidates, types, mountType)
	local bucket = {}
	for _, mountID in ipairs(candidates or {}) do
		if InType(types, mountID, mountType) then
			table.insert(bucket, mountID)
		end
	end
	return bucket
end

local function Draw(candidates, random)
	if #candidates == 0 then return nil end
	return candidates[random(#candidates)]
end

-- Chooses a mount suited to the player's current travel conditions.
function MountPreference.Choose(candidates, types, situation, mountType, random, requirePreferred)
	candidates = candidates or {}
	situation = situation or {}
	mountType = mountType or {}
	if not requirePreferred then
		for _, mountID in ipairs(candidates) do
			local classified = types and types[mountID]
			if not classified or next(classified) == nil then
				return Draw(candidates, random), "all", candidates
			end
		end
	end

	local preferred, tier
	if situation.submerged then
		preferred = Bucket(candidates, types, mountType.Aquatic)
		tier = "aquatic"
	elseif situation.advancedFlyable then
		preferred = Bucket(candidates, types, mountType.Dragonriding)
		tier = "dragonriding"
		if #preferred == 0 then
			preferred = Bucket(candidates, types, mountType.Flying)
			tier = "flying"
		end
	elseif situation.flyable then
		preferred = Bucket(candidates, types, mountType.Flying)
		tier = "flying"
	else
		preferred = Bucket(candidates, types, mountType.Ground)
		tier = "ground"
	end

	if #preferred > 0 then
		return Draw(preferred, random), tier, preferred
	end
	if requirePreferred then
		return nil, tier, preferred
	end
	return Draw(candidates, random), "all", candidates
end

ns.MountPreference = MountPreference
return MountPreference
