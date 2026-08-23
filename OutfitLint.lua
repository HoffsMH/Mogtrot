local _, ns = ...

-- Checks how completely each saved outfit controls the character's visible gear.
-- A sweep briefly views each outfit, records its unset slots, then restores the view.
local OutfitLint = {}
local Lint = ns.Lint

OutfitLint.Colours = {
	full = { 0.3, 1, 0.3 },
	short = { 1, 0.82, 0 },
	unknown = { 0.45, 0.45, 0.45 },
}

local APPEARANCE_TYPE = (Enum and Enum.TransmogType and Enum.TransmogType.Appearance) or 0
local SWEEP_STEP_DELAY = 0.1
local SWEEP_TIMEOUT = 3.0
local sweepToken = 0

function OutfitLint.Build()
	return select(4, GetBuildInfo()) or 0
end

local DISPLAY_ENUM_NAMES = {
	UNASSIGNED = "Unassigned",
	ASSIGNED = "Assigned",
	EQUIPPED = "Equipped",
	HIDDEN = "Hidden",
	DISABLED = "Disabled",
}

local function CheckDisplayEnum(addon)
	local live = Enum and Enum.TransmogOutfitDisplayType
	if not live then return end

	for key, liveName in pairs(DISPLAY_ENUM_NAMES) do
		if live[liveName] ~= Lint.DISPLAY[key] then
			addon:WarnOnce("displayEnum", "this build numbers transmog slot states "
				.. "differently, so outfit completeness is not trustworthy here.")
			return
		end
	end
end

local function SlotDisplayName(slotInfo)
	local name = _G[slotInfo.slotName]
	if C_TransmogOutfitInfo.GetSecondarySlotState(slotInfo.slot) then
		if slotInfo.slot == Enum.TransmogOutfitSlot.ShoulderRight then
			name = RIGHTSHOULDERSLOT
		elseif slotInfo.slot == Enum.TransmogOutfitSlot.ShoulderLeft then
			name = LEFTSHOULDERSLOT
		end
	end
	return name or slotInfo.slotName
end

-- Artifact options are omitted because their spec-specific slots distort the count.
local function WeaponOptionsFor(slot)
	if not C_TransmogOutfitInfo.IsSlotWeaponSlot(slot) then return nil end
	local options = C_TransmogOutfitInfo.GetWeaponOptionsForSlot(slot)
	if not options then return nil end

	local out = {}
	for _, info in ipairs(options) do
		table.insert(out, {
			option = info.weaponOption,
			name = info.name,
			enabled = info.enabled,
		})
	end
	return out
end

local function CharacterSlotInfos()
	local groups = C_TransmogOutfitInfo.GetSlotGroupInfo()
	if not groups then return nil end

	local rangedShown = not C_PaperDollInfo or C_PaperDollInfo.IsRangedSlotShown()
	local infos = {}
	for _, group in ipairs(groups) do
		for _, slotInfo in ipairs(group.appearanceSlotInfo or {}) do
			if rangedShown or slotInfo.slotName ~= "RANGEDSLOT" then
				table.insert(infos, {
					slot = slotInfo.slot,
					name = SlotDisplayName(slotInfo),
					options = WeaponOptionsFor(slotInfo.slot),
				})
			end
		end
	end
	return infos
end

local function ReadViewedSlot(slot, option)
	local info = C_TransmogOutfitInfo.GetViewedOutfitSlotInfo(slot, APPEARANCE_TYPE, option)
	return info and info.displayType
end

function OutfitLint.MeasureViewed(addon)
	local char = MogtrotCharDB
	if not char or not char.slots then return end

	local outfitID = C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID()
	if not outfitID or outfitID == 0 then return end

	CheckDisplayEnum(addon)
	local record = Lint.Measure(Lint.SlotDefs(CharacterSlotInfos()), ReadViewedSlot,
		OutfitLint.Build())
	if not record then return end

	char.slots[outfitID] = record
	return outfitID, record
end

function OutfitLint.Record(outfitID)
	local char = MogtrotCharDB
	return char and char.slots and char.slots[outfitID]
end

function OutfitLint.MountCoverage(outfitID)
	local coverage = { ground = false, flying = false }
	local mounts = MogtrotCharDB and MogtrotCharDB.mounts
	for mountID in pairs((mounts and mounts[outfitID]) or {}) do
		local mountTypeID = select(5, C_MountJournal.GetMountInfoExtraByID(mountID))
		local types = ns.MountType.Classify(mountTypeID, Enum and Enum.MountType)
		if types then
			coverage.ground = coverage.ground or types[Enum.MountType.Ground] == true
			coverage.flying = coverage.flying or types[Enum.MountType.Flying] == true
		end
	end
	return coverage
end

function OutfitLint.State(outfitID)
	return Lint.State(OutfitLint.Record(outfitID), OutfitLint.Build(),
		OutfitLint.MountCoverage(outfitID))
end

