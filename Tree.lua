local ADDON_NAME, ns = ...
-- Loaded two ways: by the client, where ... is (name, shared table), and by
-- require in the test runner, where ... is the module name and ns is nil.
if type(ns) ~= "table" then ns = {} end

-- Category tree over the per-character db. Callers pass the db table in; nothing
-- here reads MogtrotCharDB, touches a frame, or calls a C_ API.
--
--   db.cats[id] = { id, name, parent, children = {id...}, items = {outfitID...}, collapsed, protected }
--   db.roots    = { id... }              ordered top-level categories
--   db.assign   = { [outfitID] = catID }
local Tree = {}

Tree.UNSORTED_NAME = "Unsorted"
Tree.NEW_CATEGORY_NAME = "New category"

-- How far any walk of the tree will go. Nothing enforces that parent and children
-- agree, so a corrupt pair can point at each other; every recursive walk stops here
-- rather than hanging the client.
Tree.MAX_DEPTH = 20

function Tree.NewCategoryID(db)
	local id = db.nextID or 1
	db.nextID = id + 1
	return id
end

function Tree.CreateCategoryNode(db, name, parentID, protected)
	local id = Tree.NewCategoryID(db)
	db.cats[id] = {
		id = id,
		name = name,
		parent = parentID,
		children = {},
		items = {},
		collapsed = false,
		protected = protected or nil,
	}
	return id
end

function Tree.SiblingList(db, parentID)
	if parentID and db.cats[parentID] then
		return db.cats[parentID].children
	end
	return db.roots
end

function Tree.IndexInList(list, value)
	for i, v in ipairs(list) do
		if v == value then return i end
	end
end

function Tree.FindUnsortedID(db)
	for id, cat in pairs(db.cats) do
		if cat.protected then return id end
	end
	-- Should not happen, but never leave outfits homeless.
	local id = Tree.CreateCategoryNode(db, Tree.UNSORTED_NAME, nil, true)
	table.insert(db.roots, id)
	return id
end

function Tree.IsDescendantOf(db, catID, maybeAncestorID)
	local cursor = db.cats[catID]
	while cursor and cursor.parent do
		if cursor.parent == maybeAncestorID then return true end
		cursor = db.cats[cursor.parent]
	end
	return false
end

-- New categories go first among their siblings. Appended, a new category landed
-- below the fold on any list long enough to scroll and the button read as doing
-- nothing. Unsorted keeps its place, since inserting at the front cannot displace it.
-- Disambiguates an auto-generated name against every category, not just siblings:
-- the names that need it are usually nested inside each other, and a breadcrumb
-- reading "New category > New category > asdf" names nothing.
-- Only for generated names. Two categories the user deliberately named alike are
-- their business.
function Tree.UniqueName(db, base)
	local taken = {}
	for _, cat in pairs(db.cats or {}) do
		taken[cat.name] = true
	end
	if not taken[base] then return base end

	local n = 2
	while taken[base .. " " .. n] do n = n + 1 end
	return base .. " " .. n
end

function Tree.CreateCategory(db, name, parentID)
	local id = Tree.CreateCategoryNode(db, name or Tree.NEW_CATEGORY_NAME, parentID, false)

	if parentID then
		db.cats[parentID].collapsed = false
		table.insert(db.cats[parentID].children, 1, id)
	else
		table.insert(db.roots, 1, id)
	end

	return id
end

-- Returns ok, changed. An empty or whitespace-only name is ok but changes nothing.
function Tree.RenameCategory(db, catID, name)
	local cat = db.cats[catID]
	if not cat or cat.protected then return false, false end
	name = name and strtrim(name) or ""
	if name == "" then return true, false end
	cat.name = name
	return true, true
end

