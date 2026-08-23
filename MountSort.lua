local ADDON_NAME, ns = ...
-- Loaded two ways: by the client, where ... is (name, shared table), and by
-- require in the test runner, where ... is the module name and ns is nil.
if type(ns) ~= "table" then ns = {} end

-- Orders mount cards by their relationship to the outfit being edited.
local MountSort = {}

local KEYS = {
	"Chosen",
	"Pairings",
	"Pinned",
}

local function Rank(mount, ctx, key)
	if key == "Chosen" then
		return ctx.chosen[mount.mountID] and 1 or 0
	elseif key == "Pairings" then
		return mount.pairings or 0
	elseif key == "Pinned" then
		return mount.isPinned and 1 or 0
	end
	return 0
end

-- A total order. table.sort is not stable, so without a unique final key the
-- grid would reshuffle between refreshes while the user is clicking cards in it.
function MountSort.Compare(a, b, ctx)
	for _, key in ipairs(KEYS) do
		local ra, rb = Rank(a, ctx, key), Rank(b, ctx, key)
		if ra ~= rb then return ra > rb end
	end

	local na, nb = strlower(a.name or ""), strlower(b.name or "")
	if na ~= nb then return na < nb end
	return (a.mountID or 0) < (b.mountID or 0)
end

-- Sorts in place and returns the list. Callers snapshot once per window open, so
-- that clicking a card never moves it.
function MountSort.Apply(mounts, ctx)
	ctx = ctx or {}
	ctx.chosen = ctx.chosen or {}

	table.sort(mounts, function(a, b) return MountSort.Compare(a, b, ctx) end)
	return mounts
end

ns.MountSort = MountSort
return MountSort
