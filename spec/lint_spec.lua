local Lint = require("Lint")

local D = Lint.DISPLAY
local NONE = Lint.OPTION_NONE

describe("Lint.ShowInList", function()
	it("defaults off and requires an explicit opt-in", function()
		assert.is_false(Lint.ShowInList(nil))
		assert.is_false(Lint.ShowInList({}))
		assert.is_false(Lint.ShowInList({ showCompletenessInList = false }))
		assert.is_true(Lint.ShowInList({ showCompletenessInList = true }))
	end)

	it("persists through the shared setting table", function()
		local settings = {}
		Lint.SetShowInList(settings, true)
		assert.is_true(Lint.ShowInList(settings))
		Lint.SetShowInList(settings, false)
		assert.is_false(Lint.ShowInList(settings))
	end)

	it("reserves label space only while the circle is shown", function()
		assert.equal(4, Lint.NameInset({}))
		assert.equal(16, Lint.NameInset({ showCompletenessInList = true }))
	end)
end)
local BUILD = 120007

-- read(slot, option) out of a { ["<slot>:<option>"] = displayType } table. Absent
-- keys read nil, which is what the client does for a slot it has nothing to say
-- about, so a test can leave one out rather than spell it.
local function Reader(map)
	return function(slot, option)
		return map[("%d:%d"):format(slot, option)]
	end
end

local function NamesOf(defs)
	local out = {}
	for _, def in ipairs(defs) do
		table.insert(out, def.name)
	end
	return out
end

