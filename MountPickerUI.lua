local _, ns = ...

local Pins = ns.Pins or require("Pins")

-- The pairing window: what is paired with one outfit, or pinned account-wide,
-- in one of two domains, mounts or hearthstones. One frame, one sentence
-- header, one grid of pooled cards. The domain decides which rows fill the
-- grid and which renderer paints a card's body; everything else is shared.
--
-- Cards are pooled by the scroll box and move between domains, so every card
-- property is set on every paint, never at build.
local MountPickerUI = {}

function MountPickerUI.Attach(Addon, deps)
	local UI = ns.UI
	local MOUNT_TYPE_LABELS = deps.mountTypeLabels
	local CollectMounts = deps.collectMounts
	local ValidMountTypes = deps.validMountTypes
	local BuildDockGlow = deps.buildDockGlow
	local ApplyMountEditDock = deps.applyMountEditDock
	local ShowEditPreview = deps.showEditPreview
	local HideEditPreview = deps.hideEditPreview
	local OutfitWear_PreClick = deps.outfitWearPreClick
	local OutfitWear_PostClick = deps.outfitWearPostClick
	local mountPicker
	-- Hearthstone reads and writes, from AttachHearthstones once the
	-- character's store is known to carry them. Until then the domain is off.
	local hearth

local function MountPinDomain()
	local db = MogtrotDB
	local pins = db and db.pins
	if type(pins) ~= "table" then return nil end
	local domain = pins.mounts
	if type(domain) ~= "table" or type(domain.records) ~= "table"
		or domain.autoNew == nil or domain.days == nil then
		return nil
	end
	return domain
end

local function HearthPinDomain()
	local account = hearth and hearth.account
	local pins = type(account) == "table" and account.pins
	return type(pins) == "table" and pins[hearth.pinsDomain or "hearthstones"] or nil
end

local function PinDomain(domain)
	if domain == "hearthstones" then return HearthPinDomain() end
	return MountPinDomain()
end

local function ActivePins(domain)
	local store = PinDomain(domain)
	if not store then return {} end
	return Pins.ActiveSet(store, time())
end

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

local CHOSEN_COLORS = { 0.18, 0.14, 0.02, 0.9, 1, 0.82, 0 }
local PLAIN_COLORS = { 0.05, 0.05, 0.06, 0.9, 0.3, 0.3, 0.3 }
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local SEARCH_HINT = { mounts = "Search mounts", hearthstones = "Search hearthstones" }

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

local function Domain()
	return mountPicker and mountPicker.domain or "mounts"
end

function Addon:IsPickerOpen()
	return mountPicker ~= nil and mountPicker:IsShown()
end

function Addon:IsHearthstonePickerOpen()
	return self:IsPickerOpen() and Domain() == "hearthstones"
end

function Addon:ClosePicker()
	if mountPicker then mountPicker:Hide() end
end

local function OutfitName(outfitID)
	local info = Addon.outfitsByID and Addon.outfitsByID[outfitID]
	return info and info.name or tostring(outfitID)
end

local function ShowPreview()
	if not mountPicker or mountPicker.mode ~= "outfit" then return end
	ShowEditPreview(mountPicker, mountPicker.outfitID, ("Editing %s for %s"):format(
		Domain(), OutfitName(mountPicker.outfitID)))
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

local function SummonMountFromCard(mountID)
	if InCombatLockdown() then
		UIErrorsFrame:AddMessage("Mogtrot: can't summon in combat.", 1, 0.3, 0.3)
		return
	end
	C_MountJournal.SummonByID(mountID)
end

-- What each domain does with a card. Mounts and hearthstones pair the same
-- way; they differ in what a card is called, how its links and pins are
-- stored, and what shift-click means.
local DOMAINS = {}

