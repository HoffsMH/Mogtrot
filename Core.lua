local ADDON_NAME, ns = ...
if ns.Disabled then return end
local ACCOUNT_DB_NAME, CHAR_DB_NAME = ns.StartupGuard.DatabaseNames(ADDON_NAME)

-- Pure logic, listed before this file in the TOC. Everything here is the adapter:
-- frames, the WoW API, and LiteMount.
local Tree, Lint, Macro, Wear = ns.Tree, ns.Lint, ns.Macro, ns.Wear
local Addon, Database = ns.Addon, ns.Database
local OutfitLint, BlizzardOutfitUI = ns.OutfitLint, ns.BlizzardOutfitUI
local LINT_COLOURS = OutfitLint.Colours
local MountTravelSnapshot
local titleController
local previewUI
local frame
local NO_TRANSMOG = (Constants and Constants.Transmog and Constants.Transmog.NoTransmogID) or 0
local C_PetJournal, C_ToyBox, C_Item = _G.C_PetJournal, _G.C_ToyBox, _G.C_Item
local OutfitLinks = ns.OutfitLinks
local OutfitCandidates = ns.OutfitCandidates
local Pins = ns.Pins
local HearthstoneCollection = ns.HearthstoneCollection
local HearthstoneController = ns.HearthstoneController
local hearthstoneControllerDeps
local HearthstoneDefinitions = ns.HearthstoneDefinitions
local hearthstoneBaseline

local companionReady = false
local hearthstoneController
local hearthstonePinController

local function ReadActiveOutfitID()
	return C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetActiveOutfitID
		and C_TransmogOutfitInfo.GetActiveOutfitID() or nil
end

local function CurrentOutfitID()
	local outfitID = ReadActiveOutfitID()
	if outfitID == nil or outfitID == NO_TRANSMOG then return nil end
	return outfitID
end

local function HasActiveOutfit()
	return CurrentOutfitID() ~= nil
end

local function ScheduleRead(callback)
	C_Timer.After(0, callback)
end

local hearthstoneAdapter = {
	hasToy = function(itemID)
		return _G.PlayerHasToy and _G.PlayerHasToy(itemID) or false
	end,
	getToyInfo = function(itemID)
		if not (C_ToyBox and C_ToyBox.GetToyInfo) then return nil end
		local first, second, third, fourth = C_ToyBox.GetToyInfo(itemID)
		if type(first) == "number" then return second, third, fourth end
		return first, second, third
	end,
	itemCount = function(itemID)
		return C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID) or 0
	end,
	totalItemCount = function(itemID)
		return C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, true) or 0
	end,
	isUsable = function(itemID)
		return C_Item and C_Item.IsUsableItem and C_Item.IsUsableItem(itemID) or false
	end,
	getCooldown = function(itemID)
		if not (C_Item and C_Item.GetItemCooldown) then return nil, nil end
		return C_Item.GetItemCooldown(itemID)
	end,
	getItemName = function(itemID)
		return C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or nil
	end,
	getItemIcon = function(itemID)
		return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID) or nil
	end,
	-- GetItemSpell returns the spell name then its ID; both callers want one
	-- of the two and neither wants to remember the order.
	getItemSpellID = function(itemID)
		local fn = C_Item and C_Item.GetItemSpell
		if type(fn) ~= "function" then fn = _G.GetItemSpell end
		if type(fn) ~= "function" then return nil end
		local ok, _, spellID = pcall(fn, itemID)
		return ok and spellID or nil
	end,
	getItemSpell = function(itemID)
		local fn = C_Item and C_Item.GetItemSpell
		if type(fn) ~= "function" then fn = _G.GetItemSpell end
		if type(fn) ~= "function" then return nil end
		local ok, spellID = pcall(fn, itemID)
		return ok and spellID or nil
	end,
}

local function PinDomain(account, name)
	local pins = account and account.pins
	if type(pins) ~= "table" then return nil end
	local domain = pins[name]
	if type(domain) ~= "table" or type(domain.records) ~= "table"
		or domain.autoNew == nil or domain.days == nil then
		return nil
	end
	return domain
end

local function CompanionSchemaSupported(account, char)
	return type(account) == "table"
		and PinDomain(account, "hearthstones") ~= nil
		and type(char) == "table"
		and type(char.hearthstones) == "table"
		and type(char.pinOptOut) == "table"
		and type(char.pinOptOut.hearthstones) == "table"
		and type(char.rotations) == "table"
		and type(char.rotations.hearthstones) == "table"
end

local function RefreshCompanionPins()
	if not companionReady then return end
	local now = time()
	if hearthstoneControllerDeps then
		hearthstoneControllerDeps.pins =
			Pins.ActiveSet(PinDomain(MogtrotDB, "hearthstones"), now)
	end
end

local function OpenHearthstonePicker(outfitID)
	if companionReady and Addon.OpenHearthstonePicker then
		return Addon:OpenHearthstonePicker(outfitID)
	end
end

local function CountOutfitHearthstones(outfitID)
	if companionReady and Addon.CountOutfitHearthstones then
		return Addon:CountOutfitHearthstones(outfitID)
	end
	return nil
end

local function GetFirstHearthstoneIcon(outfitID)
	if companionReady and Addon.GetFirstHearthstoneIcon then
		return Addon:GetFirstHearthstoneIcon(outfitID)
	end
end

