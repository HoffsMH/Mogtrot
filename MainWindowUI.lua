local ADDON_NAME, ns = ...

-- Builds and paints the outfit list window where users organise and wear outfits.
local MainWindowUI = {}

MainWindowUI.LibraryIcon = "Interface\\QuestFrame\\UI-QuestLog-BookIcon"
MainWindowUI.SettingsLabel = ""
MainWindowUI.SettingsTooltip = "Mogtrot settings"

function MainWindowUI.OpenLibrary(libraryUI)
	if type(libraryUI) ~= "table" or type(libraryUI.Toggle) ~= "function" then
		return false
	end
	libraryUI.Toggle()
	return true
end

local function StyleHeaderControl(button, width, atlas, label)
	local MainWindow = ns.UI.MainWindow
	button:SetSize(width, MainWindow.HeaderButtonHeight)
	button.Highlight = button:CreateTexture(nil, "BACKGROUND")
	button.Highlight:SetAllPoints()
	button.Highlight:SetColorTexture(1, 1, 1, 0.08)
	button.Highlight:Hide()

	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetSize(MainWindow.HeaderControlIconSize,
		MainWindow.HeaderControlIconSize)
	button.Icon:SetPoint("LEFT", 2, 0)
	button.Icon:SetAtlas(atlas, false)
	button.Icon:SetVertexColor(0.75, 0.75, 0.75)

	button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	button.Text:SetPoint("LEFT", button.Icon, "RIGHT", 3, 0)
	button.Text:SetText(label)
	button.Text:SetTextColor(0.75, 0.75, 0.75)
end

local function HeaderControlEnter(button)
	button.Highlight:Show()
	button.Icon:SetVertexColor(1, 0.82, 0)
	button.Text:SetTextColor(1, 0.82, 0)
end

local function HeaderControlLeave(button)
	button.Highlight:Hide()
	button.Icon:SetVertexColor(0.75, 0.75, 0.75)
	button.Text:SetTextColor(0.75, 0.75, 0.75)
	GameTooltip:Hide()
end

local function BuildWindow(Addon)
	local UI, MainWindow = ns.UI, ns.UI.MainWindow

	local frame = CreateFrame("Frame", "MogtrotFrame", UIParent, "BackdropTemplate")
	Addon.window = frame
	Addon.frame = frame
	frame:SetSize(MainWindow.Width, 200)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		MogtrotDB.position = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.92)
	frame:Hide()

	frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.Title:SetPoint("TOPLEFT", UI.Pad, -UI.Pad)
	frame.Title:SetJustifyH("LEFT")
	frame.Title:SetWordWrap(false)
	return frame
end

