local Coverage = require("DonorCoverage")

local function Piece(slot, source, state)
	return { slot = slot, source = source, item = source + 1000, appearance = source + 2000,
		visible = state == "v", held = state == "v" or state == "c", hidden = state == "h" }
end

local TAUREN = { races = { "Tauren" } }

describe("DonorCoverage.ParseRaces", function()
	it("reads the races after the prefix, colour codes stripped", function()
		assert.same({ "Tauren" }, Coverage.ParseRaces("Races: Tauren", "Races: "))
		assert.same({ "Night Elf", "Void Elf" },
			Coverage.ParseRaces("|cffff2020Races: Night Elf, Void Elf|r", "Races: "))
	end)

	it("answers nil for any other line", function()
		assert.is_nil(Coverage.ParseRaces("Classes: Hunter", "Races: "))
		assert.is_nil(Coverage.ParseRaces(nil, "Races: "))
	end)
end)

describe("DonorCoverage.Classify", function()
	it("counts a visible piece as drawn and a look with nothing dropped as full", function()
		local verdict = Coverage.Classify({ Piece(5, 1, "v"), Piece(7, 2, "v") }, {},
			{ race = "Human" })
		assert.is_true(verdict.full)
		assert.equal(2, verdict.drawn)
		assert.equal(2, verdict.asked)
	end)

	it("fails a dropped piece no race lock explains, with its IDs", function()
		local verdict = Coverage.Classify({ Piece(5, 1, "v"), Piece(8, 2, "d") },
			{ [1] = false, [2] = false }, { race = "Human" })
		assert.is_false(verdict.full)
		assert.same({ { slot = 8, source = 2, item = 1002, appearance = 2002 } },
			verdict.failures)
		assert.equal(0, #verdict.excluded)
	end)

	it("excludes a dropped heritage piece of another race and does not fail on it", function()
		local verdict = Coverage.Classify({ Piece(9, 3, "d"), Piece(5, 1, "v") },
			{ [3] = TAUREN, [1] = false }, { race = "Human" })
		assert.is_true(verdict.full)
		assert.equal(1, #verdict.excluded)
		assert.same({ "Tauren" }, verdict.excluded[1].races)
	end)

	it("fails a heritage piece dropped on a body of its own race", function()
		local verdict = Coverage.Classify({ Piece(9, 3, "d") }, { [3] = TAUREN },
			{ race = "Tauren" })
		assert.is_false(verdict.full)
		assert.equal(0, #verdict.excluded)
		assert.same({ "Tauren" }, verdict.failures[1].races)
	end)

	it("fails a dropped piece whose lock was not read, and marks it unread", function()
		local verdict = Coverage.Classify({ Piece(9, 3, "d") }, {}, { race = "Human" })
		assert.is_false(verdict.full)
		assert.is_true(verdict.failures[1].unread)
	end)

	it("counts a held piece that is not visible as covered, not dropped", function()
		local verdict = Coverage.Classify({ Piece(4, 5, "c") }, { [5] = false },
			{ race = "Human" })
		assert.is_true(verdict.full)
		assert.equal(1, verdict.covered)
	end)

	it("leaves weapons and hidden appearances out", function()
		local verdict = Coverage.Classify({ Piece(16, 6, "d"), Piece(17, 7, "d"),
			Piece(1, 8, "h") }, {}, { race = "Human" })
		assert.is_true(verdict.full)
		assert.equal(0, verdict.asked)
	end)
end)

describe("DonorCoverage.Needs", function()
	local look = { id = 1, sex = 3, faction = "Horde", raceFile = "Tauren" }

	it("asks for the sex when no body of it was tried", function()
		local needs = Coverage.Needs(look, { { donor = { sex = 2, faction = "Horde" } } })
		assert.equal(3, needs.sex)
		assert.equal("Horde", needs.faction)
		assert.is_nil(needs.race)
		assert.matches("no woman body", needs.why)
	end)

	it("asks for the faction when only the other faction's bodies were tried", function()
		local needs = Coverage.Needs(look, { { donor = { sex = 3, faction = "Alliance" } } })
		assert.is_nil(needs.race)
		assert.matches("other faction", needs.why)
	end)

	it("asks for the race when a body of its sex and faction failed", function()
		local needs = Coverage.Needs(look, { { donor = { sex = 3, faction = "Horde",
			raceFile = "Orc" } } })
		assert.equal("Tauren", needs.race)
		assert.matches("sex and faction", needs.why)
	end)

	it("says so when even its own race failed", function()
		local needs = Coverage.Needs(look, { { donor = { sex = 3, faction = "Horde",
			raceFile = "Tauren" } } })
		assert.matches("own race", needs.why)
	end)
end)

describe("DonorCoverage.Wanted", function()
	it("groups uncovered looks by what they need, most looks first", function()
		local groups = Coverage.Wanted({
			{ look = 1, needs = { sex = 3, faction = "Horde" } },
			{ look = 2, needs = { sex = 3, faction = "Alliance" } },
			{ look = 3, needs = { sex = 3, faction = "Horde" } },
		})
		assert.equal(2, #groups)
		assert.equal("Horde", groups[1].faction)
		assert.same({ 1, 3 }, groups[1].looks)
	end)
end)

describe("DonorCoverage.RaceFaction", function()
	it("names the faction of both Dracthyr race IDs and nothing for an unknown race", function()
		assert.equal("Alliance", Coverage.RaceFaction(52))
		assert.equal("Horde", Coverage.RaceFaction(70))
		assert.is_nil(Coverage.RaceFaction(999))
	end)
end)

describe("DonorCoverage.SexWord", function()
	it("names both sexes and says when it does not know", function()
		assert.equal("man", Coverage.SexWord(2))
		assert.equal("woman", Coverage.SexWord(3))
		assert.equal("unknown sex", Coverage.SexWord(nil))
	end)
end)
