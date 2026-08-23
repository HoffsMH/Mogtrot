describe("Diagnostics", function()
	it("publishes itself for the WoW loader", function()
		local shared = {}
		local diagnostics = assert(loadfile("Diagnostics.lua"))("Mogtrot", shared)

		assert.equal(diagnostics, shared.Diagnostics)
	end)
end)