describe("Lint.SlotDefs", function()
	it("returns nothing for an empty or absent slot list", function()
		assert.same({}, Lint.SlotDefs({}))
		assert.same({}, Lint.SlotDefs(nil))
	end)

	it("gives a slot with no options one entry, under option None", function()
		local defs = Lint.SlotDefs({ { slot = 7, name = "Wrist" } })
		assert.same({ { slot = 7, option = NONE, name = "Wrist" } }, defs)
	end)

	it("gives a weapon slot one entry per option, named by the option", function()
		local defs = Lint.SlotDefs({
			{
				slot = 13,
				name = "Off Hand",
				options = {
					{ option = 4, name = "Off Hand", enabled = true },
					{ option = 5, name = "Shield", enabled = true },
				},
			},
		})

		assert.equal(2, #defs)
		assert.same({ "Off Hand", "Shield" }, NamesOf(defs))
		assert.equal(5, defs[2].option)
		assert.equal(13, defs[2].slot)
	end)

	it("skips options this character cannot use", function()
		local defs = Lint.SlotDefs({
			{
				slot = 12,
				name = "Main Hand",
				options = {
					{ option = 1, name = "One-Handed", enabled = true },
					{ option = 7, name = "Fury Two-Handed", enabled = false },
				},
			},
		})

		assert.same({ "One-Handed" }, NamesOf(defs))
	end)

	-- Otherwise a caster's off-hand slot would vanish from the total entirely,
	-- and the denominator would silently shrink rather than stay honest.
	it("still counts a slot once when every option is disabled", function()
		local defs = Lint.SlotDefs({
			{
				slot = 12,
				name = "Main Hand",
				options = { { option = 1, name = "One-Handed", enabled = false } },
			},
		})

		assert.same({ { slot = 12, option = NONE, name = "Main Hand" } }, defs)
	end)

	it("falls back to the slot name when an option has none", function()
		local defs = Lint.SlotDefs({
			{ slot = 12, name = "Main Hand", options = { { option = 1, enabled = true } } },
		})

		assert.same({ "Main Hand" }, NamesOf(defs))
	end)
end)

describe("Lint.Measure", function()
	local defs = {
		{ slot = 4, option = NONE, name = "Chest" },
		{ slot = 7, option = NONE, name = "Wrist" },
	}

	it("counts an assigned slot as covered", function()
		local record = Lint.Measure(defs, Reader({
			["4:0"] = D.ASSIGNED,
			["7:0"] = D.ASSIGNED,
		}), BUILD)

		assert.equal(2, record.covered)
		assert.equal(2, record.total)
		assert.same({}, record.missing)
	end)

	-- Hiding a slot is a decision that stays correct however the gear changes,
	-- which is the same property an assigned appearance has.
	it("counts a hidden slot as covered", function()
		local record = Lint.Measure(defs, Reader({
			["4:0"] = D.HIDDEN,
			["7:0"] = D.ASSIGNED,
		}), BUILD)

		assert.equal(2, record.covered)
	end)

	it("counts an unassigned slot as missing, and names it", function()
		local record = Lint.Measure(defs, Reader({
			["4:0"] = D.ASSIGNED,
			["7:0"] = D.UNASSIGNED,
		}), BUILD)

		assert.equal(1, record.covered)
		assert.equal(2, record.total)
		assert.same({ { name = "Wrist" } }, record.missing)
	end)

	-- The whole point of the feature: "show my equipped gear" means the slot
	-- changes every time the player swaps, so it is not done.
	it("counts a show-equipped slot as missing, marked apart from unset", function()
		local record = Lint.Measure(defs, Reader({
			["4:0"] = D.ASSIGNED,
			["7:0"] = D.EQUIPPED,
		}), BUILD)

		assert.equal(1, record.covered)
		assert.same({ { name = "Wrist", equipped = true } }, record.missing)
	end)

	it("leaves a disabled slot out of the total entirely", function()
		local record = Lint.Measure(defs, Reader({
			["4:0"] = D.ASSIGNED,
			["7:0"] = D.DISABLED,
		}), BUILD)

		assert.equal(1, record.covered)
		assert.equal(1, record.total)
		assert.same({}, record.missing)
	end)

	-- An unreadable slot is not evidence of an unfilled one.
	it("leaves an unreadable slot out of the total rather than counting it against", function()
		local record = Lint.Measure(defs, Reader({ ["4:0"] = D.ASSIGNED }), BUILD)

		assert.equal(1, record.covered)
		assert.equal(1, record.total)
		assert.same({}, record.missing)
	end)

	it("reports nothing at all when no slot could be read", function()
		assert.is_nil(Lint.Measure(defs, Reader({}), BUILD))
		assert.is_nil(Lint.Measure({}, Reader({}), BUILD))
	end)

	it("stamps the build it was measured on", function()
		local record = Lint.Measure(defs, Reader({ ["4:0"] = D.ASSIGNED }), BUILD)
		assert.equal(BUILD, record.at)
	end)

	it("keeps missing slots in the order they were given", function()
		local order = {
			{ slot = 1, option = NONE, name = "Head" },
			{ slot = 2, option = NONE, name = "Wrist" },
			{ slot = 3, option = NONE, name = "Waist" },
		}
		local record = Lint.Measure(order, Reader({
			["1:0"] = D.UNASSIGNED,
			["2:0"] = D.UNASSIGNED,
			["3:0"] = D.UNASSIGNED,
		}), BUILD)

		assert.same({ "Head", "Wrist", "Waist" }, NamesOf(record.missing))
	end)

	it("asks about each slot and option pair separately", function()
		local asked = {}
		local pairsDefs = {
			{ slot = 13, option = 4, name = "Off Hand" },
			{ slot = 13, option = 5, name = "Shield" },
		}

		Lint.Measure(pairsDefs, function(slot, option)
			table.insert(asked, ("%d:%d"):format(slot, option))
			return D.ASSIGNED
		end, BUILD)

		assert.same({ "13:4", "13:5" }, asked)
	end)
end)

describe("Lint.State", function()
	it("is unknown for an outfit with no record", function()
		assert.equal("unknown", Lint.State(nil, BUILD))
		assert.equal("unknown", Lint.State("nonsense", BUILD))
	end)

	-- A patch can change which slots exist, so a record from before one says
	-- nothing about this build and must not read as a measurement.
	it("is unknown for a record from another build", function()
		local record = { covered = 4, total = 4, at = 110200 }
		assert.equal("unknown", Lint.State(record, BUILD))
	end)

	it("is unknown rather than full when nothing was countable", function()
		assert.equal("unknown", Lint.State({ covered = 0, total = 0, at = BUILD }, BUILD))
	end)

	it("is full when every countable slot is covered", function()
		assert.equal("full", Lint.State({ covered = 16, total = 16, at = BUILD }, BUILD))
	end)

	it("is short while any slot is missing", function()
		assert.equal("short", Lint.State({ covered = 11, total = 16, at = BUILD }, BUILD))
	end)
end)

describe("Lint.State, linked mounts", function()
	it("requires both a ground and flying mount", function()
		local record = { covered = 14, total = 14, at = 120100 }

		assert.equals("short", Lint.State(record, 120100,
			{ ground = true, flying = false }))
		assert.equals("short", Lint.State(record, 120100,
			{ ground = false, flying = true }))
		assert.equals("full", Lint.State(record, 120100,
			{ ground = true, flying = true }))
	end)
end)

describe("Lint.Summary", function()
	-- Never "0/16" for an outfit nobody has looked at: that reads as broken.
	it("shows no numbers at all for an unmeasured outfit", function()
		assert.equal("--", Lint.Summary(nil, BUILD))
		assert.equal("--", Lint.Summary({ covered = 4, total = 4, at = 110200 }, BUILD))
	end)

	it("shows covered over total", function()
		assert.equal("11/16", Lint.Summary({ covered = 11, total = 16, at = BUILD }, BUILD))
	end)
end)

describe("Lint.MissingLines", function()
	it("says nothing when nothing is missing", function()
		assert.same({}, Lint.MissingLines(nil))
		assert.same({}, Lint.MissingLines({ missing = {} }))
	end)

	it("lists unset slots on one line", function()
		local lines = Lint.MissingLines({ missing = { { name = "Wrist" }, { name = "Waist" } } })
		assert.same({ "Not set: Wrist, Waist" }, lines)
	end)

	-- Two lines, because they are two different things to go and fix.
	it("keeps show-equipped slots apart from unset ones", function()
		local lines = Lint.MissingLines({
			missing = {
				{ name = "Wrist" },
				{ name = "Shield", equipped = true },
			},
		})

		assert.same({ "Not set: Wrist", "Shows equipped gear: Shield" }, lines)
	end)

	it("omits the unset line when only gear-showing slots are missing", function()
		local lines = Lint.MissingLines({ missing = { { name = "Shield", equipped = true } } })
		assert.same({ "Shows equipped gear: Shield" }, lines)
	end)
end)
