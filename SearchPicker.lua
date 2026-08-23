local _, ns = ...

-- One floating search-select window, shared by every caller that needs "type to
-- filter, pick, confirm". It knows nothing about outfits, categories or mounts: a
-- caller hands it a list of items and a list of confirm buttons, and gets its own
-- item tables back. Selection is keyed on the item table itself, so an item is free
-- to carry no id at all.
--
--   items   = { { name, path, note, noteDim, divider, preselected, ...caller's keys... } }
--   buttons = { { text, width, danger, tipTitle, tipBody, onClick(chosen) } }
--
-- buttons are listed left to right; Cancel is added on the right by the window.

local PAD = 10
local ROW_H = 34
local HEADER_H = 60
local FOOTER_H = 40
local WIDTH = 380
-- Only the window height: the ScrollBox derives everything else from its own rect.
local VISIBLE_ROWS = 10

local pickerWindow
local confirmButtons = {}
local RefreshItems
local RepaintRows

-- Matches the breadcrumb as well as the name, so "tier" finds everything filed
-- under Tier without having to remember what is in it.
local function FilteredItems()
	local query = pickerWindow.query
	if not query then return pickerWindow.items end

	local matches = {}
	for _, item in ipairs(pickerWindow.items) do
		if string.find(item.search, query, 1, true) then
			table.insert(matches, item)
		end
	end
	return matches
end

local function SelectedItems()
	local selectedItems = {}
	for _, item in ipairs(pickerWindow.items) do
		if pickerWindow.selectedItems[item] then table.insert(selectedItems, item) end
	end
	return selectedItems
end

local function Row_OnEnter(self)
	self.Hover:Show()
	local item = self.item
	if not item then return end

	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(item.name or "", 1, 0.82, 0)
	if item.path and item.path ~= "" then
		GameTooltip:AddLine(item.path, 0.5, 0.8, 1)
	end
	if item.note then
		GameTooltip:AddLine(item.note, 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

local function Row_OnLeave(self)
	self.Hover:Hide()
	GameTooltip:Hide()
end

local function Row_OnClick(self)
	local item = self.item
	if not item then return end

	if pickerWindow.multiSelect then
		pickerWindow.selectedItems[item] = (not pickerWindow.selectedItems[item]) or nil
	else
		-- Clicking the chosen row again keeps it. A single pick answers a question
		-- that has no useful "none of them", unlike a multi-select where zero is a
		-- real answer.
		pickerWindow.selectedItems = { [item] = true }
	end
	RepaintRows()
end

-- One-time construction. Rows come from the view's recycling pool, so nothing that
-- varies per item belongs here. Height and anchors are the view's to set.
local function BuildRow(row)
	if row.built then return end
	row.built = true

	row:RegisterForClicks("LeftButtonUp")

	row.Selected = row:CreateTexture(nil, "BACKGROUND")
	row.Selected:SetAllPoints()
	row.Selected:SetColorTexture(1, 0.82, 0, 0.14)
	row.Selected:Hide()

	row.Hover = row:CreateTexture(nil, "BACKGROUND")
	row.Hover:SetAllPoints()
	row.Hover:SetColorTexture(1, 1, 1, 0.07)
	row.Hover:Hide()

	-- Drawn only when more than one item can be picked: an empty box on a row that
	-- accepts a single choice would promise a multi-select that is not on offer.
	row.Box = row:CreateTexture(nil, "ARTWORK")
	row.Box:SetSize(18, 18)
	row.Box:SetPoint("LEFT", 4, 0)
	row.Box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
	row.Box:Hide()

	row.Check = row:CreateTexture(nil, "OVERLAY")
	row.Check:SetSize(18, 18)
	row.Check:SetPoint("CENTER", row.Box, "CENTER", 0, 0)
	row.Check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
	row.Check:Hide()

	row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Name:SetHeight(14)
	row.Name:SetJustifyH("LEFT")
	row.Name:SetWordWrap(false)

	row.Path = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.Path:SetHeight(12)
	row.Path:SetJustifyH("LEFT")
	row.Path:SetWordWrap(false)

	row.Note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Note:SetPoint("RIGHT", row, "RIGHT", -4, 0)
	row.Note:SetWidth(84)
	row.Note:SetJustifyH("RIGHT")
	row.Note:SetWordWrap(false)

	row.Divider = row:CreateTexture(nil, "ARTWORK")
	row.Divider:SetHeight(1)
	row.Divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 0)
	row.Divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
	row.Divider:SetColorTexture(1, 1, 1, 0.16)
	row.Divider:Hide()

	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", Row_OnLeave)
	row:SetScript("OnClick", Row_OnClick)
end

-- Everything that varies per item, so all of it is set on every paint: a pooled row
-- arrives carrying whatever it last displayed. A one-line item centres its name
-- rather than leaving a gap where a breadcrumb would have been.
local function PaintRow(row, item)
	local left = pickerWindow.multiSelect and 28 or 10
	local hasPath = item.path ~= nil and item.path ~= ""

	row.Name:ClearAllPoints()
	if hasPath then
		row.Name:SetPoint("TOPLEFT", row, "TOPLEFT", left, -5)
		row.Name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -92, -5)
		row.Path:ClearAllPoints()
		row.Path:SetPoint("TOPLEFT", row, "TOPLEFT", left, -20)
		row.Path:SetPoint("TOPRIGHT", row, "TOPRIGHT", -92, -20)
		row.Path:SetText(item.path)
	else
		row.Name:SetPoint("LEFT", row, "LEFT", left, 0)
		row.Name:SetPoint("RIGHT", row, "RIGHT", -92, 0)
	end
	row.Path:SetShown(hasPath)
	row.Name:SetText(item.name or "")

	row.Note:SetText(item.note or "")
	if item.noteDim then
		row.Note:SetTextColor(0.5, 0.5, 0.5)
	else
		row.Note:SetTextColor(1, 0.82, 0)
	end

	local isSelected = pickerWindow.selectedItems[item] == true
	row.Box:SetShown(pickerWindow.multiSelect)
	row.Check:SetShown(pickerWindow.multiSelect and isSelected)
	row.Selected:SetShown(isSelected)
	row.Divider:SetShown(item.divider == true)
	-- A row released while the cursor was over it keeps its hover.
	row.Hover:Hide()
	row.item = item
end

local function InitRow(row, item)
	BuildRow(row)
	PaintRow(row, item)
end

-- A count is appended only where more than one item can be chosen, so the label
-- names the exact number the click is about to change. Parenthesised rather than
-- "Replace in 3", which reads as a countdown at low numbers.
local function SetConfirmLabels(count)
	for _, button in ipairs(confirmButtons) do
		local spec = button.spec
		if spec then
			local text = spec.text
			if pickerWindow.multiSelect and count > 0 then
				text = ("%s (%d)"):format(text, count)
			end
			if spec.danger then
				text = RED_FONT_COLOR:WrapTextInColorCode(text)
			end
			button:SetText(text)
			button:SetEnabled(count > 0 or spec.allowEmpty == true)
		end
	end
end

-- The list itself changed, so the data provider is replaced. Every caller that gets
-- here also wants the top of the list, which is what discarding the scroll gives.
function RefreshItems()
	if not pickerWindow or not pickerWindow:IsShown() then return end

	local matches = FilteredItems()
	pickerWindow.ScrollBox:SetDataProvider(CreateDataProvider(matches),
		ScrollBoxConstants.DiscardScrollPosition)

	pickerWindow.EmptyMessage:SetShown(#matches == 0)
	SetConfirmLabels(#SelectedItems())
end

-- A click changes the selection, not the list. Repainting the realised rows keeps
-- the scroll position and avoids reassigning the data provider, which releases and
-- re-acquires every row.
function RepaintRows()
	if not pickerWindow or not pickerWindow:IsShown() then return end

	pickerWindow.ScrollBox:ForEachFrame(PaintRow)
	SetConfirmLabels(#SelectedItems())
end

local function Button_OnEnter(self)
	if not self.tipTitle then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(self.tipTitle)
	if self.tipBody then
		GameTooltip:AddLine(self.tipBody, 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

local function AcquireButton(index)
	local button = confirmButtons[index]
	if button then return button end

	button = CreateFrame("Button", nil, pickerWindow, "UIPanelButtonTemplate")
	button:SetHeight(22)
	button:SetScript("OnEnter", Button_OnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	confirmButtons[index] = button
	return button
end

-- Laid out right to left from Cancel, so the list reads in the order it is drawn.
-- Every button is rewired on every open, and any left over from a previous caller
-- loses its handler rather than sitting there still armed.
local function LayoutButtons(specs)
	local anchor = pickerWindow.Cancel

	for i = #specs, 1, -1 do
		local spec = specs[i]
		local button = AcquireButton(i)
		button.spec = spec
		button.tipTitle = spec.tipTitle
		button.tipBody = spec.tipBody
		button:SetWidth(spec.width or 90)
		button:ClearAllPoints()
		button:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
		button:SetScript("OnClick", function()
			local selectedItems = SelectedItems()
			if #selectedItems == 0 and not spec.allowEmpty then return end
			spec.onClick(selectedItems)
			pickerWindow:Hide()
		end)
		button:Show()
		anchor = button
	end

	for i = #specs + 1, #confirmButtons do
		confirmButtons[i].spec = nil
		confirmButtons[i]:SetScript("OnClick", nil)
		confirmButtons[i]:Hide()
	end
end

local function EnsureWindow()
	if pickerWindow then return pickerWindow end

	pickerWindow = CreateFrame("Frame", "MogtrotSearchPicker", UIParent, "BackdropTemplate")
	local window = pickerWindow
	window:SetSize(WIDTH, HEADER_H + VISIBLE_ROWS * ROW_H + FOOTER_H)
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", function(self) self:StartMoving() end)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		MogtrotDB.searchPosition = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	window:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	window:SetBackdropColor(0, 0, 0, 0.94)

	window.CloseButton = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	window.CloseButton:SetPoint("TOPRIGHT", 0, 0)

	window.Title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.Title:SetPoint("TOPLEFT", PAD, -PAD)
	window.Title:SetPoint("RIGHT", window.CloseButton, "LEFT", -4, 0)
	window.Title:SetJustifyH("LEFT")
	window.Title:SetWordWrap(false)

	window.SearchBox = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
	window.SearchBox:SetHeight(20)
	window.SearchBox:SetAutoFocus(false)
	window.SearchBox:SetPoint("TOPLEFT", window, "TOPLEFT", PAD + 6, -(PAD + 20))
	window.SearchBox:SetPoint("TOPRIGHT", window, "TOPRIGHT", -PAD, -(PAD + 20))
	window.SearchBox:HookScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or "")
		local query = (text ~= "") and strlower(text) or nil
		if query == window.query then return end
		window.query = query
		RefreshItems()
	end)

	window.EmptyMessage = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	window.EmptyMessage:SetPoint("TOP", window, "TOP", 0, -(HEADER_H + 20))
	window.EmptyMessage:Hide()

	window.ScrollBox = CreateFrame("Frame", nil, window, "WowScrollBoxList")
	window.ScrollBox:SetPoint("TOPLEFT", window, "TOPLEFT", PAD, -HEADER_H)
	-- The 12px gutter on the right is the scrollbar's.
	window.ScrollBox:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -(PAD + 12), FOOTER_H)

	window.ScrollBar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
	window.ScrollBar:SetPoint("TOPLEFT", window.ScrollBox, "TOPRIGHT", 2, 0)
	window.ScrollBar:SetPoint("BOTTOMLEFT", window.ScrollBox, "BOTTOMRIGHT", 2, 0)

	window.ListView = CreateScrollBoxListLinearView()
	window.ListView:SetElementExtent(ROW_H)
	window.ListView:SetElementInitializer("Button", InitRow)

	ScrollUtil.InitScrollBoxListWithScrollBar(window.ScrollBox, window.ScrollBar, window.ListView)
	-- Hides the bar when there is nothing to scroll. Held rather than discarded so
	-- its lifetime does not depend on Blizzard's callback table keeping it reachable.
	window.ScrollBarVisibility = ScrollUtil.AddManagedScrollBarVisibilityBehavior(
		window.ScrollBox, window.ScrollBar)

	-- The ScrollBox owns the wheel over the list. This covers the rest of the window
	-- so the wheel is never dead over the header or the footer.
	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_self, delta)
		window.ScrollBox:OnMouseWheel(delta)
	end)

	window.Cancel = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	window.Cancel:SetSize(80, 22)
	window.Cancel:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -PAD, PAD)
	window.Cancel:SetText("Cancel")
	window.Cancel:SetScript("OnClick", function() window:Hide() end)

	window:SetScript("OnHide", function()
		GameTooltip:Hide()
	end)

	-- No secure children here, so ESC can stay registered in combat too.
	table.insert(UISpecialFrames, "MogtrotSearchPicker")

	local pos = MogtrotDB.searchPosition
	if pos then
		window:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	else
		window:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
	end

	window:Hide()
	return window
end

-- Every open replaces the whole configuration, since the window may still be up for
-- a different caller.
function ns.OpenSearchPicker(config)
	local win = EnsureWindow()

	win.items = config.items or {}
	win.multiSelect = config.multi == true
	win.query = nil

	-- An item flagged preselected starts ticked, so the window opens showing the
	-- state as it is rather than blank. The caller decides what unticking means.
	win.selectedItems = {}
	for _, item in ipairs(win.items) do
		if item.preselected then win.selectedItems[item] = true end
	end

	-- The picker owns the list it is handed for as long as it is open, so the
	-- lowercased haystack goes on the item rather than into a parallel table.
	for _, item in ipairs(win.items) do
		item.search = strlower((item.name or "") .. " " .. (item.path or ""))
	end

	win.Title:SetText(config.title or "")
	win.EmptyMessage:SetText(config.emptyText or "Nothing matches.")
	if win.SearchBox.Instructions then
		win.SearchBox.Instructions:SetText(config.searchHint or "Search")
	end
	win.SearchBox:SetText("")

	LayoutButtons(config.buttons or {})

	win:Show()
	RefreshItems()
	win.SearchBox:SetFocus()
end

function ns.CloseSearchPicker()
	if pickerWindow then pickerWindow:Hide() end
end
