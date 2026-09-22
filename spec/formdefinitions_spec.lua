-- The auras that change the body a transmog is seen on.
local FormDefinitions = require("FormDefinitions")

describe("FormDefinitions", function()
	it("carries a version that rises when the set changes", function()
		assert.is_number(FormDefinitions.VERSION)
		assert.is_true(FormDefinitions.VERSION >= 1)
	end)

	it("knows the two forms that keep the transmog readable", function()
		assert.equal("silhouette", FormDefinitions.Lookup(232698).kind)
		assert.equal("Shadowform", FormDefinitions.Lookup(232698).name)
		assert.equal("silhouette", FormDefinitions.Lookup(114302).kind)
	end)

	it("knows the forms that replace the body outright", function()
		assert.equal("replaced", FormDefinitions.Lookup(24858).kind)
		assert.equal("replaced", FormDefinitions.Lookup(197625).kind)
	end)

	it("gives every entry a name and one of the two kinds", function()
		local kinds = { silhouette = true, replaced = true }
		local count = 0
		for spellID, entry in pairs(FormDefinitions.entries) do
			count = count + 1
			assert.is_number(spellID)
			assert.is_string(entry.name)
			assert.is_true(kinds[entry.kind] == true,
				("spell %d has kind %s"):format(spellID, tostring(entry.kind)))
		end
		assert.is_true(count >= 8)
	end)

	it("does not invent an entry for an unknown spell", function()
		assert.is_nil(FormDefinitions.Lookup(1))
		assert.is_nil(FormDefinitions.Lookup(nil))
		assert.is_nil(FormDefinitions.Lookup("232698"))
	end)

	describe("FromSpellIDs", function()
		it("finds the form among the auras a unit carries", function()
			local spellID, name, kind = FormDefinitions.FromSpellIDs({ 1126, 232698, 21562 })
			assert.equal(232698, spellID)
			assert.equal("Shadowform", name)
			assert.equal("silhouette", kind)
		end)

		it("answers nothing when no aura is a form", function()
			assert.is_nil(FormDefinitions.FromSpellIDs({ 1126, 21562 }))
			assert.is_nil(FormDefinitions.FromSpellIDs({}))
			assert.is_nil(FormDefinitions.FromSpellIDs(nil))
		end)

		it("takes the first form it meets", function()
			local spellID = FormDefinitions.FromSpellIDs({ 197625, 232698 })
			assert.equal(197625, spellID)
		end)
	end)
end)

describe("FormDefinitions transient forms", function()
	it("marks the cooldowns as transient", function()
		assert.is_true(FormDefinitions.IsTransient(228260))
		assert.is_true(FormDefinitions.IsTransient(102560))
		assert.is_true(FormDefinitions.IsTransient(390414))
	end)

	it("leaves a stance unmarked", function()
		assert.is_false(FormDefinitions.IsTransient(232698))
		assert.is_false(FormDefinitions.IsTransient(24858))
		assert.is_false(FormDefinitions.IsTransient(114302))
	end)

	it("says no rather than erroring on a spell it does not know", function()
		assert.is_false(FormDefinitions.IsTransient(nil))
		assert.is_false(FormDefinitions.IsTransient(1))
	end)
end)

-- A form is read out of a unit's helpful auras, and a well-buffed player can
-- carry a great many. The scan must not have a ceiling, so the decision that
-- consumes it must not care how long the list is.
describe("FormDefinitions.FromSpellIDs over a long aura list", function()
	it("finds a form sitting past where a hand-written scan would have stopped", function()
		local spellIDs = {}
		for index = 1, 80 do spellIDs[index] = 100000 + index end
		spellIDs[61] = 232698

		local spellID, name = FormDefinitions.FromSpellIDs(spellIDs)
		assert.equal(232698, spellID)
		assert.equal("Shadowform", name)
	end)

	it("answers nothing for a long list holding no form at all", function()
		local spellIDs = {}
		for index = 1, 80 do spellIDs[index] = 100000 + index end
		assert.is_nil(FormDefinitions.FromSpellIDs(spellIDs))
	end)
end)
