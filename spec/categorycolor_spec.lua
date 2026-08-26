local CategoryColor = require("CategoryColor")

describe("CategoryColor", function()
	it("creates colors inside the readable saturation and value bounds", function()
		local values = { 0.25, 0, 1 }
		local at = 0
		local color = CategoryColor.Random(function()
			at = at + 1
			return values[at]
		end)

		local max = math.max(color.r, color.g, color.b)
		local min = math.min(color.r, color.g, color.b)
		local saturation = (max - min) / max
		assert.near(CategoryColor.MIN_SATURATION, saturation, 0.000001)
		assert.near(CategoryColor.MAX_VALUE, max, 0.000001)
	end)

	it("keeps a valid saved color", function()
		local saved = { r = 0.1, g = 0.2, b = 0.3 }
		assert.same(saved, CategoryColor.Normalize(saved))
	end)

	it("replaces malformed saved colors", function()
		assert.same(CategoryColor.DEFAULT, CategoryColor.Normalize({ r = -1, g = 0, b = 0 }))
		assert.same(CategoryColor.DEFAULT, CategoryColor.Normalize(nil))
	end)
end)
