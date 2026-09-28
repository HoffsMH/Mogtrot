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

	-- Original race is offered from the first borrowed body; a card whose
	-- shape nobody has lent yet stays on you rather than showing text.
	it("keeps a look of the other sex on the viewer's body until its shape is held", function()
		local woman = Record({ sex = 3 })
		local plan = Plan({ record = woman, bodyHeld = false })
		assert.is_false(plan.wantRecordBody)
		assert.equal("Dracthyr", plan.tagRace)
		assert.is_true(Plan({ record = woman, bodyHeld = true }).wantRecordBody)
		assert.is_true(Plan({ bodyHeld = false }).wantRecordBody)
	end)

	it("shows the viewer's body on the my-race view", function()
		assert.is_false(Plan({ viewMode = "mine" }).wantRecordBody)
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

describe("LibraryBody.PopupBody", function()
	local function Input(over)
		local input = { hasLook = true, live = false, pooled = false,
			recordSex = 3, viewerSex = 2 }
		for key, value in pairs(over or {}) do input[key] = value end
		return input
	end

	it("draws the snapped player's own body when it is live", function()
		assert.equal("live", LibraryBody.PopupBody(Input({ live = true })))
		assert.equal("live", LibraryBody.PopupBody(Input({ live = true, pooled = true })))
	end)

	it("draws the record's race on your body when the sexes agree", function()
		assert.equal("own", LibraryBody.PopupBody(Input({ recordSex = 2 })))
	end)

	it("uses a borrowed body of the record's own shape for the other sex", function()
		assert.equal("pool", LibraryBody.PopupBody(Input({ pooled = true })))
	end)

	-- Your own body would be the wrong sex, which is worse than no body.
	it("shows text only for the other sex with nothing borrowed", function()
		assert.is_nil(LibraryBody.PopupBody(Input()))
	end)

	it("shows text only when the sex is unknown or there is no look", function()
		assert.is_nil(LibraryBody.PopupBody({ hasLook = true, viewerSex = 2 }))
		assert.is_nil(LibraryBody.PopupBody({ hasLook = true, recordSex = 2 }))
		assert.is_nil(LibraryBody.PopupBody(Input({ hasLook = false, live = true })))
	end)
end)

-- SetModelByUnit takes no sex override, so a body built on your unit is your
-- sex whatever the record says.
describe("LibraryBody.Donor", function()
	it("builds from the donor found", function()
		assert.equal("mouseover", LibraryBody.Donor("mouseover", 3, 2))
	end)

	it("builds from you when your sex is the record's", function()
		assert.equal("player", LibraryBody.Donor(nil, 2, 2))
	end)

	it("builds from you when the record's sex is unknown", function()
		assert.equal("player", LibraryBody.Donor(nil, nil, 2))
	end)

	it("builds nothing for the other sex with nobody to borrow from", function()
		assert.is_nil(LibraryBody.Donor(nil, 3, 2))
		assert.is_nil(LibraryBody.Donor(nil, 3, nil))
	end)
end)

describe("LibraryBody.Shortfall", function()
	it("counts nothing when every card has a body", function()
		assert.same({ 0, 0 }, { LibraryBody.Shortfall({ "a", "b" }, { a = 1, b = 1 }) })
	end)

	-- The shapes count is forgiving: one body proves the shape can be built.
	-- The cards count is what "still need one" reports.
	it("counts a second card of a built shape as a card, not a shape", function()
		assert.same({ 0, 1 }, { LibraryBody.Shortfall({ "a", "a" }, { a = 1 }) })
	end)

	it("counts each card of an unbuilt shape in both", function()
		assert.same({ 2, 2 }, { LibraryBody.Shortfall({ "a", "a" }, {}) })
	end)

	it("leaves the supply it was given alone", function()
		local supply = { a = 1 }
		LibraryBody.Shortfall({ "a" }, supply)
		assert.equal(1, supply.a)
	end)
end)

describe("LibraryBody.NoBodyText", function()
	it("names who to point at, and no debug command", function()
		assert.matches("a woman", LibraryBody.NoBodyText(3))
		assert.matches("seen a woman", LibraryBody.NoBodyText(3))
		assert.matches("target or group with one", LibraryBody.NoBodyText(3))
		assert.is_nil(LibraryBody.NoBodyText(3):find("body", 1, true))
		assert.is_nil(LibraryBody.NoBodyText(3):find("/mogtrot", 1, true))
		assert.matches("a man", LibraryBody.NoBodyText(2))
		assert.is_string(LibraryBody.NoBodyText(nil))
	end)
end)

describe("LibraryBody.DonorRank", function()
	local record = { raceID = 4, faction = "Alliance" }

	it("ranks the record's own race above its faction, and both above any", function()
		local race = LibraryBody.DonorRank({ donorRace = 4, donorFaction = "Horde" }, record)
		local faction = LibraryBody.DonorRank({ donorRace = 1, donorFaction = "Alliance" }, record)
		local any = LibraryBody.DonorRank({ donorRace = 10, donorFaction = "Horde" }, record)
		local both = LibraryBody.DonorRank({ donorRace = 4, donorFaction = "Alliance" }, record)
		assert.is_true(both > race)
		assert.is_true(race > faction)
		assert.is_true(faction > any)
	end)

	it("ranks on race and faction alone, with no background verdicts to wait for", function()
		local entry = { donorGUID = "G2", donorRace = 10, donorFaction = "Horde" }
		assert.equal(LibraryBody.DonorRank(entry, record),
			LibraryBody.DonorRank(entry, record, { G2 = true }))
	end)

	it("ranks nothing it cannot read", function()
		assert.equal(0, LibraryBody.DonorRank(nil, record))
		assert.equal(0, LibraryBody.DonorRank({}, {}))
	end)
end)

-- A body that arrives while the wall is up is put on the cards it improves,
-- without redrawing the rest.
describe("LibraryBody.WantsRepaint", function()
	local arrived = { k = true }

	it("repaints a card of an arrived shape that holds no body of it", function()
		assert.is_true(LibraryBody.WantsRepaint(nil, "k", arrived, 1, 0))
		assert.is_true(LibraryBody.WantsRepaint("other", "k", arrived, 1, 0))
	end)

	it("repaints a card only when the new body outranks the one it holds", function()
		assert.is_true(LibraryBody.WantsRepaint("k", "k", arrived, 3, 1))
		assert.is_false(LibraryBody.WantsRepaint("k", "k", arrived, 1, 1))
	end)

	it("leaves every card whose shape did not arrive", function()
		assert.is_false(LibraryBody.WantsRepaint(nil, "j", arrived, 3, 0))
		assert.is_false(LibraryBody.WantsRepaint(nil, nil, arrived, 3, 0))
	end)
end)