-- Pins, close, add category, settings and library. The Blizzard list button
-- is secure and is built later, by BuildBlizzardListButton.
local function BuildHeaderControls(Addon, frame, NEW_CATEGORY_NAME)
	local UI, MainWindow = ns.UI, ns.UI.MainWindow

	frame.PinsButton = CreateFrame("Button", nil, frame)
	StyleHeaderControl(frame.PinsButton, 42, "auctionhouse-icon-favorite", "Pins")
	frame.PinsButton.Icon:SetSize(12, 12)
	frame.PinsButton:SetScript("OnClick", function() Addon:OpenMountPins() end)
	frame.PinsButton:SetScript("OnEnter", function(self)
		HeaderControlEnter(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Pinned mounts")
		GameTooltip:AddLine("View and edit mounts used across outfits.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	frame.PinsButton:SetScript("OnLeave", function(self)
		HeaderControlLeave(self)
	end)

	frame.CloseButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.CloseButton:SetPoint("TOPRIGHT", -UI.CloseButtonInset, -UI.CloseButtonInset)

	frame.NewCategoryButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.NewCategoryButton:SetNormalFontObject(GameFontHighlightSmall)
	frame.NewCategoryButton:SetHighlightFontObject(GameFontHighlightSmall)
	frame.NewCategoryButton:SetDisabledFontObject(GameFontDisableSmall)
	frame.NewCategoryButton:SetText("Add category")
	local newCategoryLabel = frame.NewCategoryButton:GetFontString()
	newCategoryLabel:ClearAllPoints()
	newCategoryLabel:SetAllPoints()
	newCategoryLabel:SetJustifyH("CENTER")
	frame.NewCategoryButton:SetSize(frame.NewCategoryButton:GetTextWidth() + 16, 16)
	frame.NewCategoryButton:SetScript("OnClick", function()
		Addon:CreateCategory(NEW_CATEGORY_NAME, nil, true)
	end)
	frame.NewCategoryButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Add category")
		GameTooltip:AddLine("Added at the top. Use a category's own + for a sub-category.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	frame.NewCategoryButton:SetScript("OnLeave", GameTooltip_Hide)

	frame.SettingsButton = CreateFrame("Button", nil, frame)
	StyleHeaderControl(frame.SettingsButton, MainWindow.HeaderControlIconSize + 4,
		"GM-icon-settings", MainWindowUI.SettingsLabel)
	frame.SettingsButton.Icon:SetTexture("Interface\\WorldMap\\GEAR_64GREY")
	frame.SettingsButton.Icon:SetTexCoord(0, 1, 0, 1)
	frame.SettingsButton.Icon:SetSize(MainWindow.HeaderControlIconSize,
		MainWindow.HeaderControlIconSize)
	frame.SettingsButton:SetPoint("RIGHT", frame.CloseButton, "LEFT",
		-MainWindow.HeaderControlGap, 0)
	frame.SettingsButton.Icon:SetVertexColor(0.4, 0.4, 0.4)
	frame.SettingsButton.Text:SetTextColor(0.4, 0.4, 0.4)
	frame.SettingsButton:Disable()
	frame.SettingsButton:SetScript("OnClick", function()
		if Addon.settingsCategory and Settings and Settings.OpenToCategory then
			Settings.OpenToCategory(Addon.settingsCategory:GetID())
		end
	end)
	frame.SettingsButton:SetScript("OnEnter", function(self)
		HeaderControlEnter(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(MainWindowUI.SettingsTooltip)
		GameTooltip:Show()
	end)
	frame.SettingsButton:SetScript("OnLeave", function(self)
		HeaderControlLeave(self)
	end)

	frame.LibraryButton = CreateFrame("Button", nil, frame)
	StyleHeaderControl(frame.LibraryButton, 55, "GlyphIcon-Spellbook", "Library")
	frame.LibraryButton.Icon:SetTexture(MainWindowUI.LibraryIcon)
	frame.LibraryButton.Icon:SetTexCoord(0, 1, 0, 1)
	frame.LibraryButton:SetPoint("RIGHT", frame.SettingsButton, "LEFT",
		-MainWindow.HeaderControlGap, 0)
	frame.LibraryButton:SetScript("OnClick", function()
		MainWindowUI.OpenLibrary(ns.LibraryUI)
	end)
	frame.LibraryButton:SetScript("OnEnter", function(self)
		HeaderControlEnter(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Outfit library")
		GameTooltip:AddLine("Every look you have captured.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	frame.LibraryButton:SetScript("OnLeave", function(self)
		HeaderControlLeave(self)
	end)
end

local function BuildSearchRow(Addon, frame, macros)
	local UI = ns.UI

	frame.SearchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	frame.SearchBox:SetHeight(20)
	frame.SearchBox:SetAutoFocus(false)
	frame.SearchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.Pad + 6, -(UI.Pad + 18))
	frame.SearchBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.Pad, -(UI.Pad + 18))

	macros.WatchActionBars()
	if frame.SearchBox.Instructions then
		-- Wrapped placeholder text spills out of the box rather than clipping,
		-- so the hint is short and wrapping is off.
		frame.SearchBox.Instructions:SetText("Search outfits")
		frame.SearchBox.Instructions:SetWordWrap(false)
	end
	frame.SearchBox:HookScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or "")
		local query = (text ~= "") and strlower(text) or nil
		if query == Addon.searchText then return end
		Addon.searchText = query
		Addon.scrollToTop = true
		Addon:Refresh()
	end)

	frame.HideEmptyCategories = CreateFrame("CheckButton", nil, frame,
		"UICheckButtonTemplate")
	frame.HideEmptyCategories:SetSize(18, 18)
	frame.HideEmptyCategories:SetPoint("TOPLEFT", frame.SearchBox, "BOTTOMLEFT", -4, -1)
	frame.HideEmptyCategories.Label = frame.HideEmptyCategories:CreateFontString(nil,
		"OVERLAY", "GameFontHighlightSmall")
	frame.HideEmptyCategories.Label:SetPoint("LEFT", frame.HideEmptyCategories,
		"RIGHT", 2, 0)
	frame.HideEmptyCategories.Label:SetText("Hide empty categories")
	frame.HideEmptyCategories:SetHitRectInsets(0,
		-(frame.HideEmptyCategories.Label:GetStringWidth() + 2), 0, 0)
	frame.HideEmptyCategories:SetScript("OnClick", function(self)
		MogtrotDB.hideEmptyCategories = self:GetChecked() and true or false
		Addon:Refresh()
	end)

	frame.Notice = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.Notice:SetPoint("BOTTOMLEFT", UI.Pad, 8)
	frame.Notice:SetPoint("BOTTOMRIGHT", -UI.Pad, 8)
	frame.Notice:SetJustifyH("LEFT")
end

local function BuildList(Addon, frame)
	local UI, MainWindow = ns.UI, ns.UI.MainWindow

	Addon.listBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
	Addon.listBox:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.Pad,
		-(UI.Pad + 18 + MainWindow.SearchRowHeight))
	-- Width is fixed because the window only resizes vertically; the 10px gutter is the bar.
	Addon.listBox:SetSize(MainWindow.Width - 2 * UI.Pad - 10, MainWindow.MinListHeight)

	Addon.listBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	Addon.listBar:SetPoint("TOPLEFT", Addon.listBox, "TOPRIGHT", 2, 0)
	Addon.listBar:SetPoint("BOTTOMLEFT", Addon.listBox, "BOTTOMRIGHT", 2, 0)

	Addon.listView = CreateScrollBoxListLinearView()

	-- Headers and outfit rows are different heights, which is the whole reason this needs
	-- an extent calculator rather than a single element extent.
	Addon.listView:SetElementExtentCalculator(function(_dataIndex, entry)
		return entry.kind == "cat" and MainWindow.HeaderHeight or MainWindow.RowHeight
	end)

	-- Indent moves the left edge only; the view stretches every row to the right edge, so
	-- nested rows line up on the right exactly as the hand-rolled layout did.
	-- Indent stops growing well before it can eat the row. Nesting past this still
	-- nests, it just stops stepping right: unbounded indent took the row width to
	-- nothing around depth 20, and a name is worth more than the depth cue.
	local MAX_INDENT_DEPTH = 6

	Addon.listView:SetElementIndentCalculator(function(entry)
		return math.min(entry.depth, MAX_INDENT_DEPTH) * MainWindow.Indent
	end)

	Addon.listView:SetElementFactory(function(factory, entry)
		if entry.kind == "cat" then
			factory("Button", function(header, data) Addon:InitHeaderRow(header, data) end)
		else
			factory(UI.ActionButtonTemplate, function(row, data) Addon:InitOutfitRow(row, data) end)
		end
	end)

	-- Otherwise a wheel tick is however tall the first entry happens to be, so the distance
	-- changed depending on whether the list started on a header.
	Addon.listView:SetPanExtent(MainWindow.RowHeight)

	ScrollUtil.InitScrollBoxListWithScrollBar(Addon.listBox, Addon.listBar, Addon.listView)
	-- Hides the bar when there is nothing to scroll. Held rather than discarded so its
	-- lifetime does not depend on Blizzard's callback table keeping it reachable.
	Addon.listBarVisibility = ScrollUtil.AddManagedScrollBarVisibilityBehavior(Addon.listBox, Addon.listBar)

	Addon.listBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function()
		Addon:OnListUpdated()
	end, Addon)

	-- Drag feedback lives on its own frames: rows are child frames and would otherwise
	-- draw on top of textures belonging to the window itself. Parented to the ScrollBox so
	-- its clipping applies to the feedback as well as to the rows it points at.
	local function CreateOverlay(alpha, height)
		local overlay = CreateFrame("Frame", nil, Addon.listBox)
		overlay:SetFrameLevel(Addon.listBox:GetFrameLevel() + 50)
		if height then overlay:SetHeight(height) end
		overlay.Texture = overlay:CreateTexture(nil, "OVERLAY")
		overlay.Texture:SetAllPoints()
		overlay.Texture:SetColorTexture(1, 0.82, 0, alpha)
		overlay:Hide()
		return overlay
	end

	frame.InsertMarker = CreateOverlay(0.9, 2)

	-- Shown when a drop would go *into* a category rather than between rows.
	frame.DropInto = CreateOverlay(0.25)

	-- The ScrollBox owns the wheel over the list itself. This covers the rest of the window
	-- - search row, pinned row, footer - so the wheel is never dead over a Mogtrot frame.
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_self, delta)
		Addon.listBox:OnMouseWheel(delta)
	end)

	-- The button is bigger than the art it draws, so the corner is easy to grab
	-- rather than being a 16px target you have to aim at.
	frame.ResizeGrip = CreateFrame("Button", nil, frame)
	frame.ResizeGrip:SetSize(24, 24)
	frame.ResizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.ResizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	frame.ResizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	for _, texture in ipairs({ frame.ResizeGrip:GetNormalTexture(),
		frame.ResizeGrip:GetHighlightTexture() }) do
		texture:ClearAllPoints()
		texture:SetSize(16, 16)
		texture:SetPoint("BOTTOMRIGHT", -2, 2)
	end
	frame.ResizeGrip:SetScript("OnMouseDown", function(self)
		-- Resizing a frame holding secure children is not allowed in combat.
		if InCombatLockdown() then return end
		self.resizing = true
		self.startY = select(2, GetCursorPosition())
		self.startHeight = Addon:GetListHeight()
		self:SetScript("OnUpdate", function(grip)
			local _, cursorY = GetCursorPosition()
			local delta = (grip.startY - cursorY) / UIParent:GetEffectiveScale()
			Addon:SetListHeight(grip.startHeight + delta)
		end)
	end)
	frame.ResizeGrip:SetScript("OnMouseUp", function(self)
		self.resizing = nil
		self:SetScript("OnUpdate", nil)
	end)
	frame.ResizeGrip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Drag to resize the list")
		GameTooltip:Show()
	end)
	frame.ResizeGrip:SetScript("OnLeave", GameTooltip_Hide)
