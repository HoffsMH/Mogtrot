local _, ns = ...
local UI = ns.UI

-- Hearthstone picker: same chrome as the mount picker (header row with the
-- outfit, chosen count, mode switch, search box, docked outfit preview, and a
-- three-column scroll box of pooled cards) over a curated hearthstone
-- registry. Cards are pooled by the scroll box, so every card property is set
-- on every paint, never at build.
--
-- The docked preview is the shared outfit preview: it shows the outfit being
-- edited, exactly as the mount picker does. Nothing here previews a
-- hearthstone's cast effect; the client exposes no item-to-effect mapping.
--
-- Hearthstones use exact numeric item IDs. Names and icons come from the
-- collection rows and are never identity.
--
-- deps = {
--     registry,          -- curated HearthstoneDefinitions
--     collection,        -- HearthstoneCollection module (Rows/UsableInfo/Cooldown)
--     adapter,           -- live-ownership adapter handed to collection
--     links,             -- outfitID -> { [itemID] = true }
--     pinOperations,     -- generic Pins module
--     account,           -- store carrying account.pins[pinsDomain]
--     pinsDomain,        -- default "hearthstones"
--     now,
--     getLinks = function(outfitID) -> { [itemID] = true },
--     toggleLink = function(outfitID, itemID) -> added,
--     applyLinks = function(itemID, want) -> added, removed,
--     outfitsByID = function() -> { [outfitID] = { name, icon } },
--     getCurrentOutfit = function() -> outfitID or nil,
--     buildDockGlow = function(frame) -> glow textures,
--     showEditPreview = function(owner, outfitID, label),
--     hideEditPreview = function(),
-- }
local HearthstonePickerUI = {}

local GRID_COLS, GRID_ROWS = 3, 3
local CARD_W, CARD_H = 210, 226
local CARD_GAP, GRID_PAD = 10, 8
local PICKER_HEADER, PICKER_FOOTER = 72, 26
local PICKER_BAR_GUTTER = 24
local PICKER_BAR_GAP = 8
local PICKER_HEADER_CONTROL_H = 26

local PICKER_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function PickerSize()
	return UI.Pad * 2 + GRID_PAD * 2 + GRID_COLS * CARD_W
			+ (GRID_COLS - 1) * CARD_GAP + PICKER_BAR_GUTTER,
		PICKER_HEADER + GRID_PAD * 2 + GRID_ROWS * CARD_H
			+ (GRID_ROWS - 1) * CARD_GAP + PICKER_FOOTER
end

