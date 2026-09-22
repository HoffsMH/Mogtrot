local _, ns = ...

-- The independent inspector that says what a library look is made of.
--
-- One icon per slot, plus the mount and the title, with the detail in the
-- tooltip rather than on the face of it: a wall of names is unreadable and a
-- wall of icons is not.
--
local LibraryDetailUI = {}

function LibraryDetailUI.HasLook(record)
	return type(record) == "table" and type(record.look) == "string"
		and record.look ~= ""
end

-- The button is a shortcut to a window that may already be on screen. Offering
-- it then is noise: clicking would only re-raise what you are looking at.
function LibraryDetailUI.ShouldOfferLibrary(libraryUI)
	if type(libraryUI) ~= "table" or type(libraryUI.IsOpen) ~= "function" then
		return true
	end
	return not libraryUI.IsOpen()
end

function LibraryDetailUI.OpenLibrary(libraryUI)
	if type(libraryUI) ~= "table" or type(libraryUI.Show) ~= "function" then
		return false
	end
	local frame = libraryUI.Show()
	if frame and frame.Raise then frame:Raise() end
	if frame then LibraryDetailUI.Reanchor(frame) end
	return true
end

function LibraryDetailUI.AnchorSide(libraryLeft, libraryRight, screenWidth,
	paneWidth, gap)
	local left = tonumber(libraryLeft) or 0
	local right = tonumber(libraryRight) or 0
	local width = tonumber(screenWidth) or 0
	local pane = tonumber(paneWidth) or 0
	local spacing = tonumber(gap) or 0
	local leftRoom, rightRoom = left, width - right
	if rightRoom >= pane + spacing then return "RIGHT" end
	if leftRoom >= pane + spacing then return "LEFT" end
	return rightRoom >= leftRoom and "RIGHT" or "LEFT"
end

function LibraryDetailUI.IconColor(isCollected)
	if isCollected == false then return 1, 0.35, 0.35 end
	return 1, 1, 1
end

function LibraryDetailUI.ShouldTint(state)
	return state == "collectable" or state == "locked"
		or state == "collected_unusable"
end

-- A stored look is keyed on inventory slots, and so are this pane's icons.
-- Blizzard's preview matches on Enum.TransmogOutfitSlot instead, and the two
-- overlap without agreeing: inventory 8 is Feet, outfit slot 8 is Hand. This
-- is the conversion TransmogUtil.CreateTransmogLocation does, zero-based
-- argument included.
function LibraryDetailUI.OutfitSlotFor(slotID, convert)
	if type(slotID) ~= "number" then return nil end
	convert = convert or (C_TransmogOutfitInfo
		and C_TransmogOutfitInfo.GetTransmogOutfitSlotFromInventorySlot)
	if type(convert) ~= "function" then return nil end
	local ok, slot = pcall(convert, slotID - 1)
	if not ok then return nil end
	return slot
end

function LibraryDetailUI.SelectTransmogSlot(preview, slotID, appearanceType, convert)
	if not (preview and type(preview.GetSlotFrame) == "function") then return false end
	-- Documented as able to return nothing, and asking for slot nil would
	-- match whatever the preview happens to hold.
	local outfitSlot = LibraryDetailUI.OutfitSlotFor(slotID, convert)
	if outfitSlot == nil then return false end
	local slot = preview:GetSlotFrame(outfitSlot, appearanceType)
	if not (slot and type(slot.OnSelect) == "function") then return false end
	slot:OnSelect()
	return true
end

