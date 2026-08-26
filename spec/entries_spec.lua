local Tree = require("Tree")
local H = require("spec.helpers")

describe("Tree.BuildEntries", function()
	local db, tier, sub, casual, byID

	before_each(function()
		db = H.NewDB()
		tier = H.AddRoot(db, "Tier")
		sub = H.AddChild(db, tier, "Sub")
		casual = H.AddRoot(db, "Casual")
		H.AddRoot(db, "Unsorted", true)

		H.AddOutfit(db, tier, 10)
		H.AddOutfit(db, sub, 20)
		H.AddOutfit(db, casual, 30)

		byID = H.OutfitsByID({ [10] = "Tier Chest", [20] = "Sub Robe", [30] = "Casual Hat" })
	end)

	it("flattens depth first, own outfits before sub-categories", function()
		assert.same({
			"0 cat:Tier",
			"1 outfit:Tier Chest",
			"1 cat:Sub",
			"2 outfit:Sub Robe",
			"0 cat:Casual",
			"1 outfit:Casual Hat",
			"0 cat:Unsorted",
		}, H.Rows(db, Tree.BuildEntries(db, byID, nil)))
	end)

	it("hides the contents of a collapsed category", function()
		db.cats[tier].collapsed = true
		assert.same({
			"0 cat:Tier",
			"0 cat:Casual",
			"1 outfit:Casual Hat",
			"0 cat:Unsorted",
		}, H.Rows(db, Tree.BuildEntries(db, byID, nil)))
	end)

	it("skips outfits the server did not report", function()
		H.AddOutfit(db, casual, 99)
		assert.same({
			"0 cat:Casual",
			"1 outfit:Casual Hat",
		}, H.Rows(db, Tree.BuildEntries(db, byID, "casual")))
	end)

	it("brings the whole category when its own name matches", function()
		assert.same({
			"0 cat:Tier",
			"1 outfit:Tier Chest",
			"1 cat:Sub",
			"2 outfit:Sub Robe",
		}, H.Rows(db, Tree.BuildEntries(db, byID, "tier")))
	end)

	it("keeps only the matching rows when a category matches through a descendant", function()
		assert.same({
			"0 cat:Tier",
			"1 cat:Sub",
			"2 outfit:Sub Robe",
		}, H.Rows(db, Tree.BuildEntries(db, byID, "robe")))
	end)

	it("drops a category with no match anywhere beneath it", function()
		assert.same({
			"0 cat:Casual",
			"1 outfit:Casual Hat",
		}, H.Rows(db, Tree.BuildEntries(db, byID, "hat")))
	end)

	it("ignores collapsed state while searching", function()
		db.cats[tier].collapsed = true
		db.cats[sub].collapsed = true
		assert.same({
			"0 cat:Tier",
			"1 cat:Sub",
			"2 outfit:Sub Robe",
		}, H.Rows(db, Tree.BuildEntries(db, byID, "robe")))
	end)

	it("reports the true index in the category, not the filtered one", function()
		H.AddOutfit(db, casual, 31)
		H.AddOutfit(db, casual, 32)
		byID[31] = { outfitID = 31, name = "Second" }
		byID[32] = { outfitID = 32, name = "Wanted" }

		local entries = Tree.BuildEntries(db, byID, "wanted")
		local outfit
		for _, entry in ipairs(entries) do
			if entry.kind == "outfit" then outfit = entry end
		end
		assert.equal(32, outfit.outfitID)
		assert.equal(3, outfit.indexInCat)
	end)

	it("treats an empty query as matching everything, so Core must pass nil", function()
		assert.equal(7, #Tree.BuildEntries(db, byID, ""))
	end)

	it("survives an empty database", function()
		assert.same({}, Tree.BuildEntries(H.NewDB(), byID, nil))
	end)

	it("hides only category subtrees with no outfits", function()
		local emptyParent = H.AddRoot(db, "Empty parent")
		local emptyChild = H.AddChild(db, emptyParent, "Empty child")
		local parentWithOutfitBelow = H.AddRoot(db, "Parent with outfit below")
		local childWithOutfit = H.AddChild(db, parentWithOutfitBelow, "Child with outfit")
		H.AddOutfit(db, childWithOutfit, 40)
		byID[40] = { outfitID = 40, name = "Descendant outfit" }

		local rows = H.Rows(db, Tree.BuildEntries(db, byID, nil, true))

		assert.is_nil(table.concat(rows, "\n"):match("Empty parent"))
		assert.is_nil(table.concat(rows, "\n"):match("Empty child"))
		assert.is_truthy(table.concat(rows, "\n"):match("Parent with outfit below"))
		assert.is_truthy(table.concat(rows, "\n"):match("Child with outfit"))
		assert.is_truthy(table.concat(rows, "\n"):match("Descendant outfit"))
	end)

	it("composes hiding empty categories with search and collapsed state", function()
		local empty = H.AddRoot(db, "Matching empty")
		db.cats[tier].collapsed = true

		assert.same({
			"0 cat:Tier",
			"1 outfit:Tier Chest",
			"1 cat:Sub",
			"2 outfit:Sub Robe",
		}, H.Rows(db, Tree.BuildEntries(db, byID, "tier", true)))
		assert.same({}, Tree.BuildEntries(db, byID, "matching empty", true))
		assert.is_not_nil(empty)
	end)

	it("stops at the depth guard rather than following a cycle", function()
		local cyclic = H.NewDB()
		local a = H.AddRoot(cyclic, "A")
		local b = H.AddChild(cyclic, a, "B")
		cyclic.cats[b].children = { a }

		-- One header per level, and no level past the guard.
		assert.equal(Tree.MAX_DEPTH, #Tree.BuildEntries(cyclic, byID, nil))
	end)
end)

describe("Tree.CategoryPath", function()
	local db, tier, sub

	before_each(function()
		db = H.NewDB()
		tier = H.AddRoot(db, "Tier")
		sub = H.AddChild(db, tier, "Sub")
	end)

	it("joins the ancestry with a separator", function()
		assert.equal("Tier", Tree.CategoryPath(db, tier))
		assert.equal("Tier > Sub", Tree.CategoryPath(db, sub))
	end)

	it("returns nothing for an unknown or missing category", function()
		assert.is_nil(Tree.CategoryPath(db, 999))
		assert.is_nil(Tree.CategoryPath(db, nil))
		assert.is_nil(Tree.CategoryPath({}, tier))
		assert.is_nil(Tree.CategoryPath(nil, tier))
	end)

	it("stops after 20 ancestors rather than looping on a cycle", function()
		db.cats[tier].parent = sub

		local path = Tree.CategoryPath(db, sub)
		local _, separators = path:gsub(" > ", "")
		assert.equal(19, separators)
	end)
end)