end

local function BuildCategoryEditor(Addon, frame)
	-- Inline editor for creating and renaming categories.
	local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	Addon.editBox = editBox
	editBox:SetAutoFocus(false)
	editBox:SetHeight(20)
	-- Above the rows, and outside the ScrollBox so it is never clipped: the header it
	-- annotates lives two levels down inside the scroll target.
	editBox:SetFrameLevel(Addon.listBox:GetFrameLevel() + 60)
	editBox:Hide()
	editBox:SetScript("OnEnterPressed", function() Addon:CommitEdit() end)
	editBox:SetScript("OnEscapePressed", function() Addon:CancelEdit() end)
	editBox:SetScript("OnEditFocusLost", function() Addon:CommitEdit() end)

	function Addon:BeginRename(catID)
		if InCombatLockdown() then return end
		self.editing = catID
		self.editingNeedsFocus = true
		self:Refresh()
	end

	function Addon:CommitEdit()
		local catID = self.editing
		if not catID then return end
		self.editing = nil
		self.editingNeedsFocus = nil
		local text = editBox:GetText()
		editBox:Hide()
		editBox:ClearFocus()
		self:RenameCategory(catID, text)
	end

	function Addon:CancelEdit()
		if not self.editing then return end
		self.editing = nil
		self.editingNeedsFocus = nil
		editBox:Hide()
		editBox:ClearFocus()
		self:Refresh()
	end

	-- Runs at the end of every ScrollBox update, plain scrolling included. The editor is
	-- parented to the window rather than to a row, so recycling cannot strand it - but that
	-- also means this is the only thing that ever re-anchors it.
	function Addon:OnListUpdated()
		-- Play here, not in Refresh: the frame is only realised once the scroll lands,
		-- and this fires on every list update including that one.
		if self.flash then
			if GetTime() > self.flash.expires then
				self.flash = nil
			else
				local want = self.flash
				local target = self.listBox:FindFrameByPredicate(function(_frame, entry)
					local id = entry.kind == "cat" and entry.catID or entry.outfitID
					return entry.kind == want.kind and id == want.id
				end)
				if target and target.FlashAnim then
					self.flash = nil
					target.FlashAnim:Stop()
					target.FlashAnim:Play()
				end
			end
		end

		if self.editing then
			local header = self.listBox:FindFrameByPredicate(function(_rowFrame, entry)
				return entry.kind == "cat" and entry.catID == self.editing
			end)

			if header then
				editBox:ClearAllPoints()
				editBox:SetPoint("LEFT", header.Arrow, "RIGHT", 4, 0)
				editBox:SetWidth(header:GetWidth() - 60)
				editBox:Show()
				if self.editingNeedsFocus then
					self.editingNeedsFocus = nil
					local cat = MogtrotCharDB.cats[self.editing]
					editBox:SetText(cat and cat.name or "")
					editBox:SetFocus()
					editBox:HighlightText()
				end
			else
				-- The category scrolled out of view, so drop the edit. Cleared by hand rather
				-- than through CancelEdit, which refreshes and would re-enter this update.
				-- Clearing self.editing first is what makes the resulting OnEditFocusLost a
				-- no-op instead of a rename.
				self.editing = nil
				self.editingNeedsFocus = nil
				editBox:Hide()
				editBox:ClearFocus()
			end
		end

		local view = self.listView
		local total = view:GetDataProviderSize()
		self.positionText = (total > 0 and self.listBox:HasScrollableExtent())
			and string.format("rows %d-%d of %d", view:GetDataIndexBegin(), view:GetDataIndexEnd(), total)
			or nil
		self:UpdateNotice()
	end