local hearthstoneControllerProxy = {
	PreClick = function()
		if hearthstoneController then
			RefreshCompanionPins()
			return hearthstoneController.PreClick()
		end
	end,
	PostClick = function()
		if hearthstoneController then return hearthstoneController.PostClick() end
	end,
}

local function MountPinDomain(account)
	local pins = account and account.pins
	if type(pins) ~= "table" then return nil end
	local domain = pins.mounts
	if type(domain) ~= "table" or type(domain.records) ~= "table"
		or domain.autoNew == nil or domain.days == nil then
		return nil
	end
	return domain
end

local mountPinController = ns.PinController.New(nil, {
	now = time,
	changed = function()
		if Addon.Changed then Addon:Changed() end
		if Addon.CompanionChoiceChanged then Addon:CompanionChoiceChanged() end
	end,
})

local EQUIP_SPELL_ID = 1247613
if Constants and Constants.TransmogOutfitDataConsts then
	EQUIP_SPELL_ID = Constants.TransmogOutfitDataConsts.EQUIP_TRANSMOG_OUTFIT_MANUAL_SPELL_ID or EQUIP_SPELL_ID
end

local eventFrame = CreateFrame("Frame")
Addon.eventFrame = eventFrame

-- Every line this addon writes to chat goes through one of these, so there is one
-- place to silence it and no message can be added without deciding who it is for.
--   Say   things the user asked for, or a change they need to know about
--   Warn  something failed and they have to act; never silenced
--   Debug developer detail, off unless /mogtrot debug is on

local CHAT_PREFIX = "|cff8ac6ffMogtrot|r: "

local function Format(fmt, ...)
	if select("#", ...) == 0 then return fmt end
	return fmt:format(...)
end

function Addon:Say(fmt, ...)
	if MogtrotDB and MogtrotDB.quiet then return end
	print(CHAT_PREFIX .. Format(fmt, ...))
end

function Addon:Warn(fmt, ...)
	print(CHAT_PREFIX .. Format(fmt, ...))
end

function Addon:Debug(fmt, ...)
	if not (MogtrotDB and MogtrotDB.debug) then return end
	print("|cff8ac6ffMogtrot|r |cff808080debug|r: " .. Format(fmt, ...))
end

-- For a warning that would otherwise repeat on every sync.
function Addon:WarnOnce(key, fmt, ...)
	self.warned = self.warned or {}
	if self.warned[key] then return end
	self.warned[key] = true
	self:Warn(fmt, ...)
end

function Addon:CreateCategory(name, parentID, beginRename)
	local id = Tree.CreateCategory(MogtrotCharDB,
		Tree.UniqueName(MogtrotCharDB, name or Tree.NEW_CATEGORY_NAME), parentID)

	-- Scroll back to it, or the refresh drops the rename it just started for a row
	-- that is not on screen. Only new roots need it; a sub-category lands next to
	-- the parent the user just clicked.
	if not parentID then
		self.scrollToTop = true
	end

	self.reveal = { kind = "cat", id = id }

	if beginRename then
		self.editing = id
		self.editingNeedsFocus = true
	end
	self:Changed()
	return id
end

function Addon:RenameCategory(catID, name)
	if not Tree.RenameCategory(MogtrotCharDB, catID, name) then return end
	self:Changed()
end

function Addon:DeleteCategory(catID)
	if not Tree.DeleteCategory(MogtrotCharDB, catID) then return end
	self:Changed()
end

-- A refused move is usually a no-op the user does not need told about. Being sent
-- inside itself is the one they aimed at and did not get.
local function ReportMoveRefusal(reason)
	if reason == "cycle" then
		UIErrorsFrame:AddMessage("Mogtrot: a category cannot be moved inside itself.", 1, 0.3, 0.3)
	end
end

function Addon:MoveCategory(catID, newParentID, index)
	local ok, reason = Tree.MoveCategory(MogtrotCharDB, catID, newParentID, index)
	if not ok then
		ReportMoveRefusal(reason)
		return
	end
	self:Changed()
end

function Addon:MoveCategoryBySteps(catID, delta)
	local ok, reason = Tree.MoveCategoryBySteps(MogtrotCharDB, catID, delta)
	if not ok then
		ReportMoveRefusal(reason)
		return
	end
	self:Changed()
end

function Addon:MoveOutfit(outfitID, toCatID, index)
	if not Tree.MoveOutfit(MogtrotCharDB, outfitID, toCatID, index) then return end
	self:Changed()
end

function Addon:MoveOutfitBySteps(outfitID, delta)
	if not Tree.MoveOutfitBySteps(MogtrotCharDB, outfitID, delta) then return end
	self:Changed()
end

