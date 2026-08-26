local Picker = require("OutfitTitlePicker")

describe("OutfitTitlePicker", function()
	it("builds known title choices with clean names and preselection", function()
		local items = Picker.BuildItems(4, function(id) return id ~= 3 end, function(id)
			return ({ "Elder %s", "the Patient", "Unknown", "the Patient" })[id]
		end, { [2] = true }, "Bitrot")

		assert.same({
			{ titleID = 2, name = "Bitrot, the Patient", preselected = true },
			{ titleID = 4, name = "Bitrot, the Patient", preselected = false },
			{ titleID = 1, name = "Elder Bitrot", preselected = false },
		}, items)
	end)

	it("renders prefix and suffix titles with the character name", function()
		local items = Picker.BuildItems(2, function() return true end, function(id)
			return id == 1 and "%s the Explorer" or "Elder %s"
		end, {}, "Mog")
		assert.same({ "Elder Mog", "Mog the Explorer" }, { items[1].name, items[2].name })
	end)

	it("uses Blizzard's trailing-space convention when there is no placeholder", function()
		assert.equals("Corporal Bitrot", Picker.DisplayName("Corporal ", "Bitrot"))
		assert.equals("Anub' Bitrot", Picker.DisplayName("Anub'", "Bitrot"))
		assert.equals("Bitrot, Champion of the Naaru",
			Picker.DisplayName("Champion of the Naaru", "Bitrot"))
	end)

	it("lists already linked titles before unselected titles", function()
		local items = Picker.BuildItems(3, function() return true end, function(id)
			return ({ "Alpha ", "Beta ", "Zulu " })[id]
		end, { [3] = true }, "Mog")

		assert.same({ 3, 1, 2 }, {
			items[1].titleID, items[2].titleID, items[3].titleID,
		})
	end)

	it("applies exactly the selected title IDs", function()
		local replaced
		Picker.Apply({ Replace = function(_, outfitID, ids) replaced = { outfitID, ids } end }, {}, 7,
			{ { titleID = 9 }, { titleID = 2 } })
		assert.same({ 7, { 2, 9 } }, replaced)
	end)
end)