end

local function RemoveEscapeFrame()
	for index = #UISpecialFrames, 1, -1 do
		if UISpecialFrames[index] == "MogtrotFrame" then
			table.remove(UISpecialFrames, index)
		end
	end
end

local function AttachEscapeClosing(Addon)
	function Addon:SetEscapeClosing(enabled)
		RemoveEscapeFrame()
		if enabled then table.insert(UISpecialFrames, "MogtrotFrame") end
	end

	-- Blizzard cannot hide a frame referenced by secure controls while combat is
	-- locked down. Outside combat, UISpecialFrames gives the window normal ESC behavior.
	Addon:SetEscapeClosing(not InCombatLockdown())
end

local function ClearSummonClick(button)
	button:SetAttribute("type", nil)
	button:SetAttribute("*clickbutton1", nil)
end

-- A keybinding clicks on both edges and the secure action fires on the up
-- edge, so the summon is chosen there once and the down edge does nothing.
function MainWindowUI.SummonPreClick(button, Addon, down)
	if down then return end
	if InCombatLockdown() then
		Addon:SummonForActiveOutfit(false)
		return
	end
	ClearSummonClick(button)
	if Addon:SummonForActiveOutfit(true) then
		button:SetAttribute("type", "click")
		button:SetAttribute("*clickbutton1", _G.LM_B1)
	end