-- Reconcile stored assignments with the outfits the server currently reports.
function Addon:SyncOutfits()
	local char = MogtrotCharDB
	local outfits = C_TransmogOutfitInfo.GetOutfitsInfo() or {}

	-- Never prune against an empty outfit list. If the API has not populated yet the
	-- pruning below would erase every assignment, captured look and linked mount
	-- on disk, so treat "no outfits" as "no information" instead.
	if #outfits == 0 then
		self.outfitsByID = self.outfitsByID or {}
		return
	end
	local unsortedID = Tree.FindUnsortedID(char)

	self.outfitsByID = {}
	for index, info in ipairs(outfits) do
		info.index = info.playerFacingOutfitIndex or index
		self.outfitsByID[info.outfitID] = info

		-- An outfit slot nobody has used is not an outfit and gets no row. It stays
		-- in outfitsByID so the rest of the addon can still name it and so the prune
		-- below reads it as present rather than deleted.
		if Tree.UntouchedSlot(char, info, TRANSMOG_OUTFIT_NAME_DEFAULT) then
			Tree.UnfileOutfit(char, info.outfitID)
		else
			local catID = char.assign[info.outfitID]
			if not catID or not char.cats[catID] then
				catID = unsortedID
				char.assign[info.outfitID] = catID
			end
			local items = char.cats[catID].items
			if not Tree.IndexInList(items, info.outfitID) then
				table.insert(items, info.outfitID)
			end
		end
	end

	-- Drop outfits that no longer exist (different character, deleted slot).
	for _, cat in pairs(char.cats) do
		for i = #cat.items, 1, -1 do
			if not self.outfitsByID[cat.items[i]] then
				char.assign[cat.items[i]] = nil
				table.remove(cat.items, i)
			end
		end
	end

	for outfitID in pairs(char.looks) do
		if not self.outfitsByID[outfitID] then
			char.looks[outfitID] = nil
		end
	end

	for outfitID in pairs(char.worn or {}) do
		if not self.outfitsByID[outfitID] then
			char.worn[outfitID] = nil
		end
	end

	for outfitID in pairs(char.mounts) do
		if not self.outfitsByID[outfitID] then
			char.mounts[outfitID] = nil
		end
	end

	for outfitID in pairs(char.slots) do
		if not self.outfitsByID[outfitID] then
			char.slots[outfitID] = nil
		end
	end
	if titleController then titleController:Clean(self.outfitsByID) end
end

-- searchText is already trimmed and lowercased by the search box, and nil when empty.
function Addon:BuildEntries()
	return Tree.BuildEntries(MogtrotCharDB, self.outfitsByID, self.searchText,
		MogtrotDB.hideEmptyCategories)
end

function Addon:MeasureViewedOutfit()
	return OutfitLint.MeasureViewed(self)
end

function Addon:LintRecord(outfitID)
	return OutfitLint.Record(outfitID)
end

function Addon:LintState(outfitID)
	return OutfitLint.State(outfitID)
end

function Addon:AddLintTooltip(tooltip, outfitID)
	return OutfitLint.AddTooltip(tooltip, outfitID)
end

function Addon:BeginLintSweep(all, verbose)
	return OutfitLint.Begin(self, all, verbose)
end

function Addon:OnViewedSlotsReady()
	return OutfitLint.OnViewedSlotsReady(self)
end

function Addon:AbandonLintSweep(why)
	return OutfitLint.Abandon(self, why)
end

function Addon:RefreshBlizzardDecorations()
	return BlizzardOutfitUI.Refresh()
end

function Addon:CanEditOutfitInfo()
	return BlizzardOutfitUI.CanEdit()
end

function Addon:OpenOutfitEditPopup(outfitID)
	return BlizzardOutfitUI.OpenEditor(self, outfitID)
end

-- Refresh both this window and the labels over in Blizzard's, since categorising
-- usually happens with the transmogrifier open.
function Addon:Changed()
	self:Refresh()
	self:RefreshBlizzardDecorations()
end

BlizzardOutfitUI.Initialize(Addon)

-- merge adds to whatever the target already has; without it the target's list is
-- replaced. The copy window offers both as separate confirm buttons, so the
-- destructive one is chosen at the moment of commitment.
function Addon:CopyMountsTo(fromOutfitID, toOutfitID, merge)
	local char = MogtrotCharDB
	local source = char.mounts[fromOutfitID]
	if not source or not next(source) then return end

	local had = self:CountOutfitMounts(toOutfitID)

	local result, added = {}, 0
	if merge then
		for mountID in pairs(char.mounts[toOutfitID] or {}) do result[mountID] = true end
	end
	for mountID in pairs(source) do
		if not result[mountID] then added = added + 1 end
		result[mountID] = true
	end

	char.mounts[toOutfitID] = result

	local total = 0
	for _ in pairs(result) do total = total + 1 end

	local target = self.outfitsByID and self.outfitsByID[toOutfitID]
	local name = target and target.name or tostring(toOutfitID)
	if merge then
		self:Say("added %d mount(s) to '%s' - %d in total.", added, name, total)
	elseif had > 0 then
		self:Say("'%s' now has %d mount(s), replacing the %d it had.", name, total, had)
	else
		self:Say("'%s' now has %d mount(s).", name, total)
	end

	self:Changed()
end


local ANNOUNCE_FORMATS = {
	"*changes into %s*",
	"*shimmers into %s*",
	"*swaps to %s*",
	"Behold: %s.",
	"*is now wearing %s*",
}

local WEAR_REQUEST_GUARD_SECONDS = 2

-- GetActiveOutfitID lags behind the click, so briefly remember our own request.
function Addon:CanWearNow(outfitID)
	if not outfitID or InCombatLockdown() then return false end
	if C_TransmogOutfitInfo.GetActiveOutfitID() == outfitID then return false end
	if self.lastWearRequest then
		local age = GetTime() - (self.lastWearRequestAt or 0)
		if age < WEAR_REQUEST_GUARD_SECONDS then return false end
		self.lastWearRequest = nil
		self.lastWearRequestAt = nil
	end
	return true
end

local function OutfitWear_PreClick(self, _button, down)
	if down then return end
	self.willWear = Addon:CanWearNow(self.outfitID)
end