DOMAINS.mounts = {
	noun = "mount",
	IsPinned = function(id) return Addon:IsMountPinned(id) end,
	TogglePin = function(id) Addon:ToggleMountPin(id) end,
	SetPinDays = function(id, days) return Addon:SetMountPinDays(id, days) end,
	ToggleLink = function(outfitID, id) Addon:ToggleOutfitMount(outfitID, id) end,
	LinkElsewhere = function(id, name) Addon:OpenAddMountToOutfits(id, name) end,
	LinkIndex = function() return ns.MountIndex.Build(MogtrotCharDB) end,
	Selected = function(outfitID) return Addon:GetOutfitMounts(outfitID) end,
	ShiftClick = SummonMountFromCard,
	shiftHint = "Shift-left-click to mount it",
}

local function ToggleHearthPin(itemID)
	local store = HearthPinDomain()
	if not store then return end
	if Pins.IsPinned(store, itemID, time()) then
		Pins.Unpin(store, itemID)
	else
		Pins.Pin(store, itemID, time())
	end
	Addon:CompanionChoiceChanged()
end

local OpenHearthstoneLinks

DOMAINS.hearthstones = {
	noun = "hearthstone",
	IsPinned = function(id)
		local store = HearthPinDomain()
		return store and Pins.IsPinned(store, id, time()) or false
	end,
	TogglePin = function(id) ToggleHearthPin(id); Addon:RepaintMountCards() end,
	SetPinDays = function(id, days)
		local store = HearthPinDomain()
		if not store or not Pins.SetDaysRemaining(store, id, days, time()) then
			return false
		end
		Addon:CompanionChoiceChanged()
		return true
	end,
	ToggleLink = function(outfitID, id) hearth.toggleLink(outfitID, id) end,
	LinkElsewhere = function(id, name) OpenHearthstoneLinks(id, name) end,
	LinkIndex = function() return ns.OutfitLinks.IndexByLinked(hearth.links) end,
	Selected = function(outfitID) return hearth.getLinks(outfitID) or {} end,
	ShiftClick = function(id, name) OpenHearthstoneLinks(id, name) end,
	shiftHint = "Shift-click to link it to other outfits",
}

local function Card_OnEnter(self)
	self.Hover:Show()
	if not self.id then return end
	local domain = DOMAINS[self.domain]

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(self.name or domain.noun, 1, 0.82, 0)

	if self.owned == false then
		GameTooltip:AddLine("You have not collected this one", 1, 0.5, 0.5)
		GameTooltip:Show()
		return
	end

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
	if mountPicker and mountPicker.mode == "pins" then
		GameTooltip:AddLine(("Click to pin or unpin this %s"):format(domain.noun),
			0.6, 0.6, 0.6)
	else
		GameTooltip:AddLine("Left-click to link or unlink it from this outfit",
			0.6, 0.6, 0.6)
	end
	GameTooltip:AddLine(domain.shiftHint, 0.6, 0.6, 0.6)
	GameTooltip:AddLine(("Right-click for %s options"):format(domain.noun), 0.6, 0.6, 0.6)
	if self.isPinned then
		GameTooltip:AddLine(self.domain == "mounts"
			and "Pinned for outfit shuffle and pinned fallback"
			or "Pinned: used when the outfit has no hearthstone of its own", 1, 0.82, 0)
	end
	GameTooltip:Show()
end

local function Card_OnLeave(self)
	self.Hover:Hide()
	GameTooltip:Hide()
end

local function ShowCardMenu(card)
	local id, name, isPinned = card.id, card.name, card.isPinned
	local domain = DOMAINS[card.domain]
	if not id then return end

	MenuUtil.CreateContextMenu(card, function(_owner, root)
		root:CreateTitle(name or domain.noun)
		root:CreateButton(isPinned and "Unpin" or "Pin", function()
			domain.TogglePin(id)
		end)
		root:CreateButton("Link to other outfit", function()
			domain.LinkElsewhere(id, name)
		end)
		-- A hearthstone is never used from here: a cast from a picker would
		-- move the character with no warning.
		if card.domain == "mounts" then
			root:CreateDivider()
			root:CreateButton("Mount (Shift-click)", function()
				SummonMountFromCard(id)
			end)
		end
	end)
end