function Tree.DeleteCategory(db, catID)
	local cat = db.cats[catID]
	if not cat or cat.protected then return false end

	local parentID = cat.parent
	local siblings = Tree.SiblingList(db, parentID)
	local at = Tree.IndexInList(siblings, catID) or (#siblings + 1)

	-- Sub-categories are promoted into the parent, in place.
	for offset, childID in ipairs(cat.children) do
		db.cats[childID].parent = parentID
		table.insert(siblings, at + offset - 1, childID)
	end

	-- Contained outfits fall back to the parent, or to Unsorted at the top level.
	local destID = parentID or Tree.FindUnsortedID(db)
	for _, outfitID in ipairs(cat.items) do
		table.insert(db.cats[destID].items, outfitID)
		db.assign[outfitID] = destID
	end

	local removeAt = Tree.IndexInList(siblings, catID)
	if removeAt then table.remove(siblings, removeAt) end
	db.cats[catID] = nil

	return true
end

-- Returns ok, reason. Reason "cycle" is the only one worth showing the user.
function Tree.MoveCategory(db, catID, newParentID, index)
	local cat = db.cats[catID]
	if not cat then return false, "missing" end
	if cat.protected then return false, "protected" end
	-- A destination can be deleted while a window listing it is still open.
	if newParentID and not db.cats[newParentID] then return false, "missing" end
	if newParentID == catID or (newParentID and Tree.IsDescendantOf(db, newParentID, catID)) then
		return false, "cycle"
	end

	local fromList = Tree.SiblingList(db, cat.parent)
	local fromIndex = Tree.IndexInList(fromList, catID)
	local toList = Tree.SiblingList(db, newParentID)
	index = index or (#toList + 1)

	if fromIndex then
		table.remove(fromList, fromIndex)
		if fromList == toList and fromIndex < index then index = index - 1 end
	end

	-- Unsorted stays last among the roots.
	if not newParentID then
		local unsortedAt = Tree.IndexInList(db.roots, Tree.FindUnsortedID(db))
		if unsortedAt and index > unsortedAt then index = unsortedAt end
	end

	index = math.max(1, math.min(index, #toList + 1))
	table.insert(toList, index, catID)
	cat.parent = newParentID
	if newParentID then db.cats[newParentID].collapsed = false end

	return true
end

-- at + 2 down, at - 1 up: MoveCategory removes before it inserts, so a downward
-- step has to aim one past the neighbour to clear the hole it just made.
function Tree.MoveCategoryBySteps(db, catID, delta)
	local cat = db.cats[catID]
	if not cat then return false, "missing" end
	local siblings = Tree.SiblingList(db, cat.parent)
	local at = Tree.IndexInList(siblings, catID)
	if not at then return false, "missing" end
	return Tree.MoveCategory(db, catID, cat.parent, delta < 0 and (at - 1) or (at + 2))
end

function Tree.MoveOutfit(db, outfitID, toCatID, index)
	local target = db.cats[toCatID]
	if not target then return false end

	local fromCatID = db.assign[outfitID]
	local fromList = fromCatID and db.cats[fromCatID] and db.cats[fromCatID].items
	local fromIndex = fromList and Tree.IndexInList(fromList, outfitID)

	index = index or (#target.items + 1)
	if fromIndex then
		table.remove(fromList, fromIndex)
		if fromList == target.items and fromIndex < index then index = index - 1 end
	end

	index = math.max(1, math.min(index, #target.items + 1))
	table.insert(target.items, index, outfitID)
	db.assign[outfitID] = toCatID
	target.collapsed = false

	return true
end

function Tree.MoveOutfitBySteps(db, outfitID, delta)
	local catID = db.assign[outfitID]
	local cat = catID and db.cats[catID]
	if not cat then return false end
	local at = Tree.IndexInList(cat.items, outfitID)
	if not at then return false end
	return Tree.MoveOutfit(db, outfitID, catID, delta < 0 and (at - 1) or (at + 2))
end

function Tree.CountOutfits(db, catID, depth)
	depth = depth or 0
	local cat = db.cats[catID]
	if not cat or depth >= Tree.MAX_DEPTH then return 0 end
	local total = #cat.items
	for _, childID in ipairs(cat.children) do
		total = total + Tree.CountOutfits(db, childID, depth + 1)
	end
	return total
end

-- query is expected already trimmed and lowercased, and nil when there is none.
function Tree.NameMatches(name, query)
	return name ~= nil and string.find(strlower(name), query, 1, true) ~= nil
end

-- Depth-first flatten: header, then that category's own outfits, then sub-categories.
--
-- While a search is active a category survives if its own name matches, in which case
-- all of its contents come along so "tier" shows everything filed under Tier, or if
-- anything beneath it matches, in which case only the matching rows are kept as
-- context. Collapsed state is ignored during a search so hits are never hidden.
function Tree.BuildEntries(db, outfitsByID, query)
	outfitsByID = outfitsByID or {}

	local function BuildCategoryEntries(catID, depth, inheritedMatch)
		local cat = db.cats[catID]
		if not cat or depth >= Tree.MAX_DEPTH then return nil, false end

		local selfMatch = inheritedMatch or (not query) or Tree.NameMatches(cat.name, query)
		local contents, matchedBelow = {}, false

		for i, outfitID in ipairs(cat.items) do
			local info = outfitsByID[outfitID]
			if info and (selfMatch or Tree.NameMatches(info.name, query)) then
				-- indexInCat stays the true index in cat.items so drops land correctly
				-- even when the view is filtered.
				table.insert(contents, {
					kind = "outfit", outfitID = outfitID, info = info,
					catID = catID, indexInCat = i, depth = depth + 1,
				})
				matchedBelow = true
			end
		end

		for _, childID in ipairs(cat.children) do
			local childEntries, childMatched = BuildCategoryEntries(childID, depth + 1, selfMatch)
			if childEntries and childMatched then
				for _, entry in ipairs(childEntries) do
					table.insert(contents, entry)
				end
				matchedBelow = true
			end
		end

		if not (selfMatch or matchedBelow) then return nil, false end

		local entries = { { kind = "cat", catID = catID, depth = depth } }
		if query or not cat.collapsed then
			for _, entry in ipairs(contents) do
				table.insert(entries, entry)
			end
		end
		return entries, true
	end

	local allEntries = {}
	for _, rootID in ipairs(db.roots) do
		local entries, matched = BuildCategoryEntries(rootID, 0, false)
		if entries and matched then
			for _, entry in ipairs(entries) do
				table.insert(allEntries, entry)
			end
		end
	end
	return allEntries
end

-- Every category, in the order the list draws them, as choices for a picker. path
-- is the parent's breadcrumb, so a row names a category once and locates it once.
--
-- excludeID drops a category and everything under it, for moving a category:
-- re-parenting one into its own descendant would orphan the subtree.
-- skipID drops exactly one category and keeps its children, for moving an outfit:
-- the category it already sits in is a no-op destination, but the sub-categories
-- beneath that category are perfectly good ones.
function Tree.CategoryChoices(db, excludeID, skipID)
	local choices = {}
	if not db or not db.cats or not db.roots then return choices end

	local function AppendCategoryChoice(catID, depth)
		local cat = db.cats[catID]
		if not cat or depth >= Tree.MAX_DEPTH then return end
		if catID == excludeID then return end
		if excludeID and Tree.IsDescendantOf(db, catID, excludeID) then return end

		if catID == skipID then
			for _, childID in ipairs(cat.children) do
				AppendCategoryChoice(childID, depth + 1)
			end
			return
		end

		table.insert(choices, {
			catID = catID,
			name = cat.name,
			path = Tree.CategoryPath(db, cat.parent),
		})

		for _, childID in ipairs(cat.children) do
			AppendCategoryChoice(childID, depth + 1)
		end
	end

	for _, rootID in ipairs(db.roots) do AppendCategoryChoice(rootID, 0) end
	return choices
end

-- Every outfit the server still reports, in the order the list draws them. path is
-- the breadcrumb of the category holding it, which is what makes two outfits with
-- the same name tellable apart.
function Tree.OutfitChoices(db, outfitsByID, excludeOutfitID)
	local choices = {}
	if not db or not db.cats or not db.roots then return choices end
	outfitsByID = outfitsByID or {}

	local function AppendOutfitChoices(catID, depth)
		local cat = db.cats[catID]
		if not cat or depth >= Tree.MAX_DEPTH then return end

		local path = Tree.CategoryPath(db, catID)
		for _, outfitID in ipairs(cat.items) do
			local info = outfitsByID[outfitID]
			if info and outfitID ~= excludeOutfitID then
				table.insert(choices, {
					outfitID = outfitID,
					name = info.name or tostring(outfitID),
					path = path,
				})
			end
		end

		for _, childID in ipairs(cat.children) do
			AppendOutfitChoices(childID, depth + 1)
		end
	end

	for _, rootID in ipairs(db.roots) do AppendOutfitChoices(rootID, 0) end
	return choices
end

-- Breadcrumb for the outfit tooltip. The guard bounds a parent chain that loops.
function Tree.CategoryPath(db, catID)
	if not db or not db.cats then return end

	local parts, cursor, guard = {}, db.cats[catID], 0
	while cursor and guard < Tree.MAX_DEPTH do
		table.insert(parts, 1, cursor.name)
		cursor = cursor.parent and db.cats[cursor.parent] or nil
		guard = guard + 1
	end

	if #parts == 0 then return end
	return table.concat(parts, " > ")
end

ns.Tree = Tree
return Tree
