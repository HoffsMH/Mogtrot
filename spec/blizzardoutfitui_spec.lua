describe("BlizzardOutfitUI.CaptureViewedLook", function()
	local saved = {}
	local names = { "Constants", "Enum", "C_TransmogOutfitInfo", "TransmogFrame",
		"MogtrotCharDB" }

	setup(function()
		for _, name in ipairs(names) do saved[name] = _G[name] end
		_G.Constants = { Transmog = { NoTransmogID = 0 } }
		_G.Enum = { TransmogOutfitDisplayType = { Assigned = 1 } }
		_G.MogtrotCharDB = { looks = {} }
	end)

	teardown(function()
		for _, name in ipairs(names) do _G[name] = saved[name] end
	end)

	it("stores assigned slots and clears equipped or unspecified slots", function()
		local function Frame(slotID, displayType, transmogID)
			local location = {
				GetSlotID = function() return slotID end,
				GetSlot = function() return slotID end,
			}
			return {
				GetTransmogLocation = function() return location end,
				GetSlotInfo = function() return {
					displayType = displayType, transmogID = transmogID,
				} end,
				GetIllusionSlotFrame = function() return nil end,
			}
		end

		local frames = { Frame(1, 1, 101), Frame(3, 0, 303), Frame(5, 2, 505) }
		_G.TransmogFrame = { CharacterPreview = { CharacterAppearanceSlotFramePool = {
			EnumerateActive = function()
				local index = 0
				return function()
					index = index + 1
					return frames[index]
				end
			end,
		} } }
		_G.C_TransmogOutfitInfo = {
			GetCurrentlyViewedOutfitID = function() return 44 end,
			GetLinkedSlotInfo = function() return nil end,
		}
		local synced = 0
		local ui = assert(loadfile("BlizzardOutfitUI.lua"))("Mogtrot", {
			Tree = {}, Lint = {}, OutfitLint = {},
		})

		assert.is_true(ui.CaptureViewedLook({
			SyncOutfitLibrary = function() synced = synced + 1 end,
		}))
		assert.same({ 101, 0, 0 }, MogtrotCharDB.looks[44][1])
		assert.same({ 0, 0, 0 }, MogtrotCharDB.looks[44][3])
		assert.same({ 0, 0, 0 }, MogtrotCharDB.looks[44][5])
		assert.equal(1, synced)
	end)
end)
