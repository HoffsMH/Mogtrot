local _, ns = ...

local BattlePetModel = ns.BattlePetModel or require("BattlePetModel")

-- Domain-specific picker for exact owned battle-pet copies. Follows the mount
-- picker's conventions: one 3x3 pooled-card grid, a search box, a pin mode
-- with expiry editing, and SearchPicker for "link this pet to other outfits".
-- Deliberately not shared with the mount picker: pet cards carry exact-copy
-- metadata (custom name over species name, per-copy favorite) and a model
-- adapter with static icon fallback instead of a mount model scene.
--
-- Pets are never summoned from the picker; selection only links, pins or
-- opens the cross-outfit search.
--
-- deps = {
--     collectPets = function(outfitID) -> rows, note
--         rows come straight from BattlePetCollection.OwnedRows plus a
--         `selected` flag per current mode; note is an optional header note.
--     account,            -- account store carrying the generic Pins domains
--     pinsDomain = "battlePets",
--     pinOperations = {   -- generic Pins-shaped pure model
--         RecordAcquired, Unpin, Pin, Keep, SetDaysRemaining, DaysRemaining,
--         IsPinned, ActiveSet, Recent,
--     },
--     defaultPinDays = 7,
--     getLinks = function(outfitID) -> { [guid] = true },
--     toggleLink = function(outfitID, guid) -> added bool,
--     applyLinks = function(guid, want) -> added, removed  (OutfitLinks.Apply)
--     outfitsByID = function() -> { [outfitID] = { name = ... } },
--     getCurrentOutfit = function() -> outfitID or nil,
-- }
local BattlePetPickerUI = {}

local GRID_COLS, GRID_ROWS = 3, 3
local CARD_W, CARD_H = 210, 226
local CARD_GAP, GRID_PAD = 10, 8
local PICKER_HEADER, PICKER_FOOTER = 72, 26
local PICKER_BAR_GUTTER = 24

local function PickerSize()
	return 24 + GRID_PAD * 2 + GRID_COLS * CARD_W + (GRID_COLS - 1) * CARD_GAP
			+ PICKER_BAR_GUTTER,
		PICKER_HEADER + GRID_PAD * 2 + GRID_ROWS * CARD_H
			+ (GRID_ROWS - 1) * CARD_GAP + PICKER_FOOTER
end

