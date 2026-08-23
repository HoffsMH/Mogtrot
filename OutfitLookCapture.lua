local _, ns = ...

-- Captures the appearance of the outfit the player is wearing so previews can
-- show it later when Blizzard no longer exposes the outfit's appearances.
local OutfitLookCapture = {}
ns.OutfitLookCapture = OutfitLookCapture

local NO_TRANSMOG = (Constants and Constants.Transmog and Constants.Transmog.NoTransmogID) or 0
local captureModel

function OutfitLookCapture.GetModel()
	return captureModel
end

function OutfitLookCapture.Attach(Addon, callbacks)
	local function EnsureModel()
		if captureModel then return captureModel end

		captureModel = CreateFrame("DressUpModel", nil, UIParent)
		captureModel:SetSize(1, 1)
		captureModel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		captureModel:SetAlpha(0)
		captureModel:SetModelAlpha(0)
		captureModel:SetUseTransmogChoices(true)
		captureModel:SetScript("OnModelLoaded", function(self)
			self:SetModelAlpha(0)
			Addon:StoreCapturedLook()
		end)
		captureModel:Show()

		return captureModel
	end

	function Addon:StoreCapturedLook(verbose)
		local outfitID = C_TransmogOutfitInfo.GetActiveOutfitID()
		if not outfitID or outfitID == 0 or not captureModel then
			if verbose then self:Say("no active outfit to capture.") end
			return
		end

		local list = captureModel:GetItemTransmogInfoList()
		if not list then
			if verbose then self:Say("the model has not reported an appearance list yet.") end
			return
		end

		local look, anyAppearance = {}, false
		for slotID, info in pairs(list) do
			if type(info) == "table" and info.appearanceID then
				look[slotID] = {
					info.appearanceID,
					info.secondaryAppearanceID or NO_TRANSMOG,
					info.illusionID or NO_TRANSMOG,
				}
				if info.appearanceID ~= NO_TRANSMOG then anyAppearance = true end
			end
		end

		if not anyAppearance then
			if verbose then self:Say("the model is still loading, nothing captured.") end
			return
		end

		MogtrotCharDB.looks[outfitID] = look
		self.captureOutfitID = nil

		if verbose then
			local name = self.outfitsByID and self.outfitsByID[outfitID]
			self:Say("captured '%s'.", name and name.name or tostring(outfitID))
		end

		callbacks.onCaptured(outfitID)
	end

	function Addon:CaptureActiveLook(verbose)
		if InCombatLockdown() then return end

		local outfitID = C_TransmogOutfitInfo.GetActiveOutfitID()
		if not outfitID or outfitID == 0 then
			if verbose then self:Say("no outfit active, nothing to capture.") end
			return
		end

		self.captureOutfitID = outfitID
		local model = EnsureModel()
		model:ClearModel()
		model:SetUnit("player")
		model:SetModelAlpha(0)

		C_Timer.After(0.5, function() Addon:StoreCapturedLook() end)
		C_Timer.After(1.5, function() Addon:StoreCapturedLook(verbose) end)
	end

	function Addon:ScheduleCapture()
		if self.captureScheduled then return end
		self.captureScheduled = true

		C_Timer.After(1.0, function()
			Addon.captureScheduled = nil
			Addon:CaptureActiveLook()
		end)
		C_Timer.After(3.0, function() Addon:CaptureActiveLook() end)
	end
end

