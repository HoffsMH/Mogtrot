local _, ns = ...

-- Reads mounts used by linking, filtering, and summoning.
local MountCollection = {}

function MountCollection.Attach(Addon)

local MOUNT_TYPE = (Enum and Enum.MountType)
	or { Ground = 0, Flying = 1, Aquatic = 2, Dragonriding = 3, RideAlong = 4 }

local MOUNT_TYPE_LABELS = {
	[MOUNT_TYPE.Ground] = MOUNT_JOURNAL_FILTER_GROUND or "Ground",
	[MOUNT_TYPE.Flying] = MOUNT_JOURNAL_FILTER_FLYING or "Flying",
	[MOUNT_TYPE.Aquatic] = MOUNT_JOURNAL_FILTER_AQUATIC or "Aquatic",
	[MOUNT_TYPE.Dragonriding] = MOUNT_JOURNAL_FILTER_DRAGONRIDING or "Skyriding",
	[MOUNT_TYPE.RideAlong] = MOUNT_JOURNAL_FILTER_RIDEALONG or "Ride along",
}

local COLLECTED_FILTERS = {
	{ setting = LE_MOUNT_JOURNAL_FILTER_COLLECTED, wanted = true },
	{ setting = LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED, wanted = false },
	{ setting = LE_MOUNT_JOURNAL_FILTER_UNUSABLE, wanted = true },
}

local function SkyridingMounts()
	local get = C_MountJournal.GetCollectedDragonridingMounts
	return (get and get()) or {}
end

local function ValidTypeFilters()
	local filters = {}
	local meta = Enum and Enum.MountTypeMeta
	for filterIndex = 1, (meta and meta.NumValues) or 0 do
		if C_MountJournal.IsValidTypeFilter(filterIndex) then
			table.insert(filters, filterIndex)
		end
	end
	return filters
end

local function ValidMountTypes()
	local seen, values = {}, {}
	for _, filterIndex in ipairs(ValidTypeFilters()) do
		seen[filterIndex - 1] = true
	end
	if #SkyridingMounts() > 0 then seen[MOUNT_TYPE.Dragonriding] = true end

	for value in pairs(seen) do table.insert(values, value) end
	table.sort(values)
	return values
end

local function MountJournalOnScreen()
	for _, name in ipairs({ "CollectionsJournal", "MountJournal" }) do
		local frame = _G[name]
		if frame and frame.IsVisible and frame:IsVisible() then return true end
	end
	return false
end

local function WalkMountTypes()
	local filters = ValidTypeFilters()
	if #filters == 0 then return nil end

	local savedTypes = {}
	for _, filterIndex in ipairs(filters) do
		savedTypes[filterIndex] = C_MountJournal.IsTypeChecked(filterIndex)
	end

	local savedCollected = {}
	for _, entry in ipairs(COLLECTED_FILTERS) do
		if entry.setting then
			savedCollected[entry.setting] =
				C_MountJournal.GetCollectedFilterSetting(entry.setting)
		end
	end

	local savedSources = {}
	local sourceMeta = Enum and Enum.BattlePetSourcesMeta
	for filterIndex = 1, (sourceMeta and sourceMeta.NumValues) or 0 do
		if C_MountJournal.IsValidSourceFilter(filterIndex) then
			savedSources[filterIndex] = C_MountJournal.IsSourceChecked(filterIndex)
		end
	end

	local types = {}
	local ok, err = pcall(function()
		for _, entry in ipairs(COLLECTED_FILTERS) do
			if entry.setting then
				C_MountJournal.SetCollectedFilterSetting(entry.setting, entry.wanted)
			end
		end
		for filterIndex in pairs(savedSources) do
			C_MountJournal.SetSourceFilter(filterIndex, true)
		end

		for _, filterIndex in ipairs(filters) do
			for _, other in ipairs(filters) do
				C_MountJournal.SetTypeFilter(other, other == filterIndex)
			end

			local value = filterIndex - 1
			for displayIndex = 1, C_MountJournal.GetNumDisplayedMounts() do
				local mountID = C_MountJournal.GetDisplayedMountID(displayIndex)
				if mountID then
					local set = types[mountID]
					if not set then
						set = {}
						types[mountID] = set
					end
					set[value] = true
				end
			end
		end
	end)

	for filterIndex, checked in pairs(savedSources) do
		C_MountJournal.SetSourceFilter(filterIndex, checked)
	end
	for _, filterIndex in ipairs(filters) do
		C_MountJournal.SetTypeFilter(filterIndex, savedTypes[filterIndex])
	end
	for setting, checked in pairs(savedCollected) do
		C_MountJournal.SetCollectedFilterSetting(setting, checked)
	end

	if not ok then
		Addon:Warn("could not read mount types: %s", tostring(err))
		return nil
	end
	return types
