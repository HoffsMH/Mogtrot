local _, ns = ...

-- Adds Mogtrot categories and slot counts to Blizzard's outfit list, and opens
-- Blizzard's name-and-icon editor from Mogtrot's outfit menu.
local BlizzardOutfitUI = {}
local Tree, Lint, OutfitLint = ns.Tree, ns.Lint, ns.OutfitLint
local blizzardScrollBox
local initialized
local NO_TRANSMOG = (Constants and Constants.Transmog and Constants.Transmog.NoTransmogID) or 0
local ASSIGNED = (Enum and Enum.TransmogOutfitDisplayType
	and Enum.TransmogOutfitDisplayType.Assigned) or 1

local function StoredID(info)
	return info and info.displayType == ASSIGNED and info.transmogID or NO_TRANSMOG
end

function BlizzardOutfitUI.CaptureViewedLook(addon)
	local preview = TransmogFrame and TransmogFrame.CharacterPreview
	local pool = preview and preview.CharacterAppearanceSlotFramePool
	local outfitID = C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID()
	if not pool or not outfitID or outfitID == 0 then return false end

	local look = {}
	local diagnostic = {}
	for slotFrame in pool:EnumerateActive() do
		local location = slotFrame:GetTransmogLocation()
		local slotID = location and location:GetSlotID()
		if slotID then
			local slotInfo = slotFrame:GetSlotInfo()
			local primary = StoredID(slotInfo)
			local secondary, illusion = NO_TRANSMOG, NO_TRANSMOG
			local linked = C_TransmogOutfitInfo.GetLinkedSlotInfo(location:GetSlot())
			if linked and linked.primarySlotInfo.slot == location:GetSlot() then
				local option = slotFrame:GetCurrentWeaponOptionInfo().weaponOption
				secondary = StoredID(C_TransmogOutfitInfo.GetViewedOutfitSlotInfo(
					linked.secondarySlotInfo.slot, linked.secondarySlotInfo.type, option))
			end
			local illusionFrame = slotFrame:GetIllusionSlotFrame()
			if illusionFrame then illusion = StoredID(illusionFrame:GetSlotInfo()) end
			look[slotID] = { primary, secondary, illusion }
			diagnostic[#diagnostic + 1] = {
				slotID = slotID,
				displayType = slotInfo and slotInfo.displayType,
				apiID = slotInfo and slotInfo.transmogID,
				storedID = primary,
			}
		end
	end
	MogtrotCharDB.looks[outfitID] = look
	addon.ingestDiagnostics = addon.ingestDiagnostics or {}
	addon.ingestDiagnostics[outfitID] = diagnostic
	if not addon.sweep and addon.SyncOutfitLibrary then addon.SyncOutfitLibrary() end
	return true, outfitID
end

local function OutfitRowLabel(outfitID)
	local char = MogtrotCharDB
	if not char or not char.assign then return end
	local cat = char.cats[char.assign[outfitID] or 0]
	if not cat or cat.protected then return "free", 0.3, 1, 0.3 end
	return cat.name, 0.55, 0.75, 1
end

local function DecorateOutfitRow(frame)
	if type(frame) ~= "table" or not frame.GetElementData then return end
	local elementData = frame:GetElementData()
	local outfitID = elementData and elementData.outfitID
	if not outfitID then return end

	local host = frame.OutfitButton or frame
	local label = frame.MogtrotLabel
	if not label then
		label = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("RIGHT", host, "RIGHT", -8, 8)
		label:SetJustifyH("RIGHT")
		label:SetWidth(80)
		label:SetWordWrap(false)
		frame.MogtrotLabel = label
	end

	local lint = frame.MogtrotLint
	if not lint then
		lint = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		lint:SetPoint("RIGHT", host, "RIGHT", -8, -8)
		lint:SetJustifyH("RIGHT")
		lint:SetWidth(80)
		lint:SetWordWrap(false)
		frame.MogtrotLint = lint

		local hover = CreateFrame("Frame", nil, host)
		hover:SetPoint("TOPLEFT", lint, "TOPLEFT", -4, 3)
		hover:SetPoint("BOTTOMRIGHT", lint, "BOTTOMRIGHT", 4, -3)
		hover:EnableMouse(true)
		hover:SetPropagateMouseClicks(true)
		hover:SetScript("OnEnter", function(self)
			if not self.outfitID then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Outfit slots", 1, 0.82, 0)
			OutfitLint.AddTooltip(GameTooltip, self.outfitID)
			GameTooltip:Show()
		end)
		hover:SetScript("OnLeave", GameTooltip_Hide)
		frame.MogtrotLintHover = hover
	end

	local text, r, g, b = OutfitRowLabel(outfitID)
	if text then
		label:SetText(text)
		label:SetTextColor(r, g, b)
		label:Show()
	else
		label:Hide()
	end

	local state = OutfitLint.State(outfitID)
	local colour = OutfitLint.Colours[state]
	lint:SetText(Lint.Summary(OutfitLint.Record(outfitID), OutfitLint.Build()))
	lint:SetTextColor(colour[1], colour[2], colour[3])
	lint:Show()
	frame.MogtrotLintHover.outfitID = outfitID
	frame.MogtrotLintHover:Show()
