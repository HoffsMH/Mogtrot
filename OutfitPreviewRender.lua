local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Keeps Blizzard model reloads from painting an old outfit into the preview.
local OutfitPreviewRender = {}
local OUTFIT_SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 19 }

function OutfitPreviewRender.ApplyLook(model, look, createInfo, slots)
	if not (model and type(look) == "table" and type(createInfo) == "function") then
		return
	end
	if model.SetAutoDress then model:SetAutoDress(false) end
	if model.Undress then model:Undress() end
	if model.UndressSlot then
		for _, slot in ipairs(slots or OUTFIT_SLOTS) do
			local entry = look[slot]
			if type(entry) ~= "table" or type(entry[1]) ~= "number"
				or entry[1] <= 0 then model:UndressSlot(slot) end
		end
	end
	if not model.SetItemTransmogInfo then return end
	for slotID, entry in pairs(look) do
		if type(slotID) == "number" and type(entry) == "table"
			and type(entry[1]) == "number" and entry[1] > 0 then
			model:SetItemTransmogInfo(
				createInfo(entry[1], entry[2] or 0, entry[3] or 0), slotID)
		end
	end
end

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