function LibraryDetailUI.CollectionState(sourceID, collection, noError, requestItem)
	if type(sourceID) ~= "number" or not collection
		or type(collection.GetSourceInfo) ~= "function" then return "locked" end
	local ok, info = pcall(collection.GetSourceInfo, sourceID)
	if not ok or type(info) ~= "table" then return "locked" end
	local function Loaded(candidate)
		if candidate.name then return true end
		if requestItem and candidate.itemID then requestItem(candidate.itemID) end
		return false
	end
	local function Usable(candidate)
		if candidate.useError then return false end
		return candidate.useErrorType == nil or candidate.useErrorType == noError
	end
	if not Loaded(info) then return "pending" end
	if info.isCollected and Usable(info) then return "collected" end

	local pending, owned, learnable = false, info.isCollected, info.playerCanCollect
	local siblings = {}
	if type(collection.GetAllAppearanceSources) == "function" and info.visualID then
		local got, result = pcall(collection.GetAllAppearanceSources, info.visualID)
		if got and type(result) == "table" then siblings = result end
	end
	for _, siblingID in ipairs(siblings) do
		if siblingID ~= sourceID then
			local got, sibling = pcall(collection.GetSourceInfo, siblingID)
			if got and type(sibling) == "table" then
				if not Loaded(sibling) then
					pending = true
				else
					if sibling.isCollected then
						if Usable(sibling) then return "collected_other" end
						owned = true
					end
					if sibling.playerCanCollect then learnable = true end
				end
			end
		end
	end
	if owned then return "collected_unusable" end
	if pending then return "pending" end
	if learnable then return "collectable" end
	return "locked"
end

-- Laid out like the character sheet: a column of icons down each side of the
-- model, weapons underneath. Nobody has to learn where anything is.
local ICON = 36
local GAP = 4
local MARGIN = 10
local HEADER = 46
local MODEL_W = 156
local FOOTER = 12
local PANE_W = MARGIN * 2 + ICON * 2 + GAP * 2 + MODEL_W
local LIBRARY_STRATA = "DIALOG"

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local EMPTY_ICON = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local pane
local shown

-- Ctrl-click previews one piece, the way ctrl-clicking any equippable item
-- does. TryOn takes a source ID as readily as a link, and the source is what
-- pins the exact tint: an item link would preview whichever variant the base
-- item defaults to.
function LibraryDetailUI.DressUpSource(entry, dressUp)
	local source = type(entry) == "table" and entry.source
	if type(source) ~= "number" or source <= 0 then return false end
	dressUp = dressUp or _G.DressUpVisual
	if type(dressUp) ~= "function" then return false end
	-- A success return here means accepted, not visible, so nothing is
	-- reported from it; the dressing room is the observable.
	pcall(dressUp, source)
	return true
end

function LibraryDetailUI.SyncLibraryButton()
	if not (pane and pane.Library) then return end
	pane.Library:SetShown(LibraryDetailUI.ShouldOfferLibrary(ns.LibraryUI))
end

local function TransmogWindowOpen()
	return TransmogFrame and TransmogFrame:IsShown() or false
end

local function ViewedOutfitID()
	local api = C_TransmogOutfitInfo
	if not (TransmogWindowOpen() and api and api.GetCurrentlyViewedOutfitID) then
		return nil
	end
	local outfitID = api.GetCurrentlyViewedOutfitID()
	if not outfitID or outfitID == 0 then return nil end
	return outfitID
end

local function UpdateTransferButton()
	if not (pane and pane.Transfer) then return end
	pane.Transfer:SetShown(TransmogWindowOpen() and pane:IsShown())
	pane.Transfer.outfitID = ViewedOutfitID()
end

-- What the client will say about one stored appearance. Returns icon, name and
-- the visual that many items share, because a source is one item and a visual
-- is the look that item and its twins all wear.
local function SourceDetail(sourceID)
	local collection = C_TransmogCollection
	if type(sourceID) ~= "number" or sourceID <= 0 or not collection then return nil end

	local link, name, icon, visualID, itemID, isCollected
	if collection.GetSourceInfo then
		local ok, info = pcall(collection.GetSourceInfo, sourceID)
		if ok and type(info) == "table" then
			name, visualID, itemID = info.name, info.visualID, info.itemID
			isCollected = info.isCollected
		end
	end
	if collection.GetAppearanceSourceInfo then
		local ok, info = pcall(collection.GetAppearanceSourceInfo, sourceID)
		if ok and type(info) == "table" then
			link = info.itemLink
			icon = info.icon
		end
	end
	if not icon and itemID and C_Item and C_Item.GetItemIconByID then
		local ok, fromItem = pcall(C_Item.GetItemIconByID, itemID)
		if ok then icon = fromItem end
	end
	local noError = Enum and Enum.TransmogUseErrorType
		and Enum.TransmogUseErrorType.None
	local state = LibraryDetailUI.CollectionState(sourceID, collection, noError,
		function(id)
			if C_Item and C_Item.RequestLoadItemDataByID then
				C_Item.RequestLoadItemDataByID(id)
			end
		end)
	return {
		icon = icon, name = name, link = link, visualID = visualID,
		itemID = itemID, isCollected = isCollected, collectionState = state,
	}
