local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Pure multi-link operations over a caller-owned domain:
-- store[outfitID] = { [linkedID] = true }.
-- IDs are numbers or exact strings, never mixed within one linked set and
-- never coerced. Nothing here touches WoW state; the caller owns Changed().

local OutfitLinks = {}

local function CopySet(set)
	local copy = {}
	for id in pairs(set or {}) do copy[id] = true end
	return copy
end

function OutfitLinks.Get(store, outfitID)
	return store[outfitID] or {}
end

function OutfitLinks.Count(store, outfitID)
	local n = 0
	for _ in pairs(store[outfitID] or {}) do n = n + 1 end
	return n
end

function OutfitLinks.Toggle(store, outfitID, linkedID)
	local links = store[outfitID] or {}
	local adding = not links[linkedID]
	if adding then
		links[linkedID] = true
	else
		links[linkedID] = nil
	end
	store[outfitID] = next(links) and links or nil
	return adding
end

function OutfitLinks.Replace(store, outfitID, set)
	local links = CopySet(set)
	store[outfitID] = next(links) and links or nil
end

-- Returns added, had, total so the caller keeps its copy messages.
function OutfitLinks.Copy(store, fromOutfitID, toOutfitID, merge)
	local source = store[fromOutfitID]
	if not source or not next(source) then return 0, 0, 0 end

	local had = OutfitLinks.Count(store, toOutfitID)
	local prior = CopySet(store[toOutfitID])

	local result = merge and prior or {}
	local added = 0
	for linkedID in pairs(source) do
		if not prior[linkedID] then added = added + 1 end
		result[linkedID] = true
	end

	store[toOutfitID] = result
	return added, had, OutfitLinks.Count(store, toOutfitID)
end

-- want: { [outfitID] = true } for outfits that should carry linkedID.
-- Returns added, removed.
function OutfitLinks.Apply(store, linkedID, want)
	local added, removed = 0, 0
	for outfitID, selected in pairs(want or {}) do
		local links = store[outfitID]
		local has = links and links[linkedID]
		if selected and not has then
			links = links or {}
			links[linkedID] = true
			store[outfitID] = links
			added = added + 1
		elseif has and not selected then
			links[linkedID] = nil
			store[outfitID] = next(links) and links or nil
			removed = removed + 1
		end
	end
	return added, removed
end

-- Numeric outfit IDs sort numerically, string IDs directly; a linked set
-- within one domain never mixes the two, so no cross-type comparison happens.
local function LessOutfitID(a, b)
	if type(a) == "number" and type(b) == "number" then return a < b end
	return tostring(a) < tostring(b)
end

-- The one link that stands for the whole set, plus how many there are.
-- Lowest id wins: it is stable as links come and go, which a row's icon and a
-- macro's icon both need, and it is the rule the outfit list already used
-- inline before anything else wanted the same answer.
function OutfitLinks.Representative(store, outfitID)
	local best, count = nil, 0
	for linkedID in pairs((store or {})[outfitID] or {}) do
		count = count + 1
		if best == nil or LessOutfitID(linkedID, best) then best = linkedID end
	end
	return best, count
end

function OutfitLinks.IndexByLinked(store)
	local index = {}
	for outfitID, links in pairs(store or {}) do
		for linkedID in pairs(links) do
			local outfits = index[linkedID]
			if not outfits then
				outfits = {}
				index[linkedID] = outfits
			end
			outfits[#outfits + 1] = outfitID
		end
	end
	for _, outfits in pairs(index) do
		table.sort(outfits, LessOutfitID)
	end
	return index
end

-- Deletes store keys only for outfits absent from the alive set.
function OutfitLinks.Clean(store, alive)
	for outfitID in pairs(store) do
		if not alive[outfitID] then store[outfitID] = nil end
	end
end

ns.OutfitLinks = OutfitLinks
return OutfitLinks
