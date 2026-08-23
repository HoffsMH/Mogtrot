local Addon = require("Addon")

describe("Addon", function()
	it("is the shared addon coordinator, independent of Blizzard frames", function()
		assert.is_table(Addon)
		assert.is_nil(Addon.eventFrame)
	end)
end)