local function OutfitWear_PostClick(self, _button, down)
	if down or not self.outfitID then return end
	if self.willWear then
		Addon.lastWearRequest = self.outfitID
		Addon.lastWearRequestAt = GetTime()
		titleController:OnOutfitClick(self.outfitID)
		if IsShiftKeyDown() then Addon:AnnounceOutfit(self.outfitID) end
	end
	self.willWear = nil
	Addon:ScheduleCapture()
end

titleController = ns.OutfitTitleController.Attach(Addon, {
	model = ns.OutfitTitles,
	picker = ns.OutfitTitlePicker,
	showOutfitPreview = function(owner, outfitID, label)
		previewUI.ShowSearchPickerPreview(owner, outfitID, label)
	end,
	hideOutfitPreview = function() previewUI.HideSearchPickerPreview() end,
})

local mainWindowUI = ns.MainWindowUI.Attach(Addon, {
	Tree = Tree,
	Macro = Macro,
	Wear = Wear,
	Lint = Lint,
	lintColours = LINT_COLOURS,
	equipSpellID = EQUIP_SPELL_ID,
	outfitWearPreClick = OutfitWear_PreClick,
	outfitWearPostClick = OutfitWear_PostClick,
	openTitlePicker = function(outfitID) titleController:OpenPicker(outfitID) end,
	countOutfitTitles = function(outfitID) return titleController:Count(outfitID) end,
	copyOutfitTitles = function(fromOutfitID, toOutfitID, merge)
		return titleController:Copy(fromOutfitID, toOutfitID, merge)
	end,
	clearOutfitTitles = function(outfitID) return titleController:Clear(outfitID) end,
	openHearthstonePicker = OpenHearthstonePicker,
	countOutfitHearthstones = CountOutfitHearthstones,
	getFirstHearthstoneIcon = GetFirstHearthstoneIcon,
	hearthstoneController = hearthstoneControllerProxy,
})
frame = mainWindowUI.frame
local AccountMacroCount = mainWindowUI.accountMacroCount
local minimapButton = ns.MinimapButton.Attach(Addon, {
	addonName = ADDON_NAME,
	frame = frame,
})

