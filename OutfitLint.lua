local _, ns = ...

-- Checks how completely each saved outfit controls the character's visible gear.
-- A sweep briefly views each outfit, records its unset slots, then restores the view.
local OutfitLint = {}
local Lint = ns.Lint
local LookCodec = ns.LookCodec or require("LookCodec")

OutfitLint.Colours = {
	full = { 0.3, 1, 0.3 },
	short = { 1, 0.82, 0 },
	unknown = { 0.45, 0.45, 0.45 },
}

local APPEARANCE_TYPE = (Enum and Enum.TransmogType and Enum.TransmogType.Appearance) or 0
local ASSIGNED = (Enum and Enum.TransmogOutfitDisplayType
	and Enum.TransmogOutfitDisplayType.Assigned) or 1
local HIDDEN = (Enum and Enum.TransmogOutfitDisplayType
	and Enum.TransmogOutfitDisplayType.Hidden) or 3
local SWEEP_STEP_DELAY = 0.1
local SWEEP_TIMEOUT = 3.0
local SLOT_SETTLE_DELAY = 0.2
-- An outfit not yet viewed this session answers with most slots unassigned
-- until its data lands, which can be after the slot refresh. The sweep keeps
-- a read only once two reads this far apart agree.
local CONFIRM_DELAY = 0.5
local CONFIRM_TRIES = 6
local sweepToken = 0
local slotReadyToken = 0

function OutfitLint.Build()
	return select(4, GetBuildInfo()) or 0
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

local function MeasureRecord()
	return Lint.Measure(Lint.SlotDefs(CharacterSlotInfos()), ReadViewedSlot,
		OutfitLint.Build())
end

function OutfitLint.MeasureViewed(_addon)
	local char = MogtrotCharDB
	if not char or not char.slots then return end

	local outfitID = C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID()
	if not outfitID or outfitID == 0 then return end

	local record = MeasureRecord()
	if not record then return end

	char.slots[outfitID] = record
	return outfitID, record
end

-- The option Blizzard's window opens a weapon slot on: the one the equipped
-- weapon selects, else the first enabled one.
local function WeaponOption(slot)
	local api = C_TransmogOutfitInfo
	if not api.IsSlotWeaponSlot(slot) then return Lint.OPTION_NONE end
	local options = api.GetWeaponOptionsForSlot(slot) or {}
	local equipped = api.GetEquippedSlotOptionFromTransmogSlot(slot)
	local first
	for _, info in ipairs(options) do
		if info.enabled then
			if info.weaponOption == equipped then return equipped end
			first = first or info.weaponOption
		end
	end
	return first or Lint.OPTION_NONE
end