end

-- The named buttons the Mogtrot macros and keybindings click.
local function BuildClickButtons(Addon, frame, deps)
	local UI = ns.UI
	local Wear = deps.Wear
	local OutfitWear_PreClick = deps.outfitWearPreClick
	local OutfitWear_PostClick = deps.outfitWearPostClick
	local hearthstoneController = deps.hearthstoneController

	-- Secure toggle: lets "/click MogtrotToggle" and a keybinding open the frame,
	-- legally, even in combat. Deliberately unparented and never shown.
	local toggle = CreateFrame("Button", "MogtrotToggle", nil, "SecureHandlerClickTemplate")
	toggle:SetSize(1, 1)
	toggle:RegisterForClicks("AnyUp")
	toggle:SetFrameRef("main", frame)
	toggle:SetAttribute("_onclick", [[
		local f = self:GetFrameRef("main")
		if f:IsShown() then
			f:Hide()
		else
			f:Show()
		end
	]])

	-- The ordinary Mogtrot route, with a conditional secure proxy to LiteMount's
	-- published LM_B1 button when the pure plan delegates.
	local summonClick = CreateFrame("Button", "MogtrotSummon", nil,
		"SecureActionButtonTemplate")
	summonClick:SetSize(1, 1)
	summonClick:RegisterForClicks("AnyDown", "AnyUp")
	summonClick:SetAttribute("useOnKeyDown", false)

	summonClick:SetScript("PreClick", function(self, _, down)
		MainWindowUI.SummonPreClick(self, Addon, down)
	end)
	summonClick:SetScript("PostClick", function(self)
		if not InCombatLockdown() then ClearSummonClick(self) end
	end)
	summonClick:RegisterEvent("PLAYER_REGEN_DISABLED")
	summonClick:SetScript("OnEvent", ClearSummonClick)

	-- The macro targets one stable button, while each click chooses a fresh outfit
	-- before the insecure action handler reads these attributes.
	local leastWornClick = CreateFrame("Button", "MogtrotLeastWorn", nil,
		UI.ActionButtonTemplate)
	leastWornClick:SetSize(1, 1)
	leastWornClick:RegisterForClicks("AnyDown", "AnyUp")
	leastWornClick:SetAttribute("useOnKeyDown", false)

	local function ClearLeastWornClick(self)
		self:SetAttribute("type", nil)
		self:SetAttribute("action", nil)
		self:SetAttribute("outfit-index", nil)
		self.outfitID = nil
	end

	leastWornClick:SetScript("PreClick", function(self, button, down)
		if down or InCombatLockdown() then return end
		ClearLeastWornClick(self)
		Addon:SyncOutfits()

		local eligible = Wear.LeastWornEligible(MogtrotCharDB, Addon.outfitsByID)
		local outfitID = Wear.ChooseLeastWorn(Addon:WearSnapshot(), eligible,
			C_TransmogOutfitInfo.GetActiveOutfitID())
		local info = outfitID and Addon.outfitsByID[outfitID]
		if not info then
			UIErrorsFrame:AddMessage("Mogtrot: no other categorized outfit is available.",
				1, 0.3, 0.3)
			return
		end

		self.outfitID = outfitID
		self:SetAttribute("type", "outfit")
		self:SetAttribute("action", "change")
		self:SetAttribute("outfit-index", info.index)
		OutfitWear_PreClick(self, button, down)
	end)
	leastWornClick:SetScript("PostClick", function(self, button, down)
		OutfitWear_PostClick(self, button, down)
		if not InCombatLockdown() then ClearLeastWornClick(self) end
	end)
	-- The macro targets one stable action button. Core may inject the controller
	-- after its domains are composed; without one, the button remains inert.
	local hearthstoneClick = CreateFrame("Button", "MogtrotHearthstone", nil,
		UI.ActionButtonTemplate)
	hearthstoneClick:SetSize(1, 1)
	hearthstoneClick:RegisterForClicks("AnyDown", "AnyUp")
	hearthstoneClick:SetAttribute("useOnKeyDown", false)

	local function ClearHearthstoneClick()
		if InCombatLockdown() then return end
		hearthstoneClick:SetAttribute("type", nil)
		hearthstoneClick:SetAttribute("toy", nil)
		hearthstoneClick:SetAttribute("item", nil)
	end

	hearthstoneClick:SetScript("PreClick", function(_, _, down)
		if down then return end
		if type(hearthstoneController) == "table"
			and type(hearthstoneController.PreClick) == "function" then
			hearthstoneController:PreClick()
		else
			ClearHearthstoneClick()
		end
	end)
	hearthstoneClick:SetScript("PostClick", function(_, _, down)
		if down then return end
		if type(hearthstoneController) == "table"
			and type(hearthstoneController.PostClick) == "function" then
			hearthstoneController:PostClick()
		else
			ClearHearthstoneClick()
		end
	end)

	hearthstoneClick:RegisterEvent("PLAYER_REGEN_DISABLED")
	hearthstoneClick:SetScript("OnEvent", ClearHearthstoneClick)
