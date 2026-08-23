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
end)
