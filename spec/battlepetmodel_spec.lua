-- Battle-pet model adapter contract. Pure and injected: the frame hands in a
-- model fake plus display hooks; BattlePetModel.Apply decides whether the
-- copy's displayID can be rendered. Success returns true after the display
-- hooks ran; anything unsuitable - missing displayID, unavailable model,
-- throwing display setter - returns false and leaves the static icon
-- fallback in charge. No globals, no WoW API.
local BattlePetModel = require("BattlePetModel")

describe("BattlePetModel", function()
	local function FakeModel()
		local model = { shown = false }
		return model
	end

	it("applies the row's displayID and reports success", function()
		local model = FakeModel()
		local calls = {}
		local applied = BattlePetModel.Apply(model, { guid = "Pet-A", displayID = 4242 }, {
			setDisplay = function(m, displayID)
				calls[#calls + 1] = { m, displayID }
			end,
			show = function(m) m.shown = true end,
		})
		assert.is_true(applied)
		assert.same({ model, 4242 }, calls[1])
		assert.is_true(model.shown)
	end)

	it("fails cleanly when the row has no displayID", function()
		local model = FakeModel()
		local touched = false
		local applied = BattlePetModel.Apply(model, { guid = "Pet-A" }, {
			setDisplay = function() touched = true end,
			show = function() touched = true end,
		})
		assert.is_false(applied)
		assert.is_false(touched) -- static icon fallback stays in charge
		assert.is_false(model.shown)
	end)

	it("fails cleanly when the displayID is zero or negative", function()
		local model = FakeModel()
		assert.is_false(BattlePetModel.Apply(model, { guid = "Pet-A", displayID = 0 }, {
			setDisplay = function() end,
			show = function() end,
		}))
		assert.is_false(BattlePetModel.Apply(model, { guid = "Pet-A", displayID = -5 }, {
			setDisplay = function() end,
			show = function() end,
		}))
	end)

	it("reports failure when the model itself is unavailable", function()
		local applied = BattlePetModel.Apply(nil, { guid = "Pet-A", displayID = 4242 }, {
			setDisplay = function() end,
			show = function() end,
		})
		assert.is_false(applied)
	end)

	it("survives a throwing display setter and returns false", function()
		local model = FakeModel()
		local applied = BattlePetModel.Apply(model, { guid = "Pet-A", displayID = 4242 }, {
			setDisplay = function() error("model scene not ready") end,
			show = function() end,
		})
		assert.is_false(applied)
		assert.is_false(model.shown) -- icon fallback unaffected
	end)

	it("survives a missing display hook", function()
		local applied = BattlePetModel.Apply(FakeModel(), { guid = "Pet-A", displayID = 4242 }, {})
		assert.is_false(applied)
	end)

	it("does not mutate the row's metadata", function()
		local row = { guid = "Pet-A", displayID = 4242, name = "Cat" }
		BattlePetModel.Apply(FakeModel(), row, {
			setDisplay = function() end,
			show = function() end,
		})
		assert.equals(4242, row.displayID)
		assert.equals("Cat", row.name)
	end)

	it("accepts the BattlePetCollection row shape unchanged", function()
		local row = {
			guid = "BattlePet-0-00000C0FFEE-42",
			displayID = 1234,
			speciesID = 42,
			name = "Cat",
		}
		local seen = {}
		assert.is_true(BattlePetModel.Apply(FakeModel(), row, {
			setDisplay = function(_, displayID) seen[#seen + 1] = displayID end,
			show = function() end,
		}))
		assert.same({ 1234 }, seen)
	end)
end)
