local _, ns = ...

local MountPickerUI = {}

function MountPickerUI.Attach(Addon, deps)
	local UI = ns.UI
	local MOUNT_TYPE_LABELS = deps.mountTypeLabels
	local CollectMounts = deps.collectMounts
	local ValidMountTypes = deps.validMountTypes
	local BuildDockGlow = deps.buildDockGlow
	local ApplyMountEditDock = deps.applyMountEditDock
	local ShowMountEditPreview = deps.showMountEditPreview
	local HideMountEditPreview = deps.hideMountEditPreview
	local OutfitWear_PreClick = deps.outfitWearPreClick
	local OutfitWear_PostClick = deps.outfitWearPostClick
	local mountPicker

-- The picker shows a three-by-three grid; resizing changes the cards, not the count.
local GRID_COLS = 3
local GRID_ROWS = 3
local CARD_W = 210
local CARD_H = 226
local CARD_GAP = 10
local GRID_PAD = 8
local CARD_LINK_COLUMNS = 2
local CARD_LINK_ROWS = 3
local CARD_LINK_ICONS = CARD_LINK_COLUMNS * CARD_LINK_ROWS
local CARD_NUDGE = 40
local PICKER_HEADER = 72
local PICKER_FOOTER = 26
local PICKER_BAR_GUTTER = 24
local PICKER_BAR_GAP = 8
local PICKER_HEADER_CONTROL_H = 26

local PICKER_MIN_SCALE = 1
local PICKER_MAX_SCALE = 1.8

local function PickerScale()
	local scale = MogtrotDB.pickerScale or 1
	return math.max(PICKER_MIN_SCALE, math.min(scale, PICKER_MAX_SCALE))
end

local function CardSize()
	local scale = PickerScale()
	return math.floor(CARD_W * scale), math.floor(CARD_H * scale)
end

local function PickerSize()
	local cardW, cardH = CardSize()
	return UI.Pad * 2 + GRID_PAD * 2 + GRID_COLS * cardW
			+ (GRID_COLS - 1) * CARD_GAP + PICKER_BAR_GUTTER,
		PICKER_HEADER + GRID_PAD * 2 + GRID_ROWS * cardH
			+ (GRID_ROWS - 1) * CARD_GAP + PICKER_FOOTER
end
function Addon:IsPickerOpen()
	return mountPicker ~= nil and mountPicker:IsShown()
end

function Addon:ClosePicker()
	if mountPicker then mountPicker:Hide() end
end

-- Moves the mount model upward inside its card.
local function ApplyCardNudge(card)
	local nudge = MogtrotDB.cardNudge or CARD_NUDGE
	card.Scene:SetPoint("TOPLEFT", 5, -34 + nudge)
	card.Scene:SetPoint("BOTTOMRIGHT", -5, 5 + nudge)
end

-- Draws the mount using the same model scene Blizzard chose for it.
local function SetCardModel(card, mountID)
	local displayID, _description, _source, isSelfMount, _mountTypeID, modelSceneID =
		C_MountJournal.GetMountInfoExtraByID(mountID)

	if not displayID then
		local all = C_MountJournal.GetMountAllCreatureDisplayInfoByID(mountID)
		if all and #all > 0 then
			displayID = all[1].creatureDisplayID
		end
	end

	if not displayID or displayID == 0 then
		card.Scene:Hide()
		return
	end

	if modelSceneID then
		card.Scene:TransitionToModelSceneID(modelSceneID,
			CAMERA_TRANSITION_TYPE_IMMEDIATE or 1, CAMERA_MODIFICATION_TYPE_DISCARD or 1, true)
		local actor = card.Scene:GetActorByTag("unwrapped")
		if actor then
			actor:SetModelByCreatureDisplayID(displayID, true)
			actor:SetAnimation(isSelfMount and 618 or 0)
			card.Scene:Show()
			return
		end
	end

	card.Scene:Hide()
end

local function CaseInsensitive(a, b)
	return strlower(a) < strlower(b)
end

local function Card_OnEnter(self)
	self.Hover:Show()
	if not self.mountID then return end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.mountName or "Mount", 1, 0.82, 0)

	local names = {}
	for _, outfitID in ipairs(self.linkedOutfits or {}) do
		local info = Addon.outfitsByID and Addon.outfitsByID[outfitID]
		if info then table.insert(names, info.name) end
	end
	if #names > 0 then
		table.sort(names, CaseInsensitive)
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Linked to:", 0.5, 0.8, 1)
		for _, name in ipairs(names) do
			GameTooltip:AddLine("  " .. name, 0.5, 0.8, 1)
		end
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-click to link or unlink it from this outfit", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Shift-left-click to mount it", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("Right-click for mount options", 0.6, 0.6, 0.6)
	if self.isPinned then
		GameTooltip:AddLine("Pinned for outfit shuffle and pinned fallback", 1, 0.82, 0)
	end
	GameTooltip:Show()
end

local function Card_OnLeave(self)
	self.Hover:Hide()
	GameTooltip:Hide()
end

local function SummonMountFromCard(mountID)
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage("Mogtrot: can't summon in combat.", 1, 0.3, 0.3)
		return
	end
	C_MountJournal.SummonByID(mountID)
