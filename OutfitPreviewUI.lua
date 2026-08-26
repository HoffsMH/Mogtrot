local _, ns = ...
local OutfitPreviewRender = ns.OutfitPreviewRender

-- Controls the outfit preview beside the main window and the outfit preview
-- attached to the mount picker window.
local OutfitPreviewUI = {}
ns.OutfitPreviewUI = OutfitPreviewUI

local function ApplyLook(model, look)
	model:Undress()
	for slotID, entry in pairs(look) do
		model:SetItemTransmogInfo(
			ItemUtil.CreateItemTransmogInfo(entry[1], entry[2], entry[3]), slotID)
	end
end

local function BuildOutfitPreview(name, parent)
	local preview = CreateFrame("Frame", name, parent, "BackdropTemplate")
	preview:SetSize(230, 330)
	preview:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	preview:SetBackdropColor(0, 0, 0, 0.92)

	preview.Model = CreateFrame("DressUpModel", nil, preview)
	preview.Model:SetPoint("TOPLEFT", 8, -8)
	preview.Model:SetPoint("BOTTOMRIGHT", -8, 8)
	preview.Model:SetUseTransmogChoices(true)
	preview.Model:SetAutoDress(false)

	preview.Message = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	preview.Message:SetPoint("CENTER")
	preview.Message:SetWidth(190)
	preview.Message:Hide()
	preview:Hide()
	return preview
end

local function RenderOutfitPreview(preview, outfitID)
	local look = MogtrotCharDB.looks and MogtrotCharDB.looks[outfitID]
	if not look then
		preview.outfitID = outfitID
		preview.renderToken = (preview.renderToken or 0) + 1
		preview.Model:Hide()
		preview.Message:SetText("Wear this outfit once and its look is captured here.")
		preview.Message:Show()
		return
	end

	preview.Message:Hide()
	preview.Model:Show()
	OutfitPreviewRender.Render(preview, outfitID, look, {
		applyLook = ApplyLook,
		after = C_Timer.After,
	})
end

