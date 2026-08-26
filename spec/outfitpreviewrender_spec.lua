local OutfitPreviewRender = require("OutfitPreviewRender")

local function NewPreview()
	local model = { scripts = {}, resets = 0 }
	function model:SetScript(event, callback) self.scripts[event] = callback end
	function model:SetModelAlpha() end
	function model:ClearModel() self.resets = self.resets + 1 end
	function model:SetUnit() end
	function model:SetPortraitZoom() end
	function model:SetPosition() end
	function model:SetFacing() end

	local message = {}
	function message:SetText() end
	function message:Show() end
	function message:Hide() end

	return { Model = model, Message = message }
end

describe("OutfitPreviewRender", function()
	it("reloads and dresses repeated requests for the same outfit", function()
		local preview = NewPreview()
		local applied = {}
		local callbacks = {
			after = function(_, callback) callback() end,
			applyLook = function(_, look) applied[#applied + 1] = look end,
		}
		local look = { head = 12 }

		OutfitPreviewRender.Render(preview, 7, look, callbacks)
		preview.Model.scripts.OnModelLoaded(preview.Model)
		OutfitPreviewRender.Render(preview, 7, look, callbacks)
		preview.Model.scripts.OnModelLoaded(preview.Model)

		assert.are.equal(2, preview.Model.resets)
		assert.are.same({ look, look, look, look, look, look }, applied)
	end)

	it("ignores a load callback from an older request", function()
		local preview = NewPreview()
		local applied = {}
		local scheduled = {}
		local callbacks = {
			after = function(_, callback) scheduled[#scheduled + 1] = callback end,
			applyLook = function(_, look) applied[#applied + 1] = look end,
		}

		OutfitPreviewRender.Render(preview, 7, "old", callbacks)
		local oldScheduledCount = #scheduled
		local oldReady = preview.Model.scripts.OnModelLoaded
		OutfitPreviewRender.Render(preview, 8, "new", callbacks)
		oldReady(preview.Model)
		for i = 1, oldScheduledCount do scheduled[i]() end

		assert.are.same({}, applied)
	end)
end)