end

local function ShowMountCardMenu(card)
	local mountID = card.mountID
	local mountName = card.mountName
	local isPinned = card.isPinned
	if not mountID then return end

	MenuUtil.CreateContextMenu(card, function(_owner, root)
		root:CreateTitle(mountName or "Mount")
		root:CreateButton(isPinned and "Unpin" or "Pin", function()
			Addon:ToggleMountPin(mountID)
		end)
		root:CreateButton("Link to other outfit", function()
			Addon:OpenAddMountToOutfits(mountID, mountName)
		end)
		root:CreateDivider()
		root:CreateButton("Mount (Shift-click)", function()
			SummonMountFromCard(mountID)
		end)
	end)
end

local function Card_OnClick(self, button)
	if not self.mountID then return end

	if button == "RightButton" then
		ShowMountCardMenu(self)
	elseif button == "LeftButton" and IsShiftKeyDown() then
		SummonMountFromCard(self.mountID)
	elseif button == "LeftButton" and self.outfitID then
		Addon:ToggleOutfitMount(self.outfitID, self.mountID)
		if (mountPicker.filter.chosenMode or "all") ~= "all" then
			Addon:RefreshMountPicker()
		else
			Addon:RepaintMountCards()
		end
	end
end

local function CommitPinDays(edit)
	local days = tonumber(edit:GetText())
	if not days or days < 0 or days ~= math.floor(days) then
		edit:SetText(tostring(edit.previousDays or 0))
		return
	end
	if Addon:SetMountPinDays(edit.mountID, days) then
		edit.previousDays = days
		Addon:RepaintMountCards()
	end
end

