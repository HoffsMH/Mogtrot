describe("MountPinController", function()
	it("records the event payload immediately without reading the journal", function()
		local shared = { MountPins = {
			RecordAcquired = function(account, mountID, now)
				account.seen = { mountID, now }
				return true
			end,
		} }
		local Controller = assert(loadfile("MountPinController.lua"))("Mogtrot", shared)
		local account, changed = {}, 0
		local controller = Controller.New(account, {
			now = function() return 1234 end,
			changed = function() changed = changed + 1 end,
		})
		assert.is_true(controller:OnNewMount(77))
		assert.same({ 77, 1234 }, account.seen)
		assert.equal(1, changed)
	end)
end)
