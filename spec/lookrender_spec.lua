-- LookRender's decisions that need no client. First the order slots go onto
-- an actor, and which of them drag their child items along: wrong here and
-- most of an outfit silently fails to appear.
local LookRender = require("LookRender")

describe("LookRender.ApplyPlan", function()
	local function Plan(slots)
		local list = {}
		for _, slot in ipairs(slots) do list[slot] = { slot } end
		return LookRender.ApplyPlan(list)
	end

	it("applies armour ascending, then the off hand, then the main hand", function()
		local plan = Plan({ 17, 1, 16, 5, 3 })
		local order = {}
		for _, step in ipairs(plan) do order[#order + 1] = step.slot end
		assert.same({ 1, 3, 5, 17, 16 }, order)
	end)

	-- Blizzard: "offhand is processed first and mainhand might override
	-- offhand". Every path of theirs that fills both hands does it this way.
	it("puts the off hand first even when it is the only weapon", function()
		local plan = Plan({ 17, 5 })
		assert.equal(5, plan[1].slot)
		assert.equal(17, plan[2].slot)
	end)

	-- An actor remembers which hand it filled last, so without this the second
	-- weapon lands in the hand the first one already took and only one shows.
	it("resets the actor's hand memory before the first weapon", function()
		local plan = Plan({ 1, 16, 17 })
		assert.is_nil(plan[1].resetHands, "armour must not reset anything")
		assert.is_true(plan[2].resetHands)
		assert.equal(17, plan[2].slot)
		assert.is_nil(plan[3].resetHands, "only the first weapon resets")
	end)

	it("resets before a lone main hand too", function()
		local plan = Plan({ 16 })
		assert.equal(16, plan[1].slot)
		assert.is_true(plan[1].resetHands)
	end)

	-- The main hand's child is the off-hand a two-hander occupies, so it keeps
	-- its children when it is the only weapon.
	it("lets a lone main hand carry its child items", function()
		local plan = Plan({ 1, 5, 16 })
		local byslot = {}
		for _, step in ipairs(plan) do byslot[step.slot] = step.ignoreChildItems end
		assert.is_true(byslot[1])
		assert.is_true(byslot[5])
		assert.is_false(byslot[16], "the main hand must carry its child items")
	end)

	-- With two weapons the main hand goes on last, and re-evaluating its
	-- children there would undo the off-hand that was just applied. Blizzard's
	-- own two-handed preview passes true for both for this reason.
	it("ignores child items on both weapons when both hands are filled", function()
		local plan = Plan({ 1, 16, 17 })
		local byslot = {}
		for _, step in ipairs(plan) do byslot[step.slot] = step.ignoreChildItems end
		assert.is_true(byslot[17])
		assert.is_true(byslot[16], "the main hand must not undo the off hand")
	end)

	-- SetItemTransmogInfo decides for itself which hand to use, and Blizzard
	-- say it "will automatically handle whether the player can dual wield",
	-- so on a class that cannot it drops one weapon however it is ordered.
	-- TryOn with an explicit hand name is a different entry point and names
	-- the hand outright, which is what the Dressing Room set panel uses.
	it("names the hand for each weapon", function()
		local plan = Plan({ 1, 16, 17 })
		local byslot = {}
		for _, step in ipairs(plan) do byslot[step.slot] = step.hand end
		assert.is_nil(byslot[1], "armour has no hand")
		assert.equal("SECONDARYHANDSLOT", byslot[17])
		assert.equal("MAINHANDSLOT", byslot[16])
	end)

	it("covers every slot it was given", function()
		local plan = Plan({ 1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17, 19 })
		assert.equal(12, #plan)
	end)

	it("survives an empty or absent list", function()
		assert.same({}, LookRender.ApplyPlan({}))
		assert.same({}, LookRender.ApplyPlan(nil))
	end)

	it("skips a key that is not a slot number", function()
		local plan = LookRender.ApplyPlan({ [1] = {}, banana = {} })
		assert.equal(1, #plan)
		assert.equal(1, plan[1].slot)
	end)
end)

describe("LookRender.ClearUnspecifiedSlots", function()
	it("undresses slots absent from a partial look", function()
		local cleared = {}
		local actor = { UndressSlot = function(_, slot) cleared[#cleared + 1] = slot end }
		LookRender.ClearUnspecifiedSlots(actor, { [5] = {} }, { 3, 5, 6 })
		assert.same({ 3, 6 }, cleared)
	end)
end)

-- A model scene names its actors by race, form and sex. The alternate-form
-- actor is the only way to show a Dracthyr visage or a Worgen human body at
-- the right scale, and it can only be reached by that name.
describe("LookRender.ActorTag", function()
	it("names the everyday actor for a race with one body", function()
		assert.equal("orc-male", LookRender.ActorTag("Orc", 2, false))
		assert.equal("voidelf-female", LookRender.ActorTag("VoidElf", 3, false))
	end)

	it("names the alternate-form actor when the record was in it", function()
		assert.equal("dracthyr-alt-male", LookRender.ActorTag("Dracthyr", 2, true))
		assert.equal("worgen-alt-female", LookRender.ActorTag("Worgen", 3, true))
	end)

	it("treats a missing altered flag as the everyday body", function()
		assert.equal("dracthyr-male", LookRender.ActorTag("Dracthyr", 2))
		assert.equal("dracthyr-male", LookRender.ActorTag("Dracthyr", 2, nil))
	end)

	it("refuses to build a tag it cannot trust", function()
		assert.is_nil(LookRender.ActorTag(nil, 2, false))
		assert.is_nil(LookRender.ActorTag("", 2, false))
		assert.is_nil(LookRender.ActorTag("Orc", nil, false))
		assert.is_nil(LookRender.ActorTag("Orc", 0, false))
		assert.is_nil(LookRender.ActorTag("Orc", 1, false))
	end)
end)

-- A slot accepted with reason 0 can still be left empty, so what the actor
-- holds afterwards is the observable.
describe("LookRender.DroppedSlots", function()
	local function Actor(holds)
		return { GetItemTransmogInfo = function(_, slot) return holds[slot] end }
	end

	it("counts armour slots the actor did not keep", function()
		local list = { [1] = {}, [5] = {}, [7] = {}, [8] = {} }
		local actor = Actor({ [1] = {}, [5] = {} })
		assert.equal(2, LookRender.DroppedSlots(actor, list))
	end)

	it("leaves weapons out, which a hand swap can move", function()
		local list = { [16] = {}, [17] = {}, [1] = {} }
		assert.equal(0, LookRender.DroppedSlots(Actor({ [1] = {} }), list))
	end)

	it("names the dropped armour slots in order", function()
		local list = { [8] = {}, [1] = {}, [5] = {}, [16] = {} }
		assert.same({ 5, 8 }, LookRender.DroppedSlotList(Actor({ [1] = {} }), list))
		assert.same({}, LookRender.DroppedSlotList(nil, list))
	end)

	it("answers 0 when the actor cannot say", function()
		assert.equal(0, LookRender.DroppedSlots({}, { [7] = {} }))
		assert.equal(0, LookRender.DroppedSlots(nil, { [7] = {} }))
	end)
end)

-- The library's draw list. A stored shoulder with only its second side
-- assigned must still reach the actor with a primary, or nothing draws.
describe("LookRender.TransmogList", function()
	local saved
	before_each(function()
		saved = _G.ItemUtil
		_G.ItemUtil = { CreateItemTransmogInfo = function(a, b, c)
			return { appearanceID = a, secondaryAppearanceID = b, illusionID = c }
		end }
	end)
	after_each(function() _G.ItemUtil = saved end)

	it("draws a second-side-only shoulder with the other side hidden", function()
		local list = LookRender.TransmogList({ [3] = { 0, 195671, 0 } })
		assert.same({ appearanceID = 77343, secondaryAppearanceID = 195671,
			illusionID = 0 }, list[3])
	end)

	it("keeps a split, a matched and an unsplit shoulder as stored", function()
		for _, entry in ipairs({ { 5, 6, 0 }, { 5, 5, 0 }, { 5, 0, 0 } }) do
			local list = LookRender.TransmogList({ [3] = entry })
			assert.same({ appearanceID = entry[1], secondaryAppearanceID = entry[2],
				illusionID = 0 }, list[3])
		end
	end)
end)

-- The try-on tally is what DressWhenLoaded reads back from each dress. The
-- client enumeration that once sat beside it is a development tool and does
-- not ship.

describe("LookRender", function()
	it("carries no client enumeration", function()
		assert.is_nil(LookRender.Presence)
		assert.is_nil(LookRender.Lines)
		assert.is_nil(LookRender.WIDGET_METHODS)
		assert.is_nil(LookRender.NAMESPACES)
	end)
end)

describe("LookRender try-on tallies", function()
	it("names each reason the client can return", function()
		assert.equal("ok", LookRender.TRY_ON_REASON[0])
		assert.equal("wrongRace", LookRender.TRY_ON_REASON[1])
		assert.equal("notEquippable", LookRender.TRY_ON_REASON[2])
		assert.equal("pending", LookRender.TRY_ON_REASON[3])
	end)

	it("counts slots by reason rather than by call", function()
		local tally, retryable, total = LookRender.TryOnTally({
			[1] = 0, [3] = 0, [5] = 2, [16] = 1, [17] = 3,
		})
		assert.equal(2, tally.ok)
		assert.equal(1, tally.notEquippable)
		assert.equal(1, tally.wrongRace)
		assert.equal(1, tally.pending)
		assert.equal(1, retryable)
		assert.equal(5, total)
	end)

	it("treats only pending as worth retrying", function()
		local _, retryable = LookRender.TryOnTally({ [1] = 1, [2] = 2, [3] = 0 })
		assert.equal(0, retryable)
	end)

	it("keeps an unknown reason visible instead of dropping it", function()
		local tally = LookRender.TryOnTally({ [1] = 9 })
		assert.equal(1, tally["reason 9"])
	end)

	it("survives an empty result set", function()
		local tally, retryable, total = LookRender.TryOnTally(nil)
		assert.same({}, tally)
		assert.equal(0, retryable)
		assert.equal(0, total)
	end)
end)

describe("LookRender.DressWhenLoaded", function()
	local timers

	before_each(function()
		timers = {}
		_G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay, fn } end }
	end)

	after_each(function() _G.C_Timer = nil end)

	-- An early pass can look complete before the gear has streamed in, so only
	-- a pass from 1.5 s on may stand the remaining retries down.
	it("stands down only after a settled pass from the third retry on", function()
		local dresses = 0
		local actor = {
			SetAutoDress = function() end,
			Undress = function() dresses = dresses + 1 end,
			SetItemTransmogInfo = function() return 0 end,
		}
		LookRender.DressWhenLoaded(actor, { [1] = { appearanceID = 5 } })
		assert.equal(1, dresses)
		assert.same({ 0.1, 0.5, 1.5, 3, 5 }, { timers[1][1], timers[2][1], timers[3][1],
			timers[4][1], timers[5][1] })

		timers[1][2]()
		timers[2][2]()
		assert.is_nil(actor.mogtrotSettled)
		timers[3][2]()
		assert.equal(actor.mogtrotPaint, actor.mogtrotSettled)
		assert.equal(4, dresses)
		timers[4][2]()
		timers[5][2]()
		assert.equal(4, dresses)
	end)
end)