function BattlePetPickerUI.Attach(Addon, deps)
	local UI = ns.UI
	local CollectPets = deps.collectPets
	local PinOperations = deps.pinOperations
	local PinsDomain = deps.pinsDomain or "battlePets"
	local GetLinks = deps.getLinks
	local ToggleLink = deps.toggleLink
	local ApplyLinks = deps.applyLinks
	local OutfitsByID = deps.outfitsByID
	local GetCurrentOutfit = deps.getCurrentOutfit
	local Now = deps.now or function() return time and time() or 0 end
	local battlePetPicker

	-- Matches the main window's backdrop (MainWindowUI defines its own copy;
	-- UI.lua carries no shared Backdrop constant).
	local PICKER_BACKDROP = {
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	}

	-- The generic pin domain is nested under account.pins. An absent domain
	-- means pin mode is disabled until Core supplies supported schema; this
	-- picker never lazily creates schema.
	local function PinsDomainStore()
		return deps.account.pins and deps.account.pins[PinsDomain] or nil
	end

	-- ------------------------------------------------------------------
	-- Frame construction. All CreateFrame/texture/font calls stay here so
	-- the refresh logic below stays readable.
	-- ------------------------------------------------------------------

	local function CreateCard(parent, index)
		local card = CreateFrame("Button", nil, parent, "BackdropTemplate")
		card:SetSize(CARD_W, CARD_H)
		card:SetBackdrop(PICKER_BACKDROP)
		card:SetBackdropColor(0, 0, 0, 0.55)
		card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		card:SetPoint("TOPLEFT", (index - 1) % GRID_COLS * (CARD_W + CARD_GAP),
			-math.floor((index - 1) / GRID_COLS) * (CARD_H + CARD_GAP))

		card.Hover = card:CreateTexture(nil, "BACKGROUND")
		card.Hover:SetAllPoints()
		card.Hover:SetColorTexture(1, 1, 1, 0.08)
		card.Hover:Hide()

		card.Selected = card:CreateTexture(nil, "BACKGROUND")
		card.Selected:SetAllPoints()
		card.Selected:SetColorTexture(0.4, 0.8, 1, 0.18)
		card.Selected:Hide()

		card.Icon = card:CreateTexture(nil, "ARTWORK")
		card.Icon:SetSize(64, 64)
		card.Icon:SetPoint("TOPLEFT", 12, -12)
		card.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		-- Model scene behind the adapter; hidden whenever the adapter fails
		-- so the static icon always remains.
		card.Scene = CreateFrame("ModelScene", nil, card,
			"NonInteractableModelSceneTemplate")
		card.Scene:SetSize(64, 64)
		card.Scene:SetPoint("TOPLEFT", 12, -12)

		card.Favorite = card:CreateTexture(nil, "OVERLAY")
		card.Favorite:SetSize(16, 16)
		card.Favorite:SetPoint("TOPRIGHT", -10, -10)
		card.Favorite:SetAtlas("PetJournal-FavoritesIcon")
		card.Favorite:Hide()

		card.Name = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		card.Name:SetPoint("TOPLEFT", card.Icon, "BOTTOMLEFT", 0, -6)
		card.Name:SetPoint("RIGHT", -10, 0)
		card.Name:SetJustifyH("LEFT")
		card.Name:SetHeight(18)

		card.Subtitle = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
		card.Subtitle:SetPoint("TOPLEFT", card.Name, "BOTTOMLEFT", 0, -2)
		card.Subtitle:SetPoint("RIGHT", -10, 0)
		card.Subtitle:SetJustifyH("LEFT")
		card.Subtitle:SetHeight(16)

		card.PinState = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		card.PinState:SetPoint("TOPLEFT", card.Subtitle, "BOTTOMLEFT", 0, -2)
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

		card.PinButton = CreateFrame("Button", nil, card.PinRow,
			UI.ActionButtonTemplate)
		card.PinButton:SetSize(24, 24)
		card.PinButton:SetPoint("RIGHT")

		card:SetScript("OnEnter", function(self)
			self.Hover:Show()
			if not self.guid then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.displayName or "Battle pet", 1, 0.82, 0)
			if self.speciesName and self.displayName ~= self.speciesName then
				GameTooltip:AddLine(self.speciesName, 0.7, 0.7, 0.7)
			end
			GameTooltip:AddLine(" ")
			if self.pinMode then
				GameTooltip:AddLine("Click to pin or unpin this copy", 0.6, 0.6, 0.6)
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
			if not self.guid then return end
			if self.pinMode then
				Addon.ToggleBattlePetPin(self.guid)
			elseif battlePetPicker.outfitID then
				-- Straight to the injected operation. Routing through an Addon
				-- method of the same name as Core's would replace Core's, and
				-- Core's callback comes back here.
				ToggleLink(battlePetPicker.outfitID, self.guid)
			end
			Addon.RefreshBattlePetPicker()
		end)

		card.PinDays:SetScript("OnEnterPressed", function(box)
			local days = tonumber(box:GetText())
			if days and card.guid then
				local domain = PinsDomainStore()
				if not domain then return end
				PinOperations.SetDaysRemaining(domain, card.guid, days, Now())
				Addon.RefreshBattlePetPicker()
			end
			box:ClearFocus()
		end)

		return card
	end

	local function EnsureBattlePetPicker()
		if battlePetPicker then return battlePetPicker end

		local width, height = PickerSize()
		local picker = CreateFrame("Frame", "MogtrotBattlePetPicker", UIParent,
			"BackdropTemplate")
		picker:SetSize(width, height)
		picker:SetBackdrop(PICKER_BACKDROP)
		picker:SetBackdropColor(0, 0, 0, 0.85)
		picker:SetPoint("CENTER")
		picker:SetFrameStrata("HIGH")
		picker:Hide()

		picker.HeaderPrefix = picker:CreateFontString(nil, "OVERLAY",
			"GameFontNormal")
		picker.HeaderPrefix:SetPoint("TOPLEFT", 16, -18)

		picker.HeaderName = picker:CreateFontString(nil, "OVERLAY",
			"GameFontHighlight")
		picker.HeaderName:SetPoint("TOPLEFT", 16, -36)

		picker.SearchBox = CreateFrame("EditBox", nil, picker, "InputBoxTemplate")
		picker.SearchBox:SetSize(160, 20)
		picker.SearchBox:SetPoint("TOPRIGHT", -16, -16)
		picker.SearchBox:SetAutoFocus(false)
		picker.SearchBox:SetScript("OnTextChanged", function(box)
			battlePetPicker.search = box:GetText()
			battlePetPicker.scrollToTop = true
			Addon.RefreshBattlePetPicker()
		end)

		picker.Close = CreateFrame("Button", nil, picker, "UIPanelCloseButton")
		picker.Close:SetPoint("TOPRIGHT", -2, -2)
		picker.Close:SetScript("OnClick", function() picker:Hide() end)

		picker.Note = picker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		picker.Note:SetPoint("BOTTOMLEFT", 16, 10)

		picker.Cards = {}
		local grid = CreateFrame("Frame", nil, picker)
		grid:SetPoint("TOPLEFT", PICKER_BAR_GUTTER, -PICKER_HEADER)
		for i = 1, GRID_COLS * GRID_ROWS do
			picker.Cards[i] = CreateCard(grid, i)
		end

		battlePetPicker = picker
		return picker
	end

	-- ------------------------------------------------------------------
	-- Refresh. Pooled cards reset every observable property on every paint
	-- (recurring Mogtrot bug class): selection, pin state, pin row, model,
	-- icon, tooltip anchors.
	-- ------------------------------------------------------------------

	local function RowMatchesSearch(row, query)
		if not query or query == "" then return true end
		local haystack = strlower((row.displayName or "") .. " "
			.. (row.name or ""))
		return haystack:find(strlower(query), 1, true) ~= nil
	end

	function Addon.RefreshBattlePetPicker()
		local picker = battlePetPicker
		if not picker or not picker:IsShown() then return end

		local rows = picker.rows or {}
		local linked = picker.outfitID and GetLinks(picker.outfitID) or nil
		local pinned = PinOperations.ActiveSet(PinsDomainStore() or {}, Now())

		local visible = 0
		for i, card in ipairs(picker.Cards) do
			local row = rows[i]
			if row and RowMatchesSearch(row, picker.search) then
				visible = visible + 1
				card:Show()

				-- Full reset first; nothing may survive the previous paint.
				card.Selected:Hide()
				card.Favorite:Hide()
				card.PinRow:Hide()
				card.PinState:SetText(nil)
				card.Scene:Hide()
				card.Icon:SetTexture(nil)
				card.guid = row.guid
				card.displayName = row.displayName
				card.speciesName = row.name
				card.pinMode = picker.mode == "pins"

				card.Icon:SetTexture(row.icon)

				-- Model behind the adapter; any failure keeps the icon.
				BattlePetModel.Apply(card.Scene, row, {
					setDisplay = function(scene, displayID)
						scene:SetModelByCreatureDisplayID(displayID, true)
					end,
					show = function(scene) scene:Show() end,
				})

				card.Name:SetText(row.displayName or "?")
				card.Subtitle:SetText(row.name)

				if card.pinMode and PinsDomainStore() then
					local days = PinOperations.DaysRemaining(PinsDomainStore() or {},
						row.guid, Now())
					local isPinned = pinned[row.guid]
					card.PinState:SetText(isPinned and "pinned" or "not pinned")
					card.Selected:SetShown(isPinned)
					card.PinRow:SetShown(isPinned)
					if isPinned and days ~= nil then
						card.PinDaysLabel:SetText("days:")
						card.PinDays:SetText(tostring(days))
					end
				else
					local isLinked = linked and linked[row.guid]
					card.Selected:SetShown(isLinked and true or false)
					card.PinState:SetText(pinned[row.guid] and "pinned" or nil)
				end
			else
				card:Hide()
				card.guid = nil
			end
		end

		if visible == 0 then
			picker.Note:SetText("No owned copies match.")
		elseif picker.note then
			picker.Note:SetText(picker.note)
		else
			picker.Note:SetText("")
		end
	end

	-- ------------------------------------------------------------------
	-- Open entry points, mirroring the mount picker's surface.
	-- ------------------------------------------------------------------

	local function OpenPicker(outfitID, mode)
		if InCombatLockdown() then return end

		local picker = EnsureBattlePetPicker()
		picker.outfitID = outfitID
		picker.mode = mode
		picker.search = nil
		picker.SearchBox:SetText("")

		local rows, note = CollectPets(outfitID)
		picker.rows, picker.note = rows, note

		if mode == "pins" then
			picker.HeaderPrefix:SetText("Pinned battle pets:")
			picker.HeaderName:SetText("")
		else
			local name = outfitID
				and (OutfitsByID()[outfitID] and OutfitsByID()[outfitID].name
					or tostring(outfitID))
			picker.HeaderPrefix:SetText("Battle pets for")
			picker.HeaderName:SetText(name or "")
		end

		picker:Show()
		Addon.RefreshBattlePetPicker()
		picker.SearchBox:SetFocus()
	end

	function Addon.OpenBattlePetPicker(outfitID)
		OpenPicker(outfitID or GetCurrentOutfit(), "outfit")
	end

	function Addon.OpenBattlePetPins()
		OpenPicker(nil, "pins")
	end

	function Addon.CloseBattlePetPicker()
		if battlePetPicker then battlePetPicker:Hide() end
	end

	function Addon.IsBattlePetPickerOpen()
		return battlePetPicker ~= nil and battlePetPicker:IsShown()
	end

	-- ------------------------------------------------------------------
	-- Selection actions.
	-- ------------------------------------------------------------------

	function Addon.ToggleBattlePetPin(guid)
		local domain = PinsDomainStore()
		if not domain then return end
		if PinOperations.IsPinned(domain, guid, Now()) then
			PinOperations.Unpin(domain, guid)
		else
			PinOperations.Pin(domain, guid, Now())
		end
	end

	-- Cross-outfit linking: SearchPicker over every known outfit, multi-select,
	-- preselecting the outfits that already carry the GUID. Apply writes
	-- through the injected OutfitLinks.Apply-shaped operation.
	function Addon.OpenBattlePetSearch(guid)
		local outfits = {}
		local outfitMap = OutfitsByID()
		for outfitID, info in pairs(outfitMap) do
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
			if links[guid] then preselected[outfitID] = true end
		end

		-- SearchPicker's multi-select shape: preselected items start ticked,
		-- and a confirm button hands onClick the selected item tables.
		ns.OpenSearchPicker({
			title = "Link battle pet to outfits",
			searchHint = "Search outfits",
			multi = true,
			items = (function()
				local items = {}
				for _, outfit in ipairs(outfits) do
					items[#items + 1] = {
						id = outfit.outfitID,
						name = outfit.name,
						preselected = preselected[outfit.outfitID],
					}
				end
				return items
			end)(),
			buttons = { {
				text = "Apply",
				allowEmpty = true,
				onClick = function(selected)
					local want = {}
					for _, item in ipairs(selected) do
						want[item.id] = true
					end
					ApplyLinks(guid, want)
					Addon.RefreshBattlePetPicker()
				end,
			} },
		})
	end

	return Addon
end

ns.BattlePetPickerUI = BattlePetPickerUI
return BattlePetPickerUI