function Addon:AnnounceOutfit(outfitID)
	if MogtrotDB.announceEnabled == false then return end

	local info = self.outfitsByID and self.outfitsByID[outfitID]
	local name = info and info.name
	if not name or name == "" then return end

	-- Sent straight from the click rather than deferred to the swap, so the call
	-- stays inside the hardware event that triggered it.
	local template = ANNOUNCE_FORMATS[math.random(#ANNOUNCE_FORMATS)]
	SendChatMessage(template:format(name), "SAY")
end

previewUI = ns.OutfitPreviewUI.Attach(Addon, {
	mainWindow = frame,
})

ns.OutfitLibrarySyncAdapter.Attach(Addon)
ns.CustomSetLibrarySyncAdapter.Attach(Addon)

-- The wear capture feeds the docked preview only; the library reads looks.
ns.OutfitLookCapture.Attach(Addon, {
	onCaptured = function(outfitID)
		previewUI.OnCaptured(outfitID)
	end,
})

-- Keyed by outfitID, because outfit IDs are stable while names are not.
function Addon:GetOutfitMounts(outfitID)
	return MogtrotCharDB.mounts[outfitID] or {}
end

function Addon:CountOutfitMounts(outfitID)
	local n = 0
	for _ in pairs(self:GetOutfitMounts(outfitID)) do n = n + 1 end
	return n
end

function Addon:ToggleOutfitMount(outfitID, mountID)
	local mounts = MogtrotCharDB.mounts[outfitID] or {}
	local adding = not mounts[mountID]
	mounts[mountID] = adding or nil
	MogtrotCharDB.mounts[outfitID] = next(mounts) and mounts or nil

	self:Changed()
	self:CompanionChoiceChanged()
	if adding then self:NoticeSummonBindingOnce() end
end

function Addon:ClearOutfitMounts(outfitID)
	MogtrotCharDB.mounts[outfitID] = nil
	self:Changed()
	self:CompanionChoiceChanged()
end

-- Connects outfit changes to the wear time shown in the list and tooltip.
local wearSession

local function WearSession()
	if not wearSession then
		wearSession = Wear.NewSession(MogtrotCharDB.wear)
	elseif wearSession.store ~= MogtrotCharDB.wear then
		wearSession.store = MogtrotCharDB.wear
	end
	return wearSession
end

-- Which outfits still exist, for keeping a deleted one's hours out of the
-- arithmetic without deleting anything. An empty or absent list means "no
-- information yet" - the same reading SyncOutfits takes - and here that only
-- widens what is counted, never what is stored.
local function LiveOutfits(mb)
	local byID = mb.outfitsByID
	if byID and next(byID) then return byID end
	return nil
end

function Addon:WearSnapshot()
	return Wear.Snapshot(WearSession(), GetTime(), LiveOutfits(self))
end

-- What the summon and hearth keys draw from right now. Each mirrors the
-- OutfitCandidates.Resolve its own ladder makes - the same links, the same
-- pins, the same opt-out - so an icon can never disagree with its key about
-- what is in play, and an icon follows a ladder that changes its top rung.
--
-- Only that rung. Below it both ladders pick at random, and the mount one
-- falls through to random favourites, so there is nothing single to draw.
local function SummonCandidates(outfitID)
	local optOut = MogtrotCharDB.pinOptOut
	local links = MogtrotCharDB.mounts[outfitID]
	return OutfitCandidates.Resolve({
		links = links,
		pins = Pins.ActiveSet(MountPinDomain(MogtrotDB) or {}, time()),
		-- The mount ladder filters here, and account-wide pins make that
		-- matter: a mount learned on a Horde alt is hidden on this character
		-- and the key would never reach it. Usability is left out of the
		-- reading, because an icon that changed as you stepped into water
		-- would be noise on an action bar.
		isEligible = function(mountID)
			local name, _spellID, _icon, _isActive, _isUsable, _sourceType,
				_isFavorite, _isFactionSpecific, _faction, shouldHideOnChar,
				isCollected = C_MountJournal.GetMountInfoByID(mountID)
			return name ~= nil and isCollected and not shouldHideOnChar
		end,
		hasActiveOutfit = true,
		pinsOptOut = optOut and optOut.mounts and optOut.mounts[outfitID] and true or false,
		allowPinsWithoutOutfit = false,
	}), links
end

-- outfitID nil is a live case here, not a guard: hearth pins fire without an
-- outfit, and the key's own resolve says so.
local function HearthstoneCandidates(outfitID)
	local optOut = MogtrotCharDB.pinOptOut and MogtrotCharDB.pinOptOut.hearthstones
	local links = outfitID and MogtrotCharDB.hearthstones[outfitID] or nil
	return OutfitCandidates.Resolve({
		links = links,
		pins = Pins.ActiveSet(PinDomain(MogtrotDB, "hearthstones") or {}, time()),
		-- The hearth ladder merges only here and owns eligibility below, so
		-- reading it a second time would be a second answer to the same
		-- question. What it would drop is mostly cooldown anyway, and an icon
		-- that changed every time you hearthed would be the same noise.
		isEligible = function() return true end,
		hasActiveOutfit = outfitID ~= nil,
		pinsOptOut = outfitID and optOut and optOut[outfitID] and true or false,
		allowPinsWithoutOutfit = true,
	}), links
end

-- The icon a macro should be showing right now, or nil for a command whose
-- icon Mogtrot does not choose.
--
-- Summon and hearthstone stand for what their key would draw from: the
-- outfit's links by the same lowest-id rule the outfit row shows, and the
-- pins the key reaches for instead where the outfit has nothing linked. An
-- icon naming something the key will not do is worse than one that lags, and
-- a hearth pin firing under no outfit at all is the case a link-only reading
-- could not show.
function Addon.WantedMacroIcon(_self, command)
	local outfitID = CurrentOutfitID()

	if command == Macro.SUMMON then
		if not outfitID then return nil end
		local mountID = OutfitLinks.RepresentativePreferring(SummonCandidates(outfitID))
		if not mountID then return nil end
		return (select(3, C_MountJournal.GetMountInfoByID(mountID)))
	end

	if command == Macro.HEARTH then
		if not companionReady then return nil end
		local itemID = OutfitLinks.RepresentativePreferring(
			HearthstoneCandidates(outfitID))
		if not itemID then return nil end
		local entry = ns.HearthstoneDefinitions.Lookup(itemID)
		if not entry then return nil end
		if entry.kind == "toy" then
			return (select(2, hearthstoneAdapter.getToyInfo(itemID)))
		end
		return hearthstoneAdapter.getItemIcon(itemID)
	end

	return nil
end

-- The case UpdateWearTracking does not cover: the active outfit standing
-- still while what it would summon changes underneath it. Every link edit and
-- every pin edit calls this.
--
-- Not hung on Changed. Changed repaints and saves and most of its callers
-- cannot move an icon, while this walks the macro list once per command.
function Addon:CompanionChoiceChanged()
	if self.UpdateOwnedMacroIcons then self:UpdateOwnedMacroIcons() end
end

-- Idempotent for the outfit already open, so the second call from the login timer
-- cannot restart the interval and discard what it earned. Called wherever the
-- active outfit may have moved.
function Addon:UpdateWearTracking()
	Wear.Switch(WearSession(), C_TransmogOutfitInfo.GetActiveOutfitID(), GetTime(), time())
	-- The outfit moving is the whole reason the summon and hearthstone icons
	-- change. Writing one already correct is skipped further down, so this
	-- costs nothing when nothing moved.
	self:UpdateOwnedMacroIcons()
end

-- The gauge is rankable but not readable, so the figures live in the tooltip.
function Addon:AddWearTooltip(tooltip, outfitID)
	local session = WearSession()
	local snapshot = self:WearSnapshot()
	local seconds = snapshot.totals[outfitID] or 0

	if seconds <= 0 then
		tooltip:AddLine("Not worn since tracking started", 0.5, 0.5, 0.5)
		return
	end

	tooltip:AddLine(("Worn %s - %d%% of tracked time"):format(Wear.Format(seconds),
		math.floor(Wear.Share(snapshot.sum, seconds) * 100 + 0.5)), 0.5, 0.8, 1)

	if session.id == outfitID then
		tooltip:AddLine("Wearing it now", 0.5, 0.8, 1)
		return
	end

	local record = session.store[outfitID]
	if record and record.last then
		tooltip:AddLine(("Last worn %s ago"):format(Wear.Format(time() - record.last)),
			0.5, 0.8, 1)
	end
end

function Addon:WearReport()
	-- Reachable without ever opening the window, and the names come from here.
	self:SyncOutfits()

	local snapshot = self:WearSnapshot()
	if snapshot.count == 0 then
		self:Say("no outfit has been worn while Mogtrot was loaded yet.")
		return
	end

	self:Say("%s tracked across %d outfit(s).", Wear.Format(snapshot.sum), snapshot.count)

	for _, entry in ipairs(Wear.Top(snapshot, 10)) do
		local info = self.outfitsByID and self.outfitsByID[entry.outfitID]
		print(("  |cffffd100%s|r  %s  %d%%"):format(
			(info and info.name) or ("outfit " .. tostring(entry.outfitID)),
			Wear.Format(entry.seconds),
			math.floor(Wear.Share(snapshot.sum, entry.seconds) * 100 + 0.5)))
	end
end

local summon = ns.SummonController.Attach(Addon, {
	mountTravelSnapshot = function() return MountTravelSnapshot() end,
})
local summonController = summon.controller
local FALLBACK_MODES = summon.fallbackModes
local LiteMountFallbackAvailable = summon.liteMountFallbackAvailable

function Addon:LiteMountInstalled()
	return LiteMountFallbackAvailable()
end


local mountCollection = ns.MountCollection.Attach(Addon)
local MOUNT_TYPE_LABELS = mountCollection.TypeLabels
local ValidMountTypes = mountCollection.ValidTypes
local CollectMounts = mountCollection.Collect
MountTravelSnapshot = mountCollection.TravelSnapshot


ns.MountPickerUI.Attach(Addon, {
	mountTypeLabels = MOUNT_TYPE_LABELS,
	collectMounts = CollectMounts,
	validMountTypes = ValidMountTypes,
	buildDockGlow = previewUI.BuildDockGlow,
	applyMountEditDock = previewUI.ApplyMountEditDock,
	showEditPreview = previewUI.ShowEditPreview,
	hideEditPreview = previewUI.HideMountEditPreview,
	outfitWearPreClick = OutfitWear_PreClick,
	outfitWearPostClick = OutfitWear_PostClick,
})

function Addon:ApplyMountToOutfits(mountID, mountName, choices, chosen)
	local want = {}
	for _, choice in ipairs(chosen) do want[choice.outfitID] = true end

	local added, removed = 0, 0
	for _, choice in ipairs(choices) do
		local outfitID = choice.outfitID
		local mounts = MogtrotCharDB.mounts[outfitID]
		local has = mounts and mounts[mountID]

		if want[outfitID] and not has then
			mounts = mounts or {}
			mounts[mountID] = true
			MogtrotCharDB.mounts[outfitID] = mounts
			added = added + 1
		elseif has and not want[outfitID] then
			mounts[mountID] = nil
			MogtrotCharDB.mounts[outfitID] = next(mounts) and mounts or nil
			removed = removed + 1
		end
	end

	if added == 0 and removed == 0 then
		self:Say("nothing changed for %s.", mountName or "that mount")
		return
	end

	self:Say("%s: added to %d, removed from %d.", mountName or "mount", added, removed)
	self:Changed()
	self:CompanionChoiceChanged()
	if self:IsPickerOpen() then self:RepaintMountCards() end
end
function Addon:GetOutfitHearthstones(outfitID)
	if not companionReady or type(MogtrotCharDB) ~= "table" then return {} end
	return MogtrotCharDB.hearthstones[outfitID] or {}
end
function Addon:CountOutfitHearthstones(outfitID)
	if not companionReady then return 0 end
	return OutfitLinks.Count(MogtrotCharDB.hearthstones, outfitID)
end

function Addon:ToggleHearthstoneLink(outfitID, itemID)
	if not companionReady or not outfitID or not itemID then return false end
	local added = OutfitLinks.Toggle(MogtrotCharDB.hearthstones, outfitID, itemID)
	self:Changed()
	self:CompanionChoiceChanged()
	return added
end

function Addon:ApplyHearthstoneLinks(itemID, want)
	if not companionReady then return 0, 0 end
	local added, removed = OutfitLinks.Apply(MogtrotCharDB.hearthstones, itemID, want)
	self:Changed()
	self:CompanionChoiceChanged()
	return added, removed
end

function Addon:GetFirstHearthstoneIcon(outfitID)
	for itemID in pairs(self:GetOutfitHearthstones(outfitID)) do
		local icon = hearthstoneAdapter.getItemIcon(itemID)
		if icon then return icon end
	end
end

local function CompanionWarning(message)
	if UIErrorsFrame then
		UIErrorsFrame:AddMessage("Mogtrot: " .. message, 1, 0.3, 0.3)
	end
end

local function CompanionNotice(message)
	Addon:Say(message)
end

local function AttachCompanions(account, char)
	if not CompanionSchemaSupported(account, char) then return false end

	local hearthstoneDomain = PinDomain(account, "hearthstones")
	hearthstonePinController = ns.PinController.New(hearthstoneDomain, {
		now = time,
		changed = function()
			Addon:Changed()
			Addon:CompanionChoiceChanged()
		end,
	})

	local hearthButton = _G["MogtrotHearthstone"]
	if hearthButton and hearthButton.SetAttribute then
		hearthstoneControllerDeps = {
			registry = HearthstoneDefinitions,
			collection = HearthstoneCollection,
			adapter = hearthstoneAdapter,
			links = char.hearthstones,
			pins = {},
			pinsOptOut = char.pinOptOut.hearthstones,
			rotationStates = char.rotations.hearthstones,
			random = math.random,
			hasActiveOutfit = HasActiveOutfit,
			activeOutfitID = CurrentOutfitID,
			button = hearthButton,
			combat = InCombatLockdown,
			now = GetTime,
			warn = CompanionWarning,
			say = CompanionNotice,
		}
		hearthstoneController = HearthstoneController.New(hearthstoneControllerDeps)
	end

	companionReady = true
	RefreshCompanionPins()
	Addon:AttachHearthstones({
		registry = HearthstoneDefinitions,
		collection = HearthstoneCollection,
		adapter = hearthstoneAdapter,
		links = char.hearthstones,
		account = account,
		pinsDomain = "hearthstones",
		getLinks = function(outfitID) return Addon:GetOutfitHearthstones(outfitID) end,
		toggleLink = function(outfitID, itemID)
			return Addon:ToggleHearthstoneLink(outfitID, itemID)
		end,
		applyLinks = function(itemID, want)
			return Addon:ApplyHearthstoneLinks(itemID, want)
		end,
		getCurrentOutfit = CurrentOutfitID,
	})

	companionReady = true
	return true
end
local function ResetHearthstoneBaseline()
	if not companionReady then return end
	hearthstoneBaseline = HearthstoneCollection.Baseline(hearthstoneAdapter,
		HearthstoneDefinitions)
end

local function ScanHearthstoneAcquisitions()
	if not companionReady then return end
	if not hearthstoneBaseline then
		ResetHearthstoneBaseline()
		return
	end
	HearthstoneCollection.Acquisitions(hearthstoneAdapter, HearthstoneDefinitions,
		hearthstoneBaseline, function(itemID)
			hearthstonePinController:OnAcquired(itemID)
		end, function(itemID)
			return hearthstoneAdapter.hasToy(itemID)
		end)
end

ns.SettingsUI.Attach(Addon, {
	Wear = Wear,
	Lint = Lint,

	liteMountFallbackAvailable = LiteMountFallbackAvailable,
	fallbackModes = FALLBACK_MODES,
	frame = frame,
	titles = titleController,
	minimap = minimapButton,
})


eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4)
	local self = Addon
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		local account, char = Database.MigrateOrInit(_G[ACCOUNT_DB_NAME], _G[CHAR_DB_NAME])
		_G[ACCOUNT_DB_NAME], _G[CHAR_DB_NAME] = account, char
		MogtrotDB, MogtrotCharDB = account, char
		titleController:BindStores(MogtrotDB, MogtrotCharDB)
		mountPinController:BindDomain(MountPinDomain(MogtrotDB))
		minimapButton:Refresh()

		AttachCompanions(MogtrotDB, MogtrotCharDB)
		local pos = MogtrotDB.position
		if pos then
			frame:ClearAllPoints()
			frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
		end

		eventFrame:UnregisterEvent("ADDON_LOADED")
		eventFrame:RegisterEvent("TRANSMOG_OUTFITS_CHANGED")
		eventFrame:RegisterEvent("TRANSMOG_DISPLAYED_OUTFIT_CHANGED")
		eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		eventFrame:RegisterEvent("ITEM_COUNT_CHANGED")
		eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
		eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
		eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
		eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
		eventFrame:RegisterEvent("PLAYER_LOGOUT")
		eventFrame:RegisterEvent("NEW_MOUNT_ADDED")
		eventFrame:RegisterEvent("NEW_TOY_ADDED")
		eventFrame:RegisterEvent("TOYS_UPDATED")
		eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
		eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
		eventFrame:RegisterEvent("VIEWED_TRANSMOG_OUTFIT_SLOT_REFRESH")
		eventFrame:RegisterEvent("VIEWED_TRANSMOG_OUTFIT_SLOT_SAVE_SUCCESS")

	elseif event == "NEW_MOUNT_ADDED" then
		mountPinController:OnAcquired(arg1)

	elseif event == "NEW_TOY_ADDED" then
		if HearthstoneDefinitions.Lookup(arg1) and hearthstonePinController then
			hearthstonePinController:OnAcquired(arg1)
		end
		if hearthstoneBaseline then hearthstoneBaseline[arg1] = true end
		if Addon.IsHearthstonePickerOpen and Addon:IsHearthstonePickerOpen() then
			Addon:RefreshHearthstonePicker()
		end

	elseif event == "TOYS_UPDATED" or event == "BAG_UPDATE_DELAYED" then
		ScanHearthstoneAcquisitions()
		if Addon.IsHearthstonePickerOpen and Addon:IsHearthstonePickerOpen() then
			Addon:RefreshHearthstonePicker()
		end

	elseif event == "UNIT_SPELLCAST_SENT" then
		if not (issecretvalue(arg3) or issecretvalue(arg4)) then
			summonController:Transition({ type = "cast-sent", spellID = arg4, castGUID = arg3 })
		end

	elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		-- START consumes normally. SUCCEEDED covers instant casts that have no START.
		if not (issecretvalue(arg2) or issecretvalue(arg3)) then
			summonController:Transition({
				type = event == "UNIT_SPELLCAST_START" and "cast-start" or "cast-succeeded",
				spellID = arg3, castGUID = arg2, now = GetTime(),
			})
		end

	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET"
		or event == "UNIT_SPELLCAST_INTERRUPTED" then
		if not (issecretvalue(arg2) or issecretvalue(arg3)) then
			summonController:Transition({ type = "cast-failed", spellID = arg3, castGUID = arg2 })
		end

	elseif event == "VIEWED_TRANSMOG_OUTFIT_SLOT_REFRESH" then
		-- Not a synchronous event, and the point at which Blizzard's own preview reads
		-- its slots, so the data really is there.
		self:OnViewedSlotsReady()

	elseif event == "VIEWED_TRANSMOG_OUTFIT_SLOT_SAVE_SUCCESS" then
		-- Synchronous, so the save has not landed yet. Re-measure on the next frame,
		-- which is what keeps an outfit's count honest while it is being edited.
		C_Timer.After(0, function()
			if Addon.sweep then return end
			if Addon:MeasureViewedOutfit() then
				BlizzardOutfitUI.CaptureViewedLook(Addon)
				Addon:Changed()
			end
		end)

	elseif event == "SPELL_UPDATE_COOLDOWN" then
		if frame:IsShown() then self:UpdateCooldowns() end
		if Addon.IsHearthstonePickerOpen and Addon:IsHearthstonePickerOpen() then
			Addon:RefreshHearthstonePicker()
		end

	elseif event == "ITEM_COUNT_CHANGED" or event == "BAG_UPDATE_COOLDOWN"
		or event == "SPELL_UPDATE_USABLE" then
		if Addon.IsHearthstonePickerOpen and Addon:IsHearthstonePickerOpen() then
			Addon:RefreshHearthstonePicker()
		end

	elseif event == "TRANSMOG_DISPLAYED_OUTFIT_CHANGED" then
		-- Synchronous event: the swap has not settled yet, so defer both the capture
		-- and the refresh rather than reading state inline.
		RefreshCompanionPins()
		self:ScheduleCapture()
		C_Timer.After(0, function()
			-- Before the refresh, so rows paint against the interval that is open
			-- now rather than the one that has just closed.
			Addon:UpdateWearTracking()
			Addon:Refresh()
		end)

	elseif event == "PLAYER_ENTERING_WORLD" then
		-- Time-based, so login is the only moment it can have moved. Nothing
		-- schedules a sweep: a timer for something measured in days would
		-- only be a callback waiting to go stale.
		local library = MogtrotDB and MogtrotDB.library
		if library and ns.Library.EvictArchived then
			ns.Library.EvictArchived(library, MogtrotDB.archiveDays, time())
		end
		-- Prepare the hidden list so the secure toggle can reveal it during combat.
		C_Timer.After(0, ResetHearthstoneBaseline)
		C_Timer.After(0, function()
			if not InCombatLockdown() then Addon:Refresh(true) end
		end)
		-- Twice, because GetActiveOutfitID may not answer yet at the end of a
		-- loading screen and a login that read nil would then accrue nothing until
		-- the next outfit change - which for someone who logs in wearing an outfit
		-- and never switches is never. The second call is a no-op if the first
		-- worked; it cannot restart an interval already open on the same outfit.
		Addon:UpdateWearTracking()
		C_Timer.After(5, function() Addon:UpdateWearTracking() end)

		C_Timer.After(5, function() Addon:CaptureActiveLook() end)
		C_Timer.After(5, function()
			-- Covers the user who linked their mounts while LiteMount was installed
			-- and then removed it. Nothing on the linking path will fire for them
			-- again, and they are exactly who needs to hear about the key.
			if next(MogtrotCharDB.mounts or {}) then Addon:NoticeSummonBindingOnce() end
		end)
		-- Verified in game: the scan does not need Blizzard's window open, so it
		-- runs on its own after login and the counts are simply there. Late enough
		-- that it is not competing with everything else loading.
		C_Timer.After(8, function() OutfitLint.BeginAtLogin(Addon) end)
		Addon:RegisterSettings()
		Addon:UpdateOwnedMacroIcons()
		Addon:RepairSummonMacro()

	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Wearing an outfit is refused in combat, so the list stops offering it.
		self:SetEscapeClosing(false)
		self:CancelEdit()
		self:SetCombatDimmed(true)
		self:AbandonLintSweep("combat started")

	elseif event == "PLAYER_REGEN_ENABLED" then
		self:SetEscapeClosing(true)
		self:SetCombatDimmed(false)
		self:UpdateOwnedMacroIcons()
	elseif event == "PLAYER_LOGOUT" then
		summonController:Transition({ type = "clear" })
		-- Logging out, /reload and a disconnect all arrive here, and the saved
		-- variables are written afterwards. This is the only thing that turns the
		-- open interval into stored seconds, and it is the only branch that must
		-- not refresh: there is no window left to paint.
		Wear.Close(WearSession(), GetTime(), time())

	elseif event == "TRANSMOG_OUTFITS_CHANGED" then
		-- The list changing under a scan invalidates the queue it is working from.
		self:AbandonLintSweep("the outfit list changed")
		self:Refresh()
	else
		self:Refresh()
	end
end)

ns.Commands.Register(Addon, {
	frame = frame,
	diagnostics = ns.Diagnostics,
	captureModel = ns.OutfitLookCapture.GetModel,
	noTransmog = NO_TRANSMOG,
	Wear = Wear,
	wearSession = WearSession,
	liteMountFallbackAvailable = LiteMountFallbackAvailable,
	fallbackModes = FALLBACK_MODES,
	Macro = Macro,
	accountMacroCount = AccountMacroCount,
	hearthstoneDefinitions = HearthstoneDefinitions,
	hearthstoneAdapter = hearthstoneAdapter,
})
