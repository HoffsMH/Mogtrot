local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local Rotation = ns.Rotation or require("Rotation")

-- Which hearthstone the key serves, and which rung of the ladder answered it.
-- Pure: every action-time read arrives as the injected isEligible predicate,
-- and the rotation state and randomness source belong to the caller.
--
-- request = {
--     candidates,  -- { [itemID] = true } the linked and pinned union for the
--                  -- active outfit, unfiltered; the top rung in pinned mode
--     linked,      -- { [itemID] = true } the links alone; the top rung
--                  -- otherwise
--     mode,        -- the "If no hearthstone is linked" setting; see Mode
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
-- opinion, so the rungs below offer what is owned and ready instead.
-- Refusing there would leave somebody standing still next to a hearthstone
-- they own. Only a character with nothing owned, usable and ready at all
-- gets a refusal, or one whose fallback setting is off.
--
-- The toys are their own rung above the rest of the registry. The hearthstone
-- in your bags is a thing a player can throw away and rely on toys instead,
-- so serving it by default serves the one item they chose not to keep.
local HearthPick = {}

-- What the key does when no link answers. "pinned" reaches for pins and, like
-- the summon fallback's pinned mode, carries on to a random owned one when
-- none is ready. "random" skips pins. "off" refuses.
HearthPick.MODES = { pinned = true, random = true, off = true }
HearthPick.DEFAULT_MODE = "pinned"

function HearthPick.Mode(value)
	if value and HearthPick.MODES[value] then return value end
	return HearthPick.DEFAULT_MODE
end

function HearthPick.UsesPins(mode)
	return HearthPick.Mode(mode) == "pinned"
end

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

-- The registry IDs of one kind, or all of them when kind is nil.
local function RegistryIDs(registry, kind)
	local ids = {}
	for itemID, entry in pairs(registry and registry.entries or {}) do
		if kind == nil or entry.kind == kind then ids[#ids + 1] = itemID end
	end
	return ids
end

-- Rotation.Choose over a sorted pool is the deterministic pick every rung
-- shares, and an empty pool leaves the rotation state untouched. A rung that
-- finds anything always serves it, so at most one call per plan touches the
-- rotation state.
local function Serve(request, ids)
	local pool, blocked, owned = HearthPick.Ready(ids, request.isEligible)
	return Rotation.Choose(request.state, pool, request.random), blocked, owned
end

function HearthPick.Plan(request)
	local mode = HearthPick.Mode(request.mode)
	local pins = HearthPick.UsesPins(mode)
	local top = pins and request.candidates or request.linked
	local itemID, topBlocked = Serve(request, IDsOf(top))
	if itemID then
		return { action = "use", itemID = itemID, from = "linked" }
	end
	if mode == "off" then
		return { action = "refuse", reason = "nolinked", detail = topBlocked }
	end

	-- pins = false marks a plan whose top rung left the pins out.
	local skipped
	if not pins then skipped = false end
	itemID = Serve(request, RegistryIDs(request.registry, "toy"))
	if itemID then
		return { action = "use", itemID = itemID, from = "toy",
			cause = "nolinked", pins = skipped }
	end

	local blocked, owned
	itemID, blocked, owned = Serve(request, RegistryIDs(request.registry))
	if itemID then
		return { action = "use", itemID = itemID, from = "collection",
			cause = "nolinked", pins = skipped }
	end
	if not owned then
		return { action = "refuse", reason = "nocollection" }
	end
	return { action = "refuse", reason = "collectionunusable", detail = blocked }
end

-- Which rung answered, as the tail of a sentence about what just happened.
local function Did(plan)
	if plan.from == "toy" then return "a random hearthstone toy" end
	if plan.from == "collection" then return "one you own" end
	return "a linked or pinned one"
end

-- What to say about a plan: a statement for a rung the player did not ask
-- for, a reason for a refusal, and nothing at all when the linked or pinned
-- hearthstone they meant is the one being used.
function HearthPick.Text(plan)
	if plan.action ~= "refuse" then
		if not plan.cause then return nil end
		return ("no usable %s hearthstone right now, so this is %s.")
			:format(plan.pins == false and "linked" or "linked or pinned", Did(plan))
	end
	if plan.reason == "nolinked" then
		if plan.detail == "cooldown" then
			return "every linked hearthstone is on cooldown, and the fallback is "
				.. "set to do nothing."
		end
		if plan.detail then
			return "no linked hearthstone can be used here, and the fallback is "
				.. "set to do nothing."
		end
		return "nothing is linked to this outfit, and the fallback is set to do nothing."
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