function OutfitLint.AddTooltip(tooltip, outfitID)
	local record = OutfitLint.Record(outfitID)
	local coverage = OutfitLint.MountCoverage(outfitID)
	local state = Lint.State(record, OutfitLint.Build(), coverage)
	if state == "unknown" then
		tooltip:AddLine("Slots not checked yet", 0.6, 0.6, 0.6)
		tooltip:AddLine("Checked after login and when Blizzard's outfit list opens. "
			.. "/mogtrot slots scan does it now.", 0.5, 0.5, 0.5, true)
	else
		local colour = OutfitLint.Colours[state]
		tooltip:AddLine(("%d of %d slots set"):format(record.covered, record.total),
			colour[1], colour[2], colour[3])
		for _, line in ipairs(Lint.MissingLines(record)) do
			tooltip:AddLine(line, 1, 0.82, 0, true)
		end
	end

	local function AddMountLine(label, covered)
		local colour = covered and OutfitLint.Colours.full or OutfitLint.Colours.short
		tooltip:AddLine(label .. ": " .. (covered and "Yes" or "No"),
			colour[1], colour[2], colour[3])
	end
	AddMountLine("At least one ground mount chosen", coverage.ground)
	AddMountLine("At least one flying mount chosen", coverage.flying)
end

function OutfitLint.CanSweep()
	if InCombatLockdown() then return false, "you are in combat" end
	if C_TransmogOutfitInfo.InTransmogEvent() then
		return false, "Trial of Style is running"
	end
	if C_TransmogOutfitInfo.HasPendingOutfitTransmogs()
		or C_TransmogOutfitInfo.HasPendingOutfitSituations() then
		return false, "you have unsaved transmog changes"
	end
	return true
end

function OutfitLint.Begin(addon, all, verbose)
	if addon.sweep then return end
	local allowed, why = OutfitLint.CanSweep()
	if not allowed then
		if verbose then addon:Say("slot check skipped - %s.", why) end
		return
	end

	local outfits = C_TransmogOutfitInfo.GetOutfitsInfo()
	if not outfits or #outfits == 0 then return end

	local build, queue = OutfitLint.Build(), {}
	for _, info in ipairs(outfits) do
		if all or Lint.State(OutfitLint.Record(info.outfitID), build) == "unknown" then
			table.insert(queue, info.outfitID)
		end
	end
	if #queue == 0 then
		if verbose then addon:Say("every outfit has been checked already.") end
		return
	end

	sweepToken = sweepToken + 1
	addon.sweep = {
		token = sweepToken,
		queue = queue,
		index = 0,
		restore = C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID(),
	}
	local visible = TransmogFrame and TransmogFrame:IsShown()
	addon:Say("checking %d outfit%s for unset slots%s.", #queue,
		#queue == 1 and "" or "s", visible and " - the list flicks through them once" or "")
	OutfitLint.Step(addon)
end

function OutfitLint.Step(addon)
	local sweep = addon.sweep
	if not sweep then return end
	if sweep.expect and C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID() ~= sweep.expect then
		return OutfitLint.Abandon(addon, "the view changed")
	end
	if not OutfitLint.CanSweep() then
		return OutfitLint.Abandon(addon, "it is no longer safe")
	end

	sweep.index = sweep.index + 1
	local outfitID = sweep.queue[sweep.index]
	if not outfitID then return OutfitLint.Finish(addon) end
	sweep.expect = outfitID

	if C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID() == outfitID then
		OutfitLint.MeasureViewed(addon)
		return OutfitLint.Step(addon)
	end

	sweep.waiting = true
	C_TransmogOutfitInfo.ChangeViewedOutfit(outfitID)
	local token, step = sweep.token, sweep.index
	C_Timer.After(SWEEP_TIMEOUT, function()
		local current = addon.sweep
		if current and current.token == token and current.waiting and current.index == step then
			OutfitLint.Abandon(addon, "the client stopped answering")
		end
	end)
end

function OutfitLint.OnViewedSlotsReady(addon)
	local outfitID = OutfitLint.MeasureViewed(addon)
	local sweep = addon.sweep
	if not sweep then
		if outfitID then addon:Changed() end
		return
	end
	if not sweep.waiting then return end
	if outfitID and outfitID ~= sweep.expect then
		return OutfitLint.Abandon(addon, "the view changed")
	end

	sweep.waiting = false
	local token = sweep.token
	C_Timer.After(SWEEP_STEP_DELAY, function()
		if addon.sweep and addon.sweep.token == token then OutfitLint.Step(addon) end
	end)
end

function OutfitLint.Finish(addon)
	local sweep = addon.sweep
	addon.sweep = nil
	if not sweep then return end
	if sweep.restore and sweep.restore ~= 0 and sweep.expect
		and C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID() == sweep.expect then
		C_TransmogOutfitInfo.ChangeViewedOutfit(sweep.restore)
	end
	addon:Say("checked %d outfit%s.", #sweep.queue, #sweep.queue == 1 and "" or "s")
	addon:Changed()
end

function OutfitLint.Abandon(addon, why)
	local sweep = addon.sweep
	addon.sweep = nil
	if not sweep then return end
	addon:Say("slot check stopped after %d of %d - %s.",
		math.max(sweep.index - 1, 0), #sweep.queue, why or "cancelled")
	addon:Changed()
end

ns.OutfitLint = OutfitLint
return OutfitLint