local function Card_OnClick(self, button)
	if not self.id or self.owned == false then return end
	local domain = DOMAINS[self.domain]
	local chosenOnly = (mountPicker.filter.chosenMode or "all") ~= "all"

	if button == "RightButton" then
		ShowCardMenu(self)
	elseif button == "LeftButton" and IsShiftKeyDown() then
		domain.ShiftClick(self.id, self.name)
	elseif button == "LeftButton" and mountPicker.mode == "pins" then
		-- In pin mode the whole card is the pin, the same as its star. Falling
		-- through to the outfit link here is what made a click in the middle of
		-- a card do nothing while you were choosing pinned mounts.
		domain.TogglePin(self.id)
		if chosenOnly then Addon:RefreshMountPicker() end
	elseif button == "LeftButton" and self.outfitID then
		domain.ToggleLink(self.outfitID, self.id)
		if chosenOnly then
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
	if edit.id and DOMAINS[edit.domain].SetPinDays(edit.id, days) then
		edit.previousDays = days
		Addon:RepaintMountCards()
	end
end

-- The mount body: the model scene.
local function BuildMountBody(card)
	local body = CreateFrame("Frame", nil, card)
	body:SetAllPoints()
	card.MountBody = body

	card.Scene = CreateFrame("ModelScene", nil, body, "NonInteractableModelSceneMixinTemplate")
	card.Scene:SetPoint("TOPLEFT", 5, -34)
	card.Scene:SetPoint("BOTTOMRIGHT", -5, 5)
	card.Scene:EnableMouse(false)
	card.Scene:EnableMouseWheel(false)
	if card.Scene.SetMouseClickEnabled then card.Scene:SetMouseClickEnabled(false) end
	if card.Scene.SetMouseMotionEnabled then card.Scene:SetMouseMotionEnabled(false) end
	if card.Scene.SetPropagateMouseClicks then card.Scene:SetPropagateMouseClicks(true) end
	if card.Scene.SetPropagateMouseMotion then card.Scene:SetPropagateMouseMotion(true) end
end

-- The hearthstone body: a large icon, what kind of thing it is, whether it is
-- owned, and its cooldown. No model: the client exposes no item-to-effect
-- mapping, so nothing here claims to show the cast.
local function BuildHearthBody(card)
	local body = CreateFrame("Frame", nil, card)
	body:SetAllPoints()
	card.HearthBody = body

	card.BigIcon = body:CreateTexture(nil, "ARTWORK")
	card.BigIcon:SetSize(64, 64)
	card.BigIcon:SetPoint("TOPLEFT", 12, -38)
	card.BigIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local lines = {}
	for i, font in ipairs({ "GameFontNormalSmall", "GameFontNormalSmall",
		"GameFontDisable", "GameFontNormalSmall" }) do
		local line = body:CreateFontString(nil, "OVERLAY", font)
		line:SetPoint("TOPLEFT", card.BigIcon, "TOPRIGHT", 8, -2 - (i - 1) * 16)
		line:SetPoint("RIGHT", body, "RIGHT", -8, 0)
		line:SetJustifyH("LEFT")
		lines[i] = line
	end
	card.KindBadge, card.Cooldown, card.OwnedState, card.PinState =
		lines[1], lines[2], lines[3], lines[4]
end

