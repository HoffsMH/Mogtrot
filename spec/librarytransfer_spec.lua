local LibraryTransfer = assert(loadfile("LibraryTransfer.lua"))("Mogtrot", {})

local function Location(slot, kind)
	return {
		GetSlot = function() return slot end,
		GetType = function() return kind end,
	}
end

describe("LibraryTransfer", function()
	it("chooses a collected usable sibling source", function()
		local infos = {
			[101] = { visualID = 7, isCollected = false },
			[901] = { visualID = 7, isCollected = true, useErrorType = 0 },
		}
		assert.equal(901, LibraryTransfer.PreferredSource(101, {
			getSourceInfo = function(id) return infos[id] end,
			getAllSources = function() return { 101, 901 } end,
			noError = 0,
		}))
	end)

	it("plans primary, secondary shoulder, and illusion appearances", function()
		local plan = LibraryTransfer.Plan({ [3] = { 101, 102, 0 }, [16] = { 201, 0, 301 } },
			function(slot, kind, secondary)
				return Location(slot * 10 + (secondary and 1 or 0), kind)
			end, 7, 8)
		assert.same({
			{ slot = 30, type = 7, transmogID = 101 },
			{ slot = 31, type = 7, transmogID = 102 },
			{ slot = 160, type = 7, transmogID = 201 },
			{ slot = 160, type = 8, transmogID = 301 },
		}, plan)
	end)

	it("replaces appearance sources without replacing illusions", function()
		local plan = LibraryTransfer.Plan({ [3] = { 101, 102, 301 } },
			function(slot, kind, secondary)
				return Location(slot * 10 + (secondary and 1 or 0), kind)
			end, 7, 8, function(sourceID)
				return sourceID + 800
			end)
		assert.same({
			{ slot = 30, type = 7, transmogID = 901 },
			{ slot = 31, type = 7, transmogID = 902 },
			{ slot = 30, type = 8, transmogID = 301 },
		}, plan)
	end)

	it("counts an unusable weapon and its dependent illusion as unavailable", function()
		local plan = LibraryTransfer.Plan({ [16] = { 201, 0, 301 } },
			function(slot, kind) return Location(slot, kind) end,
			7, 8, function() return nil end)
		assert.equal(0, #plan)
		assert.equal(2, plan.unavailable)
	end)

	it("plans hidden display state for empty snapshot slots", function()
		local plan = LibraryTransfer.Plan({ [1] = { 101, 0, 0 } },
			function(slot, kind) return Location(slot, kind) end,
			7, 8, nil, {
				emptySlots = { 1, 3 }, noTransmogID = 0, hiddenDisplayType = 9,
			})
		assert.same({ slot = 3, type = 7, transmogID = 0, displayType = 9 }, plan[2])
	end)

	it("hides an unusable appearance instead of attempting its source", function()
		local plan = LibraryTransfer.Plan({ [16] = { 201, 0, 301 } },
			function(slot, kind) return Location(slot, kind) end,
			7, 8, function() return nil end, {
				hideUnavailable = true, noTransmogID = 0, hiddenDisplayType = 9,
			})
		assert.same({
			{ slot = 16, type = 7, transmogID = 0, displayType = 9 },
		}, plan)
		assert.equal(0, plan.unavailable or 0)
	end)

	it("counts only changes confirmed by the viewed outfit", function()
		local pending = {}
		local attempted, verified = LibraryTransfer.Apply({
			{ slot = 1, type = 7, transmogID = 101 },
			{ slot = 2, type = 7, transmogID = 202 },
		}, {
			option = function() return 0 end,
			assignedDisplayType = 4,
			setPending = function(slot, kind, option, id, display)
				pending[slot] = { kind, option, id, display }
			end,
			getViewed = function(slot)
				return { transmogID = slot == 1 and pending[slot][3] or 999 }
			end,
		})
		assert.same({ 2, 1 }, { attempted, verified })
		assert.same({ 7, 0, 101, 4 }, pending[1])
	end)
end)
