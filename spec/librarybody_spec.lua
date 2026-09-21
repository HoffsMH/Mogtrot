local LibraryBody = require("LibraryBody")

-- Race 52 is Dracthyr, whose visage is race 75. Race 22 is Worgen, which has a
-- second body but no second race ID, so it is the case that has to fall back
-- to asking for an altered form instead.
local function HasAlternateForm(raceID)
	return raceID == 52 or raceID == 22
end

local function VisageRace(raceID)
	if raceID == 52 then return 75 end
	return nil
end

local function Record(over)
	local record = { raceID = 6, raceFile = "Tauren", sex = 2 }
	for key, value in pairs(over or {}) do record[key] = value end
	return record
end

describe("LibraryBody.Form", function()
	it("shows a record's own race in its native form", function()
		local shown, native = LibraryBody.Form(Record(), HasAlternateForm, VisageRace)
		assert.equal(6, shown)
		assert.is_true(native)
	end)

	it("asks for the visage race rather than altering the viewer", function()
		local shown, native = LibraryBody.Form(
			Record({ raceID = 52, nativeForm = false }), HasAlternateForm, VisageRace)
		assert.equal(75, shown)
		assert.is_true(native)
	end)

	it("alters the form where the second body has no race of its own", function()
		local shown, native = LibraryBody.Form(
			Record({ raceID = 22, nativeForm = false }), HasAlternateForm, VisageRace)
		assert.equal(22, shown)
		assert.is_false(native)
	end)

	-- A stored false for a race with one body reads as "was transformed" and
	-- would render the viewer's alternate form wearing the record.
	it("ignores an altered flag on a race with only one body", function()
		local shown, native = LibraryBody.Form(
			Record({ raceID = 6, nativeForm = false }), HasAlternateForm, VisageRace)
		assert.equal(6, shown)
		assert.is_true(native)
	end)

	it("answers nothing for a record carrying no race", function()
		assert.is_nil(LibraryBody.Form({ raceFile = "Tauren", sex = 2 },
			HasAlternateForm, VisageRace))
		assert.is_nil(LibraryBody.Form(nil, HasAlternateForm, VisageRace))
	end)
end)

describe("LibraryBody.Key", function()
	it("separates two sexes of the same body", function()
		local record = Record()
		assert.not_equal(LibraryBody.Key(record, 6, true, 2),
			LibraryBody.Key(record, 6, true, 3))
	end)

	it("separates the two forms of one race", function()
		local record = Record({ raceID = 22 })
		assert.not_equal(LibraryBody.Key(record, 22, true, 2),
			LibraryBody.Key(record, 22, false, 2))
	end)

	it("keys the ideal from the record's own sex", function()
		local record = Record({ raceID = 52, nativeForm = false })
		assert.equal(LibraryBody.Key(record, 75, true, 2),
			LibraryBody.IdealKey(record, HasAlternateForm, VisageRace))
	end)
end)

describe("LibraryBody.Plan", function()
	local viewer = { raceFile = "Dracthyr", sex = 2, altered = false }

	local function Plan(over)
		local input = {
			record = Record(),
			viewMode = "original",
			fullFidelity = true,
			viewer = viewer,
			hasAlternateForm = HasAlternateForm,
			visageRace = VisageRace,
		}
		for key, value in pairs(over or {}) do input[key] = value end
		return LibraryBody.Plan(input)
	end

	it("shows the record's own body on the original-race view", function()
		local plan = Plan()
		assert.is_true(plan.wantRecordBody)
		assert.is_true(plan.keyed)
		assert.equal("Tauren", plan.tagRace)
		assert.equal(2, plan.tagSex)
	end)

	it("falls to the viewer's body when the wall cannot build every record", function()
		local plan = Plan({ fullFidelity = false })
		assert.is_false(plan.wantRecordBody)
		assert.is_false(plan.keyed)
		assert.equal("Dracthyr", plan.tagRace)
	end)

	it("shows the viewer's body on the my-race view", function()
		assert.is_false(Plan({ viewMode = "mine" }).wantRecordBody)
	end)

	it("never shows a pooled body on a mounted card", function()
		local plan = Plan({ mounted = true })
		assert.is_false(plan.wantRecordBody)
		assert.is_false(plan.keyed)
	end)

	it("tags the alternate-form actor for a record captured in one", function()
		local plan = Plan({ record = Record({ raceID = 52, raceFile = "Dracthyr",
			nativeForm = false }) })
		assert.is_true(plan.altered)
		assert.equal(75, plan.shownRace)
	end)

	it("takes the viewer's own form when showing the viewer's body", function()
		local plan = Plan({ viewMode = "mine",
			viewer = { raceFile = "Dracthyr", sex = 2, altered = true } })
		assert.is_true(plan.altered)
	end)
end)

describe("LibraryBody.CanReuse", function()
	local plan = LibraryBody.Plan({
		record = Record(),
		viewMode = "original",
		fullFidelity = true,
		hasAlternateForm = HasAlternateForm,
		visageRace = VisageRace,
	})

	it("reuses a body carrying exactly the key asked for", function()
		assert.is_true(LibraryBody.CanReuse(plan, plan.idealKey, true))
	end)

	it("refuses a body built for another race, sex or form", function()
		assert.is_false(LibraryBody.CanReuse(plan, "6|true|3|Tauren", true))
		assert.is_false(LibraryBody.CanReuse(plan, nil, true))
	end)

	it("refuses when there is no actor to reuse", function()
		assert.is_false(LibraryBody.CanReuse(plan, plan.idealKey, false))
	end)

	it("reuses nothing while the wall is showing your own race", function()
		local mine = LibraryBody.Plan({
			record = Record(), viewMode = "mine",
			hasAlternateForm = HasAlternateForm, visageRace = VisageRace,
		})
		assert.is_false(LibraryBody.CanReuse(mine, mine.idealKey, true))
	end)
end)