function HearthstonePickerUI.Attach(Addon, deps)
	local Collection = deps.collection
	local Registry = deps.registry
	local Adapter = deps.adapter
	local PinOperations = deps.pinOperations
	local PinsDomain = deps.pinsDomain or "hearthstones"
	local GetLinks = deps.getLinks
	local ToggleLink = deps.toggleLink
	local ApplyLinks = deps.applyLinks
	local OutfitsByID = deps.outfitsByID
	local BuildDockGlow = deps.buildDockGlow
	local ShowEditPreview = deps.showEditPreview
	local HideEditPreview = deps.hideEditPreview

	local function PinsDomainStore()
		local account = deps.account
		local pins = type(account) == "table" and account.pins
		return type(pins) == "table" and pins[PinsDomain] or nil
	end

	local function Now()
		return deps.now and deps.now() or 0
	end

	local function OutfitMap()
		local map = type(OutfitsByID) == "function" and OutfitsByID() or {}
		return type(map) == "table" and map or {}
	end

	local function RegistryRows()
		local entries = type(Registry) == "table" and Registry.entries
		if type(entries) ~= "table" then return {} end
		local rows = {}
		for itemID, entry in pairs(entries) do
			if type(itemID) == "number" and type(entry) == "table" then
				rows[#rows + 1] = { itemID = itemID, kind = entry.kind }
			end
		end
		return rows
	end

	local function CollectionRows()
		local collected
		if type(Collection) == "table" and type(Collection.Rows) == "function" then
			local ok, rows = pcall(Collection.Rows, Adapter, Registry)
			if ok and type(rows) == "table" then collected = rows end
		end

		local rows = {}
		for _, row in pairs(collected or {}) do
			if type(row) == "table" and type(row.itemID) == "number" then
				rows[#rows + 1] = row
			end
		end
		if #rows == 0 then rows = RegistryRows() end
		table.sort(rows, function(a, b) return a.itemID < b.itemID end)
		return rows
	end

	local hearthPicker
	local PaintCard

	local function ShowPreview()
		if not hearthPicker or hearthPicker.mode ~= "outfit"
			or type(ShowEditPreview) ~= "function" then return end
		local outfitID = hearthPicker.outfitID
		local info = OutfitMap()[outfitID]
		ShowEditPreview(hearthPicker, outfitID, ("Editing hearthstones for %s"):format(
			info and info.name or tostring(outfitID)))
	end

	local function HidePreview()
		if type(HideEditPreview) == "function" then HideEditPreview() end
		if hearthPicker then
			for _, texture in ipairs(hearthPicker.DockGlow or {}) do texture:Hide() end
		end
	end

	-- Pooled by the scroll box: build once, then paint every reuse.
	local function BuildCard(card)
		if card.built then return end
		card.built = true

		card:RegisterForClicks("LeftButtonUp", "RightButtonUp")

		-- The scroll box builds a plain Button, so there is no backdrop to set;
		-- the card paints its own background and border, as mount cards do.
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
			card.Edges[#card.Edges + 1] = line
		end

		-- A tint alone reads too close to the hover highlight. The border is
		-- what makes a chosen card unmistakable, so this matches the mount
		-- card exactly rather than approximately.
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

		-- Pin state is readable while pairing outfits, not only in pin mode,
		-- which is how a mount card carries it.
		card.FallbackStar = card:CreateTexture(nil, "OVERLAY")
		card.FallbackStar:SetSize(14, 14)
		card.FallbackStar:SetPoint("TOPRIGHT", -4, -4)

		card.Icon = card:CreateTexture(nil, "ARTWORK")
		card.Icon:SetSize(64, 64)
		card.Icon:SetPoint("TOPLEFT", 12, -12)
		card.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		card.KindBadge = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		card.KindBadge:SetPoint("TOPLEFT", card.Icon, "TOPRIGHT", 8, -2)

		card.Cooldown = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		card.Cooldown:SetPoint("TOPLEFT", card.Icon, "TOPRIGHT", 8, -18)

		card.Name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		card.Name:SetPoint("TOPLEFT", card.Icon, "BOTTOMLEFT", 0, -6)
		card.Name:SetPoint("RIGHT", -10, 0)
		card.Name:SetJustifyH("LEFT")
		card.Name:SetHeight(18)

		card.OwnedState = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		card.OwnedState:SetPoint("TOPLEFT", card.Name, "BOTTOMLEFT", 0, -2)
		card.OwnedState:SetHeight(16)

		card.PinState = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		card.PinState:SetPoint("TOPLEFT", card.OwnedState, "BOTTOMLEFT", 0, -2)
		card.PinState:SetHeight(14)

		card.PinRow = CreateFrame("Frame", nil, card)
		card.PinRow:SetSize(CARD_W - 20, 24)
		card.PinRow:SetPoint("BOTTOMLEFT", 10, 8)
		card.PinRow:Hide()

		card.PinDaysLabel = card.PinRow:CreateFontString(nil, "OVERLAY",
			"GameFontNormalSmall")
		card.PinDaysLabel:SetPoint("LEFT")

		card.PinDays = CreateFrame("EditBox", nil, card.PinRow, "InputBoxTemplate")
		card.PinDays:SetSize(40, 20)
		card.PinDays:SetPoint("LEFT", card.PinDaysLabel, "RIGHT", 6, 0)
		card.PinDays:SetNumeric(true)
		card.PinDays:SetAutoFocus(false)

		card:SetScript("OnEnter", function(self)
			self.Hover:Show()
			if not self.itemID then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.itemName or "Hearthstone", 1, 0.82, 0)
			if not self.owned then
				GameTooltip:AddLine("You have not collected this one", 1, 0.5, 0.5)
			elseif self.pinMode then
				GameTooltip:AddLine("Click to pin or unpin this hearthstone",
					0.6, 0.6, 0.6)
			else
				GameTooltip:AddLine("Click to link or unlink it from this outfit",
					0.6, 0.6, 0.6)
				GameTooltip:AddLine("Shift-click to link it to other outfits",
					0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
		end)
		card:SetScript("OnLeave", function(self)
			self.Hover:Hide()
			GameTooltip:Hide()
		end)
		card:SetScript("OnClick", function(self)
			if not self.itemID or not self.owned then return end
			if self.pinMode then
				Addon.ToggleHearthstonePin(self.itemID)
			elseif IsShiftKeyDown() then
				Addon.OpenHearthstoneSearch(self.itemID)
				return
			elseif hearthPicker.outfitID then
				-- Straight to the injected operation. Routing through an Addon
				-- method of the same name as Core's would replace Core's, and
				-- Core's callback comes back here.
				ToggleLink(hearthPicker.outfitID, self.itemID)
			end
			Addon.RefreshHearthstonePicker()
		end)

		card.PinDays:SetScript("OnEnterPressed", function(box)
			local days = tonumber(box:GetText())
			local domain = PinsDomainStore()
			if days and card.itemID and domain then
				PinOperations.SetDaysRemaining(domain, card.itemID, days, Now())
				Addon.RefreshHearthstonePicker()
			end
			box:ClearFocus()
		end)
	end

	local function OutfitChoices()
		local choices = {}
		for outfitID, info in pairs(OutfitMap()) do
			choices[#choices + 1] = {
				outfitID = outfitID,
				name = info.name or tostring(outfitID),
				icon = info.icon,
				preselected = hearthPicker and hearthPicker.outfitID == outfitID or nil,
			}
		end
		table.sort(choices, function(a, b)
			return strlower(a.name) < strlower(b.name)
		end)
		return choices
	end

	local function SetOutfitMode(outfitID)
		hearthPicker.mode = "outfit"
		hearthPicker.outfitID = outfitID
		ShowPreview()
		Addon.RefreshHearthstonePicker()
	end

	local function ChoosePickerOutfit()
		ns.OpenSearchPicker({
			title = "Choose an outfit",
			searchHint = "Search outfits",
			emptyText = "No outfits match.",
			items = OutfitChoices(),
			onChoose = function(chosen) SetOutfitMode(chosen.outfitID) end,
		})
	end

	local function SetPinMode()
		hearthPicker.mode = "pins"
		hearthPicker.outfitID = nil
		HidePreview()
		Addon.RefreshHearthstonePicker()
	end

	local function EnsureHearthPicker()
		if hearthPicker then return hearthPicker end

		local width, height = PickerSize()
		local picker = CreateFrame("Frame", "MogtrotHearthstonePicker", UIParent,
			"BackdropTemplate")
		picker:SetSize(width, height)
		picker:SetFrameStrata("HIGH")
		picker:SetClampedToScreen(true)
		picker:SetMovable(true)
		picker:EnableMouse(true)
		picker:RegisterForDrag("LeftButton")
		picker:SetScript("OnDragStart", function(self)
			if InCombatLockdown() then return end
			self:StartMoving()
		end)
		picker:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
		end)
		picker:SetBackdrop(PICKER_BACKDROP)
		picker:SetBackdropColor(0, 0, 0, 0.94)
		if type(BuildDockGlow) == "function" then
			picker.DockGlow = BuildDockGlow(picker)
		end
		picker:SetScript("OnHide", HidePreview)

		picker.CloseButton = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
		picker.CloseButton:SetSize(PICKER_HEADER_CONTROL_H, PICKER_HEADER_CONTROL_H)
		picker.CloseButton:SetPoint("TOPRIGHT", -UI.CloseButtonInset, -UI.CloseButtonInset)
		picker.CloseButton:SetScript("OnClick", function()
			Addon.CloseHearthstonePicker()
		end)

		picker.HeaderRow = CreateFrame("Frame", nil, picker)
		picker.HeaderRow:SetPoint("TOPLEFT", UI.Pad, -UI.Pad)
		picker.HeaderRow:SetPoint("RIGHT", picker.CloseButton, "LEFT", -8, 0)
		picker.HeaderRow:SetHeight(PICKER_HEADER_CONTROL_H)

		-- The same sentence the mount window wears, from the same component,
		-- so the two can never drift and either can be switched out of.
		picker.PaintHeader = ns.PairingHeaderUI.New(picker.HeaderRow,
			PICKER_HEADER_CONTROL_H, function(action, segment)
				if action == "outfit" then return ChoosePickerOutfit() end
				if action == "mode" then
					if picker.mode == "pins" then return ChoosePickerOutfit() end
					return SetPinMode()
				end
				if action ~= "domain" then return end
				ns.PairingHeaderUI.ShowDomainMenu(segment, function(choice)
					if choice == "hearthstones" then return end
					if picker.mode == "pins" then
						if Addon.OpenMountPins then Addon:OpenMountPins() end
					elseif Addon.OpenMountPicker then
						Addon:OpenMountPicker(picker.outfitID)
					end
				end)
			end)

		picker.SearchBox = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
		picker.SearchBox:SetSize(220, 20)
		picker.SearchBox:SetAutoFocus(false)
		picker.SearchBox:SetPoint("TOPLEFT", UI.Pad + 6, -(UI.Pad + 32))
		if picker.SearchBox.Instructions then
			picker.SearchBox.Instructions:SetText("Search hearthstones")
		end
		picker.SearchBox:HookScript("OnTextChanged", function(box)
			local text = strtrim(box:GetText() or "")
			local query = text ~= "" and text or nil
			if query == picker.search then return end
			picker.search = query
			Addon.RefreshHearthstonePicker()
		end)

		picker.Note = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		picker.Note:SetPoint("BOTTOMLEFT", UI.Pad + 6, 8)

		picker.Box = CreateFrame("Frame", nil, picker, "WowScrollBoxList")
		picker.Box:SetPoint("TOPLEFT", picker, "TOPLEFT", UI.Pad, -PICKER_HEADER)
		picker.Box:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT",
			-(UI.Pad + PICKER_BAR_GUTTER), PICKER_FOOTER)

		picker.Bar = CreateFrame("EventFrame", nil, picker, "MinimalScrollBar")
		picker.Bar:SetPoint("TOPLEFT", picker.Box, "TOPRIGHT", PICKER_BAR_GAP, 0)
		picker.Bar:SetPoint("BOTTOMLEFT", picker.Box, "BOTTOMRIGHT", PICKER_BAR_GAP, 0)

		picker.View = CreateScrollBoxListGridView(GRID_COLS,
			GRID_PAD, GRID_PAD, GRID_PAD, GRID_PAD, CARD_GAP, CARD_GAP)
		picker.View:SetElementSize(CARD_W, CARD_H)
		picker.View:SetPanExtent(CARD_H)
		picker.View:SetElementInitializer("Button", function(card, row)
			BuildCard(card)
			PaintCard(card, row)
		end)

		ScrollUtil.InitScrollBoxListWithScrollBar(picker.Box, picker.Bar, picker.View)
		ScrollUtil.AddManagedScrollBarVisibilityBehavior(picker.Box, picker.Bar)

		picker:EnableMouseWheel(true)
		picker:SetScript("OnMouseWheel", function(_self, delta)
			picker.Box:OnMouseWheel(delta)
		end)

		-- Lands where the mount picker was last left, so the two feel like one
		-- window. Only the mount picker writes that position.
		local pos = MogtrotDB and MogtrotDB.pickerPosition
		if pos then
			picker:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
		else
			picker:SetPoint("CENTER", UIParent, "CENTER", -180, 0)
		end

		picker:Hide()
		hearthPicker = picker
		return picker
	end

	local function RowMatchesSearch(row, query)
		if type(query) ~= "string" or query == "" then return true end
		local name = type(row.name) == "string"
			and row.name or ("item " .. tostring(row.itemID))
		return strlower(name):find(strlower(query), 1, true) ~= nil
	end

	local function CooldownText(row)
		if type(Collection) ~= "table" or type(Collection.Cooldown) ~= "function" then
			return nil
		end
		local start, duration = Collection.Cooldown(Adapter, row.itemID)
		if type(start) == "number" and type(duration) == "number"
			and duration > 0 and start + duration > Now() then
			return "on cooldown"
		end
		return nil
	end

	local function PaintChrome(picker, linked, pinned)
		local chosen = 0
		for _ in pairs(linked or {}) do chosen = chosen + 1 end
		local pinnedCount = 0
		for _ in pairs(pinned or {}) do pinnedCount = pinnedCount + 1 end

		local info = OutfitMap()[picker.outfitID]
		picker.PaintHeader({
			domain = "hearthstones",
			mode = picker.mode,
			outfitName = info and info.name,
			outfitIcon = info and info.icon,
			chosen = picker.mode == "pins" and pinnedCount or chosen,
		})
	end

	-- Paint state lives on the picker so the pooled initializer can read it
	-- without threading it through the data provider.
	local paint = { linked = nil, pinned = {}, domain = nil, pinMode = false }

	function PaintCard(card, row)
		card.itemID = row.itemID
		card.itemName = type(row.name) == "string" and row.name
			or ("item " .. tostring(row.itemID))
		card.pinMode = paint.pinMode
		card.owned = row.owned == true

		card:SetSize(CARD_W, CARD_H)
		card:SetCardColors(0.05, 0.05, 0.06, 0.9, 0.3, 0.3, 0.3)
		card.Icon:SetTexture(row.icon or FALLBACK_ICON)
		card.Icon:SetDesaturated(not card.owned)
		card.Name:SetText(card.itemName)
		card.KindBadge:SetText(row.kind == "toy" and "toy" or "item")
		card.Hover:Hide()
		card.PinRow:Hide()
		card.PinState:SetText(nil)
		card.Cooldown:SetText(nil)

		if row.equipped then
			card.OwnedState:SetText("equipped")
		elseif type(row.count) == "number" then
			card.OwnedState:SetText(("carried: %d"):format(row.count))
		else
			card.OwnedState:SetText(card.owned and "owned" or "not collected")
		end

		card.Cooldown:SetText(card.owned and CooldownText(row) or nil)
		card:SetAlpha(card.owned and 1 or 0.45)

		local isPinned = paint.pinned[row.itemID] and true or false
		card.FallbackStar:SetAtlas(isPinned and "auctionhouse-icon-favorite"
			or "auctionhouse-icon-favorite-off", false)
		card.FallbackStar:SetShown(card.owned)

		if not card.owned then return end

		if card.pinMode then
			card.PinState:SetText(isPinned and "pinned" or "not pinned")
			if isPinned then
				card:SetCardColors(0.18, 0.14, 0.02, 0.9, 1, 0.82, 0)
			end
			if paint.domain and isPinned
				and type(PinOperations.DaysRemaining) == "function" then
				local days = PinOperations.DaysRemaining(paint.domain, row.itemID, Now())
				card.PinRow:SetShown(days ~= nil)
				if days ~= nil then
					card.PinDaysLabel:SetText("days:")
					if not card.PinDays:HasFocus() then
						card.PinDays:SetText(tostring(days))
					end
				end
			end
		else
			if paint.linked and paint.linked[row.itemID] then
				card:SetCardColors(0.18, 0.14, 0.02, 0.9, 1, 0.82, 0)
			end
			card.PinState:SetText(isPinned and "pinned" or nil)
		end
	end

	-- Collected first, then by name, so a large registry still opens on the
	-- hearthstones the player can actually use.
	local function SortRows(rows)
		table.sort(rows, function(a, b)
			local ao, bo = a.owned == true, b.owned == true
			if ao ~= bo then return ao end
			local an = type(a.name) == "string" and strlower(a.name) or tostring(a.itemID)
			local bn = type(b.name) == "string" and strlower(b.name) or tostring(b.itemID)
			if an ~= bn then return an < bn end
			return a.itemID < b.itemID
		end)
	end

	function Addon.RefreshHearthstonePicker()
		local picker = hearthPicker
		if not picker or not picker:IsShown() then return end
		if InCombatLockdown() then return end

		local rows = CollectionRows()
		local matches, collected = {}, 0
		for _, row in ipairs(rows) do
			if row.owned == true then collected = collected + 1 end
			if RowMatchesSearch(row, picker.search) then
				matches[#matches + 1] = row
			end
		end
		SortRows(matches)

		paint.domain = PinsDomainStore()
		paint.pinMode = picker.mode == "pins"
		paint.linked = picker.outfitID and type(GetLinks) == "function"
			and GetLinks(picker.outfitID) or nil
		paint.pinned = {}
		if paint.domain and type(PinOperations) == "table"
			and type(PinOperations.ActiveSet) == "function" then
			local active = PinOperations.ActiveSet(paint.domain, Now())
			if type(active) == "table" then paint.pinned = active end
		end

		PaintChrome(picker, paint.linked, paint.pinned)

		local retain = ScrollBoxConstants.RetainScrollPosition
		if picker.scrollToTop then retain = ScrollBoxConstants.DiscardScrollPosition end
		picker.scrollToTop = nil
		picker.Box:SetDataProvider(CreateDataProvider(matches), retain)

		if #matches == 0 then
			picker.Note:SetText("No reviewed hearthstones match.")
		else
			picker.Note:SetText(("%d of %d collected."):format(collected, #rows))
		end
	end

	local function OpenPicker(outfitID, mode)
		if InCombatLockdown() then return end

		-- One pairing window at a time: mounts and hearthstones are two views
		-- of the same question, and two of them open at once is two answers.
		if Addon.ClosePicker then Addon:ClosePicker() end
		-- The library is the other full-size window about these outfits, so
		-- it closes too rather than sitting underneath.
		if ns.LibraryUI and ns.LibraryUI.Hide then ns.LibraryUI.Hide() end

		local picker = EnsureHearthPicker()
		picker.outfitID = outfitID
		picker.mode = mode
		picker.search = nil
		picker.scrollToTop = true
		picker.SearchBox:SetText("")

		if Addon.HidePreview then Addon:HidePreview() end
		picker:Show()
		if mode == "pins" then HidePreview() else ShowPreview() end
		Addon.RefreshHearthstonePicker()
		picker.SearchBox:SetFocus()
	end

	function Addon.OpenHearthstonePicker(outfitID)
		local current = type(deps.getCurrentOutfit) == "function"
			and deps.getCurrentOutfit() or nil
		OpenPicker(outfitID or current, "outfit")
	end

	function Addon.OpenHearthstonePins()
		OpenPicker(nil, "pins")
	end

	function Addon.CloseHearthstonePicker()
		if hearthPicker then hearthPicker:Hide() end
	end

	function Addon.IsHearthstonePickerOpen()
		return hearthPicker ~= nil and hearthPicker:IsShown()
	end

	function Addon.ToggleHearthstonePin(itemID)
		local domain = PinsDomainStore()
		if not domain or type(PinOperations) ~= "table" then return end
		if type(PinOperations.IsPinned) == "function"
			and PinOperations.IsPinned(domain, itemID, Now()) then
			if type(PinOperations.Unpin) == "function" then
				PinOperations.Unpin(domain, itemID)
			end
		elseif type(PinOperations.Pin) == "function" then
			PinOperations.Pin(domain, itemID, Now())
		end
	end

	function Addon.OpenHearthstoneSearch(itemID)
		local outfits = {}
		for outfitID, info in pairs(OutfitMap()) do
			outfits[#outfits + 1] = {
				outfitID = outfitID,
				name = info.name or tostring(outfitID),
			}
		end
		table.sort(outfits, function(a, b)
			return strlower(a.name) < strlower(b.name)
		end)

		local preselected = {}
		for outfitID, links in pairs(deps.links or {}) do
			if links[itemID] then preselected[outfitID] = true end
		end

		local items = {}
		for _, outfit in ipairs(outfits) do
			items[#items + 1] = {
				id = outfit.outfitID,
				name = outfit.name,
				preselected = preselected[outfit.outfitID],
			}
		end

		ns.OpenSearchPicker({
			title = "Link hearthstone to outfits",
			searchHint = "Search outfits",
			multi = true,
			items = items,
			buttons = { {
				text = "Apply",
				allowEmpty = true,
				onClick = function(selected)
					local want = {}
					for _, item in ipairs(selected) do
						want[item.id] = true
					end
					ApplyLinks(itemID, want)
					Addon.RefreshHearthstonePicker()
				end,
			} },
		})
	end

	return Addon
end

ns.HearthstonePickerUI = HearthstonePickerUI
return HearthstonePickerUI
