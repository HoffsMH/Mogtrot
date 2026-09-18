-- Race and sex to a body that renders. Wrong numbers here show the wrong
-- person, so the contract is deliberately strict: an unknown race returns nil
-- and a reason, never a guess.
local RaceBody = require("RaceBody")

describe("RaceBody", function()
	it("uses the UnitSex convention, not the enum", function()
		assert.equal(2, RaceBody.MALE)
		assert.equal(3, RaceBody.FEMALE)
	end)

	it("answers for a core race in both sexes", function()
		assert.equal(55261, RaceBody.Lookup(6, RaceBody.MALE))
		assert.equal(55260, RaceBody.Lookup(6, RaceBody.FEMALE))
	end)

	it("answers for an allied race", function()
		assert.equal(117528, RaceBody.Lookup(29, RaceBody.MALE))
	end)

	it("renders Dracthyr as their visage, both factions alike", function()
		assert.equal(RaceBody.Lookup(52, RaceBody.MALE), RaceBody.Lookup(70, RaceBody.MALE))
		assert.equal(RaceBody.Lookup(52, RaceBody.MALE), RaceBody.Lookup(75, RaceBody.MALE))
	end)

	it("shares one body across the three Pandaren races", function()
		assert.equal(RaceBody.Lookup(24, RaceBody.MALE), RaceBody.Lookup(26, RaceBody.MALE))
	end)

	it("returns nil and a reason for a race it does not know", function()
		local id, why = RaceBody.Lookup(9999, RaceBody.MALE)
		assert.is_nil(id)
		assert.truthy(why:find("9999", 1, true))
	end)

	it("refuses a sex it does not recognise rather than picking one", function()
		local id, why = RaceBody.Lookup(6, 0)
		assert.is_nil(id)
		assert.truthy(why:find("unexpected sex", 1, true))
		assert.is_nil(RaceBody.Lookup(6, nil))
	end)

	it("refuses a missing race ID", function()
		local id, why = RaceBody.Lookup(nil, RaceBody.MALE)
		assert.is_nil(id)
		assert.equal("no race ID", why)
	end)

	it("carries a positive display ID for every entry, both sexes", function()
		local count = 0
		for raceID, entry in pairs(RaceBody.bodies) do
			assert.is_number(raceID)
			for _, key in ipairs({ "male", "female" }) do
				assert.is_number(entry[key], ("race %d has no %s"):format(raceID, key))
				assert.is_true(entry[key] > 0)
			end
			count = count + 1
		end
		assert.is_true(count >= 30)
	end)

	it("never reuses one body across unrelated races", function()
		local seen = {}
		local shared = { [24] = true, [26] = true, [52] = true, [70] = true,
			[75] = true, [76] = true }
		for raceID, entry in pairs(RaceBody.bodies) do
			if not shared[raceID] then
				assert.is_nil(seen[entry.male],
					("race %d reuses a male body"):format(raceID))
				seen[entry.male] = raceID
			end
		end
	end)
end)

describe("RaceBody.HasAlternateForm", function()
	it("knows the races with a second body", function()
		assert.is_true(RaceBody.HasAlternateForm(22))
		assert.is_true(RaceBody.HasAlternateForm(52))
		assert.is_true(RaceBody.HasAlternateForm(70))
		assert.is_true(RaceBody.HasAlternateForm(75))
		assert.is_true(RaceBody.HasAlternateForm(76))
	end)

	it("says no for a race that has only one form", function()
		assert.is_false(RaceBody.HasAlternateForm(2))
		assert.is_false(RaceBody.HasAlternateForm(1))
		assert.is_false(RaceBody.HasAlternateForm(6))
	end)

	it("says no rather than erroring on a race it does not know", function()
		assert.is_false(RaceBody.HasAlternateForm(nil))
		assert.is_false(RaceBody.HasAlternateForm(9999))
		assert.is_false(RaceBody.HasAlternateForm("worgen"))
	end)
end)

describe("RaceBody.VisageRace", function()
	it("maps each Dracthyr race to its visage race", function()
		assert.equal(75, RaceBody.VisageRace(52))
		assert.equal(76, RaceBody.VisageRace(70))
	end)

	it("has no second race for a Worgen, whose human form shares race 22", function()
		assert.is_nil(RaceBody.VisageRace(22))
	end)

	it("answers nothing for a race with one body", function()
		assert.is_nil(RaceBody.VisageRace(2))
		assert.is_nil(RaceBody.VisageRace(nil))
	end)

	it("keeps a body for every visage race it names", function()
		for _, visage in pairs(RaceBody.visageRaces) do
			assert.is_number(RaceBody.Lookup(visage, RaceBody.MALE))
			assert.is_number(RaceBody.Lookup(visage, RaceBody.FEMALE))
		end
	end)
end)
