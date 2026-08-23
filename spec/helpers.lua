require("spec.wow_stubs")
local Tree = require("Tree")

-- Fixture builders. These append, where Tree.CreateCategory prepends, because a
-- test that asserts ordering wants to state the order it started from.
local H = {}

function H.NewDB()
	return {
		version = 3,
		nextID = 1,
		cats = {},
		roots = {},
		assign = {},
		looks = {},
		mounts = {},
		titles = {},
		titleRotation = {},
	}
end

function H.AddRoot(db, name, protected)
	local id = Tree.CreateCategoryNode(db, name, nil, protected)
	table.insert(db.roots, id)
	return id
end

function H.AddChild(db, parentID, name)
	local id = Tree.CreateCategoryNode(db, name, parentID, false)
	table.insert(db.cats[parentID].children, id)
	return id
end

function H.AddOutfit(db, catID, outfitID)
	table.insert(db.cats[catID].items, outfitID)
	db.assign[outfitID] = catID
	return outfitID
end

-- { [outfitID] = name } into the shape BuildEntries expects from Core.
function H.OutfitsByID(names)
	local byID = {}
	for outfitID, name in pairs(names) do
		byID[outfitID] = { outfitID = outfitID, name = name }
	end
	return byID
end

function H.NamesOf(db, list)
	local out = {}
	for _, id in ipairs(list) do
		table.insert(out, db.cats[id].name)
	end
	return out
end

-- BuildEntries output as "<depth> kind:name", so an assertion reads like the list.
function H.Rows(db, entries)
	local out = {}
	for _, entry in ipairs(entries) do
		if entry.kind == "cat" then
			table.insert(out, ("%d cat:%s"):format(entry.depth, db.cats[entry.catID].name))
		else
			table.insert(out, ("%d outfit:%s"):format(entry.depth, entry.info.name))
		end
	end
	return out
end

return H
