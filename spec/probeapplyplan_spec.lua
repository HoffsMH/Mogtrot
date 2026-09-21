-- The order slots go onto an actor, and which of them drag their child items
-- along. Wrong here and most of an outfit silently fails to appear.
local ProbeRenderUI = require("ProbeRenderUI")

describe("ProbeRenderUI.ApplyPlan", function()
	local function Plan(slots)
		local list = {}
		for _, slot in ipairs(slots) do list[slot] = { slot } end
		return ProbeRenderUI.ApplyPlan(list)
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
		assert.same({}, ProbeRenderUI.ApplyPlan({}))
		assert.same({}, ProbeRenderUI.ApplyPlan(nil))
	end)

	it("skips a key that is not a slot number", function()
		local plan = ProbeRenderUI.ApplyPlan({ [1] = {}, banana = {} })
		assert.equal(1, #plan)
		assert.equal(1, plan[1].slot)
	end)
end)

describe("ProbeRenderUI.ClearUnspecifiedSlots", function()
	it("undresses slots absent from a partial look", function()
		local cleared = {}
		local actor = { UndressSlot = function(_, slot) cleared[#cleared + 1] = slot end }
		ProbeRenderUI.ClearUnspecifiedSlots(actor, { [5] = {} }, { 3, 5, 6 })
		assert.same({ 3, 6 }, cleared)
	end)
end)

-- A model scene names its actors by race, form and sex. The alternate-form
-- actor is the only way to show a Dracthyr visage or a Worgen human body at
-- the right scale, and it can only be reached by that name.
describe("ProbeRenderUI.ActorTag", function()
	it("names the everyday actor for a race with one body", function()
		assert.equal("orc-male", ProbeRenderUI.ActorTag("Orc", 2, false))
		assert.equal("voidelf-female", ProbeRenderUI.ActorTag("VoidElf", 3, false))
	end)

	it("names the alternate-form actor when the record was in it", function()
		assert.equal("dracthyr-alt-male", ProbeRenderUI.ActorTag("Dracthyr", 2, true))
		assert.equal("worgen-alt-female", ProbeRenderUI.ActorTag("Worgen", 3, true))
	end)

	it("treats a missing altered flag as the everyday body", function()
		assert.equal("dracthyr-male", ProbeRenderUI.ActorTag("Dracthyr", 2))
		assert.equal("dracthyr-male", ProbeRenderUI.ActorTag("Dracthyr", 2, nil))
	end)

	it("refuses to build a tag it cannot trust", function()
		assert.is_nil(ProbeRenderUI.ActorTag(nil, 2, false))
		assert.is_nil(ProbeRenderUI.ActorTag("", 2, false))
		assert.is_nil(ProbeRenderUI.ActorTag("Orc", nil, false))
		assert.is_nil(ProbeRenderUI.ActorTag("Orc", 0, false))
		assert.is_nil(ProbeRenderUI.ActorTag("Orc", 1, false))
	end)
end)
