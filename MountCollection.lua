local _, ns = ...

local Pins = ns.Pins or require("Pins")

-- Reads mounts used for linking and summoning.
local MountCollection = {}

function MountCollection.Attach(Addon)

local function MountPinDomain()
	return Pins.Domain(MogtrotDB, "mounts")
end

local function ActiveMountPins()
	local domain = MountPinDomain()
	if not domain then return {} end
	return Pins.ActiveSet(domain, time())
end

local MOUNT_TYPE = (Enum and Enum.MountType)
	or { Ground = 0, Flying = 1, Aquatic = 2, Dragonriding = 3, RideAlong = 4 }

local function MountTravelSnapshot()
	local types = {}
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local mountTypeID = select(5, C_MountJournal.GetMountInfoExtraByID(mountID))
		types[mountID] = ns.MountType.Classify(mountTypeID, MOUNT_TYPE)
	end
	local submerged = IsSubmerged("player")
	local advancedFlyable = IsAdvancedFlyableArea()
	local flyable = IsFlyableArea()
	return {
		types = types,
		situation = {
			swimming = IsSwimming("player"),
			submerged = submerged,
			advancedFlyable = advancedFlyable,
			flyable = flyable,
			drivable = IsDrivableArea(),
		},
		mountType = MOUNT_TYPE,
		requirePreferred = not submerged and (advancedFlyable or flyable),
	}
end

local function CollectMounts(chosenFor)
	local mounts = {}
	local pinned = ActiveMountPins()
	local linkCounts = {}
	for mountID, outfits in pairs(ns.OutfitLinks.IndexByLinked(MogtrotCharDB.mounts)) do
		linkCounts[mountID] = #outfits
	end
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local name, spellID, icon, _isActive, _isUsable, _sourceType, isFavorite,
			_isFactionSpecific, _faction, shouldHideOnChar, isCollected =
			C_MountJournal.GetMountInfoByID(mountID)

		if name and isCollected and not shouldHideOnChar then
			table.insert(mounts, {
				mountID = mountID, name = name, icon = icon, spellID = spellID,
				search = strlower(name),
				isFavorite = isFavorite,
				isPinned = pinned[mountID] and true or false,
				pairings = linkCounts[mountID] or 0,
			})
		end
	end

	ns.MountSort.Apply(mounts, {
		chosen = Addon:GetOutfitMounts(chosenFor),
	})
	return mounts
end
	return {
		Collect = CollectMounts,
		TravelSnapshot = MountTravelSnapshot,
	}
end

ns.MountCollection = MountCollection
return MountCollection