end

local mountTypes, mountTypesBroken

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

local NO_TYPES_NOTE = "Mount types are unavailable this session."
local JOURNAL_OPEN_NOTE = "Close the Mount Journal, then reopen this window, to filter by type."

local function MountTypesFor(collectedIDs)
	if mountTypes then return mountTypes end
	if mountTypesBroken then return nil, NO_TYPES_NOTE end
	if MountJournalOnScreen() then return nil, JOURNAL_OPEN_NOTE end

	local types = WalkMountTypes()
	if not types then return nil, NO_TYPES_NOTE end

	ns.MountFilter.InjectType(types, SkyridingMounts(), MOUNT_TYPE.Dragonriding)
	local ok, reason, unknown = ns.MountFilter.Verify(types, collectedIDs)

	if not ok then
		mountTypesBroken = true
		Addon:WarnOnce("mountTypes", "could not classify mounts (%s), so the type filters "
			.. "are off for this session.", tostring(reason))
		return nil, NO_TYPES_NOTE
	end

	if unknown == 0 then mountTypes = types end
	return types
end

function Addon:ReportMountTypes()
	if MountJournalOnScreen() then
		self:Debug("the Mount Journal is open, and the walk is skipped while it is")
		return
	end

	local collectedIDs = {}
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local name, _sp, _ic, _ac, _us, _so, _fv, _fs, _fc, hidden, collected =
			C_MountJournal.GetMountInfoByID(mountID)
		if name and collected and not hidden then
			table.insert(collectedIDs, mountID)
		end
	end

	mountTypes, mountTypesBroken = nil, nil
	local started = debugprofilestop()
	local types = WalkMountTypes()
	local elapsed = debugprofilestop() - started
	if not types then
		self:Debug("the walk returned nothing")
		return
	end

	local skyriding = SkyridingMounts()
	local walked = ns.MountFilter.OverlapCount(types, skyriding, MOUNT_TYPE.Dragonriding)
	local asFlying = ns.MountFilter.OverlapCount(types, skyriding, MOUNT_TYPE.Flying)
	ns.MountFilter.InjectType(types, skyriding, MOUNT_TYPE.Dragonriding)
	local ok, reason, unknown = ns.MountFilter.Verify(types, collectedIDs)

	local counts = {}
	for _, set in pairs(types) do
		for value in pairs(set) do counts[value] = (counts[value] or 0) + 1 end
	end
	for _, value in ipairs(ValidMountTypes()) do
		self:Debug("%s: %d", MOUNT_TYPE_LABELS[value] or tostring(value), counts[value] or 0)
	end

	self:Debug("%d collected, %d unplaced, walk took %.0f ms", #collectedIDs, unknown, elapsed)
	self:Debug("skyriding: %d in Blizzard's list, %d of them walked into Skyriding, "
		.. "%d into Flying", #skyriding, walked, asFlying)
	self:Debug("verdict: %s", ok and "usable" or ("rejected - " .. tostring(reason)))

	if ok and unknown == 0 then
		mountTypes = types
	else
		mountTypesBroken = not ok
	end
end

local function CollectMounts(chosenFor)
	local mounts = {}
	local collectedIDs = {}
	local pinned = ns.MountPins.ActiveSet(MogtrotDB, time())
	local linkCounts = {}
	for mountID, outfits in pairs(ns.MountIndex.Build(MogtrotCharDB)) do
		linkCounts[mountID] = #outfits
	end
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local name, spellID, icon, _isActive, _isUsable, _sourceType, isFavorite,
			_isFactionSpecific, _faction, shouldHideOnChar, isCollected =
			C_MountJournal.GetMountInfoByID(mountID)

		if name and isCollected and not shouldHideOnChar then
			table.insert(collectedIDs, mountID)
			table.insert(mounts, {
				mountID = mountID, name = name, icon = icon, spellID = spellID,
				search = strlower(name),
				isFavorite = isFavorite,
				isPinned = pinned[mountID] and true or false,
				pairings = linkCounts[mountID] or 0,
			})
		end
	end
	local types, typeNote = MountTypesFor(collectedIDs)
	if types then
		for _, mount in ipairs(mounts) do
			mount.types = types[mount.mountID]
		end
	end

	ns.MountSort.Apply(mounts, {
		chosen = Addon:GetOutfitMounts(chosenFor),
	})
	return mounts, typeNote
end
	return {
		TypeLabels = MOUNT_TYPE_LABELS,
		ValidTypes = ValidMountTypes,
		Collect = CollectMounts,
		TravelSnapshot = MountTravelSnapshot,
	}
end

ns.MountCollection = MountCollection
return MountCollection
