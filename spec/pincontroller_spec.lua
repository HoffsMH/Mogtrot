-- Generic acquisition controller contract, ported from the mount-pin
-- controller. It binds one caller-owned pin domain and translates an
-- OnAcquired(id) event into Pins.RecordAcquired(domain, id, now) plus a
-- changed callback that fires only for newly recorded acquisitions.
describe("PinController", function()
	-- A stub Pins model recording the last (domain, id, now) it was handed,
	-- with the next RecordAcquired result chosen per call.
	local function StubPins(results)
		local recorded = {}
		local pins = {
			recorded = recorded,
			RecordAcquired = function(domain, id, now)
				recorded[#recorded + 1] = { domain = domain, id = id, now = now }
				return table.remove(results, 1)
			end,
		}
		return pins
	end

	local function Load(pins)
		return assert(loadfile("PinController.lua"))("Mogtrot", { Pins = pins })
	end

	it("records the event payload immediately without reading the journal", function()
		local pins = StubPins({ true })
		local domain, changed = { records = {} }, 0
		local controller = Load(pins).New(domain, {
			now = function() return 1234 end,
			changed = function() changed = changed + 1 end,
		})
		assert.is_true(controller:OnAcquired("pet-1"))
		assert.same({ domain = domain, id = "pet-1", now = 1234 }, pins.recorded[1])
		assert.equal(1, changed)
	end)

	it("passes the injected now to Pins.RecordAcquired, never a wall clock", function()
		local pins = StubPins({ true })
		local controller = Load(pins).New({ records = {} }, { now = function() return 777 end })
		controller:OnAcquired(42)
		assert.equal(777, pins.recorded[1].now)
	end)

	it("preserves exact numeric and string IDs", function()
		local pins = StubPins({ true, true })
		local controller = Load(pins).New({ records = {} }, { now = function() return 1 end })
		controller:OnAcquired("Pet-0xA-0002")
		controller:OnAcquired(42)
		assert.equal("Pet-0xA-0002", pins.recorded[1].id)
		assert.equal(42, pins.recorded[2].id)
	end)

	it("does not notify when the acquisition was already recorded or suppressed", function()
		local pins = StubPins({ false })
		local changed = 0
		local controller = Load(pins).New({ records = {} }, {
			now = function() return 1 end,
			changed = function() changed = changed + 1 end,
		})
		assert.is_false(controller:OnAcquired(42))
		assert.equal(0, changed)
	end)

	it("returns false safely when no domain is bound", function()
		local pins = StubPins({})
		local changed = 0
		local controller = Load(pins).New(nil, {
			now = function() return 1 end,
			changed = function() changed = changed + 1 end,
		})
		assert.is_false(controller:OnAcquired(42))
		assert.equal(0, #pins.recorded)
		assert.equal(0, changed)
	end)

	it("switches to a late-bound store and leaves the old one untouched", function()
		local pins = StubPins({ true })
		local first, second = { records = {} }, { records = {} }
		local controller = Load(pins).New(first, { now = function() return 1 end })
		controller:BindDomain(second)
		controller:OnAcquired("pet-1")
		assert.equal(second, pins.recorded[1].domain)
		assert.same({ records = {} }, first)
	end)
end)
