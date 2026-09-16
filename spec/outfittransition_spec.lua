-- Deferred authoritative outfit-transition guard contract. The controller
-- coalesces synchronous TRANSMOG_DISPLAYED_OUTFIT_CHANGED events, reads the
-- authoritative active outfit ID on the next scheduled frame, and dispatches
-- onChanged only when that ID differs from its guard. The first successful
-- read initializes the guard with no dispatch, so login never summons.
-- Everything (reader, scheduler) is injected; no globals, no clock, no WoW.
local OutfitTransition = require("OutfitTransition")

describe("OutfitTransition", function()
	-- Fake scheduler: OnChanged-style callbacks land in a queue the test runs
	local function FakeScheduler()
		local fake = { pending = {} }
		function fake.schedule(fn)
			fake.pending[#fake.pending + 1] = fn
			return #fake.pending
		end
		function fake.run()
			local queued = fake.pending
			-- Clear to a fresh table before callbacks run, so a callback can
			-- schedule the next frame without indexing nil.
			fake.pending = {}
			for _, fn in ipairs(queued) do fn() end
		end
		return fake
	end

	it("initializes the guard on the first successful read without dispatch", function()
		local schedule = FakeScheduler()
		local dispatched = {}
		local controller = OutfitTransition.New(
			function() return 7 end,
			schedule.schedule,
			function(id) dispatched[#dispatched + 1] = id end)

		controller:Initialize()
		schedule.run()
		assert.same({}, dispatched)
		-- Same ID afterwards is a no-op: the guard now knows 7.
		controller:OutfitChanged()
		schedule.run()
		assert.same({}, dispatched)
	end)

	it("does not dispatch from a nil first read; it retries exactly once", function()
		local schedule = FakeScheduler()
		local reads = { nil, nil } -- first frame nil, retry also nil
		local dispatched = {}
		local controller = OutfitTransition.New(
			function() return table.remove(reads, 1) end,
			schedule.schedule,
			function(id) dispatched[#dispatched + 1] = id end)

		controller:Initialize()
		-- First frame: nil -> schedules exactly one retry.
		schedule.run()
		assert.same({}, dispatched)
		-- Retry frame: still nil -> the one-retry budget is spent, so the guard
		-- gives up this cycle without dispatching or scheduling again.
		schedule.run()
		assert.same({}, dispatched)
		assert.same({}, schedule.pending)
	end)

	it("dispatches exactly once when the authoritative ID differs from the guard", function()
		local schedule = FakeScheduler()
		local reads, dispatched = { 7 }, {}
		local controller = OutfitTransition.New(
			function() return table.remove(reads, 1) end,
			schedule.schedule,
			function(id) dispatched[#dispatched + 1] = id end)

		controller:Initialize()
		schedule.run() -- guard := 7, no dispatch

		reads = { 9 }
		controller:OutfitChanged()
		schedule.run()
		assert.same({ 9 }, dispatched)
		assert.same({}, schedule.pending)
	end)

	it("dispatches on a change back to an earlier ID, then no-ops on same ID", function()
		local schedule = FakeScheduler()
		local reads, dispatched = { 7 }, {}
		local controller = OutfitTransition.New(
			function() return table.remove(reads, 1) end,
			schedule.schedule,
			function(id) dispatched[#dispatched + 1] = id end)

		controller:Initialize()
		schedule.run()

		reads = { 9 }
		controller:OutfitChanged()
		schedule.run()
		assert.same({ 9 }, dispatched)

		-- Every real authoritative change dispatches, including back to 7.
		reads = { 7 }
		controller:OutfitChanged()
		schedule.run()
		assert.same({ 9, 7 }, dispatched)

		-- A further same-ID event does not dispatch again.
		reads = { 7 }
		controller:OutfitChanged()
		schedule.run()
		assert.same({ 9, 7 }, dispatched)
	end)

	it("coalesces duplicate events into one scheduled read", function()
		local schedule = FakeScheduler()
		local reads, dispatched = { 7 }, {}
		local controller = OutfitTransition.New(
			function() return table.remove(reads, 1) end,
			schedule.schedule,
			function(id) dispatched[#dispatched + 1] = id end)

		controller:Initialize()
		schedule.run()

		reads = { 9 } -- all three events coalesce into this single read
		controller:OutfitChanged()
		controller:OutfitChanged()
		controller:OutfitChanged()
		assert.equal(1, #schedule.pending)
		schedule.run()
		assert.equal(0, #reads) -- exactly one read happened
		assert.same({ 9 }, dispatched)
	end)

	it("dispatches a coalesced change once and leaves nothing pending", function()
		local schedule = FakeScheduler()
		local reads, dispatched = { 7 }, {}
		local controller = OutfitTransition.New(
			function() return table.remove(reads, 1) end,
			schedule.schedule,
			function(id) dispatched[#dispatched + 1] = id end)

		controller:Initialize()
		schedule.run()

		reads = { 8 }
		controller:OutfitChanged()
		controller:OutfitChanged()
		schedule.run() -- the coalesced read dispatches 8 once, guard := 8
		schedule.run() -- nothing was scheduled after it
		assert.same({ 8 }, dispatched)
		assert.same({}, schedule.pending)
	end)

	it("passes exact numeric outfit IDs through unchanged", function()
		local schedule = FakeScheduler()
		local reads, dispatched = { 1200000000 }, {}
		local controller = OutfitTransition.New(
			function() return table.remove(reads, 1) end,
			schedule.schedule,
			function(id) dispatched[#dispatched + 1] = id end)

		controller:Initialize()
		schedule.run()
		reads = { 1200000001 }
		controller:OutfitChanged()
		schedule.run()
		assert.same({ 1200000001 }, dispatched)
	end)

	it("treats a nil read after a known guard as no information, not a change", function()
		local schedule = FakeScheduler()
		local reads, dispatched = { 7 }, {}
		local controller = OutfitTransition.New(
			function() return table.remove(reads, 1) end,
			schedule.schedule,
			function(id) dispatched[#dispatched + 1] = id end)

		controller:Initialize()
		schedule.run()
		reads = { nil, 7 }
		controller:OutfitChanged()
		schedule.run() -- nil: one retry
		schedule.run() -- retry answers 7: same as guard, no dispatch
		assert.same({}, dispatched)
	end)
	it("resets the retry budget for each later outfit-change cycle", function()
		local schedule = FakeScheduler()
		local reads, dispatched = { 7 }, {}
		local controller = OutfitTransition.New(
			function() return table.remove(reads, 1) end,
			schedule.schedule,
			function(id) dispatched[#dispatched + 1] = id end)

		controller:Initialize()
		schedule.run()

		-- A nil read and its nil retry exhaust the first cycle.
		reads = { nil, nil }
		controller:OutfitChanged()
		schedule.run()
		schedule.run()
		assert.same({}, dispatched)

		-- A later cycle gets its own retry and can settle normally.
		reads = { nil, 9 }
		controller:OutfitChanged()
		schedule.run()
		assert.equal(1, #schedule.pending)
		schedule.run()
		assert.same({ 9 }, dispatched)
	end)
end)