-- The viewed outfit's slot infos per inventory slot, read through the API so
-- Blizzard's window need not be open. Same parts BlizzardOutfitUI.CaptureViewedLook
-- reads from the window's slot frames.
local function ViewedSlotEntries()
	local api = C_TransmogOutfitInfo
	local groups = api.GetSlotGroupInfo()
	if not groups then return nil end
	local rangedShown = C_PaperDollInfo.IsRangedSlotShown()

	local entries, bySlot = {}, {}
	for _, group in ipairs(groups) do
		for _, info in ipairs(group.appearanceSlotInfo or {}) do
			if not info.isSecondary and (rangedShown or info.slotName ~= "RANGEDSLOT") then
				local option = WeaponOption(info.slot)
				local entry = {
					slotID = C_PaperDollInfo.GetInventorySlotInfo(info.slotName),
					option = option,
					primary = api.GetViewedOutfitSlotInfo(info.slot, APPEARANCE_TYPE, option),
				}
				local linked = api.GetLinkedSlotInfo(info.slot)
				if linked and linked.primarySlotInfo.slot == info.slot then
					entry.secondary = api.GetViewedOutfitSlotInfo(linked.secondarySlotInfo.slot,
						linked.secondarySlotInfo.type, option)
				end
				entries[#entries + 1] = entry
				bySlot[info.slot] = entry
			end
		end
	end
	for _, group in ipairs(groups) do
		for _, info in ipairs(group.illusionSlotInfo or {}) do
			local entry = bySlot[info.slot]
			if entry then
				entry.illusion = api.GetViewedOutfitSlotInfo(info.slot, info.type, entry.option)
			end
		end
	end
	return entries
end

-- The viewed outfit's definition and slot record, stored nowhere.
local function ReadViewed()
	local outfitID = C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID()
	if not outfitID or outfitID == 0 then return nil end
	local entries = ViewedSlotEntries()
	local look = entries and #entries > 0 and LookCodec.FromSlotInfos(entries, ASSIGNED, HIDDEN) or nil
	return {
		outfitID = outfitID,
		look = look,
		text = look and LookCodec.Encode(look),
		record = MeasureRecord(),
	}
end

local function SameRead(a, b)
	return a.outfitID == b.outfitID and a.text == b.text
		and (a.record and a.record.covered) == (b.record and b.record.covered)
end

-- True when look leaves empty a part that stored fills.
function OutfitLint.DropsParts(stored, look)
	if type(stored) ~= "table" or type(look) ~= "table" then return false end
	for slot, parts in pairs(stored) do
		if type(parts) == "table" then
			local now = type(look[slot]) == "table" and look[slot] or {}
			for i = 1, 3 do
				if (tonumber(parts[i]) or 0) > 0 and (tonumber(now[i]) or 0) <= 0 then
					return true
				end
			end
		end
	end
	return false
end

local function Pending(char)
	char.lookPending = char.lookPending or {}
	return char.lookPending
end

-- A settled read that drops parts of the stored definition is also what a
-- read that never landed looks like, so it replaces the stored one only when
-- a later sweep reads the same thing.
local function Commit(sweep, read)
	local char = MogtrotCharDB
	if not char or not char.looks or not char.slots then return end
	local id, pending = read.outfitID, Pending(char)
	if not read.look then return end
	if OutfitLint.DropsParts(char.looks[id], read.look) and pending[id] ~= read.text then
		pending[id] = read.text
		return
	end
	pending[id] = nil
	if read.record then char.slots[id] = read.record end
	char.looks[id] = read.look
	sweep.stored = true
end

local function Next(addon)
	local token = addon.sweep.token
	C_Timer.After(SWEEP_STEP_DELAY, function()
		if addon.sweep and addon.sweep.token == token then OutfitLint.Step(addon) end
	end)
end

-- Reads until two reads CONFIRM_DELAY apart agree. One that never settles is
-- left for the next sweep, keeping what is stored.
local function Confirm(addon, previous, tries)
	local sweep = addon.sweep
	if not sweep then return end
	local read = ReadViewed()
	if not read or read.outfitID ~= sweep.expect then
		return OutfitLint.Abandon(addon, "the view changed")
	end
	if previous and SameRead(previous, read) then
		Commit(sweep, read)
		return Next(addon)
	end
	if tries >= CONFIRM_TRIES then
		if MogtrotCharDB then Pending(MogtrotCharDB)[read.outfitID] = true end
		return Next(addon)
	end
	local token, step = sweep.token, sweep.index
	C_Timer.After(CONFIRM_DELAY, function()
		local current = addon.sweep
		if current and current.token == token and current.index == step then
			Confirm(addon, read, tries + 1)
		end
	end)
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
		tooltip:AddLine("Checked shortly after login, or when you view it in "
			.. "Blizzard's outfit list.", 0.5, 0.5, 0.5, true)
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

function OutfitLint.Begin(addon, all)
	if addon.sweep then return end
	if not OutfitLint.CanSweep() then return end

	local outfits = C_TransmogOutfitInfo.GetOutfitsInfo()
	if not outfits or #outfits == 0 then return end

	local char = MogtrotCharDB
	local looks = char and char.looks or {}
	local pending = char and char.lookPending or {}
	all = all or (char and char.rereadLooks == true)
	local build, queue = OutfitLint.Build(), {}
	for _, info in ipairs(outfits) do
		if all or looks[info.outfitID] == nil or pending[info.outfitID] ~= nil
			or Lint.State(OutfitLint.Record(info.outfitID), build) == "unknown" then
			table.insert(queue, info.outfitID)
		end
	end
	if #queue == 0 then return end

	sweepToken = sweepToken + 1
	addon.sweep = {
		token = sweepToken,
		queue = queue,
		index = 0,
		restore = C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID(),
	}
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
		return Confirm(addon, nil, 0)
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

local function ProcessViewedSlotsReady(addon)
	local sweep = addon.sweep
	if not sweep then
		local outfitID = OutfitLint.MeasureViewed(addon)
		if outfitID and ns.BlizzardOutfitUI then
			ns.BlizzardOutfitUI.CaptureViewedLook(addon)
		end
		if outfitID then addon:Changed() end
		return
	end
	if not sweep.waiting then return end
	sweep.waiting = false
	Confirm(addon, nil, 0)
end

function OutfitLint.DebounceViewedSlotsReady(addon, after, process)
	slotReadyToken = slotReadyToken + 1
	local token = slotReadyToken
	process = process or ProcessViewedSlotsReady
	after(SLOT_SETTLE_DELAY, function()
		if token == slotReadyToken then process(addon) end
	end)
end

function OutfitLint.OnViewedSlotsReady(addon)
	OutfitLint.DebounceViewedSlotsReady(addon, C_Timer.After)
end

function OutfitLint.Finish(addon)
	local sweep = addon.sweep
	addon.sweep = nil
	if not sweep then return end
	if sweep.restore and sweep.restore ~= 0 and sweep.expect
		and C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID() == sweep.expect then
		C_TransmogOutfitInfo.ChangeViewedOutfit(sweep.restore)
	end
	if MogtrotCharDB then MogtrotCharDB.rereadLooks = nil end
	if sweep.stored and addon.SyncOutfitLibrary then
		addon.SyncOutfitLibrary()
	end
	addon:Changed()
end

-- The sweep after a loading screen. Not inside an instance, so it never runs
-- on a dungeon's loading screen; leaving the instance is another loading
-- screen, which runs it then.
function OutfitLint.BeginAtLogin(addon)
	if IsInInstance() then return end
	return OutfitLint.Begin(addon, false)
end

-- why names the cause at the call site; nothing reports it.
function OutfitLint.Abandon(addon, _why)
	local sweep = addon.sweep
	addon.sweep = nil
	if not sweep then return end
	addon:Changed()
end

ns.OutfitLint = OutfitLint
return OutfitLint
