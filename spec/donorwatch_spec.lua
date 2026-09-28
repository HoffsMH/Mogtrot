local Watch = require("DonorWatch")

local MAN, WOMAN = 2, 3

-- The last check before a passive donor's facts are taken.
describe("DonorWatch.Refusal", function()
	local ready = { exists = true, isPlayer = true, ready = true }

	it("accepts a ready player who is not you", function()
		assert.is_nil(Watch.Refusal(ready))
	end)

	it("refuses no unit, a non-player, you, a secret identity and a model not ready", function()
		assert.matches("target a player", Watch.Refusal({}))
		assert.matches("not a player", Watch.Refusal({ exists = true }))
		assert.matches("that is you", Watch.Refusal({ exists = true, isPlayer = true,
			isSelf = true, ready = true }))
		assert.matches("secret", Watch.Refusal({ exists = true, isPlayer = true,
			secret = true, ready = true }))
		assert.matches("not loaded", Watch.Refusal({ exists = true, isPlayer = true }))
		assert.matches("combat", Watch.Refusal({ exists = true, isPlayer = true,
			ready = true, combat = true }))
	end)
end)

describe("DonorWatch.EventUnits", function()
	it("names the unit each event is about", function()
		assert.same({ "target" }, Watch.EventUnits("PLAYER_TARGET_CHANGED"))
		assert.same({ "mouseover" }, Watch.EventUnits("UPDATE_MOUSEOVER_UNIT"))
		assert.same({ "nameplate7" }, Watch.EventUnits("NAME_PLATE_UNIT_ADDED", "nameplate7"))
	end)

	it("walks party and raid on a roster change", function()
		local units = Watch.EventUnits("GROUP_ROSTER_UPDATE")
		assert.equal("party1", units[1])
		assert.equal(44, #units)
		assert.equal("raid40", units[44])
	end)

	it("looks at everything on a rescan, and at nothing for other events", function()
		local units = Watch.EventUnits("rescan")
		assert.equal("target", units[1])
		assert.equal("mouseover", units[2])
		assert.equal(46, #units)
		assert.same({}, Watch.EventUnits("UNIT_AURA"))
	end)
end)

describe("DonorWatch.Accepts", function()
	local held
	local ready

	before_each(function()
		held = { guids = {}, classes = {} }
		ready = { exists = true, isPlayer = true, ready = true, sex = WOMAN, viewerSex = MAN,
			guid = "G1", raceID = 10, raceFile = "BloodElf", faction = "Horde" }
	end)

	local function With(change)
		local facts = {}
		for k, v in pairs(ready) do facts[k] = v end
		for k, v in pairs(change) do facts[k] = v end
		return facts
	end

	-- What DonorWatchUI does with each yes: the donor and its key count as
	-- held from the moment it is queued.
	local function Take(facts)
		local ok, why = Watch.Accepts(facts, held)
		if ok then
			held.guids[facts.guid] = true
			held.classes[Watch.ClassKey(facts.sex, facts.faction, facts.raceID)] = true
		end
		return ok, why
	end

	it("takes a ready player of the other sex whose body is new, with no list of needs", function()
		assert.is_true((Watch.Accepts(ready, held)))
	end)

	it("takes several players in a row, each with a new race, sex or faction", function()
		assert.is_true((Take(ready)))
		assert.is_true((Take(With({ guid = "G2", raceID = 2, raceFile = "Orc" }))))
		assert.is_true((Take(With({ guid = "G3", raceID = 10, faction = "Alliance" }))))
		assert.is_true((Take(With({ guid = "G4", raceID = 4, raceFile = "NightElf",
			faction = "Alliance" }))))
	end)

	it("skips a second player of a race, sex and faction already held", function()
		assert.is_true((Take(ready)))
		local ok, why = Take(With({ guid = "G2" }))
		assert.is_false(ok)
		assert.matches("like", why)
	end)

	it("never waits for another donor to finish building", function()
		held.building = true
		assert.is_true((Watch.Accepts(ready, held)))
	end)

	it("waits out combat, instances and an unloaded model", function()
		for _, change in ipairs({ { combat = true }, { instance = true }, { ready = false } }) do
			local ok, _, retry = Watch.Accepts(With(change), held)
			assert.is_false(ok)
			assert.is_true(retry)
		end
	end)

	it("refuses for good anyone who is not a usable stranger", function()
		local cases = {
			{ exists = false }, { isPlayer = false }, { isSelf = true }, { secret = true },
			{ sex = 1 }, { sex = MAN }, { guid = false },
		}
		for _, change in ipairs(cases) do
			local facts = With(change)
			if facts.guid == false then facts.guid = nil end
			local ok, _, retry = Watch.Accepts(facts, held)
			assert.is_false(ok)
			assert.is_falsy(retry)
		end
	end)

	it("skips a donor already held", function()
		held.guids.G1 = true
		assert.is_false((Watch.Accepts(ready, held)))
	end)

	it("takes nobody while the body pool has no room", function()
		held.full = true
		local ok, why = Watch.Accepts(ready, held)
		assert.is_false(ok)
		assert.matches("room", why)
	end)
end)

describe("DonorWatch.SearchUnits", function()
	it("asks the token it came from first, then every token that can name a player", function()
		local units = Watch.SearchUnits("nameplate7")
		assert.equal("nameplate7", units[1])
		assert.equal("target", units[2])
		assert.equal("mouseover", units[3])
		local seen = {}
		for _, unit in ipairs(units) do
			assert.is_nil(seen[unit])
			seen[unit] = true
		end
		assert.is_true(seen.nameplate40)
		assert.is_true(seen.raid40)
		assert.is_true(seen.party4)
	end)
end)

describe("DonorWatch.BuildStep", function()
	local build

	before_each(function()
		build = { total = 3, done = 0 }
	end)

	local function Facts(change)
		local facts = { now = 10, token = "mouseover", ready = true }
		for k, v in pairs(change or {}) do facts[k] = v end
		return facts
	end

	it("builds one step on whichever token names the donor now", function()
		local action, token = Watch.BuildStep(build, Facts({ token = "nameplate3" }))
		assert.equal("build", action)
		assert.equal("nameplate3", token)
	end)

	it("finishes when every step is built", function()
		build.done = 3
		assert.equal("finish", (Watch.BuildStep(build, Facts({ combat = true }))))
	end)

	it("waits in combat and while the model loads", function()
		assert.equal("wait", (Watch.BuildStep(build, Facts({ combat = true }))))
		assert.equal("wait", (Watch.BuildStep(build, Facts({ ready = false }))))
	end)

	it("abandons on entering an instance, even half built", function()
		build.done = 2
		assert.equal("abandon", (Watch.BuildStep(build, Facts({ instance = true }))))
	end)

	it("waits a moment when no token names the donor, then abandons", function()
		assert.equal("wait", (Watch.BuildStep(build, Facts({ token = false, now = 10 }))))
		assert.equal("wait", (Watch.BuildStep(build, Facts({ token = false, now = 12 }))))
		assert.equal("build", (Watch.BuildStep(build, Facts({ now = 13 }))))
		assert.equal("wait", (Watch.BuildStep(build, Facts({ token = false, now = 14 }))))
		local action, why = Watch.BuildStep(build, Facts({ token = false,
			now = 14 + Watch.LOST_GRACE }))
		assert.equal("abandon", action)
		assert.matches("reach", why)
	end)
end)
