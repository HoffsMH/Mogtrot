local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local OutfitTransition = ns.OutfitTransition or require("OutfitTransition")
local OutfitCandidates = ns.OutfitCandidates or require("OutfitCandidates")
local Rotation = ns.Rotation or require("Rotation")

-- Dependency-injected battle-pet controller. Core wires events later; this
-- module is pure: the outfit guard, the candidate sets, the rotation and the
-- summon call are all injected or caller-owned. The observable action of a
-- settled transition is deps.summon(guid) - and only that call touches a pet.
--
-- deps = {
--     links,             -- outfitID -> { [guid] = true }
--     pins,              -- active account pins, { [guid] = true }
--     pinsOptOut,        -- outfitID -> true
--     rotationStates,    -- caller-owned per-outfit Rotation state map
--     random,            -- function(n) -> 1..n
--     summon,            -- function(guid); the pet-touching call
--     collection,        -- BattlePetCollection-shaped reads
--     hasActiveOutfit,   -- function() -> bool
--     activeOutfitID,    -- function() -> outfitID
--     readActiveOutfitID, schedule,  -- transition guard plumbing
-- }
local BattlePetController = {}

function BattlePetController.New(deps)
	local controller = { pending = nil }

	local function OnSettledOutfit(outfitID)
		if not deps.hasActiveOutfit() then return end

		local candidates = OutfitCandidates.Resolve({
			links = deps.links and deps.links[outfitID] or nil,
			pins = deps.pins,
			isEligible = function(guid)
				local summonable = deps.collection.getSummonInfo(guid)
				return summonable and true or false
			end,
			hasActiveOutfit = true,
			pinsOptOut = deps.pinsOptOut and deps.pinsOptOut[outfitID] or false,
			allowPinsWithoutOutfit = false,
		})

		-- Eligibility order is not identity order; Rotation wants a list.
		-- Resolve returns a set (unordered), so the controller canonicalizes
		-- it: numeric IDs ascending, strings lexicographically. This keeps
		-- the injected random deterministic under any pairs order.
		local pool = {}
		for guid in pairs(candidates) do pool[#pool + 1] = guid end
		table.sort(pool, function(a, b)
			if type(a) == "number" and type(b) == "number" then return a < b end
			return tostring(a) < tostring(b)
		end)

		local state = deps.rotationStates[outfitID]
		if not state then
			state = {}
			deps.rotationStates[outfitID] = state
		end

		local chosen = Rotation.Choose(state, pool, deps.random)
		if not chosen then return end

		if deps.collection.getSummonedPetGUID() == chosen then
			-- The chosen copy is already out: commit it so the rotation
			-- advances without toggling or dismissing the pet.
			Rotation.Commit(state, chosen)
			controller.pending = nil
			controller.pendingOutfitID = nil
			return
		end

		-- Stage before the call: a failed or unconfirmed summon leaves an
		-- observable pending GUID that confirmation resolves. The staging
		-- outfit is remembered so confirmation commits the right rotation
		-- state even if the active outfit changed in between.
		controller.pending = chosen
		controller.pendingOutfitID = outfitID
		deps.summon(chosen)
	end

	-- The guard is built on first use so tests can inject the reader and
	-- scheduler through deps after New but before Initialize.
	local transition
	local function Guard()
		if not transition then
			transition = OutfitTransition.New(
				deps.readActiveOutfitID,
				deps.schedule,
				OnSettledOutfit
			)
		end
		return transition
	end

	function controller.Initialize()
		Guard():Initialize()
	end

	function controller.OutfitChanged()
		Guard():OutfitChanged()
	end

	function controller:PendingGUID()
		return self.pending
	end

	-- Deferred confirmation: the journal's current summoned GUID either
	-- matches the pending one (commit: rotation advances, pending clears) or
	-- does not (clear without commit so a failed summon cannot trap rotation).
	-- Commit always lands on the outfit that staged the pending GUID, never
	-- on whatever is active at confirmation time.
	function controller:OnCompanionUpdate()
		local summoned = deps.collection.getSummonedPetGUID()
		if self.pending and summoned == self.pending then
			Rotation.Commit(deps.rotationStates[self.pendingOutfitID], self.pending)
		end
		self.pending = nil
		self.pendingOutfitID = nil
	end

	return controller
end

ns.BattlePetController = BattlePetController
return BattlePetController
