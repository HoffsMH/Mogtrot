-- The wear capture renders the player, so a slot the outfit leaves empty shows
-- equipped gear. That is the last worn appearance, not the outfit's definition.
describe("OutfitLookCapture wear capture", function()
	local saved = {}
	local names = { "Constants", "C_TransmogOutfitInfo", "C_Timer", "CreateFrame",
		"UIParent", "InCombatLockdown", "MogtrotCharDB" }

	-- Devnull's Outfit 2 (outfitID 3): head assigned, shirt and main hand left
	-- empty while gear is equipped there.
	local rendered = {
		[1] = { appearanceID = 302897, secondaryAppearanceID = 0, illusionID = 0 },
		[4] = { appearanceID = 83202, secondaryAppearanceID = 0, illusionID = 0 },
		[16] = { appearanceID = 219532, secondaryAppearanceID = -1, illusionID = 0 },
	}

	local captured, addon

	setup(function()
		for _, name in ipairs(names) do saved[name] = _G[name] end
	end)

	teardown(function()
		for _, name in ipairs(names) do _G[name] = saved[name] end
	end)

	before_each(function()
		captured = {}
		_G.Constants = { Transmog = { NoTransmogID = 0 } }
		_G.C_TransmogOutfitInfo = { GetActiveOutfitID = function() return 3 end }
		_G.C_Timer = { After = function() end }
		_G.UIParent = {}
		_G.InCombatLockdown = function() return false end
		_G.CreateFrame = function()
			local model = {}
			for _, method in ipairs({ "SetSize", "SetPoint", "SetAlpha", "SetModelAlpha",
				"SetUseTransmogChoices", "SetScript", "Show", "ClearModel", "SetUnit" }) do
				model[method] = function() end
			end
			model.GetItemTransmogInfoList = function() return rendered end
			return model
		end
		_G.MogtrotCharDB = { looks = { [3] = "ingested" }, worn = {} }

		local ns = {}
		assert(loadfile("OutfitLookCapture.lua"))("Mogtrot", ns)
		addon = { Say = function() end }
		ns.OutfitLookCapture.Attach(addon, {
			onCaptured = function(outfitID) captured[#captured + 1] = outfitID end,
		})
		addon:CaptureActiveLook()
	end)

	it("stores what the model renders under worn, fallthrough included", function()
		addon:StoreCapturedLook()
		local worn = MogtrotCharDB.worn[3]
		assert.same({ 302897, 0, 0 }, worn[1])
		assert.same({ 83202, 0, 0 }, worn[4])
		assert.same({ 219532, -1, 0 }, worn[16])
		assert.same({ 3 }, captured)
	end)

	it("never writes the outfit's definition", function()
		addon:StoreCapturedLook()
		assert.equal("ingested", MogtrotCharDB.looks[3])
	end)

	it("creates the worn store when an older character has none", function()
		MogtrotCharDB.worn = nil
		addon:StoreCapturedLook()
		assert.same({ 302897, 0, 0 }, MogtrotCharDB.worn[3][1])
	end)
end)