end

local function IllusionName(illusionID)
	local collection = C_TransmogCollection
	if type(illusionID) ~= "number" or illusionID <= 0 or not collection then return nil end
	if collection.GetIllusionInfo then
		local ok, info = pcall(collection.GetIllusionInfo, illusionID)
		if ok and type(info) == "table" then
			return info.name or info.sourceText
		end
	end
	return nil
end

local function SlotTooltip(button)
	local entry = button.entry
	if not entry then return end
	local Text = ns.LibraryText

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(Text and Text.SlotName(entry.slot) or "Slot")
	if entry.empty then
		GameTooltip:AddLine("Nothing stored for this slot.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
		return
	end

	local detail = entry.detail
	if detail then
		GameTooltip:AddLine(detail.link or detail.name or "the client would not name it",
			1, 1, 1, true)
		if detail.itemID then
			GameTooltip:AddLine(("item %d"):format(detail.itemID), 0.6, 0.6, 0.6)
		end
		if detail.visualID then
			-- Worth saying out loud: many different items share one visual, so
			-- this number is the look and the one above is the thing that wears it.
			GameTooltip:AddLine(("appearance %d, shared by every item that looks like this")
				:format(detail.visualID), 0.6, 0.6, 0.6, true)
		end
	end
	if detail and detail.collectionState == "collected_unusable" then
		GameTooltip:AddLine("Collected, but unavailable to this character", 1, 0.25, 0.25)
	elseif entry.uncollected then
		GameTooltip:AddLine("Not collected", 1, 0.25, 0.25)
	elseif detail and detail.collectionState == "collected_other" then
		GameTooltip:AddLine("Collected from another item", 0.35, 1, 0.35)
	end
	if entry.illusion and entry.illusion > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(("Enchant: %s"):format(
			IllusionName(entry.illusion) or ("illusion " .. entry.illusion)), 0.6, 0.9, 1)
	end
	if entry.secondary and entry.secondary > 0 and entry.secondary ~= entry.source then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Shoulders are set apart; the other one differs.",
			0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end

local function ExtraTooltip(button)
	if not button.lines then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(button.heading or "")
	for _, line in ipairs(button.lines) do
		GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

local function BuildIcon(parent, onEnter)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(ICON, ICON)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button.Texture = button:CreateTexture(nil, "ARTWORK")
	button.Texture:SetAllPoints()
	button.Texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.Border = button:CreateTexture(nil, "OVERLAY")
	button.Border:SetColorTexture(0.3, 0.3, 0.3, 1)
	button.Border:SetAllPoints()
	button.Border:SetDrawLayer("BACKGROUND")
	button:SetScript("OnEnter", onEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button:SetScript("OnClick", function(self, mouseButton)
		if mouseButton == "LeftButton" and IsControlKeyDown and IsControlKeyDown() then
			if LibraryDetailUI.DressUpSource(self.entry) then GameTooltip:Hide() end
			return
		end
		if mouseButton ~= "RightButton" or not self.slotID or not TransmogWindowOpen()
			or not (Enum and Enum.TransmogType) then return end
		local preview = TransmogFrame and TransmogFrame.CharacterPreview
		if LibraryDetailUI.SelectTransmogSlot(preview, self.slotID,
			Enum.TransmogType.Appearance) then GameTooltip:Hide() end
	end)
	return button
end

local function Ensure(library)
	if pane then return pane end

	if library and library.HookScript then
		library:HookScript("OnShow", LibraryDetailUI.SyncLibraryButton)
		library:HookScript("OnHide", LibraryDetailUI.SyncLibraryButton)
	end

	pane = CreateFrame("Frame", "MogtrotLibraryDetail", UIParent, "BackdropTemplate")
	pane:SetFrameStrata(LIBRARY_STRATA)
	pane:SetToplevel(true)
	pane:SetFlattensRenderLayers(true)
	pane:SetIsFrameBuffer(true)
	pane:SetBackdrop(BACKDROP)
	pane:SetBackdropColor(0, 0, 0, 0.94)
	pane:SetClampedToScreen(true)
	pane:SetMovable(true)
	pane:EnableMouse(true)
	pane:RegisterForDrag("LeftButton")
	pane:SetScript("OnDragStart", pane.StartMoving)
	pane:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	pane:SetPoint("CENTER", UIParent, "CENTER", 260, 0)

	pane.Close = CreateFrame("Button", nil, pane, "UIPanelCloseButton")
	pane.Close:SetPoint("TOPRIGHT", -4, -4)
	pane.Close:SetScript("OnClick", function() LibraryDetailUI.Hide() end)

	local libraryIcon = ns.MainWindowUI and ns.MainWindowUI.LibraryIcon
		or "Interface\\QuestFrame\\UI-QuestLog-BookIcon"
	pane.Library = CreateFrame("Button", nil, pane)
	pane.Library:SetSize(24, 24)
	pane.Library:SetPoint("RIGHT", pane.Close, "LEFT", -2, 0)
	pane.Library.Icon = pane.Library:CreateTexture(nil, "ARTWORK")
	pane.Library.Icon:SetSize(20, 20)
	pane.Library.Icon:SetPoint("CENTER")
	pane.Library.Icon:SetTexture(libraryIcon)
	pane.Library.Icon:SetTexCoord(0, 1, 0, 1)
	pane.Library:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
	pane.Library:SetScript("OnClick", function()
		LibraryDetailUI.OpenLibrary(ns.LibraryUI)
	end)
	pane.Library:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Outfit library")
		GameTooltip:AddLine("Action: Open outfit library", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Texture: " .. libraryIcon, 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	pane.Library:SetScript("OnLeave", GameTooltip_Hide)

	pane.Title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	pane.Title:SetPoint("TOPLEFT", MARGIN, -12)
	pane.Title:SetPoint("TOPRIGHT", pane.Library, "TOPLEFT", -4, -12)
	pane.Title:SetJustifyH("LEFT")
	pane.Title:SetWordWrap(false)

	pane.Sub = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pane.Sub:SetPoint("TOPLEFT", MARGIN, -28)
	pane.Sub:SetPoint("TOPRIGHT", pane.Library, "TOPLEFT", -4, -28)
	pane.Sub:SetJustifyH("LEFT")
	pane.Sub:SetWordWrap(false)

	local Text = ns.LibraryText
	local columns = Text and Text.SLOT_COLUMNS or { left = {}, right = {}, bottom = {} }

	pane.Slots = {}
	local function Column(slots, anchorX)
		for index, slotID in ipairs(slots) do
			local button = BuildIcon(pane, SlotTooltip)
			button:SetPoint("TOPLEFT", anchorX, -(HEADER + (index - 1) * (ICON + GAP)))
			button.slotID = slotID
			pane.Slots[slotID] = button
		end
	end
	Column(columns.left, MARGIN)
	Column(columns.right, MARGIN + ICON + GAP + MODEL_W + GAP)

	local tallest = math.max(#columns.left, #columns.right)
	local columnBottom = HEADER + tallest * (ICON + GAP)

	-- The model stands between the columns, as it does on the character sheet.
	-- It is not built here: the wall lends the pane the body it is already
	-- showing, so the two can never be two different people.
	pane.ModelSlot = CreateFrame("Frame", nil, pane)
	pane.ModelSlot:SetPoint("TOPLEFT", MARGIN + ICON + GAP, -HEADER)
	pane.ModelSlot:SetSize(MODEL_W, columnBottom - HEADER - GAP)

	-- Used when the body needs nothing borrowed, so building one here cannot
	-- disagree with the card: both come from your own unit.
	pane.OwnScene = CreateFrame("ModelScene", nil, pane.ModelSlot,
		"ModelSceneMixinTemplate")
	pane.OwnScene:SetFixedFrameStrata(false)
	pane.OwnScene:SetFixedFrameLevel(false)
	pane.OwnScene:SetFixedFrameStrata(true)
	pane.OwnScene:SetFixedFrameLevel(true)
	pane.OwnScene:SetAllPoints()
	pane.OwnScene:EnableMouse(false)
	pane.OwnScene:EnableMouseWheel(false)
	pane.OwnScene:Hide()

	pane.NoModel = pane.ModelSlot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	pane.NoModel:SetPoint("CENTER")
	pane.NoModel:SetWidth(MODEL_W - 8)
	pane.NoModel:SetJustifyH("CENTER")
	pane.NoModel:SetWordWrap(true)

	-- Weapons underneath the model, centred, the way they hang below a
	-- character sheet.
	local weapons = columns.bottom
	local weaponsWidth = #weapons * ICON + math.max(0, #weapons - 1) * GAP
	local weaponsLeft = (PANE_W - weaponsWidth) / 2
	for index, slotID in ipairs(weapons) do
		local button = BuildIcon(pane, SlotTooltip)
		button:SetPoint("TOPLEFT", weaponsLeft + (index - 1) * (ICON + GAP),
			-columnBottom)
		button.slotID = slotID
		pane.Slots[slotID] = button
	end

	local extrasTop = columnBottom + ICON + GAP

	pane.Mount = BuildIcon(pane, ExtraTooltip)
	pane.Mount:SetPoint("TOPLEFT", MARGIN, -extrasTop)
	pane.Title2 = BuildIcon(pane, ExtraTooltip)
	pane.Title2:SetPoint("TOPLEFT", MARGIN + ICON + GAP, -extrasTop)

	pane.Transfer = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
	pane.Transfer:SetSize(PANE_W - MARGIN * 2, 22)
	pane.Transfer:SetPoint("TOPLEFT", MARGIN, -(extrasTop + ICON + GAP))
	pane.Transfer:SetText("Transfer to currently selected outfit")
	pane.Transfer:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Transfer to currently selected outfit")
		GameTooltip:AddLine(("Selected outfit: %s"):format(
			tostring(self.outfitID or "none")), 0.6, 0.6, 0.6)
		GameTooltip:AddLine(self.mogtrotStatus or "No transfer attempted yet.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	pane.Transfer:SetScript("OnLeave", GameTooltip_Hide)
	pane.Transfer:SetScript("OnClick", function(self)
		local Transfer = ns.LibraryTransfer
		local codec = ns.LookCodec
		local api = C_TransmogOutfitInfo
		local preview = TransmogFrame and TransmogFrame.CharacterPreview
		if not (Transfer and codec and shown and api and preview and TransmogUtil
			and Enum and Enum.TransmogType and Enum.TransmogOutfitDisplayType) then return end
		local look = codec.Decode(shown.look) or {}
		local collection = C_TransmogCollection
		local noError = Enum.TransmogUseErrorType and Enum.TransmogUseErrorType.None
		local function Preferred(sourceID)
			if not collection then return sourceID end
			return Transfer.PreferredSource(sourceID, {
				getSourceInfo = collection.GetSourceInfo,
				getAllSources = collection.GetAllAppearanceSources,
				noError = noError,
			})
		end
		local hideOptions
		if Constants and Constants.Transmog then
			hideOptions = {
				hideUnavailable = true,
				noTransmogID = Constants.Transmog.NoTransmogID,
				hiddenDisplayType = Enum.TransmogOutfitDisplayType.Hidden,
			}
			if shown.source == "snap" and Text then
				hideOptions.emptySlots = Text.SLOT_ORDER
			end
		end
		local plan = Transfer.Plan(look, TransmogUtil.CreateTransmogLocation,
			Enum.TransmogType.Appearance, Enum.TransmogType.Illusion, Preferred,
			hideOptions)
		local attempted, verified, unavailable = Transfer.Apply(plan, {
			assignedDisplayType = Enum.TransmogOutfitDisplayType.Assigned,
			option = function(slot, kind)
				local slotFrame = preview:GetSlotFrame(slot, kind)
				local info = slotFrame and slotFrame.slotData
					and slotFrame.slotData.currentWeaponOptionInfo
				return info and info.weaponOption
					or Enum.TransmogOutfitSlotOption.None
			end,
			setPending = api.SetPendingTransmog,
			getViewed = api.GetViewedOutfitSlotInfo,
		})
		self.mogtrotStatus = ("Verified %d of %d transferable changes; %d unavailable.")
			:format(verified, attempted, unavailable)
		self:SetText(("Transfer (%d/%d, %d unavailable)"):format(
			verified, attempted, unavailable))
	end)

	pane:SetSize(PANE_W, extrasTop + ICON + GAP + 22 + FOOTER)
	pane:Hide()
	local events = CreateFrame("Frame")
	events:RegisterEvent("TRANSMOGRIFY_OPEN")
	events:RegisterEvent("TRANSMOGRIFY_CLOSE")
	events:RegisterEvent("TRANSMOG_COLLECTION_UPDATED")
	events:RegisterEvent("TRANSMOG_COLLECTION_ITEM_UPDATE")
	events:RegisterEvent("TRANSMOG_SOURCE_COLLECTABILITY_UPDATE")
	events:SetScript("OnEvent", function(_self, event)
		if event == "TRANSMOGRIFY_OPEN" and C_Timer and C_Timer.After then
			-- The open event arrives before the frame reports itself shown.
			C_Timer.After(0, UpdateTransferButton)
		elseif event == "TRANSMOGRIFY_CLOSE" then
			UpdateTransferButton()
		elseif shown and pane:IsShown() then
			LibraryDetailUI.Show(library, shown)
		end
	end)
	return pane
end

-- Fills the pane from a record. Everything it shows is read here rather than
-- in the tooltip, so hovering never has to hit the client.
function LibraryDetailUI.Show(library, record)
	local frame = Ensure(library)
	local wasShown = frame:IsShown()
	local Text = ns.LibraryText
	local codec = ns.LookCodec
	if not (Text and codec and record) then return end

	shown = record
	frame.Transfer.mogtrotStatus = nil
	frame.Transfer:SetText("Transfer to currently selected outfit")
	frame.Title:SetText(Text.Title(record))
	-- Players read class off the colour before they read the name, and the
	-- cards already do this. Unknown class keeps the font's own colour.
	local libraryUI = ns.LibraryUI
	local className, classColor
	if libraryUI and libraryUI.ClassInfoFor then
		className, classColor = libraryUI.ClassInfoFor(record.classID)
	end
	if classColor then
		frame.Title:SetTextColor(classColor.r, classColor.g, classColor.b)
	else
		frame.Title:SetTextColor(frame.Title:GetFontObject():GetTextColor())
	end
	frame.Sub:SetText(Text.Subtitle(record, className))

	local look = codec.Decode(record.look) or {}
	for slotID, button in pairs(frame.Slots) do
		local entry = look[slotID]
		local source = entry and entry[1] or 0
		if source and source > 0 then
			local detail = SourceDetail(source)
			local secondary = entry[2] and entry[2] > 0
				and SourceDetail(entry[2]) or nil
			local uncollected = detail
				and LibraryDetailUI.ShouldTint(detail.collectionState)
				or secondary and LibraryDetailUI.ShouldTint(secondary.collectionState)
			button.entry = {
				slot = slotID, source = source,
				secondary = entry[2], illusion = entry[3], detail = detail,
				uncollected = uncollected and true or nil,
			}
			button.Texture:SetTexture(detail and detail.icon or EMPTY_ICON)
			button.Texture:SetDesaturated(false)
			button.Texture:SetVertexColor(LibraryDetailUI.IconColor(not uncollected))
			button:Show()
		else
			button.entry = { slot = slotID, empty = true }
			button.Texture:SetTexture(EMPTY_ICON)
			button.Texture:SetDesaturated(true)
			button.Texture:SetVertexColor(1, 1, 1)
			button:Show()
		end
	end

	local journal = C_MountJournal
	if record.mount and journal and journal.GetMountInfoByID then
		local ok, name, _spell, icon = pcall(journal.GetMountInfoByID, record.mount)
		frame.Mount.Texture:SetTexture(ok and icon or EMPTY_ICON)
		frame.Mount.Texture:SetDesaturated(false)
		frame.Mount.heading = "Mount"
		frame.Mount.lines = { ok and tostring(name) or ("mount " .. record.mount) }
	else
		frame.Mount.Texture:SetTexture(EMPTY_ICON)
		frame.Mount.Texture:SetDesaturated(true)
		frame.Mount.heading = "Mount"
		frame.Mount.lines = { "They were on foot." }
	end

	frame.Title2.heading = "Title"
	if record.title then
		frame.Title2.Texture:SetTexture("Interface\\Icons\\INV_Scroll_11")
		frame.Title2.Texture:SetDesaturated(false)
		frame.Title2.lines = { record.title }
	else
		frame.Title2.Texture:SetTexture(EMPTY_ICON)
		frame.Title2.Texture:SetDesaturated(true)
		frame.Title2.lines = { "No title was showing." }
	end

	if not LibraryDetailUI.HasLook(record) then
		local ui = ns.LibraryUI
		if ui and ui.ReturnPaneBody then ui.ReturnPaneBody() end
		frame.OwnScene:Hide()
		frame.NoModel:SetText("Appearance not captured. Wear this outfit once.")
		if not wasShown then LibraryDetailUI.Reanchor(library) end
		frame:Show()
		frame:Raise()
		UpdateTransferButton()
		return frame
	end

	-- Borrow the body the wall built. Rebuilding one here would borrow from
	-- whoever happens to be standing about now, and once the original donor has
	-- gone that is a different face wearing the same clothes.
	local ui = ns.LibraryUI
	local inset = { left = 0, right = 0, top = 0, bottom = 0 }

	-- A twin first: that is the only way to match a body borrowed from a
	-- stranger. Failing that, build one here, but only when doing so cannot
	-- disagree with the card.
	local shownBody = ui and ui.PaneBody and ui.PaneBody(record, frame.ModelSlot, inset)
	if shownBody then
		frame.OwnScene:Hide()
	else
		if ui and ui.ReturnPaneBody then ui.ReturnPaneBody() end
		if ui and ui.BodyIsDeterministic and ui.BodyIsDeterministic(record)
			and ui.RenderInto then
			local how = select(2, ui.RenderInto(frame.OwnScene, record))
			shownBody = how ~= nil
			frame.OwnScene:SetShown(shownBody and true or false)
		else
			frame.OwnScene:Hide()
		end
	end

	frame.NoModel:SetText(shownBody and ""
		or "No body has been built for this look yet. Point at somebody of the"
			.. " other sex and it will appear here.")

	if not wasShown then LibraryDetailUI.Reanchor(library) end
	frame:Show()
	frame:Raise()
	UpdateTransferButton()
	LibraryDetailUI.SyncLibraryButton()
	return frame
end

function LibraryDetailUI.Hide()
	if ns.LibraryUI and ns.LibraryUI.ReturnPaneBody then
		ns.LibraryUI.ReturnPaneBody()
	end
	if pane then pane:Hide() end
	shown = nil
end

function LibraryDetailUI.Shown()
	return shown
end

function LibraryDetailUI.Reanchor(library)
	if not (pane and library and library.GetLeft and library.GetRight) then return end
	local screenLeft = UIParent:GetLeft() or 0
	local screenWidth = UIParent:GetWidth() or 0
	local left = (library:GetLeft() or screenLeft) - screenLeft
	local right = (library:GetRight() or screenLeft) - screenLeft
	local side = LibraryDetailUI.AnchorSide(left, right, screenWidth,
		pane:GetWidth(), 8)
	pane:ClearAllPoints()
	if side == "RIGHT" then
		pane:SetPoint("TOPLEFT", library, "TOPRIGHT", 8, 0)
	else
		pane:SetPoint("TOPRIGHT", library, "TOPLEFT", -8, 0)
	end
	pane:SetFrameLevel(library:GetFrameLevel() + 1)
	if pane:IsShown() then pane:Raise() end
end

ns.LibraryDetailUI = LibraryDetailUI
return LibraryDetailUI
