-- Injected-adapter contract for the hearthstone collection over the curated
-- HearthstoneDefinitions registry. The adapter stands in for C_ToyBox/C_Item:
-- hasToy(itemID), getToyInfo(itemID) -> name, icon, isFavorite or nil,
-- itemCount(itemID) -> carried count, totalItemCount(itemID) -> total owned
-- (or nil if the adapter does not expose totals), isUsable(itemID),
-- getCooldown(itemID) -> start, duration, enable, getItemName(itemID),
-- getItemIcon(itemID). The collection iterates only the reviewed registry IDs
-- - never a Toy Box filter walk - and is a pure read layer: fresh rows, no
-- mutation, no invented metadata.
local HearthstoneDefinitions = require("HearthstoneDefinitions")
local HearthstoneCollection = require("HearthstoneCollection")

describe("HearthstoneCollection", function()
	local HEARTH = 6948
	local TOY = 900001 -- test-only toy ID; never written to runtime definitions
	local SLIPPERS = 28585

	local function Adapter(overrides)
		local adapter = {
			hasToy = function(itemID) return itemID == TOY end,
			getToyInfo = function(itemID)
				if itemID == TOY then return "Unstable Portalstone", "portal-icon", true end
				return nil
			end,
			itemCount = function(itemID) return itemID == HEARTH and 1 or 0 end,
			totalItemCount = function(itemID) return itemID == HEARTH and 1 or 0 end,
			isUsable = function() return true end,
			getCooldown = function() return 0, 0, 0 end,
			getItemName = function(itemID)
				if itemID == HEARTH then return "Hearthstone" end
			end,
			getItemIcon = function(itemID)
				if itemID == HEARTH then return "temp" end
			end,
		}
		for k, v in pairs(overrides or {}) do adapter[k] = v end
		return adapter
	end

	-- A test-only registry extension: runtime definitions stay untouched.
	local function TestRegistry()
		return {
			VERSION = HearthstoneDefinitions.VERSION,
			entries = {
				[HEARTH] = { kind = "item" },
				[TOY] = { kind = "toy" },
			},
		}
	end

	describe("Rows", function()
		it("returns one fresh row per reviewed registry ID", function()
			local rows = HearthstoneCollection.Rows(Adapter(), TestRegistry())
			assert.equal(2, #rows)
			local byID = {}
			for _, row in ipairs(rows) do byID[row.itemID] = row end
			assert.is_table(byID[HEARTH])
			assert.is_table(byID[TOY])
		end)

		it("carries kind, resolved name/icon and favorite on each row", function()
			local rows = HearthstoneCollection.Rows(Adapter(), TestRegistry())
			local byID = {}
			for _, row in ipairs(rows) do byID[row.itemID] = row end
			assert.equals("item", byID[HEARTH].kind)
			assert.equals("Hearthstone", byID[HEARTH].name)
			assert.equals("temp", byID[HEARTH].icon)
			assert.equals("toy", byID[TOY].kind)
			assert.equals("Unstable Portalstone", byID[TOY].name)
			assert.equals("portal-icon", byID[TOY].icon)
			assert.is_true(byID[TOY].favorite)
			assert.is_nil(byID[HEARTH].favorite) -- inventory items have none
		end)

		it("reports toy ownership via hasToy and item ownership via itemCount", function()
			local rows = HearthstoneCollection.Rows(Adapter(), TestRegistry())
			local byID = {}
			for _, row in ipairs(rows) do byID[row.itemID] = row end
			assert.is_true(byID[TOY].owned)
			assert.is_true(byID[HEARTH].owned) -- carried 1 > 0
			assert.equal(1, byID[HEARTH].count)
		end)

		it("distinguishes carried count from total ownership", function()
			local adapter = Adapter({
				itemCount = function() return 0 end, -- all copies in the bank
				totalItemCount = function(itemID) return itemID == HEARTH and 2 or 0 end,
			})
			local rows = HearthstoneCollection.Rows(adapter, TestRegistry())
			local byID = {}
			for _, row in ipairs(rows) do byID[row.itemID] = row end
			assert.equal(0, byID[HEARTH].count) -- carried: not summonable now
			assert.equal(2, byID[HEARTH].total) -- but two copies owned overall
		end)

		it("leaves not-ready metadata nil without inventing values", function()
			local adapter = Adapter({
				getItemName = function() return nil end,
				getItemIcon = function() return nil end,
			})
			local row = HearthstoneCollection.Rows(adapter, TestRegistry())[1]
			assert.is_nil(row.name)
			assert.is_nil(row.icon)
		end)

		it("rows are fresh tables: registry and adapter inputs unmutated", function()
			local registry = TestRegistry()
			local adapter = Adapter()
			local rows = HearthstoneCollection.Rows(adapter, registry)
			assert.is_not_equal(registry.entries[HEARTH], rows[1])
			assert.equals("item", registry.entries[HEARTH].kind)
			assert.equals(2, #rows)
			local rowsAgain = HearthstoneCollection.Rows(adapter, registry)
			assert.is_not_equal(rows[1], rowsAgain[1])
		end)
		it("spies per domain: toys probe toy reads, items probe item reads only", function()
			local toyProbes, itemProbes = {}, {}
			local adapter = Adapter()
		local oldHasToy, oldCount = adapter.hasToy, adapter.itemCount
		local oldTotal, oldName, oldIcon =
			adapter.totalItemCount, adapter.getItemName, adapter.getItemIcon
		adapter.hasToy = function(itemID)
			toyProbes[#toyProbes + 1] = itemID
			return oldHasToy(itemID)
		end
		adapter.itemCount = function(itemID)
			itemProbes[#itemProbes + 1] = itemID
			return oldCount(itemID)
		end
		adapter.totalItemCount = function(itemID)
			itemProbes[#itemProbes + 1] = itemID
			return oldTotal(itemID)
		end
		adapter.getItemName = function(itemID)
			itemProbes[#itemProbes + 1] = itemID
			return oldName(itemID)
		end
		adapter.getItemIcon = function(itemID)
			itemProbes[#itemProbes + 1] = itemID
			return oldIcon(itemID)
		end

		HearthstoneCollection.Rows(adapter, TestRegistry())

		-- Toy ownership probes ran only for the toy ID; item reads only for
		-- the item ID. No cross-domain calls either way.
		for _, id in ipairs(toyProbes) do assert.equals(TOY, id) end
		for _, id in ipairs(itemProbes) do assert.equals(HEARTH, id) end
		assert.is_true(#toyProbes > 0)
		assert.is_true(#itemProbes > 0)
	end)
	end)

	describe("Action-time usability and cooldown", function()
		it("passes through usable and cooldown state per item ID", function()
			local adapter = Adapter({
				isUsable = function(itemID) return itemID ~= HEARTH end,
				getCooldown = function(itemID)
					if itemID == HEARTH then return 100, 600, 1 end
					return 0, 0, 0
				end,
			})
			local usable, noMana = HearthstoneCollection.UsableInfo(adapter, HEARTH)
			assert.is_false(usable)
			assert.is_nil(noMana)
			local start, duration, enable =
				HearthstoneCollection.Cooldown(adapter, HEARTH)
			assert.equals(100, start)
			assert.equals(600, duration)
			assert.equals(1, enable)
		end)

		it("reports the noMana flag when the adapter provides it", function()
			local adapter = Adapter({ isUsable = function() return false, true end })
			local usable, noMana = HearthstoneCollection.UsableInfo(adapter, HEARTH)
			assert.is_false(usable)
			assert.is_true(noMana)
		end)
	end)

	describe("Acquisition baseline", function()
		it("initial inventory total is baseline: no acquisition emitted", function()
			local adapter = Adapter({
				itemCount = function(itemID) return itemID == HEARTH and 1 or 0 end,
				totalItemCount = function(itemID) return itemID == HEARTH and 1 or 0 end,
			})
			local acquisitions = {}
			local after = HearthstoneCollection.Baseline(adapter, TestRegistry(),
				function(itemID) acquisitions[#acquisitions + 1] = itemID end)
			assert.same({}, acquisitions)
			assert.equal(1, after[HEARTH])
		end)
		it("uses carried count for both baseline and acquisitions without totals", function()
			local carried = 1
			local adapter = Adapter({
				itemCount = function(itemID)
					return itemID == HEARTH and carried or 0
				end,
			})
			adapter.totalItemCount = nil
			local baseline = HearthstoneCollection.Baseline(adapter, TestRegistry())
			carried = 2
			local acquisitions = {}
			HearthstoneCollection.Acquisitions(adapter, TestRegistry(), baseline,
				function(itemID) acquisitions[#acquisitions + 1] = itemID end)
			assert.same({ HEARTH }, acquisitions)
			assert.equal(2, baseline[HEARTH])
		end)
		it("falls back to carried count when total ownership is unavailable", function()
			local carried = 1
			local adapter = Adapter({
				itemCount = function(itemID)
					return itemID == HEARTH and carried or 0
				end,
				totalItemCount = function() return nil end,
			})
			local baseline = HearthstoneCollection.Baseline(adapter, TestRegistry())
			carried = 2
			local acquisitions = {}
			HearthstoneCollection.Acquisitions(adapter, TestRegistry(), baseline,
				function(itemID) acquisitions[#acquisitions + 1] = itemID end)
			assert.same({ HEARTH }, acquisitions)
			assert.equal(2, baseline[HEARTH])
		end)


		it("uses adapter.hasToy when no toy probe is supplied", function()
			local adapter = Adapter()
			local baseline = HearthstoneCollection.Baseline(adapter, TestRegistry())
			local acquisitions = {}
			HearthstoneCollection.Acquisitions(adapter, TestRegistry(), baseline,
				function(itemID) acquisitions[#acquisitions + 1] = itemID end)
			assert.same({}, acquisitions)
			assert.is_true(baseline[TOY])
		end)

		it("preserves an unknown toy baseline without a toy probe", function()
			local adapter = Adapter()
			adapter.hasToy = nil
			local baseline = HearthstoneCollection.Baseline(adapter, TestRegistry())
			local acquisitions = {}
			HearthstoneCollection.Acquisitions(adapter, TestRegistry(), baseline,
				function(itemID) acquisitions[#acquisitions + 1] = itemID end)
			assert.same({}, acquisitions)
			assert.is_nil(baseline[TOY])
		end)
		it("does not overwrite a known toy baseline without a current probe", function()
			local adapter = Adapter({ hasToy = function() return false end })
			local baseline = HearthstoneCollection.Baseline(adapter, TestRegistry())
			adapter.hasToy = nil
			local acquisitions = {}
			HearthstoneCollection.Acquisitions(adapter, TestRegistry(), baseline,
				function(itemID) acquisitions[#acquisitions + 1] = itemID end)
			assert.same({}, acquisitions)
			assert.is_false(baseline[TOY])
		end)


		it("leaves an unavailable item count unknown", function()
			local adapter = Adapter()
			adapter.itemCount = nil
			local rows = HearthstoneCollection.Rows(adapter, TestRegistry())
			local row
			for _, candidate in ipairs(rows) do
				if candidate.itemID == HEARTH then row = candidate end
			end
			assert.is_nil(row.count)
			assert.is_nil(row.owned)
		end)


		it("a later total increase over the baseline is an acquisition", function()
			local adapter = Adapter({
			totalItemCount = function(itemID) return itemID == HEARTH and 2 or 0 end,
			})
			local before = { [HEARTH] = 1 }
			local acquisitions = {}
			HearthstoneCollection.Acquisitions(adapter, TestRegistry(), before,
				function(itemID) acquisitions[#acquisitions + 1] = itemID end)
			assert.same({ HEARTH }, acquisitions)
			-- The caller's baseline map is updated, not rebuilt.
			assert.equal(2, before[HEARTH])
		end)

		it("toy acquisition rides the same exact-itemID pass-through", function()
			local adapter = Adapter()
			local before = { [TOY] = false }
			local acquisitions = {}
			HearthstoneCollection.Acquisitions(adapter, TestRegistry(), before,
				function(itemID) acquisitions[#acquisitions + 1] = itemID end,
				function(itemID) return itemID == TOY end) -- toy-ownership probe
			assert.same({ TOY }, acquisitions)
			assert.is_true(before[TOY])
		end)

		it("an unchanged or negative change emits nothing", function()
			local adapter = Adapter()
			local before = { [HEARTH] = 1, [TOY] = true }
			local acquisitions = {}
			HearthstoneCollection.Acquisitions(adapter, TestRegistry(), before,
				function(itemID) acquisitions[#acquisitions + 1] = itemID end,
				function(itemID) return itemID == TOY end)
			assert.same({}, acquisitions)
		end)
	end)

	describe("Registry fidelity", function()
		it("reads the real runtime registry without changing it", function()
			local rows = HearthstoneCollection.Rows(Adapter(), HearthstoneDefinitions)
			local byID = {}
			for _, row in ipairs(rows) do byID[row.itemID] = row end
			local expected = 0
			for _ in pairs(HearthstoneDefinitions.entries) do expected = expected + 1 end
			assert.equal(expected, #rows)
			assert.equals("item", byID[HEARTH].kind)
			assert.equals("toy", byID[246565].kind)
			assert.is_true(HearthstoneDefinitions.VERSION >= 3)
			assert.is_nil(HearthstoneDefinitions.entries[TOY])
		end)

		it("leaves a carried item's ownership to its count", function()
			local rows = HearthstoneCollection.Rows(Adapter(), {
				VERSION = 1,
				entries = { [HEARTH] = { kind = "item" } },
			})
			assert.is_true(rows[1].owned)
		end)

		-- The worn hearthstones are out of scope: a bag count of zero is all
		-- this layer sees of a pair of slippers on your feet, and no equipment
		-- read is asked for.
		it("counts a worn hearthstone the bags do not carry as not owned", function()
			local asked = false
			local adapter = Adapter({
				itemCount = function() return 0 end,
				totalItemCount = function() return 0 end,
				isEquipped = function() asked = true return true end,
			})
			local rows = HearthstoneCollection.Rows(adapter, {
				VERSION = 1,
				entries = { [SLIPPERS] = { kind = "item" } },
			})
			assert.is_falsy(rows[1].owned)
			assert.is_false(asked)
		end)

		it("rows carry no preview field", function()
			for _, row in ipairs(HearthstoneCollection.Rows(Adapter(), HearthstoneDefinitions)) do
				assert.is_nil(row.preview)
			end
		end)
	end)

	-- What the pairing window lists: search, collected first then by name, the
	-- cooldown mark and the footer note.
	describe("PickerList", function()
		local function Rows()
			return {
				{ itemID = 3, name = "Zeta Stone", owned = true },
				{ itemID = 1, name = "alpha stone", owned = false },
				{ itemID = 2, name = "Beta Stone", owned = true },
				{ itemID = 4, owned = true },
			}
		end
		local function IDs(list)
			local out = {}
			for _, row in ipairs(list.rows) do out[#out + 1] = row.itemID end
			return out
		end

		it("puts collected first, then sorts by name", function()
			assert.same({ 2, 4, 3, 1 }, IDs(HearthstoneCollection.PickerList(Rows())))
		end)

		it("searches names without case, and an unnamed row by its item ID", function()
			assert.same({ 2 }, IDs(HearthstoneCollection.PickerList(Rows(), { query = "BETA" })))
			assert.same({ 2, 3, 1 }, IDs(HearthstoneCollection.PickerList(Rows(), { query = "stone" })))
			assert.same({ 4 }, IDs(HearthstoneCollection.PickerList(Rows(), { query = "item 4" })))
		end)

		it("counts collected over every row, not only the matches", function()
			assert.equal("3 of 4 collected.",
				HearthstoneCollection.PickerList(Rows(), { query = "zeta" }).note)
		end)

		it("says so when nothing matches", function()
			assert.equal("No reviewed hearthstones match.",
				HearthstoneCollection.PickerList(Rows(), { query = "nothing" }).note)
		end)

		-- The client's item cooldown starts on the GetTime clock. Compared
		-- against time() it is never running, and the card never says so.
		it("marks an owned row whose cooldown is still running", function()
			local list = HearthstoneCollection.PickerList(Rows(), {
				now = 1000,
				cooldown = function(itemID)
					if itemID == 2 then return 900, 900 end
					if itemID == 3 then return 10, 900 end
					return 0, 0
				end,
			})
			local marked = {}
			for _, row in ipairs(list.rows) do marked[row.itemID] = row.onCooldown end
			assert.same({ [2] = true, [3] = false, [4] = false, [1] = false }, marked)
		end)
	end)
end)