-- Creates the controls shared by every recycled mount card.
local function BuildMountCard(card)
	if card.built then return end
	card.built = true

	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	card.Bg = card:CreateTexture(nil, "BACKGROUND")
	card.Bg:SetAllPoints()

	card.Edges = {}
	for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = card:CreateTexture(nil, "BORDER")
		if edge == "TOP" or edge == "BOTTOM" then
			line:SetHeight(1)
			line:SetPoint(edge .. "LEFT")
			line:SetPoint(edge .. "RIGHT")
		else
			line:SetWidth(1)
			line:SetPoint("TOP" .. edge)
			line:SetPoint("BOTTOM" .. edge)
		end
		table.insert(card.Edges, line)
	end

	function card:SetCardColors(r, g, b, a, er, eg, eb)
		self.Bg:SetColorTexture(r, g, b, a)
		for _, line in ipairs(self.Edges) do
			line:SetColorTexture(er, eg, eb, 1)
		end
	end

	card.Hover = card:CreateTexture(nil, "BACKGROUND")
	card.Hover:SetAllPoints()
	card.Hover:SetColorTexture(1, 1, 1, 0.08)
	card.Hover:Hide()

	card.Icon = card:CreateTexture(nil, "ARTWORK")
	card.Icon:SetSize(22, 22)
	card.Icon:SetPoint("TOPLEFT", 6, -6)
	card.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	card.Name = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.Name:SetPoint("TOPLEFT", card.Icon, "TOPRIGHT", 5, -2)
	card.Name:SetJustifyH("LEFT")
	card.Name:SetHeight(18)
	card.Name:SetWordWrap(false)
	card.Name:SetMaxLines(1)

	card.PinButton = CreateFrame("Button", nil, card)
	card.PinButton:SetSize(22, 22)
	card.PinButton:SetPoint("TOPRIGHT", -1, -1)
	card.PinButton:SetScript("OnClick", function(self)
		if self.mountID then Addon:ToggleMountPin(self.mountID) end
	end)
	card.FallbackStar = card.PinButton:CreateTexture(nil, "ARTWORK")
	card.FallbackStar:SetSize(14, 14)
	card.FallbackStar:SetPoint("CENTER")
	card.Name:SetPoint("RIGHT", card.FallbackStar, "LEFT", -4, 0)

	card.PinRow = CreateFrame("Frame", nil, card)
	card.PinRow:SetPoint("BOTTOMLEFT", 6, 7)
	card.PinRow:SetSize(190, 22)
	card.PinLabel = card.PinRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.PinLabel:SetPoint("LEFT")
	card.PinLabel:SetText("Expires in")
	card.PinDays = CreateFrame("EditBox", nil, card.PinRow, "InputBoxTemplate")
	card.PinDays:SetSize(38, 20)
	card.PinDays:SetPoint("LEFT", card.PinLabel, "RIGHT", 5, 0)
	card.PinDays:SetAutoFocus(false)
	card.PinDays:SetNumeric(true)
	card.PinDays:SetMaxLetters(5)
	card.PinDays:SetScript("OnEnterPressed", function(self) CommitPinDays(self); self:ClearFocus() end)
	card.PinDays:SetScript("OnEditFocusLost", CommitPinDays)
	card.PinDays:SetScript("OnEscapePressed", function(self)
		self:SetText(tostring(self.previousDays or 0)); self:ClearFocus()
	end)
	card.PinDays:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Pin expiration")
		GameTooltip:AddLine("Enter whole days remaining. 0 never expires.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	card.PinDays:SetScript("OnLeave", GameTooltip_Hide)
	card.PinSuffix = card.PinRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.PinSuffix:SetPoint("LEFT", card.PinDays, "RIGHT", 5, 0)
	card.PinSuffix:SetText("days")
	card.PinRow:Hide()

	card.Scene = CreateFrame("ModelScene", nil, card, "NonInteractableModelSceneMixinTemplate")
	card.Scene:SetPoint("TOPLEFT", 5, -34)
	card.Scene:SetPoint("BOTTOMRIGHT", -5, 5)

	card.LinkLayer = CreateFrame("Frame", nil, card)
	card.LinkLayer:SetAllPoints()
	card.LinkLayer:SetFrameLevel(card.Scene:GetFrameLevel() + 5)
	card.PinRow:SetFrameLevel(card.LinkLayer:GetFrameLevel() + 1)
	card.PinButton:SetFrameLevel(card.LinkLayer:GetFrameLevel() + 2)

	card.Linked = {}
	for i = 1, CARD_LINK_ICONS do
		local entry = {}
		entry.Button = CreateFrame("Button", nil, card.LinkLayer, UI.ActionButtonTemplate)
		entry.Button:RegisterForClicks("AnyDown", "AnyUp")
		entry.Button:SetAttribute("useOnKeyDown", false)
		entry.Button:SetAttribute("type", "outfit")
		entry.Button:SetAttribute("action", "change")
		entry.Button:SetPropagateMouseClicks(false)
		entry.Button:SetScript("PreClick", OutfitWear_PreClick)
		entry.Button:SetScript("PostClick", OutfitWear_PostClick)

		entry.Shade = entry.Button:CreateTexture(nil, "BACKGROUND")
		entry.Shade:SetColorTexture(0, 0, 0, 0.6)

		entry.Icon = entry.Button:CreateTexture(nil, "OVERLAY")
		entry.Icon:SetSize(14, 14)
		entry.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		entry.Name = entry.Button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		entry.Name:SetPoint("LEFT", entry.Icon, "RIGHT", 4, 0)
		entry.Name:SetJustifyH("LEFT")
		entry.Name:SetWordWrap(false)
		entry.Name:SetMaxLines(1)

		entry.Hover = entry.Button:CreateTexture(nil, "HIGHLIGHT")
		entry.Hover:SetAllPoints()
		entry.Hover:SetColorTexture(1, 1, 1, 0.12)
		entry.Button:SetScript("OnEnter", function(self)
			if not self.outfitID then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.outfitName or "Outfit")
			GameTooltip:AddLine("Click to switch to this outfit.", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		entry.Button:SetScript("OnLeave", GameTooltip_Hide)

		entry.Shade:SetPoint("TOPLEFT", entry.Icon, "TOPLEFT", -3, 2)
		entry.Shade:SetPoint("BOTTOMRIGHT", entry.Name, "BOTTOMRIGHT", 3, -2)

		card.Linked[i] = entry
	end

	card.LinkedShade = card.LinkLayer:CreateTexture(nil, "BACKGROUND")
	card.LinkedShade:SetColorTexture(0, 0, 0, 0.6)
	card.LinkedShade:Hide()

	card.LinkedText = card.LinkLayer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.LinkedText:SetJustifyH("LEFT")
	card.LinkedText:SetWordWrap(false)
	card.LinkedText:Hide()

	card.Scene:EnableMouse(false)
	card.Scene:EnableMouseWheel(false)
	if card.Scene.SetMouseClickEnabled then card.Scene:SetMouseClickEnabled(false) end
	if card.Scene.SetMouseMotionEnabled then card.Scene:SetMouseMotionEnabled(false) end
	if card.Scene.SetPropagateMouseClicks then card.Scene:SetPropagateMouseClicks(true) end
	if card.Scene.SetPropagateMouseMotion then card.Scene:SetPropagateMouseMotion(true) end

	card:SetScript("OnEnter", Card_OnEnter)
	card:SetScript("OnLeave", Card_OnLeave)
	card:SetScript("OnClick", Card_OnClick)
end

local LINK_LINE_H = 17

function Addon:PaintCardLinks(card, outfitIDs, excludedOutfitID)
	local names = {}
	for _, outfitID in ipairs(outfitIDs or {}) do
		local info = self.outfitsByID and self.outfitsByID[outfitID]
		if info and outfitID ~= excludedOutfitID then
			table.insert(names, {
				name = info.name,
				icon = info.icon,
				index = info.index,
				outfitID = outfitID,
			})
		end
	end
	table.sort(names, function(a, b) return strlower(a.name) < strlower(b.name) end)

	local shown = math.min(#names, CARD_LINK_ICONS)
	local overflow = #names > CARD_LINK_ICONS
	local shownRows = math.ceil(shown / CARD_LINK_COLUMNS)
	local cardWidth = CardSize()
	local columnWidth = math.floor((cardWidth - 12) / CARD_LINK_COLUMNS)

	for i = 1, shown do
		local entry = card.Linked[i]
		local row = math.floor((i - 1) / CARD_LINK_COLUMNS)
		local column = (i - 1) % CARD_LINK_COLUMNS
		local left = 6 + column * columnWidth
		entry.Button.outfitID = names[i].outfitID
		entry.Button.outfitName = names[i].name
		entry.Button.willWear = nil
		entry.Button:SetAttribute("type", "outfit")
		entry.Button:SetAttribute("action", "change")
		entry.Button:SetAttribute("outfit-index", names[i].index)
		entry.Button:ClearAllPoints()
		entry.Button:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", left, 6 + row * LINK_LINE_H)
		entry.Button:SetSize(columnWidth - 4, LINK_LINE_H)
		entry.Icon:ClearAllPoints()
		entry.Icon:SetPoint("LEFT", entry.Button, "LEFT", 0, 0)
		entry.Name:ClearAllPoints()
		entry.Name:SetPoint("LEFT", entry.Icon, "RIGHT", 4, 0)
		entry.Name:SetPoint("RIGHT", entry.Button, "RIGHT", -4, 0)
		entry.Shade:ClearAllPoints()
		entry.Shade:SetPoint("TOPLEFT", entry.Icon, "TOPLEFT", -3, 2)
		entry.Shade:SetPoint("BOTTOMRIGHT", entry.Name, "BOTTOMRIGHT", 3, -2)
		entry.Icon:SetTexture(names[i].icon)
		entry.Name:SetText(names[i].name)
		entry.Icon:Show()
		entry.Name:Show()
		entry.Shade:Show()
		entry.Button:Enable()
		entry.Button:Show()
	end

	for i = shown + 1, CARD_LINK_ICONS do
		card.Linked[i].Button.outfitID = nil
		card.Linked[i].Button.outfitName = nil
		card.Linked[i].Button.willWear = nil
		card.Linked[i].Button:SetAttribute("outfit-index", nil)
		card.Linked[i].Button:ClearAllPoints()
		card.Linked[i].Button:Disable()
		card.Linked[i].Button:Hide()
		card.Linked[i].Icon:ClearAllPoints()
		card.Linked[i].Icon:SetTexture(nil)
		card.Linked[i].Name:ClearAllPoints()
		card.Linked[i].Name:SetText(nil)
		card.Linked[i].Shade:ClearAllPoints()
		card.Linked[i].Icon:Hide()
		card.Linked[i].Name:Hide()
		card.Linked[i].Shade:Hide()
	end

	if overflow then
		card.LinkedText:ClearAllPoints()
		card.LinkedText:SetPoint("BOTTOMLEFT", 6, 6 + shownRows * LINK_LINE_H)
		card.LinkedText:SetText(("+%d more"):format(#names - CARD_LINK_ICONS))
		card.LinkedText:Show()
		card.LinkedShade:ClearAllPoints()
		card.LinkedShade:SetPoint("TOPLEFT", card.LinkedText, "TOPLEFT", -3, 2)
		card.LinkedShade:SetPoint("BOTTOMRIGHT", card.LinkedText, "BOTTOMRIGHT", 3, -2)
		card.LinkedShade:Show()
	else
		card.LinkedText:ClearAllPoints()
		card.LinkedText:SetText(nil)
		card.LinkedShade:ClearAllPoints()
		card.LinkedText:Hide()
		card.LinkedShade:Hide()
	end
end

-- Updates a recycled card with one mount and its linked outfits.
function Addon:PaintMountCard(card, mount)
	card.mountID = mount.mountID
	card.mountName = mount.name
	card.outfitID = mountPicker.mode == "outfit" and mountPicker.outfitID or nil
	card.PinButton.mountID = mount.mountID
	card.Icon:SetTexture(mount.icon)
	card.Name:SetText(mount.name)

	card:SetSize(CardSize())
	ApplyCardNudge(card)

	card.linkedOutfits = mountPicker.linkIndex[mount.mountID]
	if mountPicker.mode == "pins" then
		self:PaintCardLinks(card, {})
	else
		self:PaintCardLinks(card, card.linkedOutfits, mountPicker.outfitID)
	end

	local isChosen = mountPicker.selected[mount.mountID] == true

	local isPinned = self:IsMountPinned(mount.mountID)
	card.isPinned = isPinned
	card.FallbackStar:SetSize(14, 14)
	card.FallbackStar:ClearAllPoints()
	card.FallbackStar:SetPoint("TOPRIGHT", -4, -4)
	card.FallbackStar:SetAtlas(isPinned and "auctionhouse-icon-favorite"
		or "auctionhouse-icon-favorite-off", false)
	card.FallbackStar:Show()
	local days = ns.MountPins.DaysRemaining(MogtrotDB, mount.mountID, time())
	card.PinRow:SetShown(mountPicker.mode == "pins" and days ~= nil)
	if mountPicker.mode == "pins" and days ~= nil then
		card.PinDays.mountID = mount.mountID
		card.PinDays.previousDays = days
		if not card.PinDays:HasFocus() then card.PinDays:SetText(tostring(days)) end
	end

	if isChosen then
		card:SetCardColors(0.18, 0.14, 0.02, 0.9, 1, 0.82, 0)
	else
		card:SetCardColors(0.05, 0.05, 0.06, 0.9, 0.3, 0.3, 0.3)
	end

	card.Hover:Hide()
end

function Addon:InitMountCard(card, mount)
	BuildMountCard(card)
	self:PaintMountCard(card, mount)
	SetCardModel(card, mount.mountID)
end

local function RefreshPickerState()
	mountPicker.selected = mountPicker.mode == "pins"
		and ns.MountPins.ActiveSet(MogtrotDB, time())
		or Addon:GetOutfitMounts(mountPicker.outfitID)
	mountPicker.linkIndex = ns.MountIndex.Build(MogtrotCharDB)
end

local function OutfitChoices()
	local choices = {}
	for outfitID, info in pairs(Addon.outfitsByID or {}) do
		table.insert(choices, {
			outfitID = outfitID,
			name = info.name,
			icon = info.icon,
			preselected = mountPicker.outfitID == outfitID or nil,
		})
	end
	table.sort(choices, function(a, b) return CaseInsensitive(a.name, b.name) end)
	return choices
end

local function ChoosePickerOutfit()
	ns.OpenSearchPicker({
		title = "Choose an outfit",
		searchHint = "Search outfits",
		emptyText = "No outfits match.",
		items = OutfitChoices(),
		onChoose = function(chosen)
			Addon:SetMountPickerOutfit(chosen.outfitID)
		end,
	})
end

function Addon:SetMountPickerOutfit(outfitID)
	if not mountPicker then return end
	mountPicker.mode = "outfit"
	mountPicker.outfitID = outfitID
	mountPicker.mounts, mountPicker.typeNote = CollectMounts(outfitID)
	ShowMountEditPreview(outfitID)
	self:RefreshMountPicker({ preserveScrollOffset = true })
end

function Addon:SetMountPickerPinMode()
	if not mountPicker then return end
	mountPicker.mode = "pins"
	mountPicker.mounts, mountPicker.typeNote = CollectMounts(nil)
	HideMountEditPreview()
	self:RefreshMountPicker()
end

function Addon:PaintPickerChrome()
	local chosen = 0
	for _ in pairs(mountPicker.selected) do chosen = chosen + 1 end

	local info = self.outfitsByID and self.outfitsByID[mountPicker.outfitID]
	mountPicker.Title:SetText("")
	mountPicker.HeaderPrefix:SetText(mountPicker.mode == "pins" and "Pinned mounts:" or "Mounts for")
	mountPicker.HeaderName:SetText(mountPicker.mode == "pins" and tostring(chosen)
		or (info and info.name or "Outfit"))
	if mountPicker.mode == "pins" then
		mountPicker.HeaderIcon:SetAtlas("auctionhouse-icon-favorite", false)
	else
		mountPicker.HeaderIcon:SetTexture(info and info.icon or nil)
	end
	mountPicker.HeaderCount:SetText(mountPicker.mode == "pins" and "chosen  -" or
		("  %d chosen  -"):format(chosen))
	mountPicker.ModeButton.Text:SetText(mountPicker.mode == "pins" and "Switch to outfit"
		or "Switch to pins")
	mountPicker.TitleIcon:Hide()
end

function Addon:ApplyPickerSize()
	if not mountPicker then return end

	local cardW, cardH = CardSize()
	mountPicker.View:SetElementSize(cardW, cardH)
	mountPicker.View:SetPanExtent(cardH)
	mountPicker.Box:ForEachFrame(function(card) card:SetSize(cardW, cardH) end)

	mountPicker:SetSize(PickerSize())
	mountPicker.Box:FullUpdate(ScrollBoxConstants.UpdateImmediately)
	ApplyMountEditDock()
end
-- Rebuilds the visible grid after search or filter controls change.
function Addon:RefreshMountPicker(options)
	if not mountPicker or not mountPicker:IsShown() then return end
	if InCombatLockdown() then return end
	local scrollOffset = options and options.preserveScrollOffset
		and mountPicker.Box:GetDerivedScrollOffset()

	RefreshPickerState()

	local matches = ns.MountFilter.Apply(mountPicker.mounts, mountPicker.filter,
		mountPicker.selected)
	if mountPicker.mode == "pins" then
		local original = {}
		for i, mount in ipairs(matches) do original[mount.mountID] = i end
		table.sort(matches, function(a, b)
			local ap, bp = Addon:IsMountPinned(a.mountID), Addon:IsMountPinned(b.mountID)
			if ap ~= bp then return ap end
			local ar = MogtrotDB.mountPins[a.mountID]
			local br = MogtrotDB.mountPins[b.mountID]
			local aa, ba = ar and ar.acquiredAt, br and br.acquiredAt
			if (aa ~= nil) ~= (ba ~= nil) then return aa ~= nil end
			if aa and aa ~= ba then return aa > ba end
			return original[a.mountID] < original[b.mountID]
		end)
	end
	mountPicker.shownCount = #matches

	local retain = ScrollBoxConstants.RetainScrollPosition
	if mountPicker.scrollToTop then
		retain = ScrollBoxConstants.DiscardScrollPosition
	end
	mountPicker.scrollToTop = nil
	mountPicker.Box:SetDataProvider(CreateDataProvider(matches), retain)
	if scrollOffset then mountPicker.Box:ScrollToOffset(scrollOffset, 0, 0) end

	self:PaintPickerChrome()
end

function Addon:OnPickerFilterChanged()
	if not mountPicker or not mountPicker:IsShown() then return end

	mountPicker.scrollToTop = true
	self:RefreshMountPicker()
	mountPicker.Filter:ValidateResetState()
end

function Addon:RepaintMountCards()
	if not mountPicker or not mountPicker:IsShown() then return end
	if InCombatLockdown() then return end

	RefreshPickerState()
	mountPicker.Box:ForEachFrame(function(card, mount) self:PaintMountCard(card, mount) end)
	self:PaintPickerChrome()
end

-- Builds the mount picker window the first time users open it.
local function EnsureMountPicker()
	if mountPicker then return mountPicker end

	local width, height = PickerSize()

	mountPicker = CreateFrame("Frame", "MogtrotMountPicker", UIParent, "BackdropTemplate")
	if deps.onPickerCreated then deps.onPickerCreated(mountPicker) end
	mountPicker:SetSize(width, height)
	mountPicker:SetFrameStrata("HIGH")
	mountPicker:SetClampedToScreen(true)
	mountPicker:SetMovable(true)
	mountPicker:EnableMouse(true)
	mountPicker:RegisterForDrag("LeftButton")
	mountPicker:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		self:StartMoving()
	end)
	mountPicker:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		MogtrotDB.pickerPosition = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	mountPicker:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	mountPicker:SetBackdropColor(0, 0, 0, 0.94)
	mountPicker.DockGlow = BuildDockGlow(mountPicker)

	mountPicker.TitleIcon = mountPicker:CreateTexture(nil, "ARTWORK")
	mountPicker.TitleIcon:SetSize(24, 24)
	mountPicker.TitleIcon:SetPoint("TOPLEFT", UI.Pad, -UI.Pad + 1)
	mountPicker.TitleIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	mountPicker.Title = mountPicker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mountPicker.Title:SetPoint("LEFT", mountPicker.TitleIcon, "RIGHT", 6, -1)

	mountPicker.CloseButton = CreateFrame("Button", nil, mountPicker, "UIPanelCloseButton")
	mountPicker.CloseButton:SetSize(PICKER_HEADER_CONTROL_H, PICKER_HEADER_CONTROL_H)
	mountPicker.CloseButton:SetPoint("TOPRIGHT", -UI.CloseButtonInset, -UI.CloseButtonInset)

	mountPicker.Title:SetPoint("RIGHT", mountPicker.CloseButton, "LEFT", -4, 0)
	mountPicker.Title:SetJustifyH("LEFT")
	mountPicker.Title:SetWordWrap(false)

	mountPicker.HeaderRow = CreateFrame("Frame", nil, mountPicker)
	mountPicker.HeaderRow:SetPoint("TOPLEFT", UI.Pad, -UI.Pad)
	mountPicker.HeaderRow:SetPoint("RIGHT", mountPicker.CloseButton, "LEFT", -8, 0)
	mountPicker.HeaderRow:SetHeight(PICKER_HEADER_CONTROL_H)

	mountPicker.HeaderClick = CreateFrame("Button", nil, mountPicker.HeaderRow, "BackdropTemplate")
	mountPicker.HeaderClick:SetSize(210, PICKER_HEADER_CONTROL_H)
	mountPicker.HeaderClick:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	mountPicker.HeaderClick:SetBackdropBorderColor(1, 0.82, 0, 1)
	mountPicker.HeaderClick:SetScript("OnClick", function()
		ChoosePickerOutfit()
	end)
	mountPicker.HeaderClick:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		if mountPicker.mode == "pins" then
			GameTooltip:SetText("Switch to outfit")
		else
			GameTooltip:SetText("Choose another outfit")
			GameTooltip:AddLine("Click to select an outfit.", 0.6, 0.6, 0.6)
		end
		GameTooltip:Show()
	end)
	mountPicker.HeaderClick:SetScript("OnLeave", GameTooltip_Hide)
	mountPicker.HeaderPrefix = mountPicker.HeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mountPicker.HeaderPrefix:SetPoint("LEFT", 0, 0)
	mountPicker.HeaderClick:SetPoint("LEFT", mountPicker.HeaderPrefix, "RIGHT", 6, 0)
	mountPicker.HeaderName = mountPicker.HeaderClick:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mountPicker.HeaderName:SetPoint("CENTER", 10, 0)
	mountPicker.HeaderIcon = mountPicker.HeaderClick:CreateTexture(nil, "ARTWORK")
	mountPicker.HeaderIcon:SetSize(22, 22)
	mountPicker.HeaderIcon:SetPoint("RIGHT", mountPicker.HeaderName, "LEFT", -5, 0)
	mountPicker.HeaderIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	mountPicker.HeaderCount = mountPicker.HeaderRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mountPicker.HeaderCount:SetPoint("LEFT", mountPicker.HeaderClick, "RIGHT", 6, 0)
	mountPicker.ModeButton = CreateFrame("Button", nil, mountPicker.HeaderRow, "BackdropTemplate")
	mountPicker.ModeButton:SetSize(120, PICKER_HEADER_CONTROL_H)
	mountPicker.ModeButton:SetPoint("LEFT", mountPicker.HeaderCount, "RIGHT", 6, 0)
	mountPicker.ModeButton:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	mountPicker.ModeButton:SetBackdropBorderColor(1, 0.82, 0, 1)
	mountPicker.ModeButton.Text = mountPicker.ModeButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	mountPicker.ModeButton.Text:SetPoint("CENTER")
	mountPicker.ModeButton:SetScript("OnClick", function()
		if mountPicker.mode == "pins" then ChoosePickerOutfit()
		else Addon:SetMountPickerPinMode() end
	end)

	mountPicker.SearchBox = CreateFrame("EditBox", nil, mountPicker, "SearchBoxTemplate")
	mountPicker.SearchBox:SetSize(220, 20)
	mountPicker.SearchBox:SetAutoFocus(false)
	mountPicker.SearchBox:SetPoint("TOPLEFT", UI.Pad + 6, -(UI.Pad + 32))
	if mountPicker.SearchBox.Instructions then
		mountPicker.SearchBox.Instructions:SetText("Search mounts")
	end
	mountPicker.SearchBox:HookScript("OnTextChanged", function(self)
		if not mountPicker.filter then return end
		local text = strtrim(self:GetText() or "")
		local nextQuery = (text ~= "") and strlower(text) or nil
		if nextQuery == mountPicker.filter.query then return end
		mountPicker.filter.query = nextQuery
		mountPicker.scrollToTop = true
		Addon:RefreshMountPicker()
	end)

	mountPicker.Filter = CreateFrame("DropdownButton", nil, mountPicker,
		"WowStyle1FilterDropdownTemplate")
	mountPicker.Filter:SetPoint("LEFT", mountPicker.SearchBox, "RIGHT", 14, 0)
	mountPicker.Filter:SetIsDefaultCallback(function()
		return ns.MountFilter.IsDefault(mountPicker.filter)
	end)
	mountPicker.Filter:SetDefaultCallback(function()
		ns.MountFilter.Reset(mountPicker.filter)
		Addon:OnPickerFilterChanged()
	end)
	local function TypeTicked(typeValue)
		local filter = mountPicker.filter
		return (filter and filter.types[typeValue]) == true
	end

	local function ToggleType(typeValue)
		local filter = mountPicker.filter
		if not filter then return end
		local on = not filter.types[typeValue]
		filter.types[typeValue] = on or nil
		Addon:OnPickerFilterChanged()
		return MenuResponse.Refresh
	end

	local function SetEveryType(checked)
		local filter = mountPicker.filter
		if filter then
			ns.MountFilter.SetAllTypes(filter, checked)
			Addon:OnPickerFilterChanged()
		end
		return MenuResponse.Refresh
	end

	local function FavouritesOnly()
		local filter = mountPicker.filter
		return (filter and filter.favoritesOnly) == true
	end

	local function ToggleFavourites()
		local filter = mountPicker.filter
		if not filter then return end
		local on = not filter.favoritesOnly
		filter.favoritesOnly = on or nil
		Addon:OnPickerFilterChanged()
		return MenuResponse.Refresh
	end

	local function ChosenModeIs(value)
		local filter = mountPicker.filter
		return ((filter and filter.chosenMode) or "all") == value
	end

	local function SetChosenMode(value)
		local filter = mountPicker.filter
		if not filter then return end
		filter.chosenMode = value
		Addon:OnPickerFilterChanged()
		return MenuResponse.Refresh
	end

	mountPicker.Filter:SetupMenu(function(_dropdown, root)
		local filter = mountPicker.filter
		if not filter then return end

		if mountPicker.typeNote then
			root:CreateTitle(mountPicker.typeNote)
		else
			root:CreateButton(CHECK_ALL or "Check All", SetEveryType, true)
			root:CreateButton(UNCHECK_ALL or "Uncheck All", SetEveryType, false)

			root:CreateSpacer()
			root:CreateTitle(MOUNT_JOURNAL_FILTER_TYPE or "Type")

			for _, value in ipairs(filter.validTypes) do
				root:CreateCheckbox(MOUNT_TYPE_LABELS[value] or tostring(value),
					TypeTicked, ToggleType, value)
			end
			root:CreateDivider()
		end

		root:CreateCheckbox("Favourites only", FavouritesOnly, ToggleFavourites)

		root:CreateDivider()
		local MakeOption = root.CreateRadio or root.CreateCheckbox
		MakeOption(root, "All mounts", ChosenModeIs, SetChosenMode, "all")
		MakeOption(root, "On this outfit", ChosenModeIs, SetChosenMode, "chosen")
		MakeOption(root, "Not on this outfit", ChosenModeIs, SetChosenMode, "unchosen")

		if ns.MountFilter.ShouldShowLinkedMountNotice(filter) then
			root:CreateSpacer()
			root:CreateTitle("Mounts already on this outfit always show.")
		end
	end)

	mountPicker.Box = CreateFrame("Frame", nil, mountPicker, "WowScrollBoxList")
	mountPicker.Box:SetPoint("TOPLEFT", mountPicker, "TOPLEFT", UI.Pad, -PICKER_HEADER)
	mountPicker.Box:SetPoint("BOTTOMRIGHT", mountPicker, "BOTTOMRIGHT",
		-(UI.Pad + PICKER_BAR_GUTTER), PICKER_FOOTER)

	mountPicker.Bar = CreateFrame("EventFrame", nil, mountPicker, "MinimalScrollBar")
	mountPicker.Bar:SetPoint("TOPLEFT", mountPicker.Box, "TOPRIGHT", PICKER_BAR_GAP, 0)
	mountPicker.Bar:SetPoint("BOTTOMLEFT", mountPicker.Box, "BOTTOMRIGHT", PICKER_BAR_GAP, 0)

	local cardW, cardH = CardSize()
	mountPicker.View = CreateScrollBoxListGridView(GRID_COLS,
		GRID_PAD, GRID_PAD, GRID_PAD, GRID_PAD, CARD_GAP, CARD_GAP)
	mountPicker.View:SetElementSize(cardW, cardH)
	mountPicker.View:SetPanExtent(cardH)
	mountPicker.View:SetElementInitializer("Button", function(card, mount)
		Addon:InitMountCard(card, mount)
	end)

	ScrollUtil.InitScrollBoxListWithScrollBar(mountPicker.Box, mountPicker.Bar, mountPicker.View)
	mountPicker.BarVisibility = ScrollUtil.AddManagedScrollBarVisibilityBehavior(
		mountPicker.Box, mountPicker.Bar)


	mountPicker:EnableMouseWheel(true)
	mountPicker:SetScript("OnMouseWheel", function(_self, delta)
		mountPicker.Box:OnMouseWheel(delta)
	end)

	mountPicker.ResizeGrip = CreateFrame("Button", nil, mountPicker)
	mountPicker.ResizeGrip:SetSize(24, 24)
	mountPicker.ResizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
	mountPicker.ResizeGrip:SetFrameLevel(mountPicker.Box:GetFrameLevel() + 20)
	mountPicker.ResizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	mountPicker.ResizeGrip:SetHighlightTexture(
		"Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	for _, tex in ipairs({ mountPicker.ResizeGrip:GetNormalTexture(),
		mountPicker.ResizeGrip:GetHighlightTexture() }) do
		tex:ClearAllPoints()
		tex:SetSize(16, 16)
		tex:SetPoint("BOTTOMRIGHT", -2, 2)
	end

	mountPicker.ResizeGrip:SetScript("OnMouseDown", function(self)
		local x, y = GetCursorPosition()
		self.startX, self.startY = x, y
		self.startScale = PickerScale()
		self:SetScript("OnUpdate", function()
			local cx, cy = GetCursorPosition()
			local scaleFactor = UIParent:GetEffectiveScale()
			local delta = ((cx - self.startX) + (self.startY - cy)) / (2 * scaleFactor)
			MogtrotDB.pickerScale = self.startScale + delta / CARD_W
			Addon:ApplyPickerSize()
		end)
	end)
	mountPicker.ResizeGrip:SetScript("OnMouseUp", function(self)
		self:SetScript("OnUpdate", nil)
		MogtrotDB.pickerScale = PickerScale()
	end)
	mountPicker.ResizeGrip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Drag to resize the cards")
		GameTooltip:AddLine("Always three by three; the mounts get bigger.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	mountPicker.ResizeGrip:SetScript("OnLeave", GameTooltip_Hide)

	mountPicker:SetScript("OnHide", function()
		HideMountEditPreview()
		for _, texture in ipairs(mountPicker.DockGlow or {}) do texture:Hide() end
	end)

	local pos = MogtrotDB.pickerPosition
	if pos then
		mountPicker:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		mountPicker:SetPoint("CENTER", UIParent, "CENTER", -180, 0)
	end

	mountPicker:Hide()
	return mountPicker
end

-- Opens a fresh mount picker for one outfit.
function Addon:OpenMountPicker(outfitID)
	if InCombatLockdown() then return end

	local picker = EnsureMountPicker()
	if picker:IsShown() then
		self:SetMountPickerOutfit(outfitID)
		picker.SearchBox:SetFocus()
		return
	end

	picker.outfitID = outfitID
	picker.mode = "outfit"
	picker.mounts, picker.typeNote = CollectMounts(outfitID)
	picker.filter = ns.MountFilter.DefaultState(ValidMountTypes())
	picker.Filter:ValidateResetState()
	picker.SearchBox:SetText("")
	picker.scrollToTop = true

	self:HidePreview()
	picker:Show()
	ShowMountEditPreview(outfitID)
	self:RefreshMountPicker()
	picker.SearchBox:SetFocus()
end

function Addon:OpenMountPins()
	if InCombatLockdown() then return end

	local picker = EnsureMountPicker()
	picker.outfitID = nil
	picker.mode = "pins"
	picker.mounts, picker.typeNote = CollectMounts(nil)
	picker.filter = ns.MountFilter.DefaultState(ValidMountTypes())
	picker.Filter:ValidateResetState()
	picker.SearchBox:SetText("")
	picker.scrollToTop = true

	self:HidePreview()
	picker:Show()
	HideMountEditPreview()
	self:RefreshMountPicker()
	picker.SearchBox:SetFocus()
end

	return Addon
end

ns.MountPickerUI = MountPickerUI
return MountPickerUI
