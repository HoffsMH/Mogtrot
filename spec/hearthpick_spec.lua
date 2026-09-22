-- Fail-first tests for the hearthstone fallback ladder. HearthPick is the
-- pure half of the hearthstone key: it decides which rung answers and which
-- item it serves, with the action-time reads arriving as one injected
-- predicate and the rotation state and randomness belonging to the caller.
-- No globals, no WoW API, no clock.
--
-- API under contract:
--   HearthPick.Ready(ids, isEligible) -> pool, blocked, owned
--   HearthPick.Plan(request) where request = {
--       candidates,  -- { [itemID] = true } linked and pinned union
--       registry,    -- curated definitions (entries: itemID -> entry)
--       isEligible,  -- function(itemID) -> ready, blocked
--       state,       -- caller-owned Rotation state
--       random,      -- function(n) -> 1..n
--   }
--   HearthPick.Text(plan) -> the line to show, or nil when there is none
--
-- The ladder is three rungs: the linked and pinned union, then the toys, then
-- the whole registry. Toys sit above the rest because the hearthstone in your
-- bags is a thing a player can throw away.
local HearthPick = require("HearthPick")

describe("HearthPick", function()
	local HEARTH, PORTAL, TOY = 6948, 54452, 165802

	local REGISTRY = {
		VERSION = 1,
		entries = {
			[HEARTH] = { kind = "item" },
			[PORTAL] = { kind = "toy" },
			[TOY] = { kind = "toy" },
		},
	}

	-- The action-time answer per ID: true when it is ready, otherwise the
	-- token naming what stopped it. Anything unlisted is simply not owned.
	local function Eligibility(states)
		return function(itemID)
			local state = states[itemID] or "unowned"
			if state == true then return true end
			return false, state
		end
	end

	local function Request(over)
		local request = {
			candidates = {},
			registry = REGISTRY,
			isEligible = Eligibility({}),
			state = {},
			random = function(n) return n end, -- deterministic: highest index
		}
		for key, value in pairs(over or {}) do request[key] = value end
		return request
	end

	describe("Ready", function()
		it("returns the ready IDs in canonical numeric order", function()
			local pool = HearthPick.Ready({ TOY, HEARTH, PORTAL },
				Eligibility({ [HEARTH] = true, [PORTAL] = true, [TOY] = true }))
			assert.same({ HEARTH, PORTAL, TOY }, pool)
		end)

		it("reports nothing owned when every ID is unowned", function()
			local pool, blocked, owned = HearthPick.Ready({ HEARTH, TOY }, Eligibility({}))
			assert.same({}, pool)
			assert.is_nil(blocked)
			assert.is_false(owned)
		end)

		it("reports the first owned ID that was blocked, in that order", function()
			local pool, blocked, owned = HearthPick.Ready({ TOY, HEARTH },
				Eligibility({ [HEARTH] = "unusable", [TOY] = "cooldown" }))
			assert.same({}, pool)
			-- HEARTH sorts first, so its reason is the one reported.
			assert.equals("unusable", blocked)
			assert.is_true(owned)
		end)

		it("counts an owned ID as owned even while a ready one exists", function()
			local pool, blocked, owned = HearthPick.Ready({ HEARTH, TOY },
				Eligibility({ [HEARTH] = true, [TOY] = "cooldown" }))
			assert.same({ HEARTH }, pool)
			assert.equals("cooldown", blocked)
			assert.is_true(owned)
		end)
	end)

	describe("Plan, the linked and pinned rung", function()
		it("serves a ready linked or pinned candidate", function()
			local plan = HearthPick.Plan(Request({
				candidates = { [HEARTH] = true },
				isEligible = Eligibility({ [HEARTH] = true, [TOY] = true }),
			}))
			assert.same({ action = "use", itemID = HEARTH, from = "linked" }, plan)
		end)

		it("picks deterministically over the sorted pool", function()
			local plan = HearthPick.Plan(Request({
				candidates = { [TOY] = true, [HEARTH] = true },
				isEligible = Eligibility({ [HEARTH] = true, [TOY] = true }),
				random = function() return 1 end, -- the lowest ID of the sorted pool
			}))
			assert.equals(HEARTH, plan.itemID)
		end)

		it("says nothing about a rung that needed no explanation", function()
			local plan = HearthPick.Plan(Request({
				candidates = { [HEARTH] = true },
				isEligible = Eligibility({ [HEARTH] = true }),
			}))
			assert.is_nil(HearthPick.Text(plan))
		end)
	end)

	describe("Plan, the toy rung", function()
		it("prefers a hearthstone toy over the one in your bags", function()
			local plan = HearthPick.Plan(Request({
				candidates = {},
				isEligible = Eligibility({ [HEARTH] = true, [PORTAL] = true, [TOY] = true }),
				random = function() return 1 end, -- the lowest ID of the sorted pool
			}))
			-- HEARTH is the lowest ID in the whole registry, so PORTAL coming
			-- back is the toys having been their own pool.
			assert.same({ action = "use", itemID = PORTAL, from = "toy",
				cause = "nolinked" }, plan)
		end)

		it("falls to a toy when the linked hearthstone is not ready", function()
			local plan = HearthPick.Plan(Request({
				candidates = { [HEARTH] = true },
				isEligible = Eligibility({ [HEARTH] = "cooldown", [TOY] = true }),
			}))
			assert.same({ action = "use", itemID = TOY, from = "toy",
				cause = "nolinked" }, plan)
		end)

		it("falls to a toy with nothing linked or pinned at all", function()
			local plan = HearthPick.Plan(Request({
				candidates = {},
				isEligible = Eligibility({ [PORTAL] = true }),
			}))
			assert.equals(PORTAL, plan.itemID)
			assert.equals("toy", plan.from)
		end)

		it("names the toy rung in what it says", function()
			local plan = HearthPick.Plan(Request({
				candidates = { [HEARTH] = true },
				isEligible = Eligibility({ [HEARTH] = "cooldown", [TOY] = true }),
			}))
			assert.equals("no usable linked or pinned hearthstone right now, so this "
				.. "is a random hearthstone toy.", HearthPick.Text(plan))
		end)

		it("spreads repeats over every ready toy", function()
			local Rotation = require("Rotation")
			local request = Request({
				candidates = {},
				isEligible = Eligibility({ [HEARTH] = true, [PORTAL] = true, [TOY] = true }),
			})

			local first = HearthPick.Plan(request)
			Rotation.Commit(request.state, first.itemID)
			local second = HearthPick.Plan(request)

			assert.equals("toy", first.from)
			assert.equals("toy", second.from)
			assert.not_equals(first.itemID, second.itemID)
		end)
	end)

	describe("Plan, the rung below the toys", function()
		it("uses a hearthstone from your bags when no toy is ready", function()
			local plan = HearthPick.Plan(Request({
				candidates = { [TOY] = true },
				isEligible = Eligibility({ [TOY] = "cooldown", [HEARTH] = true }),
			}))
			assert.same({ action = "use", itemID = HEARTH, from = "collection",
				cause = "nolinked" }, plan)
		end)

		it("ignores registry entries the player does not own", function()
			local plan = HearthPick.Plan(Request({
				candidates = {},
				isEligible = Eligibility({ [HEARTH] = true }),
			}))
			-- Both toys sort above HEARTH and the random source picks the
			-- highest index, so an unowned entry being skipped is what leaves it.
			assert.equals(HEARTH, plan.itemID)
		end)

		it("states which rung answered instead of refusing", function()
			local plan = HearthPick.Plan(Request({
				candidates = { [TOY] = true },
				isEligible = Eligibility({ [TOY] = "cooldown", [HEARTH] = true }),
			}))
			assert.equals("no usable linked or pinned hearthstone right now, so this "
				.. "is one you own.", HearthPick.Text(plan))
		end)
	end)

	describe("Plan, refusal", function()
		it("refuses when nothing in the registry is owned", function()
			local plan = HearthPick.Plan(Request({ candidates = { [HEARTH] = true } }))
			assert.same({ action = "refuse", reason = "nocollection" }, plan)
			assert.equals("no hearthstone on this character to fall back on yet.",
				HearthPick.Text(plan))
		end)

		it("refuses when everything owned is still on cooldown", function()
			local plan = HearthPick.Plan(Request({
				candidates = { [HEARTH] = true },
				isEligible = Eligibility({ [HEARTH] = "cooldown", [TOY] = "cooldown" }),
			}))
			assert.same({ action = "refuse", reason = "collectionunusable",
				detail = "cooldown" }, plan)
			assert.equals("every hearthstone you own is still on cooldown.",
				HearthPick.Text(plan))
		end)

		it("refuses when nothing owned can be used here", function()
			local plan = HearthPick.Plan(Request({
				candidates = {},
				isEligible = Eligibility({ [HEARTH] = "unusable" }),
			}))
			assert.equals("collectionunusable", plan.reason)
			assert.equals("no hearthstone you own can be used here.",
				HearthPick.Text(plan))
		end)

		it("leaves the rotation untouched when it refuses", function()
			local request = Request({ candidates = { [HEARTH] = true } })
			HearthPick.Plan(request)
			assert.same({}, request.state)
		end)
	end)

	describe("Plan, rotation", function()
		it("serves every ready linked hearthstone before repeating", function()
			local Rotation = require("Rotation")
			local request = Request({
				candidates = { [HEARTH] = true, [TOY] = true },
				isEligible = Eligibility({ [HEARTH] = true, [TOY] = true }),
			})

			local first = HearthPick.Plan(request).itemID
			Rotation.Commit(request.state, first)
			local second = HearthPick.Plan(request).itemID

			assert.not_equals(first, second)
			assert.is_true(first == HEARTH or first == TOY)
			assert.is_true(second == HEARTH or second == TOY)
		end)
	end)
end)
