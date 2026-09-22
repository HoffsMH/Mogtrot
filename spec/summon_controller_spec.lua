describe("SummonController", function()
	it("shows a formatted summon refusal", function()
		local shared = {}
		local controller = assert(loadfile("SummonController.lua"))("Mogtrot", shared)
		local messages = {}
		_G.UIErrorsFrame = {
			AddMessage = function(_, text) table.insert(messages, text) end,
		}
		local addon = {}
		controller.Attach(addon, { mountTravelSnapshot = function() end })

		addon:RefuseSummon(false, "can't summon %s.", "here")

		assert.same({ "Mogtrot: can't summon here." }, messages)
	end)

	-- A pin joins or leaves the set the summon key draws from, so the macro
	-- icon standing for that set is stale the moment one is toggled. Nothing
	-- else tells it: the outfit has not moved.
	describe("pin edits", function()
		local addon

		before_each(function()
			local shared = { Pins = assert(loadfile("Pins.lua"))("Mogtrot", {}) }
			_G.time = function() return 1000 end
			_G.MogtrotDB = {
				pins = { mounts = { records = {}, autoNew = true, days = 7 } },
			}
			addon = { refreshes = 0 }
			addon.RepaintMountCards = function() end
			function addon:CompanionChoiceChanged()
				self.refreshes = self.refreshes + 1
			end
			assert(loadfile("SummonController.lua"))("Mogtrot", shared)
				.Attach(addon, { mountTravelSnapshot = function() end })
		end)

		it("refreshes the macro icons when a mount is pinned and unpinned", function()
			addon:ToggleMountPin(42)
			assert.is_true(addon:IsMountPinned(42))
			assert.equal(1, addon.refreshes)

			addon:ToggleMountPin(42)
			assert.is_false(addon:IsMountPinned(42))
			assert.equal(2, addon.refreshes)
		end)

		it("refreshes the macro icons when an unpinned mount is kept", function()
			addon:ToggleMountPin(42)
			addon:ToggleMountPin(42)
			addon.refreshes = 0

			addon:KeepMountPinned(42)
			assert.is_true(addon:IsMountPinned(42))
			assert.equal(1, addon.refreshes)
		end)
	end)
end)