-- Creates the controls shared by every recycled card, whichever domain it is
-- painted for: background, border, name row, pin star, pin expiry and the
-- linked-outfit chips. Each domain's body sits in its own layer.
local function BuildCard(card)
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

	BuildMountBody(card)
	BuildHearthBody(card)

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
	card.PinButton:SetScript("OnClick", function()
		if card.id and card.owned ~= false then DOMAINS[card.domain].TogglePin(card.id) end
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

-- The domain's own body. Everything above and below it is PaintCard's.
local BODY_PAINTERS = {
	mounts = function(card, mount)
		ApplyCardNudge(card)
		SetCardModel(card, mount.mountID)
	end,
	hearthstones = function(card, row)
		card.BigIcon:SetTexture(row.icon or FALLBACK_ICON)
		card.BigIcon:SetDesaturated(not card.owned)
		card.KindBadge:SetText(row.kind == "toy" and "toy" or "item")
		card.Cooldown:SetText(card.owned and row.onCooldown and "on cooldown" or nil)
		if type(row.count) == "number" then
			card.OwnedState:SetText(("carried: %d"):format(row.count))
		else
			card.OwnedState:SetText(card.owned and "owned" or "not collected")
		end
		card.PinState:SetText(card.owned and card.isPinned and "pinned" or nil)
	end,
}

-- Updates a recycled card with one row of the domain on show. Rows carry
-- mountID for mounts and itemID for hearthstones.
function Addon:PaintMountCard(card, row)
	local domain = Domain()
	card.domain = domain
	card.id = row.mountID or row.itemID
	card.name = type(row.name) == "string" and row.name or ("item " .. tostring(card.id))
	-- Only a hearthstone can be listed without being owned; every mount row
	-- comes from the player's own collection.
	card.owned = domain == "mounts" or row.owned == true
	card.outfitID = mountPicker.mode == "outfit" and mountPicker.outfitID or nil
	card.Icon:SetTexture(row.icon or FALLBACK_ICON)
	card.Icon:SetDesaturated(not card.owned)
	card.Name:SetText(card.name)
	card:SetAlpha(card.owned and 1 or 0.45)
	card.MountBody:SetShown(domain == "mounts")
	card.HearthBody:SetShown(domain == "hearthstones")

	card:SetSize(CardSize())

	card.linkedOutfits = mountPicker.linkIndex[card.id]
	if mountPicker.mode == "pins" then
		self:PaintCardLinks(card, {})
	else
		self:PaintCardLinks(card, card.linkedOutfits, mountPicker.outfitID)
	end

	local isPinned = DOMAINS[domain].IsPinned(card.id)
	card.isPinned = isPinned
	card.FallbackStar:SetAtlas(isPinned and "auctionhouse-icon-favorite"
		or "auctionhouse-icon-favorite-off", false)
	card.PinButton:SetShown(card.owned)
	local store = PinDomain(domain)
	local days = store and Pins.DaysRemaining(store, card.id, time()) or nil
	card.PinRow:SetShown(mountPicker.mode == "pins" and days ~= nil)
	if mountPicker.mode == "pins" and days ~= nil then
		card.PinDays.id = card.id
		card.PinDays.domain = domain
		card.PinDays.previousDays = days
		if not card.PinDays:HasFocus() then card.PinDays:SetText(tostring(days)) end
	end

	if card.owned and mountPicker.selected[card.id] == true then
		card:SetCardColors(unpack(CHOSEN_COLORS))
	else
		card:SetCardColors(unpack(PLAIN_COLORS))
	end

	BODY_PAINTERS[domain](card, row)
	card.Hover:Hide()
end

local function RefreshPickerState()
	local domain = DOMAINS[Domain()]
	mountPicker.selected = mountPicker.mode == "pins"
		and ActivePins(Domain())
		or domain.Selected(mountPicker.outfitID)
	mountPicker.linkIndex = domain.LinkIndex()
end

-- An outfit reads as its icon, its name and the category it lives in, in that
-- category's own colour: the same three things the main window's rows show,
-- so a name that appears twice is still tellable apart.
local function OutfitCategory(outfitID)
	local char = MogtrotCharDB
	if type(char) ~= "table" or type(char.assign) ~= "table" then return nil end
	local cat = type(char.cats) == "table" and char.cats[char.assign[outfitID] or 0]
	if not cat or cat.protected then return nil end
	return cat.name, ns.CategoryColor and ns.CategoryColor.Normalize(cat.color) or nil
end

-- Tree walks the roots in order, each category's own outfits before its
-- children, which is the order the main window's list is built from. Reusing
-- it means the two can never drift, and an alphabetical sort here would have
-- put the list in an order that appears nowhere else in the addon.
local function OutfitChoices(preselect)
	local choices = ns.Tree.OutfitChoices(MogtrotCharDB, Addon.outfitsByID)
	for _, choice in ipairs(choices) do
		local info = (Addon.outfitsByID or {})[choice.outfitID]
		local category, color = OutfitCategory(choice.outfitID)
		choice.icon = info and info.icon
		choice.tag = category
		choice.tagColor = color
		choice.preselected = preselect(choice.outfitID) or nil
		-- The category rides on the name line, so the breadcrumb would only
		-- add a second line saying the same thing.
		choice.path = nil
	end
	return choices
end

local function ChoosePickerOutfit()
	ns.OpenSearchPicker({
		title = "Choose an outfit",
		searchHint = "Search outfits",
		emptyText = "No outfits match.",
		items = OutfitChoices(function(outfitID)
			return mountPicker.outfitID == outfitID
		end),
		onChoose = function(chosen)
			Addon:SetMountPickerOutfit(chosen.outfitID)
		end,
	})
end

-- Every outfit, ticked where the hearthstone is linked; Apply links the
-- ticked ones and unlinks the rest.
function OpenHearthstoneLinks(itemID, name)
	local linked = {}
	for _, outfitID in ipairs(ns.OutfitLinks.IndexByLinked(hearth.links)[itemID] or {}) do
		linked[outfitID] = true
	end
	local choices = OutfitChoices(function(outfitID) return linked[outfitID] end)

	ns.OpenSearchPicker({
		title = ("Outfits using %s"):format(name or "hearthstone"),
		searchHint = "Search outfits",
		emptyText = "No outfits match.",
		multi = true,
		items = choices,
		buttons = { {
			text = "Apply",
			allowEmpty = true,
			onClick = function(chosen)
				hearth.applyLinks(itemID, ns.OutfitLinks.Want(choices, chosen))
				Addon:RepaintMountCards()
			end,
		} },
	})
end

function Addon:SetMountPickerOutfit(outfitID)
	if not mountPicker then return end
	mountPicker.mode = "outfit"
	mountPicker.outfitID = outfitID
	if Domain() == "mounts" then
		mountPicker.mounts, mountPicker.typeNote = CollectMounts(outfitID)
	end
	ShowPreview()
	self:RefreshMountPicker({ preserveScrollOffset = true })
end

function Addon:SetMountPickerPinMode()
	if not mountPicker then return end
	mountPicker.mode = "pins"
	if Domain() == "mounts" then
		mountPicker.mounts, mountPicker.typeNote = CollectMounts(nil)
	end
	HideEditPreview()
	self:RefreshMountPicker()
end

local OpenPairing

-- What each changeable word does. How they look is PairingHeaderUI's.
--
-- The domain word opens a menu rather than toggling on the spot: swapping the
-- whole window under the cursor with no warning reads as a misclick, and a
-- menu shows both choices instead of hiding one.
local function HeaderAction(action, segment)
	if action == "outfit" then return ChoosePickerOutfit() end
	if action == "mode" then
		if mountPicker.mode == "pins" then return ChoosePickerOutfit() end
		return Addon:SetMountPickerPinMode()
	end
	if action ~= "domain" then return end
	ns.PairingHeaderUI.ShowMenu(segment, "domain", function(choice)
		if choice == "hearthstones" and not hearth then return end
		local target = ns.PairingHeader.SwitchDomain({ domain = Domain(),
			mode = mountPicker.mode, outfitID = mountPicker.outfitID }, choice)
		if target then OpenPairing(target.domain, target.mode, target.outfitID) end
	end)
end

function Addon:PaintPickerChrome()
	local chosen = 0
	for _ in pairs(mountPicker.selected) do chosen = chosen + 1 end

	local info = self.outfitsByID and self.outfitsByID[mountPicker.outfitID]
	mountPicker.PaintHeader({
		domain = Domain(),
		mode = mountPicker.mode,
		outfitName = info and info.name,
		outfitIcon = info and info.icon,
		chosen = chosen,
	})
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

-- The rows the hearthstone domain lists: the collection read, or the bare
-- registry when that read fails, so the window never opens empty.
local function HearthRows()
	local ok, rows = pcall(hearth.collection.Rows, hearth.adapter, hearth.registry)
	local found = {}
	for _, row in ipairs(ok and type(rows) == "table" and rows or {}) do
		if type(row) == "table" and type(row.itemID) == "number" then
			found[#found + 1] = row
		end
	end
	if #found > 0 then return found end
	for itemID, entry in pairs(hearth.registry.entries or {}) do
		if type(itemID) == "number" and type(entry) == "table" then
			found[#found + 1] = { itemID = itemID, kind = entry.kind }
		end
	end
	return found
end

local function MountMatches()
	local matches = ns.MountFilter.Apply(mountPicker.mounts, mountPicker.filter,
		mountPicker.selected)
	if mountPicker.mode == "pins" then
		local original = {}
		for i, mount in ipairs(matches) do original[mount.mountID] = i end
		local domain = MountPinDomain()
		table.sort(matches, function(a, b)
			local ap, bp = Addon:IsMountPinned(a.mountID), Addon:IsMountPinned(b.mountID)
			if ap ~= bp then return ap end
			local ar = domain and domain.records[a.mountID]
			local br = domain and domain.records[b.mountID]
			local aa, ba = ar and ar.acquiredAt, br and br.acquiredAt
			if (aa ~= nil) ~= (ba ~= nil) then return aa ~= nil end
			if aa and aa ~= ba then return aa > ba end
			return original[a.mountID] < original[b.mountID]
		end)
	end
	mountPicker.Note:SetText("")
	return matches
end

local function HearthMatches()
	local list = ns.HearthstoneCollection.PickerList(HearthRows(), {
		query = mountPicker.filter.query,
		now = GetTime(),
		cooldown = function(itemID)
			return hearth.collection.Cooldown(hearth.adapter, itemID)
		end,
	})
	mountPicker.Note:SetText(list.note)
	return list.rows
end

-- Rebuilds the visible grid after search or filter controls change.
function Addon:RefreshMountPicker(options)
	if not mountPicker or not mountPicker:IsShown() then return end
	if InCombatLockdown() then return end
	local scrollOffset = options and options.preserveScrollOffset
		and mountPicker.Box:GetDerivedScrollOffset()

	RefreshPickerState()

	local matches = Domain() == "hearthstones" and HearthMatches() or MountMatches()
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

-- Cooldowns, bag counts and toy ownership move under an open hearthstone
-- window; nothing else needs the refresh.
function Addon:RefreshHearthstonePicker()
	if self:IsHearthstonePickerOpen() then self:RefreshMountPicker() end
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
	mountPicker.Box:ForEachFrame(function(card, row) self:PaintMountCard(card, row) end)
	self:PaintPickerChrome()
end

-- Builds the pairing window the first time it is opened.
local function EnsureMountPicker()
	if mountPicker then return mountPicker end

	local width, height = PickerSize()

	mountPicker = CreateFrame("Frame", "MogtrotMountPicker", UIParent, "BackdropTemplate")
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

	mountPicker.CloseButton = CreateFrame("Button", nil, mountPicker, "UIPanelCloseButton")
	mountPicker.CloseButton:SetSize(PICKER_HEADER_CONTROL_H, PICKER_HEADER_CONTROL_H)
	mountPicker.CloseButton:SetPoint("TOPRIGHT", -UI.CloseButtonInset, -UI.CloseButtonInset)

	mountPicker.HeaderRow = CreateFrame("Frame", nil, mountPicker)
	mountPicker.HeaderRow:SetPoint("TOPLEFT", UI.Pad, -UI.Pad)
	mountPicker.HeaderRow:SetPoint("RIGHT", mountPicker.CloseButton, "LEFT", -8, 0)
	mountPicker.HeaderRow:SetHeight(PICKER_HEADER_CONTROL_H)

	-- The header is one sentence and its changeable words are its controls,
	-- so it is laid out from PairingHeader's segments rather than from fixed
	-- widgets. Nothing here knows what the sentence says.
	mountPicker.PaintHeader = ns.PairingHeaderUI.New(mountPicker.HeaderRow,
		PICKER_HEADER_CONTROL_H, HeaderAction, ns.PairingHeader.Segments)

	mountPicker.SearchBox = CreateFrame("EditBox", nil, mountPicker, "SearchBoxTemplate")
	mountPicker.SearchBox:SetSize(220, 20)
	mountPicker.SearchBox:SetAutoFocus(false)
	mountPicker.SearchBox:SetPoint("TOPLEFT", UI.Pad + 6, -(UI.Pad + 32))
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

	mountPicker.Note = mountPicker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	mountPicker.Note:SetPoint("BOTTOMLEFT", UI.Pad + 6, 8)

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
	mountPicker.View:SetElementInitializer("Button", function(card, row)
		BuildCard(card)
		Addon:PaintMountCard(card, row)
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
		GameTooltip:AddLine("Always three by three; the cards get bigger.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	mountPicker.ResizeGrip:SetScript("OnLeave", GameTooltip_Hide)

	mountPicker:SetScript("OnHide", function()
		HideEditPreview()
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

-- Opens the window on one domain and mode with fresh search and filters.
-- Opening while it is shown for the same domain only changes the outfit, so
-- a second click on a row keeps what was typed.
function OpenPairing(domain, mode, outfitID)
	if InCombatLockdown() then return end
	if domain == "hearthstones" and not hearth then return end

	-- The library is the other full-size window about these outfits, so it
	-- closes rather than sitting underneath.
	if ns.LibraryUI and ns.LibraryUI.Hide then ns.LibraryUI.Hide() end

	local picker = EnsureMountPicker()
	if picker:IsShown() and picker.domain == domain and mode == "outfit" then
		Addon:SetMountPickerOutfit(outfitID)
		picker.SearchBox:SetFocus()
		return
	end

	picker.domain = domain
	picker.outfitID = outfitID
	picker.mode = mode
	if domain == "mounts" then
		picker.mounts, picker.typeNote = CollectMounts(outfitID)
	else
		picker.mounts, picker.typeNote = nil, nil
	end
	picker.filter = ns.MountFilter.DefaultState(ValidMountTypes())
	picker.Filter:ValidateResetState()
	picker.Filter:SetShown(domain == "mounts")
	if picker.SearchBox.Instructions then
		picker.SearchBox.Instructions:SetText(SEARCH_HINT[domain])
	end
	picker.SearchBox:SetText("")
	picker.scrollToTop = true

	Addon:HidePreview()
	picker:Show()
	if mode == "pins" then HideEditPreview() else ShowPreview() end
	Addon:RefreshMountPicker()
	picker.SearchBox:SetFocus()
end

function Addon:OpenMountPicker(outfitID)
	OpenPairing("mounts", "outfit", outfitID)
end

function Addon:OpenMountPins()
	OpenPairing("mounts", "pins")
end

-- Wires the hearthstone domain once the character's store carries it.
--
-- hdeps = {
--     registry,     -- curated HearthstoneDefinitions
--     collection,   -- HearthstoneCollection (Rows, Cooldown)
--     adapter,      -- live-ownership adapter handed to collection
--     links,        -- outfitID -> { [itemID] = true }
--     account,      -- store carrying account.pins[pinsDomain]
--     pinsDomain,   -- default "hearthstones"
--     getLinks = function(outfitID) -> { [itemID] = true },
--     toggleLink = function(outfitID, itemID) -> added,
--     applyLinks = function(itemID, want) -> added, removed,
--     getCurrentOutfit = function() -> outfitID or nil,
-- }
function Addon:AttachHearthstones(hdeps)
	hearth = hdeps
end

function Addon:OpenHearthstonePicker(outfitID)
	local current = hearth and hearth.getCurrentOutfit and hearth.getCurrentOutfit()
	OpenPairing("hearthstones", "outfit", outfitID or current)
end

function Addon:OpenHearthstonePins()
	OpenPairing("hearthstones", "pins")
end

	return Addon
end

ns.MountPickerUI = MountPickerUI
return MountPickerUI
