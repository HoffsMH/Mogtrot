local Tree = require("Tree")
local H = require("spec.helpers")

describe("Tree lookups", function()
	local db, tier, sub, unsorted

	before_each(function()
		db = H.NewDB()
		tier = H.AddRoot(db, "Tier")
		sub = H.AddChild(db, tier, "Sub")
		unsorted = H.AddRoot(db, "Unsorted", true)
	end)

	it("returns the root list for a nil or unknown parent", function()
		assert.equal(db.roots, Tree.SiblingList(db, nil))
		assert.equal(db.roots, Tree.SiblingList(db, 999))
	end)

	it("returns the child list for a known parent", function()
		assert.equal(db.cats[tier].children, Tree.SiblingList(db, tier))
	end)

	it("finds a value's index, or nothing", function()
		assert.equal(2, Tree.IndexInList({ "a", "b", "c" }, "b"))
		assert.is_nil(Tree.IndexInList({ "a" }, "z"))
	end)

	it("walks parents to answer IsDescendantOf", function()
		local deep = H.AddChild(db, sub, "Deep")
		assert.is_true(Tree.IsDescendantOf(db, sub, tier))
		assert.is_true(Tree.IsDescendantOf(db, deep, tier))
		assert.is_false(Tree.IsDescendantOf(db, tier, sub))
	end)

	it("does not call a category its own descendant", function()
		assert.is_false(Tree.IsDescendantOf(db, tier, tier))
	end)

	it("finds the protected category", function()
		assert.equal(unsorted, Tree.FindUnsortedID(db))
	end)

	it("creates Unsorted rather than leaving outfits homeless", function()
		db.cats[unsorted] = nil
		table.remove(db.roots, Tree.IndexInList(db.roots, unsorted))

		local made = Tree.FindUnsortedID(db)
		assert.equal("Unsorted", db.cats[made].name)
		assert.is_true(db.cats[made].protected)
		assert.equal(made, db.roots[#db.roots])
	end)

	it("counts outfits in a category and everything under it", function()
		H.AddOutfit(db, tier, 10)
		H.AddOutfit(db, sub, 20)
		H.AddOutfit(db, sub, 21)
		assert.equal(3, Tree.CountOutfits(db, tier))
		assert.equal(2, Tree.CountOutfits(db, sub))
		assert.equal(0, Tree.CountOutfits(db, 999))
	end)

	it("stops counting at the depth guard rather than following a cycle", function()
		db.cats[sub].children = { tier }
		H.AddOutfit(db, tier, 10)

		-- Tier carries the one outfit and sits at every even depth up to the guard.
		assert.equal(Tree.MAX_DEPTH / 2, Tree.CountOutfits(db, tier))
	end)
end)

describe("Tree.CreateCategory", function()
	local db, unsorted

	before_each(function()
		db = H.NewDB()
		H.AddRoot(db, "Tier")
		unsorted = H.AddRoot(db, "Unsorted", true)
	end)

	it("puts a new root first, leaving Unsorted last", function()
		local id = Tree.CreateCategory(db, "Fresh", nil)
		assert.same({ "Fresh", "Tier", "Unsorted" }, H.NamesOf(db, db.roots))
		assert.equal(id, db.roots[1])
		assert.equal(unsorted, db.roots[#db.roots])
	end)

	it("puts a new sub-category first and opens its parent", function()
		local parent = db.roots[2]
		H.AddChild(db, parent, "Old")
		db.cats[parent].collapsed = true

		local id = Tree.CreateCategory(db, "Fresh", parent)
		assert.same({ "Fresh", "Old" }, H.NamesOf(db, db.cats[parent].children))
		assert.equal(id, db.cats[parent].children[1])
		assert.is_false(db.cats[parent].collapsed)
	end)

	it("falls back to the placeholder name", function()
		local id = Tree.CreateCategory(db, nil, nil)
		assert.equal("New category", db.cats[id].name)
	end)

	it("stores a readable color on a new category", function()
		local id = Tree.CreateCategory(db, "Fresh", nil, function() return 0.5 end)
		local color = db.cats[id].color
		assert.is_table(color)
		assert.is_true(color.r >= 0 and color.r <= 1)
		assert.is_true(color.g >= 0 and color.g <= 1)
		assert.is_true(color.b >= 0 and color.b <= 1)
	end)
end)

describe("Tree.RenameCategory", function()
	local db, tier, unsorted

	before_each(function()
		db = H.NewDB()
		tier = H.AddRoot(db, "Tier")
		unsorted = H.AddRoot(db, "Unsorted", true)
	end)

	it("renames and reports the change", function()
		local ok, changed = Tree.RenameCategory(db, tier, "  Raids  ")
		assert.is_true(ok)
		assert.is_true(changed)
		assert.equal("Raids", db.cats[tier].name)
	end)

	it("refuses a protected or missing category", function()
		assert.is_false(Tree.RenameCategory(db, unsorted, "Mine"))
		assert.is_false(Tree.RenameCategory(db, 999, "Mine"))
		assert.equal("Unsorted", db.cats[unsorted].name)
	end)

	it("accepts a blank name without applying it", function()
		local ok, changed = Tree.RenameCategory(db, tier, "   ")
		assert.is_true(ok)
		assert.is_false(changed)
		assert.equal("Tier", db.cats[tier].name)
	end)
end)

describe("Tree.SetCategoryColor", function()
	it("stores a valid color", function()
		local db = H.NewDB()
		local id = H.AddRoot(db, "Tier")
		assert.is_true(Tree.SetCategoryColor(db, id, 0.1, 0.2, 0.3))
		assert.same({ r = 0.1, g = 0.2, b = 0.3 }, db.cats[id].color)
	end)

	it("refuses malformed colors and missing categories", function()
		local db = H.NewDB()
		local id = H.AddRoot(db, "Tier")
		assert.is_false(Tree.SetCategoryColor(db, id, -1, 0.2, 0.3))
		assert.is_false(Tree.SetCategoryColor(db, 999, 0.1, 0.2, 0.3))
	end)
end)

describe("Tree.DeleteCategory", function()
	local db, a, unsorted

	before_each(function()
		db = H.NewDB()
		a = H.AddRoot(db, "A")
		H.AddRoot(db, "B")
		unsorted = H.AddRoot(db, "Unsorted", true)
	end)

	it("refuses a protected or missing category", function()
		assert.is_false(Tree.DeleteCategory(db, unsorted))
		assert.is_false(Tree.DeleteCategory(db, 999))
		assert.is_not_nil(db.cats[unsorted])
	end)

	it("promotes children into the hole it leaves", function()
		H.AddChild(db, a, "A1")
		H.AddChild(db, a, "A2")

		assert.is_true(Tree.DeleteCategory(db, a))
		assert.same({ "A1", "A2", "B", "Unsorted" }, H.NamesOf(db, db.roots))
		assert.is_nil(db.cats[a])
	end)

	it("re-parents promoted children", function()
		local nested = H.AddChild(db, a, "A1")
		local grand = H.AddChild(db, nested, "A1a")

		Tree.DeleteCategory(db, nested)
		assert.equal(a, db.cats[grand].parent)
		assert.same({ "A1a" }, H.NamesOf(db, db.cats[a].children))
	end)

	it("drops a root category's outfits into Unsorted", function()
		H.AddOutfit(db, a, 10)
		H.AddOutfit(db, a, 11)

		Tree.DeleteCategory(db, a)
		assert.same({ 10, 11 }, db.cats[unsorted].items)
		assert.equal(unsorted, db.assign[10])
		assert.equal(unsorted, db.assign[11])
	end)

	it("drops a sub-category's outfits into its parent", function()
		local nested = H.AddChild(db, a, "A1")
		H.AddOutfit(db, a, 10)
		H.AddOutfit(db, nested, 20)

		Tree.DeleteCategory(db, nested)
		assert.same({ 10, 20 }, db.cats[a].items)
		assert.equal(a, db.assign[20])
	end)
end)

describe("Tree.MoveCategory", function()
	local db, a, b, c, unsorted

	before_each(function()
		db = H.NewDB()
		a = H.AddRoot(db, "A")
		b = H.AddRoot(db, "B")
		c = H.AddRoot(db, "C")
		unsorted = H.AddRoot(db, "Unsorted", true)
	end)

	it("refuses to move a category into itself", function()
		local ok, reason = Tree.MoveCategory(db, a, a)
		assert.is_false(ok)
		assert.equal("cycle", reason)
		assert.same({ "A", "B", "C", "Unsorted" }, H.NamesOf(db, db.roots))
	end)

	it("refuses to move a category into its own descendant", function()
		local child = H.AddChild(db, a, "A1")
		local grand = H.AddChild(db, child, "A1a")

		local ok, reason = Tree.MoveCategory(db, a, grand)
		assert.is_false(ok)
		assert.equal("cycle", reason)
		assert.equal(nil, db.cats[a].parent)
	end)

	it("refuses a protected or missing category", function()
		assert.equal("protected", select(2, Tree.MoveCategory(db, unsorted, a)))
		assert.equal("missing", select(2, Tree.MoveCategory(db, 999, a)))
	end)

	it("refuses a parent that is no longer there", function()
		-- A picker left open outlives the category it was listing.
		assert.equal("missing", select(2, Tree.MoveCategory(db, a, 999)))
		assert.same({ "A", "B", "C", "Unsorted" }, H.NamesOf(db, db.roots))
	end)

	it("compensates for its own removal when reordering in place", function()
		-- Index 3 in the original list, which is index 2 once A is lifted out.
		assert.is_true(Tree.MoveCategory(db, a, nil, 3))
		assert.same({ "B", "A", "C", "Unsorted" }, H.NamesOf(db, db.roots))
	end)

	it("does not compensate when moving up", function()
		assert.is_true(Tree.MoveCategory(db, c, nil, 1))
		assert.same({ "C", "A", "B", "Unsorted" }, H.NamesOf(db, db.roots))
	end)

	it("keeps Unsorted last however far the drop overshoots", function()
		assert.is_true(Tree.MoveCategory(db, a, nil, 99))
		assert.same({ "B", "C", "A", "Unsorted" }, H.NamesOf(db, db.roots))
	end)

	it("appends when given no index", function()
		local child = H.AddChild(db, b, "B1")
		assert.is_true(Tree.MoveCategory(db, a, b))
		assert.same({ "B1", "A" }, H.NamesOf(db, db.cats[b].children))
		assert.equal(b, db.cats[a].parent)
		assert.equal(child, db.cats[b].children[1])
	end)

	it("opens the category it is dropped into", function()
		db.cats[b].collapsed = true
		Tree.MoveCategory(db, a, b)
		assert.is_false(db.cats[b].collapsed)
		assert.same({ "B", "C", "Unsorted" }, H.NamesOf(db, db.roots))
	end)
end)

describe("Tree.MoveCategoryBySteps", function()
	local db

	before_each(function()
		db = H.NewDB()
		H.AddRoot(db, "A")
		H.AddRoot(db, "B")
		H.AddRoot(db, "C")
		H.AddRoot(db, "Unsorted", true)
	end)

	it("moves one place down", function()
		Tree.MoveCategoryBySteps(db, db.roots[1], 1)
		assert.same({ "B", "A", "C", "Unsorted" }, H.NamesOf(db, db.roots))
	end)

	it("moves one place up", function()
		Tree.MoveCategoryBySteps(db, db.roots[3], -1)
		assert.same({ "A", "C", "B", "Unsorted" }, H.NamesOf(db, db.roots))
	end)

	it("does nothing useful at the top", function()
		Tree.MoveCategoryBySteps(db, db.roots[1], -1)
		assert.same({ "A", "B", "C", "Unsorted" }, H.NamesOf(db, db.roots))
	end)

	it("refuses a missing category", function()
		assert.is_false(Tree.MoveCategoryBySteps(db, 999, 1))
	end)
end)

describe("Tree.MoveOutfit", function()
	local db, tier, casual

	before_each(function()
		db = H.NewDB()
		tier = H.AddRoot(db, "Tier")
		casual = H.AddRoot(db, "Casual")
		H.AddOutfit(db, tier, 10)
		H.AddOutfit(db, tier, 20)
		H.AddOutfit(db, tier, 30)
	end)

	it("compensates for its own removal when reordering in place", function()
		assert.is_true(Tree.MoveOutfit(db, 10, tier, 3))
		assert.same({ 20, 10, 30 }, db.cats[tier].items)
	end)

	it("does not compensate when moving up", function()
		assert.is_true(Tree.MoveOutfit(db, 30, tier, 1))
		assert.same({ 30, 10, 20 }, db.cats[tier].items)
	end)

	it("moves between categories and repoints the assignment", function()
		assert.is_true(Tree.MoveOutfit(db, 20, casual))
		assert.same({ 10, 30 }, db.cats[tier].items)
		assert.same({ 20 }, db.cats[casual].items)
		assert.equal(casual, db.assign[20])
	end)

	it("clamps an index past the end", function()
		Tree.MoveOutfit(db, 10, casual, 99)
		assert.same({ 10 }, db.cats[casual].items)
	end)

	it("opens the category it lands in", function()
		db.cats[casual].collapsed = true
		Tree.MoveOutfit(db, 10, casual)
		assert.is_false(db.cats[casual].collapsed)
	end)

	it("files an outfit that had no category", function()
		assert.is_true(Tree.MoveOutfit(db, 77, casual))
		assert.same({ 77 }, db.cats[casual].items)
		assert.equal(casual, db.assign[77])
	end)

	it("refuses an unknown target", function()
		assert.is_false(Tree.MoveOutfit(db, 10, 999))
		assert.same({ 10, 20, 30 }, db.cats[tier].items)
	end)
end)

describe("Tree.MoveOutfitBySteps", function()
	local db, tier

	before_each(function()
		db = H.NewDB()
		tier = H.AddRoot(db, "Tier")
		H.AddOutfit(db, tier, 10)
		H.AddOutfit(db, tier, 20)
		H.AddOutfit(db, tier, 30)
	end)

	it("moves one place down", function()
		Tree.MoveOutfitBySteps(db, 10, 1)
		assert.same({ 20, 10, 30 }, db.cats[tier].items)
	end)

	it("moves one place up", function()
		Tree.MoveOutfitBySteps(db, 30, -1)
		assert.same({ 10, 30, 20 }, db.cats[tier].items)
	end)

	it("refuses an unfiled outfit", function()
		assert.is_false(Tree.MoveOutfitBySteps(db, 77, 1))
	end)

	it("refuses an outfit assigned to a category that does not list it", function()
		db.assign[77] = tier
		assert.is_false(Tree.MoveOutfitBySteps(db, 77, 1))
		assert.same({ 10, 20, 30 }, db.cats[tier].items)
	end)
end)

describe("Tree.UniqueName", function()
  local Tree = require("Tree")

  local function db(...)
    local cats = {}
    for i, name in ipairs({...}) do cats[i] = { id = i, name = name } end
    return { cats = cats }
  end

  it("leaves an unused name alone", function()
    assert.equal("New category", Tree.UniqueName(db("Tier"), "New category"))
  end)

  it("numbers from 2 when the base is taken", function()
    assert.equal("New category 2", Tree.UniqueName(db("New category"), "New category"))
  end)

  it("skips numbers already in use", function()
    local d = db("New category", "New category 2", "New category 3")
    assert.equal("New category 4", Tree.UniqueName(d, "New category"))
  end)

  it("matches across the whole tree, not just siblings", function()
    -- The nested case is the one that produced an unreadable breadcrumb.
    local d = db("New category")
    d.cats[1].parent = nil
    assert.equal("New category 2", Tree.UniqueName(d, "New category"))
  end)

  it("copes with an empty db", function()
    assert.equal("New category", Tree.UniqueName({}, "New category"))
  end)
end)

describe("Tree.CategoryChoices", function()
	local db, tier, sub, deep, unsorted

	before_each(function()
		db = H.NewDB()
		tier = H.AddRoot(db, "Tier")
		sub = H.AddChild(db, tier, "Sub")
		deep = H.AddChild(db, sub, "Deep")
		H.AddRoot(db, "Sets")
		unsorted = H.AddRoot(db, "Unsorted", true)
	end)

	local function NamesOf(choices)
		local out = {}
		for _, choice in ipairs(choices) do table.insert(out, choice.name) end
		return out
	end

	it("lists every category depth-first, in list order", function()
		assert.same({ "Tier", "Sub", "Deep", "Sets", "Unsorted" },
			NamesOf(Tree.CategoryChoices(db)))
	end)

	it("gives the parent breadcrumb, and none for a root", function()
		local byName = {}
		for _, choice in ipairs(Tree.CategoryChoices(db)) do byName[choice.name] = choice end

		assert.is_nil(byName["Tier"].path)
		assert.equal("Tier", byName["Sub"].path)
		assert.equal("Tier > Sub", byName["Deep"].path)
		assert.equal(deep, byName["Deep"].catID)
	end)

	it("drops the excluded category and everything under it", function()
		assert.same({ "Tier", "Sets", "Unsorted" }, NamesOf(Tree.CategoryChoices(db, sub)))
	end)

	it("drops a descendant reachable while its parent chain says otherwise", function()
		-- Children and parent disagreeing is corrupt, but the chain is what
		-- re-parenting follows, so the chain is what decides.
		table.insert(db.roots, 1, deep)
		assert.same({ "Tier", "Sets", "Unsorted" }, NamesOf(Tree.CategoryChoices(db, sub)))
	end)

	it("keeps Unsorted, which is a legal destination", function()
		local choices = Tree.CategoryChoices(db, tier)
		assert.same({ "Sets", "Unsorted" }, NamesOf(choices))
		assert.equal(unsorted, choices[2].catID)
	end)

	it("ignores an exclusion that is not there", function()
		assert.equal(5, #Tree.CategoryChoices(db, 999))
	end)

	it("stops at the depth guard rather than following a cycle", function()
		db.cats[deep].children = { tier }
		assert.equal(Tree.MAX_DEPTH + 2, #Tree.CategoryChoices(db))
	end)
end)

describe("Tree.OutfitChoices", function()
	local db, tier, sub, byID

	before_each(function()
		db = H.NewDB()
		tier = H.AddRoot(db, "Tier")
		sub = H.AddChild(db, tier, "Sub")
		H.AddRoot(db, "Unsorted", true)

		H.AddOutfit(db, tier, 10)
		H.AddOutfit(db, sub, 20)
		H.AddOutfit(db, tier, 11)
		byID = H.OutfitsByID({ [10] = "Mage", [11] = "Rogue", [20] = "Priest" })
	end)

	local function NamesOf(choices)
		local out = {}
		for _, choice in ipairs(choices) do table.insert(out, choice.name) end
		return out
	end

	it("lists outfits in list order, own items before sub-categories", function()
		assert.same({ "Mage", "Rogue", "Priest" }, NamesOf(Tree.OutfitChoices(db, byID)))
	end)

	it("gives the breadcrumb of the category holding the outfit", function()
		local choices = Tree.OutfitChoices(db, byID)
		assert.equal("Tier", choices[1].path)
		assert.equal("Tier > Sub", choices[3].path)
		assert.equal(20, choices[3].outfitID)
	end)

	it("skips the excluded outfit", function()
		assert.same({ "Mage", "Priest" }, NamesOf(Tree.OutfitChoices(db, byID, 11)))
	end)

	it("skips an outfit the server no longer reports", function()
		byID[10] = nil
		assert.same({ "Rogue", "Priest" }, NamesOf(Tree.OutfitChoices(db, byID)))
	end)
end)

describe("Tree.CategoryChoices skipID", function()
  local Tree = require("Tree")

  -- Parent > Child, plus a sibling. Moving an outfit out of Parent should still
  -- offer Child, because a sub-category of where you are is a real destination.
  local function db()
    return {
      roots = { 1, 3 },
      cats = {
        [1] = { id = 1, name = "Parent", children = { 2 }, items = {} },
        [2] = { id = 2, name = "Child", parent = 1, children = {}, items = {} },
        [3] = { id = 3, name = "Other", children = {}, items = {} },
      },
    }
  end

  local function names(list)
    local out = {}
    for _, c in ipairs(list) do table.insert(out, c.name) end
    table.sort(out)
    return out
  end

  it("offers everything when nothing is skipped", function()
    assert.same({ "Child", "Other", "Parent" }, names(Tree.CategoryChoices(db())))
  end)

  it("drops the skipped category but keeps its children", function()
    assert.same({ "Child", "Other" }, names(Tree.CategoryChoices(db(), nil, 1)))
  end)

  it("excludeID still drops the whole subtree", function()
    assert.same({ "Other" }, names(Tree.CategoryChoices(db(), 1)))
  end)
end)
