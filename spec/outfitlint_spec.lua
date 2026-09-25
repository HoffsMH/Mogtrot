describe("OutfitLint.DebounceViewedSlotsReady", function()
	it("ignores an early slot refresh when another slot follows it", function()
		local callbacks = {}
		local after = function(_, callback) callbacks[#callbacks + 1] = callback end
		local module = assert(loadfile("OutfitLint.lua"))("Mogtrot", {
			Lint = { DISPLAY = {} },
		})

		local processed = 0
		local process = function() processed = processed + 1 end
		module.DebounceViewedSlotsReady({}, after, process)
		module.DebounceViewedSlotsReady({}, after, process)
		assert.equal(2, #callbacks)
		callbacks[1]()
		assert.equal(0, processed)
		callbacks[2]()
		assert.equal(1, processed)
	end)
end)

-- The login sweep reads each outfit's definition through the API, so it works
-- without Blizzard's window. Shaped on Devnull's Outfit 2 (outfitID 3): head
-- and split shoulders assigned, shirt and main hand left empty.
describe("OutfitLint sweep stores definitions", function()
	local saved = {}
	local names = { "Enum", "Constants", "C_TransmogOutfitInfo", "C_PaperDollInfo",
		"C_Timer", "InCombatLockdown", "GetBuildInfo", "IsInInstance", "TransmogFrame",
		"MogtrotCharDB" }

	local SLOT = { Head = 0, ShoulderRight = 2, ShoulderLeft = 3, Body = 4, MainHand = 12 }
	local INVENTORY = { HEADSLOT = 1, SHOULDERSLOT = 3, SHIRTSLOT = 4, MAINHANDSLOT = 16 }
	local APPEARANCE, ILLUSION = 0, 1
	local OPTION_NONE, OPTION_ONE_HAND = 0, 1

	-- [outfitID][slot][type] = { displayType, transmogID }, read at the
	-- option the equipped weapon selects.
	local definitions = {
		[3] = {
			[SLOT.Head] = { [APPEARANCE] = { 1, 302897 } },
			[SLOT.ShoulderRight] = { [APPEARANCE] = { 1, 302899 } },
			[SLOT.ShoulderLeft] = { [APPEARANCE] = { 1, 302900 } },
			[SLOT.Body] = { [APPEARANCE] = { 0, 83202 } },
			[SLOT.MainHand] = { [APPEARANCE] = { 2, 219532 }, [ILLUSION] = { 1, 8553 } },
		},
		[4] = {
			[SLOT.Head] = { [APPEARANCE] = { 1, 186245 } },
		},
	}

	local viewed, inInstance, instanceChecks, addon, lint

	setup(function()
		for _, name in ipairs(names) do saved[name] = _G[name] end
	end)

	teardown(function()
		for _, name in ipairs(names) do _G[name] = saved[name] end
	end)

	before_each(function()
		viewed, inInstance, instanceChecks = 0, false, 0
		_G.Enum = {
			TransmogType = { Appearance = APPEARANCE, Illusion = ILLUSION },
			TransmogOutfitDisplayType = { Unassigned = 0, Assigned = 1, Equipped = 2,
				Hidden = 3, Disabled = 4 },
			TransmogOutfitSlotOption = { None = OPTION_NONE },
			TransmogOutfitSlot = SLOT,
		}
		_G.Constants = { Transmog = { NoTransmogID = 0 } }
		_G.C_TransmogOutfitInfo = {
			InTransmogEvent = function() return false end,
			HasPendingOutfitTransmogs = function() return false end,
			HasPendingOutfitSituations = function() return false end,
			GetOutfitsInfo = function() return { { outfitID = 3 }, { outfitID = 4 } } end,
			GetCurrentlyViewedOutfitID = function() return viewed end,
			ChangeViewedOutfit = function(outfitID) viewed = outfitID end,
			GetSlotGroupInfo = function()
				return { {
					appearanceSlotInfo = {
						{ slot = SLOT.Head, type = APPEARANCE, slotName = "HEADSLOT", isSecondary = false },
						{ slot = SLOT.ShoulderRight, type = APPEARANCE, slotName = "SHOULDERSLOT", isSecondary = false },
						{ slot = SLOT.ShoulderLeft, type = APPEARANCE, slotName = "SHOULDERSLOT", isSecondary = true },
						{ slot = SLOT.Body, type = APPEARANCE, slotName = "SHIRTSLOT", isSecondary = false },
						{ slot = SLOT.MainHand, type = APPEARANCE, slotName = "MAINHANDSLOT", isSecondary = false },
					},
					illusionSlotInfo = {
						{ slot = SLOT.MainHand, type = ILLUSION, slotName = "MAINHANDSLOT", isSecondary = false },
					},
				} }
			end,
			GetSecondarySlotState = function() return false end,
			IsSlotWeaponSlot = function(slot) return slot == SLOT.MainHand end,
			GetWeaponOptionsForSlot = function()
				return { { weaponOption = OPTION_ONE_HAND, name = "One-Handed", enabled = true } }
			end,
			GetEquippedSlotOptionFromTransmogSlot = function() return OPTION_ONE_HAND end,
			GetLinkedSlotInfo = function(slot)
				if slot ~= SLOT.ShoulderRight and slot ~= SLOT.ShoulderLeft then return nil end
				return {
					primarySlotInfo = { slot = SLOT.ShoulderRight, type = APPEARANCE },
					secondarySlotInfo = { slot = SLOT.ShoulderLeft, type = APPEARANCE },
				}
			end,
			GetViewedOutfitSlotInfo = function(slot, transmogType, option)
				if (slot == SLOT.MainHand) ~= (option == OPTION_ONE_HAND) then
					return { displayType = 0, transmogID = 0 }
				end
				local outfit = definitions[viewed] or {}
				local entry = outfit[slot] and outfit[slot][transmogType]
				if not entry then return { displayType = 0, transmogID = 0 } end
				return { displayType = entry[1], transmogID = entry[2] }
			end,
		}
		_G.C_PaperDollInfo = {
			IsRangedSlotShown = function() return false end,
			GetInventorySlotInfo = function(name) return INVENTORY[name] end,
		}
		_G.C_Timer = { After = function(_, callback) callback() end }
		_G.InCombatLockdown = function() return false end
		_G.GetBuildInfo = function() return "12.1.0", "69933", "", 120100 end
		_G.IsInInstance = function()
			instanceChecks = instanceChecks + 1
			return inInstance, inInstance and "party" or "none"
		end
		_G.TransmogFrame = nil
		_G.MogtrotCharDB = {
			looks = { [3] = { [4] = { 83202, 0, 0 } } },
			slots = {
				[3] = { covered = 9, total = 14, missing = {}, at = 120100 },
				[4] = { covered = 1, total = 14, missing = {}, at = 120100 },
			},
		}

		local ns = { Lint = require("Lint"), LookCodec = require("LookCodec") }
		lint = assert(loadfile("OutfitLint.lua"))("Mogtrot", ns)
		local synced = 0
		addon = {
			Say = function() end,
			Changed = function() end,
			WarnOnce = function() end,
			SyncOutfitLibrary = function() synced = synced + 1 end,
			Synced = function() return synced end,
		}
		-- The slot refresh the client sends once a view change lands.
		C_TransmogOutfitInfo.ChangeViewedOutfit = function(outfitID)
			viewed = outfitID
			lint.OnViewedSlotsReady(addon)
		end
	end)

	it("stores only assigned slots, with split shoulders and the illusion", function()
		MogtrotCharDB.rereadLooks = true
		lint.BeginAtLogin(addon)

		local look = MogtrotCharDB.looks[3]
		assert.same({ 302897, 0, 0 }, look[1])
		assert.same({ 302899, 302900, 0 }, look[3])
		assert.same({ 0, 0, 0 }, look[4])
		assert.same({ 0, 0, 8553 }, look[16])
		assert.same({ 186245, 0, 0 }, MogtrotCharDB.looks[4][1])
	end)

	it("re-reads every outfit once when asked, then stops asking", function()
		MogtrotCharDB.rereadLooks = true
		lint.BeginAtLogin(addon)
		assert.is_nil(MogtrotCharDB.rereadLooks)
		assert.equal(1, addon.Synced())

		MogtrotCharDB.looks[3] = "kept"
		lint.BeginAtLogin(addon)
		assert.equal("kept", MogtrotCharDB.looks[3])
	end)

	it("reads an outfit that has a slot record but no definition", function()
		lint.BeginAtLogin(addon)
		assert.same({ 186245, 0, 0 }, MogtrotCharDB.looks[4][1])
		assert.same({ [4] = { 83202, 0, 0 } }, MogtrotCharDB.looks[3])
	end)

	it("does not start inside an instance", function()
		inInstance = true
		MogtrotCharDB.rereadLooks = true
		lint.BeginAtLogin(addon)
		assert.equal(1, instanceChecks)
		assert.equal(0, viewed)
		assert.same({ [4] = { 83202, 0, 0 } }, MogtrotCharDB.looks[3])
		assert.is_true(MogtrotCharDB.rereadLooks)
	end)
end)
