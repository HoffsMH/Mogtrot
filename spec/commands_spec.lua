local Commands = assert(loadfile("Commands.lua"))("Mogtrot", {})

describe("Commands.RepairOutfitLooks", function()
	it("keeps the known capture and blanks only this character's other outfits", function()
		local charDB = { looks = { [2] = "known", [3] = "poison", [4] = "poison" } }
		local accountDB = { library = { records = {
			{ source = "mine", origin = "outfit", guid = "player", originID = 2, look = "known" },
			{ source = "mine", origin = "outfit", guid = "player", originID = 3, look = "poison" },
			{ source = "mine", origin = "outfit", guid = "alt", originID = 3, look = "alt" },
			{ source = "mine", origin = "customSet", guid = "player", originID = 3, look = "set" },
		} } }

		assert.equal(1, Commands.RepairOutfitLooks(charDB, accountDB, "player", 2))
		assert.same({ [2] = "known" }, charDB.looks)
		assert.equal("known", accountDB.library.records[1].look)
		assert.equal("", accountDB.library.records[2].look)
		assert.equal("alt", accountDB.library.records[3].look)
		assert.equal("set", accountDB.library.records[4].look)
	end)
end)
