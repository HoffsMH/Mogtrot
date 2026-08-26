local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Keeps Blizzard model reloads from painting an old outfit into the preview.
local OutfitPreviewRender = {}

function OutfitPreviewRender.Render(preview, outfitID, look, callbacks)
	preview.outfitID = outfitID
	preview.renderToken = (preview.renderToken or 0) + 1
	local token = preview.renderToken
	local model = preview.Model

	local function Paint()
		if preview.outfitID ~= outfitID or preview.renderToken ~= token then return end
		callbacks.applyLook(model, look)
		model:SetModelAlpha(1)
		preview.Message:Hide()
	end

	model:SetScript("OnModelLoaded", function()
		callbacks.after(0, Paint)
		callbacks.after(0.1, Paint)
	end)
	model:SetModelAlpha(0)
	preview.Message:SetText("Loading...")
	preview.Message:Show()
	model:ClearModel()
	model:SetUnit("player")
	model:SetPortraitZoom(0)
	model:SetPosition(0, 0, 0)
	model:SetFacing(0.4)
	callbacks.after(0.5, Paint)
end

ns.OutfitPreviewRender = OutfitPreviewRender
return OutfitPreviewRender