end

local function BuildBlizzardListButton(frame)
	local UI, MainWindow = ns.UI, ns.UI.MainWindow

	-- Opens Blizzard's outfit list, where locking, renaming and icons live. That window
	-- can be shown anywhere - no transmogrifier needed - but it takes a real click on a
	-- secure handler: calling Click() from addon code carries taint and is refused.
	--
	-- Styled by hand rather than with UIPanelButtonTemplate: combining templates lets the
	-- button template's OnLoad replace SecureHandlerBaseTemplate's, and that OnLoad is what
	-- installs SetFrameRef and the restricted environment. Re-running it by hand is not an
	-- option either, since the template's own OnClick has to stay untainted.
	local blizzardListButton = CreateFrame("Button", "MogtrotBlizzardList", frame,
		"SecureHandlerClickTemplate")
	StyleHeaderControl(blizzardListButton, 68, "lootroll-icon-transmog", "Blizzard")
	blizzardListButton:SetPoint("RIGHT", frame.LibraryButton, "LEFT",
		-MainWindow.HeaderControlGap, 0)
	blizzardListButton:RegisterForClicks("AnyUp")
	frame.PinsButton:SetPoint("RIGHT", blizzardListButton, "LEFT",
		-(MainWindow.HeaderControlGap + 3), 0)
	blizzardListButton:SetAttribute("_onclick", [[
		local f = self:GetFrameRef("transmog")
		if not f then return end
		if f:IsShown() then
			f:Hide()
		else
			f:Show()
		end
	]])
	blizzardListButton:SetScript("PreClick", function(self)
		if InCombatLockdown() then return end
		-- Blizzard_Transmog is load-on-demand, so it may not exist until now.
		if not TransmogFrame and Transmog_LoadUI then
			Transmog_LoadUI()
		end
		if TransmogFrame then
			self:SetFrameRef("transmog", TransmogFrame)
		end
	end)
	blizzardListButton:SetScript("OnEnter", function(self)
		HeaderControlEnter(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Blizzard's outfit list")
		GameTooltip:AddLine("Locking, renaming and icons only work there. No NPC needed.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	local function LayoutTitleBar()
		local rightControls = frame.CloseButton:GetWidth()
			+ frame.PinsButton:GetWidth() + blizzardListButton:GetWidth()
			+ frame.LibraryButton:GetWidth() + frame.SettingsButton:GetWidth()
			+ MainWindow.HeaderControlGap * 4 + 3
			+ UI.CloseButtonInset
		local available = MainWindow.Width - UI.Pad - rightControls
		frame.Title:SetWidth(math.max(20, math.min(frame.Title:GetStringWidth(), available)))
	end

	blizzardListButton:SetScript("OnLeave", function(self)
		HeaderControlLeave(self)
	end)

	return LayoutTitleBar
end

-- List height, the footer notice, combat dimming, Refresh, and show and hide.
local function AttachListLayout(Addon, frame, LayoutTitleBar)
	local UI, MainWindow = ns.UI, ns.UI.MainWindow

	-- Pixel height of the scrolling area. Defaults to a row count, like Plumber's fixed
	-- ten-row list, then clamped so it can never exceed the screen at any UI scale.
	function Addon:GetListHeight()
		local height = MogtrotDB.listHeight or (MainWindow.DefaultListRows * MainWindow.RowHeight)
		local ceiling = math.max(MainWindow.MinListHeight, UIParent:GetHeight() - 220)
		return math.max(MainWindow.MinListHeight, math.min(height, MainWindow.MaxListHeight, ceiling))
	end

	function Addon:SetListHeight(height)
		MogtrotDB.listHeight = math.max(MainWindow.MinListHeight, math.min(height, MainWindow.MaxListHeight))
		self:UpdateListSize()
	end

	-- The grip drives this every frame while it is held, so it stops at geometry. Resizing
	-- the ScrollBox is enough on its own: it re-lays-out from its own size-changed handler,
	-- and no entry has to be rebuilt for that.
	function Addon:UpdateListSize()
		local contentHeight = self:GetListHeight()

		self.listBox:SetHeight(contentHeight)

		local clearRow = self:EnsureClearRow()
		clearRow:ClearAllPoints()
		-- Pinned below the list rather than after the last entry, so it does not move.
		clearRow:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.Pad,
			-(UI.Pad + 18 + MainWindow.SearchRowHeight + contentHeight))

		-- Constant: chrome + list budget + the pinned row + footer.
		frame:SetHeight(UI.Pad + 18 + MainWindow.SearchRowHeight
			+ contentHeight + MainWindow.RowHeight + 26)
	end

	function Addon:UpdateNotice()
		if InCombatLockdown() then
			frame.Notice:SetText("In combat - wearing an outfit is disabled")
		elseif self.positionText then
			frame.Notice:SetText(self.positionText)
		else
			frame.Notice:SetText("Drag rows and categories to organise")
		end
	end

	-- Greys the list and stops it taking clicks, because the game refuses to wear an
	-- outfit in combat and a row that looks live but does nothing is worse than one
	-- that looks unavailable. Only the list dims: the window, its scrollbar, the close
	-- button and ESC all keep working, which is the point of the rows not being
	-- protected. Applied to the box rather than per row, so pooled frames cannot
	-- arrive carrying a stale state.
	function Addon:SetCombatDimmed(dimmed)
		local clearRow = self:EnsureClearRow()

		if not self.combatShield then
			-- A frame that eats mouse input, rather than disabling each row. Rows are
			-- pooled, so per-row state would have to be re-applied on every paint and
			-- would be wrong the moment one was recycled mid-combat. EnableMouse on the
			-- list box would not do it either: it does not stop children being clicked.
			local shield = CreateFrame("Frame", nil, frame)
			shield:SetFrameLevel(self.listBox:GetFrameLevel() + 100)
			shield:SetPoint("TOPLEFT", self.listBox, "TOPLEFT", 0, 0)
			shield:SetPoint("BOTTOMRIGHT", clearRow, "BOTTOMRIGHT", 0, 0)
			shield:EnableMouse(true)
			shield:Hide()
			self.combatShield = shield
		end

		self.listBox:SetAlpha(dimmed and 0.45 or 1)
		clearRow:SetAlpha(dimmed and 0.45 or 1)
		self.combatShield:SetShown(dimmed)
		self:UpdateNotice()
	end

	function Addon:Refresh(whileHidden)
		if not whileHidden and not frame:IsShown() then return end

		self:SyncOutfits()
		self:UpdateListSize()
		self:PaintClearRow()

		local entries = self:BuildEntries()

		-- A fresh entry table every time means the view never recycles across a refresh, so
		-- rows are always repainted from current data. What is retained is a scroll
		-- percentage, not an entry index, which is how every Blizzard list behaves.
		local retain = ScrollBoxConstants.RetainScrollPosition
		if self.scrollToTop then
			retain = ScrollBoxConstants.DiscardScrollPosition
		end
		self.scrollToTop = nil
		self.listBox:SetDataProvider(CreateDataProvider(entries), retain)

		-- Scroll to something that just moved, so a move from a window does not leave
		-- the user looking at where it used to be. Requested by id and resolved against
		-- the list that now exists: entries are rebuilt every refresh, so holding the
		-- old entry table would scroll to something that no longer is.
		local reveal = self.reveal
		self.reveal = nil
		-- Handed to OnListUpdated rather than played here: the frame may not be
		-- realised until the scroll lands. Time-bounded so a row that never comes into
		-- view does not flash minutes later when it finally does.
		if reveal then self.flash = { kind = reveal.kind, id = reveal.id, expires = GetTime() + 3 } end
		if reveal then
			for i, entry in ipairs(entries) do
				local id = entry.kind == "cat" and entry.catID or entry.outfitID
				if entry.kind == reveal.kind and id == reveal.id then
					self.listBox:ScrollToElementDataIndex(i)
					break
				end
			end
		end

		local titleText = "Outfits"
		if self.searchText then
			local matches = 0
			for _, entry in ipairs(entries) do
				if entry.kind == "outfit" then matches = matches + 1 end
			end
			titleText = string.format("Outfits - %d shown", matches)
		end
		frame.Title:SetText(titleText)
		LayoutTitleBar()

		self:UpdateNotice()
	end

	frame:SetScript("OnShow", function()
		-- Combat may show the prepared window, but cannot rebuild its protected rows.
		if InCombatLockdown() then return end
		Addon:UpdateMacroDragControls()
		frame.HideEmptyCategories:SetChecked(MogtrotDB.hideEmptyCategories)
		Addon:Refresh()
		Addon:SetCombatDimmed(false)
	end)

	frame:SetScript("OnHide", function()
		Addon:CancelEdit()
		Addon:ClosePicker()
		ns.CloseSearchPicker()
		Addon:HidePreview()
		frame.SearchBox:SetText("")
		Addon.searchText = nil
	end)
end

function MainWindowUI.Attach(Addon, deps)
	assert(type(deps.openTitlePicker) == "function", "MainWindowUI requires openTitlePicker")
	assert(type(deps.countOutfitTitles) == "function", "MainWindowUI requires countOutfitTitles")
	assert(type(deps.copyOutfitTitles) == "function", "MainWindowUI requires copyOutfitTitles")
	assert(type(deps.clearOutfitTitles) == "function", "MainWindowUI requires clearOutfitTitles")

	-- Called in the order the window was always built: frames created in the
	-- same order keep the same draw order, and no secure frame moves.
	local menus = ns.MainWindowMenus.Attach(Addon, deps)
	local macros = ns.MacroSidebarUI.Attach(Addon, deps)
	local frame = BuildWindow(Addon)
	BuildHeaderControls(Addon, frame, deps.Tree.NEW_CATEGORY_NAME)
	BuildSearchRow(Addon, frame, macros)
	BuildList(Addon, frame)
	BuildCategoryEditor(Addon, frame)
	AttachEscapeClosing(Addon)
	BuildClickButtons(Addon, frame, deps)
	macros.BuildSidebar(frame)

	BINDING_HEADER_MOGTROT = "Mogtrot"
	_G["BINDING_NAME_CLICK MogtrotToggle:LeftButton"] = "Toggle outfit list"
	_G["BINDING_NAME_CLICK MogtrotSummon:LeftButton"] = "Summon a mount for this outfit"
	_G["BINDING_NAME_CLICK MogtrotLeastWorn:LeftButton"] = "Wear a least-worn outfit"
	-- Hearthstone dispatch is intentionally not a keybinding: the action-bar macro
	-- supplies the hardware click that permits the secure toy/item action.

	local LayoutTitleBar = BuildBlizzardListButton(frame)
	ns.MainWindowRows.Attach(Addon, deps, {
		frame = frame,
		showOutfitMenu = menus.ShowOutfitMenu,
		showCategoryMenu = menus.ShowCategoryMenu,
		macroIcon = macros.MacroIcon,
	})
	ns.MainWindowDrag.Attach(Addon, deps, frame)
	AttachListLayout(Addon, frame, LayoutTitleBar)

	return {
		frame = frame,
	}
end

ns.MainWindowUI = MainWindowUI
return MainWindowUI
