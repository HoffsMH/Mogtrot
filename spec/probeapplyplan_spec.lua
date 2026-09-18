-- The order slots go onto an actor, and which of them drag their child items
-- along. Wrong here and most of an outfit silently fails to appear.
local ProbeRenderUI = require("ProbeRenderUI")

describe("ProbeRenderUI.ApplyPlan", function()
	local function Plan(slots)
		local list = {}
		for _, slot in ipairs(slots) do list[slot] = { slot } end
		return ProbeRenderUI.ApplyPlan(list)
	end

	it("applies slots in ascending order whatever order they arrived in", function()
		local plan = Plan({ 17, 1, 16, 5, 3 })
		local order = {}
		for _, step in ipairs(plan) do order[#order + 1] = step.slot end
		assert.same({ 1, 3, 5, 16, 17 }, order)
	end)

	it("ignores child items on every slot but the main hand", function()
		local plan = Plan({ 1, 5, 16, 17 })
		local byslot = {}
		for _, step in ipairs(plan) do byslot[step.slot] = step.ignoreChildItems end
		assert.is_true(byslot[1])
		assert.is_true(byslot[5])
		assert.is_true(byslot[17])
		assert.is_false(byslot[16], "the main hand must carry its child items")
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
