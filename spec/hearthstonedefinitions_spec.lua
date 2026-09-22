-- Pure curated hearthstone registry contract. One versioned table keyed by
-- numeric item ID with a toy/item kind each - the plan's shape exactly. Names,
-- icons and any other display metadata are resolved live by the collection
-- adapter; the registry stores identities only. Deliberately curated: adding
-- an ID is an explicit review decision, never a name heuristic.
local HearthstoneDefinitions = require("HearthstoneDefinitions")

describe("HearthstoneDefinitions", function()
	it("exposes a numeric VERSION", function()
		assert.is_number(HearthstoneDefinitions.VERSION)
		assert.is_true(HearthstoneDefinitions.VERSION >= 1)
	end)

	it("keys entries by positive numeric item IDs with toy/item kinds only", function()
		for itemID, entry in pairs(HearthstoneDefinitions.entries) do
			assert.is_number(itemID)
			assert.is_true(itemID > 0, "item ID must be positive")
			assert.equals(math.floor(itemID), itemID)
			assert.is_table(entry)
			assert.is_true(entry.kind == "toy" or entry.kind == "item",
				"kind must be 'toy' or 'item'")
		end
	end)

	it("entries store no localized name or icon fields", function()
		for _, entry in pairs(HearthstoneDefinitions.entries) do
			assert.is_nil(entry.name)
			assert.is_nil(entry.icon)
			assert.is_nil(entry.iconFileID)
		end
	end)

	it("contains the classic inventory hearthstone 6948 as an item", function()
		local entry = HearthstoneDefinitions.entries[6948]
		assert.is_table(entry)
		assert.equals("item", entry.kind)
	end)
	it("contains Cosmic Hearthstone as a toy with its use spell", function()
		local entry = HearthstoneDefinitions.entries[246565]
		assert.is_table(entry)
		assert.equals("toy", entry.kind)
		assert.equals(1242509, entry.spellID)
	end)

	it("entries carry no preview or animation metadata", function()
		for _, entry in pairs(HearthstoneDefinitions.entries) do
			assert.is_nil(entry.preview)
			assert.is_nil(entry.animationID)
			assert.is_nil(entry.spellVisualKitID)
		end
	end)

	it("exposes a non-empty collection-ready registry shape", function()
		assert.is_table(HearthstoneDefinitions.entries)
		assert.is_function(HearthstoneDefinitions.Lookup)
		assert.is_true(next(HearthstoneDefinitions.entries) ~= nil)
		for _, entry in pairs(HearthstoneDefinitions.entries) do
			assert.is_table(entry)
			assert.is_true(entry.kind == "toy" or entry.kind == "item")
		end
	end)

	it("looks up every registry entry by its exact numeric key", function()
		for itemID, entry in pairs(HearthstoneDefinitions.entries) do
			assert.equals(entry, HearthstoneDefinitions.Lookup(itemID))
			assert.is_nil(HearthstoneDefinitions.Lookup(tostring(itemID)))
		end
	end)

	it("looks an entry up by item ID without mutating the registry", function()
		local entry = HearthstoneDefinitions.Lookup(6948)
		assert.is_table(entry)
		assert.equals("item", entry.kind)
		assert.is_nil(HearthstoneDefinitions.Lookup(99999999))
		assert.is_nil(HearthstoneDefinitions.Lookup("6948")) -- no coercion
		assert.is_nil(HearthstoneDefinitions.Lookup(-1))
		-- Lookup introduced nothing.
		assert.is_nil(HearthstoneDefinitions.entries[99999999])
	end)
end)
