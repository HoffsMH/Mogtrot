local MinimapButton = require("MinimapButton")

describe("MinimapButton", function()
	it("shows by default and stores an explicit hide choice", function()
		local account = {}
		assert.is_true(MinimapButton.IsShown(account))
		MinimapButton.SetShown(account, false)
		assert.is_false(MinimapButton.IsShown(account))
		assert.is_true(account.minimap.hide)
	end)

	it("uses the active addon folder for its icon", function()
		assert.equal("Interface\\AddOns\\MogtrotDev\\Art\\MogtrotMinimap",
			MinimapButton.IconPath("MogtrotDev"))
	end)

	it("only moves while attached to the minimap", function()
		local minimap = {}
		assert.is_true(MinimapButton.CanDrag(minimap, minimap))
		assert.is_false(MinimapButton.CanDrag({}, minimap))
	end)

	it("places the button just outside the actual minimap edge", function()
		local x, y = MinimapButton.Coordinates(0, 280, 260)
		assert.equal(145, x)
		assert.near(0, y, 0.0001)
	end)
end)
