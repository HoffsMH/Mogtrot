local Titles = require("OutfitTitles")

describe("OutfitTitles", function()
	it("replaces links and prunes history for titles no longer linked", function()
		local char = {
			titles = { [7] = { [1] = true, [2] = true } },
			titleRotation = { [7] = { serial = 4, used = { [1] = 3, [2] = 4 } } },
		}

		Titles.Replace(char, 7, { 2, 3 })

		assert.same({ [2] = true, [3] = true }, char.titles[7])
		assert.same({ [2] = 4 }, char.titleRotation[7].used)
		Titles.Replace(char, 7, {})
		assert.is_nil(char.titles[7])
		assert.is_nil(char.titleRotation[7])
	end)

	it("adds copied titles while preserving the target links and history", function()
		local char = {
			titles = { [7] = { [1] = true, [2] = true }, [8] = { [2] = true, [3] = true } },
			titleRotation = { [8] = { serial = 5, used = { [2] = 4, [3] = 5 } } },
		}

		Titles.Copy(char, 7, 8, true)

		assert.same({ [1] = true, [2] = true, [3] = true }, char.titles[8])
		assert.same({ [2] = 4, [3] = 5 }, char.titleRotation[8].used)
	end)

	it("replaces copied titles and drops history for removed titles", function()
		local char = {
			titles = { [7] = { [1] = true, [2] = true }, [8] = { [2] = true, [3] = true } },
			titleRotation = { [8] = { serial = 5, used = { [2] = 4, [3] = 5 } } },
		}

		Titles.Copy(char, 7, 8, false)

		assert.same({ [1] = true, [2] = true }, char.titles[8])
		assert.same({ [2] = 4 }, char.titleRotation[8].used)
	end)

	it("clears title links and their rotation history", function()
		local char = {
			titles = { [7] = { [1] = true } },
			titleRotation = { [7] = { serial = 2, used = { [1] = 2 } } },
		}

		Titles.Clear(char, 7)

		assert.is_nil(char.titles[7])
		assert.is_nil(char.titleRotation[7])
	end)

	it("uses every known linked title before repeating", function()
		local char = { titles = { [7] = { [1] = true, [2] = true, [3] = true } }, titleRotation = {} }
		local known = { [1] = true, [2] = true, [3] = true }
		local chosen = {}
		for _ = 1, 4 do
			local id = Titles.Choose(char, 7, known, nil, function(n) return n end)
			table.insert(chosen, id)
			Titles.Record(char, 7, id)
		end

		assert.same({ 3, 2, 1, 3 }, chosen)
	end)

	it("skips unknown titles and prefers a different current title in a tie", function()
		local char = { titles = { [7] = { [1] = true, [2] = true, [3] = true } }, titleRotation = {} }
		local id = Titles.Choose(char, 7, { [1] = true, [2] = true }, 2, function() return 1 end)
		assert.equal(1, id)
	end)

	it("cleans deleted outfits", function()
		local char = {
			titles = { [7] = { [1] = true }, [8] = { [2] = true } },
			titleRotation = { [7] = {}, [8] = {} },
		}
		Titles.Clean(char, { [8] = true })
		assert.same({ [8] = { [2] = true } }, char.titles)
		assert.same({ [8] = {} }, char.titleRotation)
	end)
end)
