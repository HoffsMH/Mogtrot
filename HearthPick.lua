local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local Rotation = ns.Rotation or require("Rotation")

-- Which hearthstone the key serves, and which rung of the ladder answered it.
-- Pure: every action-time read arrives as the injected isEligible predicate,
-- and the rotation state and randomness source belong to the caller.
--
-- request = {
--     candidates,  -- { [itemID] = true } the linked and pinned union for the
--                  -- active outfit, unfiltered; the top rung
--     registry,    -- curated definitions (entries: itemID -> entry)
--     isEligible,  -- function(itemID) -> ready, blocked. blocked names what
--                  -- stopped an unready ID: "unowned", "unusable" or
--                  -- "cooldown"
--     state,       -- caller-owned Rotation state for this rotation key
--     random,      -- function(n) -> 1..n
-- }
--
-- A link or a pin is a preference, not a restriction. Nothing linked, nothing
-- pinned, everything pinned on cooldown: all three mean the pins have no
-- opinion, so the rung below offers everything owned and ready instead.
-- Refusing there would leave somebody standing still next to a hearthstone
-- they own. Only a character with nothing owned, usable and ready at all
-- gets a refusal.
local HearthPick = {}

-- The ready IDs in canonical numeric order, plus what stopped the rest: the
-- first blocked ID's reason, and whether the player owns any of them at all.
-- Ownership is what separates "you have none of these" from "yours are not
-- ready", which are different things to be told.
function HearthPick.Ready(ids, isEligible)
	table.sort(ids)

	local pool, blocked, owned = {}, nil, false
	for _, itemID in ipairs(ids) do
		local ready, reason = isEligible(itemID)
		if ready then
			pool[#pool + 1] = itemID
			owned = true
		elseif reason and reason ~= "unowned" then
			owned = true
			if blocked == nil then blocked = reason end
		end
	end
	return pool, blocked, owned
end

local function IDsOf(set)
	local ids = {}
	for itemID in pairs(set or {}) do ids[#ids + 1] = itemID end
	return ids
end

local function RegistryIDs(registry)
	local entries = registry and registry.entries
	return IDsOf(entries)
end

-- Rotation.Choose over a sorted pool is the deterministic pick both rungs
-- share, and an empty pool leaves the rotation state untouched.
local function Serve(request, ids)
	local pool, blocked, owned = HearthPick.Ready(ids, request.isEligible)
	return Rotation.Choose(request.state, pool, request.random), blocked, owned
end

function HearthPick.Plan(request)
	local itemID = Serve(request, IDsOf(request.candidates))
	if itemID then
		return { action = "use", itemID = itemID, from = "linked" }
	end

	local blocked, owned
	itemID, blocked, owned = Serve(request, RegistryIDs(request.registry))
	if itemID then
		return { action = "use", itemID = itemID, from = "collection",
			cause = "nolinked" }
	end
	if not owned then
		return { action = "refuse", reason = "nocollection" }
	end
	return { action = "refuse", reason = "collectionunusable", detail = blocked }
end

-- Which rung answered, as the tail of a sentence about what just happened.
local function Did(plan)
	if plan.from == "collection" then return "one you own" end
	return "a linked or pinned one"
end

-- What to say about a plan: a statement for a rung the player did not ask
-- for, a reason for a refusal, and nothing at all when the linked or pinned
-- hearthstone they meant is the one being used.
function HearthPick.Text(plan)
	if plan.action ~= "refuse" then
		if not plan.cause then return nil end
		return ("no usable linked or pinned hearthstone right now, so this is %s.")
			:format(Did(plan))
	end
	if plan.reason == "nocollection" then
		return "no hearthstone on this character to fall back on yet."
	end
	if plan.detail == "cooldown" then
		return "every hearthstone you own is still on cooldown."
	end
	return "no hearthstone you own can be used here."
end

ns.HearthPick = HearthPick
return HearthPick
