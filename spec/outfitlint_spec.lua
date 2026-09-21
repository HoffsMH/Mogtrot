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
