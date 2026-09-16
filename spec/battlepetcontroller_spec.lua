-- Fail-first tests for the dependency-injected BattlePetController
-- (plan checkpoint 33). Everything impure is injected: an outfit-transition
-- guard in the OutfitTransition shape, a pure Rotation for no-repeat
-- selection, a collection adapter in the BattlePetCollection shape, and
-- explicit summon/pending hooks. No globals, no WoW API, no clock.
--
-- API under contract:
--   BattlePetController.New(deps) where deps = {
--       transition,        -- OutfitTransition-shaped guard (Initialize/OutfitChanged)
--       collection,        -- BattlePetCollection-shaped pure reads
--       links,             -- { [outfitID] = { [guid] = true } }
--       pins,              -- { [guid] = true } active account pins
--       pinsOptOut,        -- { [outfitID] = true }
--       rotationStates,   -- caller-owned per-outfit Rotation state map
--       random,            -- function(n) -> 1..n
--       summon,            -- function(guid); the only call that touches the pet
--       hasActiveOutfit,   -- function() -> bool
--       activeOutfitID,    -- function() -> outfitID or nil
--   }
--   controller:Initialize()                 -- login guard; never summons
--   controller:OutfitChanged()              -- synchronous event; coalesces
--   controller:PendingGUID()                -- staged guid or nil
--   controller:OnCompanionUpdate()          -- deferred confirmation commit/clear
local BattlePetController = require("BattlePetController")