end

function BlizzardOutfitUI.Refresh()
	if blizzardScrollBox then blizzardScrollBox:ForEachFrame(DecorateOutfitRow) end
end

function BlizzardOutfitUI.CanEdit()
	return TransmogFrame ~= nil and TransmogFrame:IsShown()
end

function BlizzardOutfitUI.OpenEditor(addon, outfitID)
	if InCombatLockdown() then return end
	local info = addon.outfitsByID and addon.outfitsByID[outfitID]
	if not BlizzardOutfitUI.CanEdit() or not info then
		UIErrorsFrame:AddMessage(
			"Mogtrot: open Blizzard's outfit list to change an outfit's name or icon.",
			1, 0.3, 0.3)
		return
	end

	local popup = TransmogFrame.OutfitPopup
	popup.mode = IconSelectorPopupFrameModes.Edit
	popup.outfitData = { outfitID = outfitID, name = info.name, icon = info.icon }
	popup:Show()
end

function BlizzardOutfitUI.Initialize(addon)
	if initialized then return end
	initialized = true

	hooksecurefunc(GameTooltip, "SetOutfit", function(tooltip, outfitID)
		local char = MogtrotCharDB
		if not char or not char.assign then return end
		local path = Tree.CategoryPath(char, char.assign[outfitID])
		if not path then return end
		tooltip:AddLine(" ")
		tooltip:AddLine("Mogtrot: " .. path, 0.5, 0.8, 1)
		tooltip:Show()
	end)

	EventUtil.ContinueOnAddOnLoaded("Blizzard_Transmog", function()
		if not TransmogFrame or addon.transmogHooked then return end
		addon.transmogHooked = true

		TransmogFrame:HookScript("OnHide", function()
			OutfitLint.Abandon(addon, "the window closed")
		end)

		local collection = TransmogFrame.OutfitCollection
		if not collection then return end
		local ingest = CreateFrame("Button", nil, collection)
		ingest:SetSize(28, 28)
		ingest:SetPoint("TOPRIGHT", collection, "TOPRIGHT", -34, -4)
		ingest:SetNormalTexture("Interface\\Icons\\ability_hisek_aim")
		ingest:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		ingest:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Ingest all outfits", 1, 0.82, 0)
			GameTooltip:AddLine("Tell Mogtrot to ingest all your outfits. This may take a few seconds.",
				1, 1, 1, true)
			GameTooltip:Show()
		end)
		ingest:SetScript("OnLeave", GameTooltip_Hide)
		ingest:SetScript("OnClick", function()
			if addon.sweep then OutfitLint.Abandon(addon, "ingest requested") end
			OutfitLint.Begin(addon, true, true, true)
		end)
		collection.MogtrotIngestButton = ingest
		local scrollBox = collection and collection.OutfitList and collection.OutfitList.ScrollBox
		if not scrollBox or blizzardScrollBox then return end
		blizzardScrollBox = scrollBox
		ScrollUtil.AddInitializedFrameCallback(scrollBox, function(a, b)
			local frame = (type(a) == "table" and a.GetElementData and a) or b
			DecorateOutfitRow(frame)
		end, addon)
		BlizzardOutfitUI.Refresh()
	end)
end

ns.BlizzardOutfitUI = BlizzardOutfitUI
return BlizzardOutfitUI