local function BuildDockGlow(owner)
	local glow = {}
	for _, width in ipairs({ 8, 2 }) do
		local texture = owner:CreateTexture(nil, width == 2 and "OVERLAY" or "BORDER")
		texture:SetColorTexture(1, 0.72, 0.18, width == 2 and 0.8 or 0.2)
		texture.thickness = width
		texture:Hide()
		glow[#glow + 1] = texture
	end
	return glow
end

local function PaintDockGlow(glow, side)
	if not glow then return end
	for _, texture in ipairs(glow) do
		texture:ClearAllPoints()
		local inset = texture.thickness / 2
		if side == "left" or side == "right" then
			local point = side:upper()
			local x = side == "left" and inset or -inset
			texture:SetWidth(texture.thickness)
			texture:SetPoint("TOP" .. point, texture:GetParent(), "TOP" .. point, x, -4)
			texture:SetPoint("BOTTOM" .. point,
				texture:GetParent(), "BOTTOM" .. point, x, 4)
		else
			local point = side:upper()
			local y = side == "top" and -inset or inset
			texture:SetHeight(texture.thickness)
			texture:SetPoint(point .. "LEFT", texture:GetParent(), point .. "LEFT", 4, y)
			texture:SetPoint(point .. "RIGHT", texture:GetParent(), point .. "RIGHT", -4, y)
		end
		texture:Show()
	end
end

function OutfitPreviewUI.Attach(Addon, callbacks)
	local previewFrame, mountEditPreview, searchPickerPreview, mountPicker
	local mountEditDock = { side = "right", position = 0.5 }
	local mainWindow = callbacks.mainWindow

	local function EnsurePreview()
		if previewFrame then return previewFrame end
		previewFrame = BuildOutfitPreview("MogtrotPreview", mainWindow)
		previewFrame:SetPoint("TOPRIGHT", mainWindow, "TOPLEFT", -6, 0)
		return previewFrame
	end

	local function UpdateMountEditDockGlow()
		if not (mountPicker and mountEditPreview) then return end
		local opposite = { left = "right", right = "left", top = "bottom", bottom = "top" }
		PaintDockGlow(mountPicker.DockGlow, mountEditDock.side)
		PaintDockGlow(mountEditPreview.DockGlow, opposite[mountEditDock.side])
	end

	local function ApplyMountEditDock()
		if not (mountPicker and mountEditPreview) then return end
		local side = mountEditDock.side
		local position = math.max(0, math.min(mountEditDock.position or 0.5, 1))
		local pickerWidth, pickerHeight = mountPicker:GetSize()
		local previewWidth, previewHeight = mountEditPreview:GetSize()

		mountEditPreview:ClearAllPoints()
		if side == "left" or side == "right" then
			local span = math.max(0, pickerHeight - previewHeight)
			local offset = (position - 0.5) * span
			if side == "left" then
				mountEditPreview:SetPoint("RIGHT", mountPicker, "LEFT", 0, offset)
			else
				mountEditPreview:SetPoint("LEFT", mountPicker, "RIGHT", 0, offset)
			end
		else
			local span = math.max(0, pickerWidth - previewWidth)
			local offset = (position - 0.5) * span
			if side == "top" then
				mountEditPreview:SetPoint("BOTTOM", mountPicker, "TOP", offset, 0)
			else
				mountEditPreview:SetPoint("TOP", mountPicker, "BOTTOM", offset, 0)
			end
		end
		UpdateMountEditDockGlow()
	end

	local function UpdateMountEditDockFromCursor()
		if not (mountPicker and mountEditPreview) then return end
		local scale = UIParent:GetEffectiveScale()
		local x, y = GetCursorPosition()
		x, y = x / scale, y / scale
		local left, right = mountPicker:GetLeft(), mountPicker:GetRight()
		local bottom, top = mountPicker:GetBottom(), mountPicker:GetTop()
		if not (left and right and bottom and top) then return end

		local distances = {
			left = math.abs(x - left),
			right = math.abs(x - right),
			bottom = math.abs(y - bottom),
			top = math.abs(y - top),
		}
		local side, nearest = "right", math.huge
		for _, candidate in ipairs({ "left", "right", "bottom", "top" }) do
			if distances[candidate] < nearest then
				side, nearest = candidate, distances[candidate]
			end
		end

		mountEditDock.side = side
		if side == "left" or side == "right" then
			mountEditDock.position = (y - bottom) / math.max(1, top - bottom)
		else
			mountEditDock.position = (x - left) / math.max(1, right - left)
		end
		mountEditDock.position = math.max(0, math.min(mountEditDock.position, 1))
		ApplyMountEditDock()
	end

	local function EnsureMountEditPreview()
		if mountEditPreview then return mountEditPreview end
		mountEditPreview = BuildOutfitPreview("MogtrotMountEditPreview", UIParent)
		mountEditPreview:SetFrameStrata("HIGH")
		mountEditPreview.DockGlow = BuildDockGlow(mountEditPreview)
		mountEditPreview:EnableMouse(true)
		mountEditPreview:RegisterForDrag("LeftButton")

		mountEditPreview.Model:ClearAllPoints()
		mountEditPreview.Model:SetPoint("TOPLEFT", 8, -8)
		mountEditPreview.Model:SetPoint("BOTTOMRIGHT", -8, 28)
		mountEditPreview.Model:EnableMouse(false)
		if mountEditPreview.Model.SetPropagateMouseClicks then
			mountEditPreview.Model:SetPropagateMouseClicks(true)
		end
		if mountEditPreview.Model.SetPropagateMouseMotion then
			mountEditPreview.Model:SetPropagateMouseMotion(true)
		end

		mountEditPreview.Label = mountEditPreview:CreateFontString(
			nil, "OVERLAY", "GameFontHighlightSmall")
		mountEditPreview.Label:SetPoint("BOTTOMLEFT", 10, 9)
		mountEditPreview.Label:SetPoint("BOTTOMRIGHT", -10, 9)
		mountEditPreview.Label:SetJustifyH("CENTER")
		mountEditPreview.Label:SetWordWrap(false)

		mountEditPreview:SetScript("OnDragStart", function(self)
			self:SetScript("OnUpdate", UpdateMountEditDockFromCursor)
		end)
		mountEditPreview:SetScript("OnDragStop", function(self)
			self:SetScript("OnUpdate", nil)
		end)
		return mountEditPreview
	end

	local function EnsureSearchPickerPreview()
		if searchPickerPreview then return searchPickerPreview end
		searchPickerPreview = BuildOutfitPreview("MogtrotTitlePickerPreview", UIParent)
		searchPickerPreview:SetFrameStrata("HIGH")
		searchPickerPreview.Model:ClearAllPoints()
		searchPickerPreview.Model:SetPoint("TOPLEFT", 8, -8)
		searchPickerPreview.Model:SetPoint("BOTTOMRIGHT", -8, 28)
		searchPickerPreview.Label = searchPickerPreview:CreateFontString(
			nil, "OVERLAY", "GameFontHighlightSmall")
		searchPickerPreview.Label:SetPoint("BOTTOMLEFT", 10, 9)
		searchPickerPreview.Label:SetPoint("BOTTOMRIGHT", -10, 9)
		searchPickerPreview.Label:SetJustifyH("CENTER")
		searchPickerPreview.Label:SetWordWrap(false)
		return searchPickerPreview
	end

	function Addon:ShowPreview(outfitID)
		if not outfitID or not MogtrotDB.previewEnabled or InCombatLockdown() then return end
		if self:IsPickerOpen() then
			self:HidePreview()
			return
		end

		local preview = EnsurePreview()
		preview:ClearAllPoints()
		local previewOnLeft = (mainWindow:GetLeft() or 0) > preview:GetWidth() + 10
		if previewOnLeft then
			preview:SetPoint("TOPRIGHT", mainWindow, "TOPLEFT", -6, 0)
		else
			preview:SetPoint("TOPLEFT", mainWindow, "TOPRIGHT", 6, 0)
		end
		preview:Show()
		RenderOutfitPreview(preview, outfitID)
	end

	function Addon:HidePreview()
		if not previewFrame then return end
		previewFrame:Hide()
		previewFrame.outfitID = nil
	end

	function Addon:IsPreviewHovered()
		return previewFrame and previewFrame:IsShown() and previewFrame:IsMouseOver()
	end

	function Addon:PreviewIsShown()
		return previewFrame ~= nil and previewFrame:IsShown()
	end

	return {
		BuildDockGlow = BuildDockGlow,
		ApplyMountEditDock = ApplyMountEditDock,
		ShowMountEditPreview = function(outfitID)
			local preview = EnsureMountEditPreview()
			local info = Addon.outfitsByID and Addon.outfitsByID[outfitID]
			preview.Label:SetText(("Editing mounts for %s"):format(
				info and info.name or tostring(outfitID)))
			ApplyMountEditDock()
			preview:Show()
			RenderOutfitPreview(preview, outfitID)
		end,
		HideMountEditPreview = function()
			if not mountEditPreview then return end
			mountEditPreview:Hide()
			for _, texture in ipairs(mountEditPreview.DockGlow or {}) do texture:Hide() end
		end,
		ShowSearchPickerPreview = function(owner, outfitID, label)
			local preview = EnsureSearchPickerPreview()
			preview.Label:SetText(label)
			preview:ClearAllPoints()
			local fitsRight = (owner:GetRight() or 0) + preview:GetWidth() <= UIParent:GetRight()
			if fitsRight then
				preview:SetPoint("TOPLEFT", owner, "TOPRIGHT", 0, 0)
			else
				preview:SetPoint("TOPRIGHT", owner, "TOPLEFT", 0, 0)
			end
			preview:Show()
			RenderOutfitPreview(preview, outfitID)
		end,
		HideSearchPickerPreview = function()
			if searchPickerPreview then searchPickerPreview:Hide() end
		end,
		SetMountPicker = function(picker) mountPicker = picker end,
		OnCaptured = function(outfitID)
			if previewFrame and previewFrame.outfitID == outfitID then
				if previewFrame:IsShown() then Addon:ShowPreview(outfitID) end
			end
			if mountEditPreview and mountEditPreview:IsShown()
				and mountEditPreview.outfitID == outfitID then
				RenderOutfitPreview(mountEditPreview, outfitID)
			end
		end,
	}
end