describe("BattlePetController", function()
	local GUID_A, GUID_B, GUID_C = "Pet-A", "Pet-B", "Pet-C"

	-- Eligible except the GUIDs listed as not summonable.
	local function MakeDeps(overrides)
		local deps
		deps = {
			links = { [7] = { [GUID_A] = true } },
			pins = { [GUID_B] = true },
			pinsOptOut = {},
			rotationStates = {},
			random = function(n) return n end,
			hasActiveOutfit = function() return true end,
			activeOutfitID = function() return 7 end,
			collection = {
				getSummonInfo = function(guid)
					if overrides.unsummonable and overrides.unsummonable[guid] then
						return false, "PetIsDead", "dead"
					end
					return true, nil, nil
				end,
				getSummonedPetGUID = function() return overrides.summoned end,
			},
			summonCalls = {},
			summon = function(guid) deps.summonCalls[#deps.summonCalls + 1] = guid end,
		}
		for k, v in pairs(overrides or {}) do deps[k] = v end
		return deps
	end

	local function MakeController(overrides)
		local deps = MakeDeps(overrides)
		local controller = BattlePetController.New(deps)
		return controller, deps
	end
	-- The observable action of a settled transition is the injected summon
	-- call itself; no separate dispatch notification belongs to the contract.

	-- Drive a settled transition: event fires, next-frame read runs.
	local function FireEvent(controller, scheduler)
		controller:OutfitChanged()
		scheduler.run()
	end

	local function FakeScheduler()
		local fake = { pending = {} }
		function fake.schedule(fn)
			fake.pending[#fake.pending + 1] = fn
			return #fake.pending
		end
		function fake.run()
			local queued = fake.pending
			fake.pending = {}
			for _, fn in ipairs(queued) do fn() end
		end
		return fake
	end

	-- The controller builds its own transition guard from deps.transition
	-- inputs; for these tests we let it construct one around injected
	-- reader/schedule hooks so coalescing is observable.
	-- Fixture sentinel: the controller's first scheduled read must initialize
	-- its guard against a *previous* outfit, not the current one, or no real
	-- transition would exist when the event fires. The first read therefore
	-- answers a distinct prior ID (-1) before delegating to the supplied
	-- reader; the no-active-outfit case returns nil after the sentinel, which
	-- is still a first read (initializes the guard with nothing).
	local function WithReader(deps, reader, schedule)
		local first = true
		deps.readActiveOutfitID = function()
			if first then
				first = false
				return deps.hasActiveOutfit() and -1 or nil
			end
			return reader()
		end
		deps.schedule = schedule
	end

	describe("candidate resolution", function()
		it("uses multiple exact GUID links plus account pins by default", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({
				links = { [7] = { [GUID_A] = true, [GUID_B] = true } },
				pins = { [GUID_C] = true },
			})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			-- Change from nothing to outfit 7 dispatches once; the summon was
			-- staged then called with one of the three eligible GUIDs.
			assert.equal(1, #deps.summonCalls)
			assert.is_true(deps.summonCalls[1] == GUID_A
				or deps.summonCalls[1] == GUID_B
				or deps.summonCalls[1] == GUID_C)
		end)

		it("excludes pins when the outfit opts out", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({
				links = { [7] = { [GUID_A] = true } },
				pins = { [GUID_B] = true },
				pinsOptOut = { [7] = true },
			})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			assert.equal(1, #deps.summonCalls)
			assert.equals(GUID_A, deps.summonCalls[1])
		end)

		it("filters ineligible, dead and unowned GUIDs via summonInfo", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({
				links = { [7] = { [GUID_A] = true, [GUID_B] = true } },
				pins = { [GUID_C] = true },
				unsummonable = { [GUID_A] = true, [GUID_B] = true },
			})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			assert.equal(1, #deps.summonCalls)
			assert.equals(GUID_C, deps.summonCalls[1])
		end)

		it("summons nothing when every candidate is ineligible", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({
				links = { [7] = { [GUID_A] = true } },
				pins = { [GUID_B] = true },
				unsummonable = { [GUID_A] = true, [GUID_B] = true },
			})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			assert.equal(0, #deps.summonCalls)
			assert.is_nil(controller:PendingGUID())
		end)

		it("does nothing with no active outfit", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({
				hasActiveOutfit = function() return false end,
			})
			WithReader(deps, function() return nil end, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			assert.equal(0, #deps.summonCalls)
		end)
	end)

	describe("login and event guards", function()
		it("sentinel initialization reads the prior outfit and never summons", function()
			-- The sentinel first read answers -1 (a prior outfit), so the
			-- guard is initialized without dispatch and the current outfit
			-- is untouched until a real change arrives.
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()
			assert.equal(0, #deps.summonCalls)
		end)

		it("coalesces duplicate synchronous events into one dispatch", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			-- One real outfit change fires three synchronous events before the
			-- next frame: they coalesce into exactly one dispatch.
			controller:OutfitChanged()
			controller:OutfitChanged()
			controller:OutfitChanged()
			scheduler.run()
			assert.equal(1, #deps.summonCalls)
		end)

		it("dispatches once per real change and not again on the same ID", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			assert.equal(1, #deps.summonCalls)

			FireEvent(controller, scheduler)
			assert.equal(1, #deps.summonCalls) -- same outfit, no new dispatch
		end)
	end)

	describe("pending lifecycle", function()
		it("stages the pending GUID before the summon call and commits on match", function()
			local scheduler = FakeScheduler()
			local staged = {}
			local controller, deps = MakeController({})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			-- Wrap summon to observe the pending state at call time.
			local baseSummon = deps.summon
			deps.summon = function(guid)
				staged[#staged + 1] = controller:PendingGUID()
				baseSummon(guid)
			end
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			-- Stage-before-call: the pending GUID was set when summon fired.
			assert.equal(1, #staged)
			assert.equals(deps.summonCalls[1], staged[1])

			-- Deferred confirmation: the summoned GUID matches -> commit.
			deps.collection.getSummonedPetGUID = function() return deps.summonCalls[1] end
			controller:OnCompanionUpdate()
			assert.is_nil(controller:PendingGUID())
		end)

		it("does not re-summon the currently summoned chosen GUID", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({
				links = { [7] = { [GUID_A] = true } },
				pins = {},
				summoned = GUID_A, -- already out
			})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			assert.equal(0, #deps.summonCalls) -- chosen copy already out: no toggle
			assert.is_nil(controller:PendingGUID())
		end)

		it("clears an expired pending without commit on mismatched confirmation", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			assert.is_not_nil(controller:PendingGUID())

			-- Confirmation answers a different GUID than the pending one.
			deps.collection.getSummonedPetGUID = function() return "Pet-Other" end
			controller:OnCompanionUpdate()
			assert.is_nil(controller:PendingGUID())
		end)

		it("commits the staging outfit's rotation even if the outfit changed before confirmation", function()
			-- Race: pending staged on outfit 7, then the player switches to
			-- outfit 8 (or the active ID goes nil) before COMPANION_UPDATE.
			-- The commit must land on outfit 7's rotation state, which the
			-- controller remembered at staging time.
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			local stagedGUID = controller:PendingGUID()
			assert.is_not_nil(stagedGUID)

			deps.activeOutfitID = function() return 8 end
			deps.collection.getSummonedPetGUID = function() return stagedGUID end
			controller:OnCompanionUpdate()

			assert.is_nil(controller:PendingGUID())
			assert.equals(stagedGUID, deps.rotationStates[7].last)
			assert.is_nil(deps.rotationStates[8] and deps.rotationStates[8].last)

			-- A nil active outfit at confirmation must not error either.
			deps.activeOutfitID = function() return nil end
		end)

		it("clears pending when confirmation reports nothing summoned", function()
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({})
			WithReader(deps, deps.activeOutfitID, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			FireEvent(controller, scheduler)
			assert.is_not_nil(controller:PendingGUID())

			deps.collection.getSummonedPetGUID = function() return nil end
			controller:OnCompanionUpdate()
			assert.is_nil(controller:PendingGUID())
		end)
	end)

	describe("no-repeat rotation", function()
		it("cycles every eligible GUID of one outfit before repeating", function()
			-- Per-outfit rotation state (plan): outfit 7 remembers its own
			-- last summon across visits, so a return visit does not repeat.
			local scheduler = FakeScheduler()
			local controller, deps = MakeController({
				links = {
					[7] = { [GUID_A] = true, [GUID_B] = true },
					[8] = { [GUID_A] = true, [GUID_B] = true },
				},
				pins = {},
				random = function(n) return n end, -- deterministic: highest index
			})
			-- One WithReader call only: the outfit reader is a mutable local
			-- so later visits change what it answers without resetting the
			-- first-read sentinel.
			local outfit = 7
			WithReader(deps, function() return outfit end, scheduler.schedule)
			controller:Initialize()
			scheduler.run()

			-- Visit 7: fresh per-outfit state; deterministic pick is GUID_B.
			FireEvent(controller, scheduler)
			deps.collection.getSummonedPetGUID = function() return deps.summonCalls[1] end
			controller:OnCompanionUpdate()

			-- Visit 8: a different outfit has its own fresh state; 7->8 is a
			-- real change so the transition dispatches. Nothing is summoned
			-- right now (the player dismissed between transitions), so the
			-- current-pet no-toggle contract does not block the fresh pick.
			deps.collection.getSummonedPetGUID = function() return nil end
			outfit = 8
			FireEvent(controller, scheduler)
			deps.collection.getSummonedPetGUID = function() return deps.summonCalls[2] end
			controller:OnCompanionUpdate()

			-- Return to 7: real change, and outfit 7's persisted rotation
			-- state must avoid repeating GUID_B.
			outfit = 7
			FireEvent(controller, scheduler)

			assert.equal(3, #deps.summonCalls)
			assert.equals(GUID_B, deps.summonCalls[1]) -- outfit 7, first visit
			assert.equals(GUID_B, deps.summonCalls[2]) -- outfit 8, fresh state
			assert.equals(GUID_A, deps.summonCalls[3]) -- outfit 7: no repeat
		end)
	end)
end)
