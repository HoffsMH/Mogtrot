local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local OutfitCandidates = ns.OutfitCandidates or require("OutfitCandidates")
local HearthPick = ns.HearthPick or require("HearthPick")
local Rotation = ns.Rotation or require("Rotation")

-- Dependency-injected hearthstone controller. The picker button drives it:
-- PreClick installs exactly one secure action's attributes (toy or item) for
-- the click that follows, PostClick commits the per-outfit rotation and
-- clears the transient attributes. Protected dispatch itself belongs to the
-- secure handler - this module never calls UseToy/UseItem, and a failed use
-- is never retried automatically.
--
-- Which hearthstone is served, and which rung of the fallback ladder serves
-- it, belongs to HearthPick. This half supplies the live reads.
--
-- deps = {
--     registry,          -- curated definitions (entries: itemID -> kind)
--     collection,        -- HearthstoneCollection-shaped reads
--     adapter,           -- live-ownership adapter handed to collection
--     links,             -- outfitID -> { [itemID] = true }
--     pins,              -- { [itemID] = true } active account pins
--     pinsOptOut,        -- outfitID -> true
--     rotationStates,    -- caller-owned per-outfit Rotation state map
--     random,            -- function(n) -> 1..n
--     hasActiveOutfit,   -- function() -> bool
--     activeOutfitID,    -- function() -> outfitID
--     button,            -- SetAttribute(name, value)
--     combat,            -- function() -> bool
--     now,               -- function() -> number, for cooldown math
--     warn,              -- function(message) for visible refusals
--     say,               -- function(message) for what just happened
-- }
--
-- Rotation key: outfitID when one is active, otherwise the sentinel false
-- ("no outfit") - hearth pins are usable without an outfit, so their rotation
-- persists under that documented key.
local NO_OUTFIT_KEY = false

local HearthstoneController = {}

local function ClearAttributes(deps)
	local set = deps.button.SetAttribute
	set(deps.button, "type", nil)
	set(deps.button, "toy", nil)
	set(deps.button, "item", nil)
end

-- Action-time state, read fresh every click: ownership, usability and
-- cooldown. Nothing is cached across clicks. An entry that is not ready says
-- which of the three stopped it, so a refusal can tell owning none from
-- owning none that are ready.
local function Eligible(deps, itemID)
	local entry = deps.registry.entries[itemID]
	if not entry then return false, "unowned" end

	local owned
	if entry.kind == "toy" then
		owned = deps.adapter.hasToy(itemID) and true or false
	else
		owned = (deps.adapter.itemCount(itemID) or 0) > 0
		-- A worn hearthstone carries a bag count of zero, so only entries the
		-- registry marks equippable pay for the equipment check.
		if not owned and entry.equippable and deps.adapter.isEquipped then
			owned = deps.adapter.isEquipped(itemID) and true or false
		end
	end
	if not owned then return false, "unowned" end

	if not deps.collection.UsableInfo(deps.adapter, itemID) then
		return false, "unusable"
	end

	-- Cooldown is active only while start + duration is in the future; a
	-- historical duration already elapsed is ready.
	local start, duration = deps.collection.Cooldown(deps.adapter, itemID)
	if type(start) == "number" and type(duration) == "number"
		and duration > 0 and start + duration > deps.now() then
		return false, "cooldown"
	end
	return true
end

function HearthstoneController.New(deps)
	local controller = { choice = nil }

	function controller.PreClick()
		if deps.combat() then
			deps.warn("hearthstone: cannot change the action during combat")
			return
		end

		ClearAttributes(deps)

		local outfitID = deps.hasActiveOutfit() and deps.activeOutfitID() or nil
		local candidates = OutfitCandidates.Resolve({
			links = outfitID and deps.links and deps.links[outfitID] or nil,
			pins = deps.pins,
			-- The ladder below owns eligibility, so here the sets only merge.
			isEligible = function() return true end,
			hasActiveOutfit = deps.hasActiveOutfit(),
			pinsOptOut = outfitID and deps.pinsOptOut and deps.pinsOptOut[outfitID] or false,
			-- Hearthstones are usable without an outfit: pins alone.
			allowPinsWithoutOutfit = true,
		})

		-- The state is published only once something is served, so a refusal
		-- leaves no empty rotation behind in the saved variables.
		local key = outfitID or NO_OUTFIT_KEY
		local state = deps.rotationStates[key] or {}

		local plan = HearthPick.Plan({
			candidates = candidates,
			registry = deps.registry,
			isEligible = function(itemID) return Eligible(deps, itemID) end,
			state = state,
			random = deps.random,
		})

		local text = HearthPick.Text(plan)
		if plan.action == "refuse" then
			deps.warn("hearthstone: " .. text)
			return
		end
		-- A rung below the linked and pinned ones is not a refusal, so it is
		-- said rather than flashed red.
		if text then deps.say("hearthstone: " .. text) end

		deps.rotationStates[key] = state

		local entry = deps.registry.entries[plan.itemID]
		if entry.kind == "toy" then
			deps.button.SetAttribute(deps.button, "type", "toy")
			deps.button.SetAttribute(deps.button, "toy", plan.itemID)
		else
			deps.button.SetAttribute(deps.button, "type", "item")
			deps.button.SetAttribute(deps.button, "item", "item:" .. plan.itemID)
		end
		controller.choice = { itemID = plan.itemID, key = key, state = state }
	end

	function controller.PostClick()
		if not controller.choice then return end
		-- One commit per served click; a failed use still advances the
		-- rotation so one bad item cannot trap every click. No retry.
		Rotation.Commit(controller.choice.state, controller.choice.itemID)
		ClearAttributes(deps)
		controller.choice = nil
	end

	return controller
end

ns.HearthstoneController = HearthstoneController
return HearthstoneController
