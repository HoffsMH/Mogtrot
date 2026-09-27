require("DonorCoverage")
local Watch = require("DonorWatch")

local MAN, WOMAN = 2, 3
local NE_W = "4|true|3|NightElf"
local BE_W = "10|true|3|BloodElf"
local DR_M = "52|true|2|Dracthyr"

local YOU = { id = "self", self = true, sex = MAN, faction = "Alliance", raceFile = "Dracthyr",
	raceID = 52 }

local function Look(id, sex, faction, raceFile, key, archived)
	return { id = id, sex = sex, faction = faction, raceFile = raceFile, key = key,
		archived = archived }
end

local function Donor(id, sex, faction, raceFile, raceID, keys)
	local set = {}
	for _, key in ipairs(keys or {}) do set[key] = true end
	return { id = id, sex = sex, faction = faction, raceFile = raceFile, raceID = raceID,
		keys = set }
end

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
		held = { guids = {}, classes = {}, needs = { { sex = WOMAN } } }
		ready = { exists = true, isPlayer = true, ready = true, sex = WOMAN, viewerSex = MAN,
			guid = "G1", raceID = 10, raceFile = "BloodElf", faction = "Horde" }
	end)

	local function With(change)
		local facts = {}
		for k, v in pairs(ready) do facts[k] = v end
		for k, v in pairs(change) do facts[k] = v end
		return facts
	end

	it("takes a ready player of the other sex who meets a need", function()
		assert.is_true((Watch.Accepts(ready, held)))
	end)

	it("waits out combat, instances, an unloaded model and another donor building", function()
		for _, change in ipairs({ { combat = true }, { instance = true }, { ready = false } }) do
			local ok, _, retry = Watch.Accepts(With(change), held)
			assert.is_false(ok)
			assert.is_true(retry)
		end
		held.building = true
		local ok, why, retry = Watch.Accepts(ready, held)
		assert.is_false(ok)
		assert.matches("being built", why)
		assert.is_true(retry)
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

	it("skips a donor already held and a body like one already held", function()
		held.guids.G1 = true
		assert.is_false((Watch.Accepts(ready, held)))
		held.guids.G1 = nil
		held.classes[Watch.ClassKey(WOMAN, "Horde", 10)] = true
		local ok, why = Watch.Accepts(ready, held)
		assert.is_false(ok)
		assert.matches("like", why)
		assert.is_true((Watch.Accepts(With({ raceID = 2, raceFile = "Orc" }), held)))
	end)

	it("takes only someone who meets a need, and nobody once there are none", function()
		held.needs = {}
		local ok, why = Watch.Accepts(ready, held)
		assert.is_false(ok)
		assert.matches("no body like", why)
		held.needs = { { sex = WOMAN, faction = "Alliance" } }
		assert.is_false((Watch.Accepts(ready, held)))
		held.needs = { { sex = WOMAN, faction = "Horde", race = "Orc" } }
		assert.is_false((Watch.Accepts(ready, held)))
		held.needs[2] = { sex = WOMAN, faction = "Horde", race = "BloodElf" }
		assert.is_true((Watch.Accepts(ready, held)))
	end)

	it("has no cap on how many donors a session takes", function()
		held.count, held.cap = 8, 8
		assert.is_true((Watch.Accepts(ready, held)))
	end)
end)

describe("DonorWatch.Needs", function()
	local woman = Donor("w", WOMAN, "Horde", "BloodElf", 10, { NE_W, BE_W })

	local function Input(looks, bodies, tried, extra)
		local input = { looks = looks, bodies = bodies, tried = tried or {}, pending = {},
			viewerSex = MAN, pooled = { [NE_W] = { w = true }, [BE_W] = { w = true } } }
		for k, v in pairs(extra or {}) do input[k] = v end
		return input
	end

	it("starts coarse: any body of each other sex a live look has", function()
		local needs = Watch.Needs(Input({ Look(1, MAN, "Alliance", "Dracthyr", DR_M),
			Look(2, WOMAN, "Alliance", "NightElf", NE_W), Look(3, WOMAN, "Horde", "BloodElf", BE_W),
			Look(4, WOMAN, "Alliance", "NightElf", NE_W, true) }, { YOU }))
		assert.same({ { sex = WOMAN } }, needs)
	end)

	it("needs nothing of your own sex, archived looks, or an empty library", function()
		assert.same({}, Watch.Needs(Input({ Look(1, MAN, "Horde", "Orc", "2|true|2|Orc"),
			Look(4, WOMAN, "Alliance", "NightElf", NE_W, true) }, { YOU })))
		assert.same({}, Watch.Needs(Input({}, { YOU })))
	end)

	it("wants nobody of a sex while a donor of it is still building", function()
		local needs, blocked = Watch.Needs(Input({ Look(2, WOMAN, "Alliance", "NightElf", NE_W) },
			{ YOU }, {}, { building = { { sex = WOMAN, faction = "Horde" } } }))
		assert.same({}, needs)
		assert.is_true(blocked[WOMAN])
	end)

	it("wants nobody of a sex while its looks are being checked on a held donor", function()
		local needs, blocked = Watch.Needs(Input({ Look(2, WOMAN, "Alliance", "NightElf", NE_W),
			Look(3, WOMAN, "Horde", "BloodElf", BE_W) }, { YOU, woman },
			{ [3] = { w = { full = true } } }))
		assert.same({}, needs)
		assert.is_true(blocked[WOMAN])
	end)

	it("turns uncovered looks into precise needs once the checks are done", function()
		local needs = Watch.Needs(Input({ Look(2, WOMAN, "Alliance", "NightElf", NE_W),
			Look(5, WOMAN, "Alliance", "NightElf", NE_W), Look(3, WOMAN, "Horde", "BloodElf", BE_W),
			Look(6, WOMAN, "Horde", "Orc", BE_W) }, { YOU, woman },
			{ [2] = { w = { full = false } }, [5] = { w = { full = false } },
				[3] = { w = { full = true } }, [6] = { w = { full = false } } }))
		assert.same({ { sex = WOMAN, faction = "Alliance" },
			{ sex = WOMAN, faction = "Horde", race = "Orc" } }, needs)
	end)

	it("needs nothing once every live look is covered, until a new look fails", function()
		local looks = { Look(3, WOMAN, "Horde", "BloodElf", BE_W) }
		local tried = { [3] = { w = { full = true } } }
		assert.same({}, (Watch.Needs(Input(looks, { YOU, woman }, tried))))
		looks[2] = Look(7, WOMAN, "Horde", "Troll", BE_W)
		local needs, blocked = Watch.Needs(Input(looks, { YOU, woman }, tried))
		assert.same({}, needs)
		assert.is_true(blocked[WOMAN])
		tried[7] = { w = { full = false } }
		assert.same({ { sex = WOMAN, faction = "Horde", race = "Troll" } },
			(Watch.Needs(Input(looks, { YOU, woman }, tried))))
	end)
end)

describe("DonorWatch.Meets", function()
	it("matches sex, then faction and race only when the need names them", function()
		local facts = { sex = WOMAN, faction = "Horde", raceFile = "Orc" }
		assert.is_true(Watch.Meets({ sex = WOMAN }, facts))
		assert.is_true(Watch.Meets({ sex = WOMAN, faction = "Horde" }, facts))
		assert.is_true(Watch.Meets({ sex = WOMAN, faction = "Horde", race = "Orc" }, facts))
		assert.is_false(Watch.Meets({ sex = MAN }, facts))
		assert.is_false(Watch.Meets({ sex = WOMAN, faction = "Alliance" }, facts))
		assert.is_false(Watch.Meets({ sex = WOMAN, race = "Troll" }, facts))
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

describe("DonorWatch.Eligible", function()
	it("offers only your own body for a look of your sex", function()
		local bodies = { YOU, Donor("m", MAN, "Horde", "Orc", 2, { DR_M }) }
		local list = Watch.Eligible(Look(1, MAN, "Horde", "Orc", "2|true|2|Orc"), bodies, MAN)
		assert.equal(1, #list)
		assert.equal("self", list[1].id)
	end)

	it("offers donors of the look's sex holding its key, own race then faction first", function()
		local any = Donor("any", WOMAN, "Horde", "Orc", 2, { NE_W })
		local faction = Donor("faction", WOMAN, "Alliance", "Human", 1, { NE_W })
		local race = Donor("race", WOMAN, "Alliance", "NightElf", 4, { NE_W })
		local nokey = Donor("nokey", WOMAN, "Alliance", "NightElf", 4, { BE_W })
		local list = Watch.Eligible(Look(1, WOMAN, "Alliance", "NightElf", NE_W),
			{ YOU, any, faction, nokey, race }, MAN)
		assert.same({ "race", "faction", "any" }, { list[1].id, list[2].id, list[3].id })
		assert.equal(3, #list)
	end)
end)

describe("DonorWatch.NextPairs", function()
	local woman = Donor("w", WOMAN, "Alliance", "Human", 1, { NE_W, BE_W })

	it("pairs each unsettled live look with its best untried body", function()
		local looks = { Look(1, MAN, "Alliance", "Dracthyr", DR_M), Look(2, WOMAN, "Alliance",
			"NightElf", NE_W), Look(3, WOMAN, "Horde", "BloodElf", BE_W, true) }
		local pairs = Watch.NextPairs({ looks = looks, bodies = { YOU, woman }, tried = {},
			pending = {}, busy = {}, viewerSex = MAN, limit = 5 })
		assert.same({ { look = 1, body = "self" }, { look = 2, body = "w" } }, pairs)
	end)

	it("leaves out covered, pending and tried pairs, busy bodies, and stops at the limit", function()
		local looks = { Look(1, MAN, "Alliance", "Dracthyr", DR_M),
			Look(2, WOMAN, "Alliance", "NightElf", NE_W),
			Look(3, WOMAN, "Alliance", "NightElf", NE_W),
			Look(4, WOMAN, "Horde", "BloodElf", BE_W) }
		local out = Watch.NextPairs({ looks = looks, bodies = { YOU, woman },
			tried = { [1] = { self = { full = true } } }, pending = { [2] = true },
			busy = { ["w|" .. NE_W] = true }, viewerSex = MAN, limit = 5 })
		assert.same({ { look = 4, body = "w" } }, out)
		out = Watch.NextPairs({ looks = looks, bodies = { YOU, woman }, tried = {},
			pending = {}, busy = {}, viewerSex = MAN, limit = 1 })
		assert.equal(1, #out)
	end)

	it("takes one pair per body key at a time", function()
		local looks = { Look(2, WOMAN, "Alliance", "NightElf", NE_W),
			Look(3, WOMAN, "Alliance", "NightElf", NE_W) }
		local out = Watch.NextPairs({ looks = looks, bodies = { YOU, woman }, tried = {},
			pending = {}, busy = {}, viewerSex = MAN, limit = 5 })
		assert.equal(1, #out)
	end)
end)

describe("DonorWatch.Status", function()
	local woman = Donor("w", WOMAN, "Alliance", "Human", 1, { NE_W, BE_W })
	local horde = Donor("h", WOMAN, "Horde", "BloodElf", 10, { NE_W, BE_W })

	local function Input(looks, bodies, tried, extra)
		local input = { looks = looks, bodies = bodies, tried = tried or {}, pending = {},
			viewerSex = MAN, pooled = { [NE_W] = { w = true, h = true },
				[BE_W] = { w = true, h = true } } }
		for k, v in pairs(extra or {}) do input[k] = v end
		return input
	end

	it("offers original race when every live look has a covering body", function()
		local out = Watch.Status(Input({ Look(1, MAN, "Alliance", "Dracthyr", DR_M),
			Look(2, WOMAN, "Alliance", "NightElf", NE_W) }, { YOU, woman },
			{ [1] = { self = { full = true } }, [2] = { w = true and { full = true } } }))
		assert.is_true(out.offered)
		assert.equal("w", out.coveredBy[2][1])
		assert.equal("self", out.coveredBy[1][1])
	end)

	it("leaves out archived looks and looks that drop pieces on their own race", function()
		local out = Watch.Status(Input({ Look(1, MAN, "Alliance", "Dracthyr", DR_M),
			Look(99, MAN, "Alliance", "Dracthyr", DR_M),
			Look(775, WOMAN, "Alliance", "NightElf", NE_W, true) }, { YOU },
			{ [1] = { self = { full = true } }, [99] = { self = { full = false } } }))
		assert.is_true(out.offered)
		assert.same({ 99 }, out.known)
	end)

	it("counts a donor-covered look only while that donor has a card body of its key", function()
		local input = Input({ Look(2, WOMAN, "Alliance", "NightElf", NE_W) }, { YOU, woman },
			{ [2] = { w = { full = true } } })
		input.pooled = {}
		local out = Watch.Status(input)
		assert.is_false(out.offered)
		assert.equal(1, out.noRoom)
		assert.matches("no free body", out.text)
	end)

	it("says checking while an eligible body is untried or a pair is in flight", function()
		local out = Watch.Status(Input({ Look(1, MAN, "Alliance", "Dracthyr", DR_M),
			Look(2, WOMAN, "Alliance", "NightElf", NE_W) }, { YOU, woman }, {},
			{ pending = { [2] = true } }))
		assert.is_false(out.offered)
		assert.equal(2, out.checking)
		assert.equal("Original race: checking 2 looks", out.text)
	end)

	it("names the body a look needs, by sex and faction", function()
		local out = Watch.Status(Input({ Look(2, WOMAN, "Alliance", "NightElf", NE_W),
			Look(3, WOMAN, "Horde", "BloodElf", BE_W), Look(4, WOMAN, "Horde", "Orc", BE_W) },
			{ YOU }))
		assert.equal("Original race needs a Horde woman for 2 looks and an Alliance woman"
			.. " for 1 look", out.text)
	end)

	it("names the race when a body of the look's sex and faction dropped pieces", function()
		local out = Watch.Status(Input({ Look(2, WOMAN, "Alliance", "NightElf", NE_W) },
			{ YOU, woman }, { [2] = { w = { full = false } } }))
		assert.equal("Original race needs a night elf woman for 1 look", out.text)
	end)

	it("asks for the other faction when only one faction's body was tried", function()
		local out = Watch.Status(Input({ Look(775, WOMAN, "Alliance", "NightElf", NE_W) },
			{ YOU, horde }, { [775] = { h = { full = false } } }))
		assert.equal("Original race needs an Alliance woman for 1 look", out.text)
	end)

	it("says when a look of your sex drops pieces on your own body", function()
		local out = Watch.Status(Input({ Look(5, MAN, "Horde", "Orc", "2|true|2|Orc") },
			{ YOU }, { [5] = { self = { full = false } } }))
		assert.equal(1, out.dropsOnYou)
		assert.equal("Original race: 1 look drops pieces on your body", out.text)
	end)

	it("joins needs and checking, and says when checks are paused", function()
		local out = Watch.Status(Input({ Look(1, MAN, "Alliance", "Dracthyr", DR_M),
			Look(3, WOMAN, "Horde", "BloodElf", BE_W) }, { YOU }, {},
			{ paused = "in combat" }))
		assert.equal("Original race needs a Horde woman for 1 look; checking 1 look"
			.. " (checks paused in combat)", out.text)
	end)

	it("offers nothing on an empty library", function()
		local out = Watch.Status(Input({}, { YOU }))
		assert.is_false(out.offered)
	end)
end)

describe("DonorWatch.RaceWord", function()
	it("reads a race file as words", function()
		assert.equal("night elf", Watch.RaceWord("NightElf"))
		assert.equal("undead", Watch.RaceWord("Scourge"))
		assert.equal("mag'har orc", Watch.RaceWord("MagharOrc"))
		assert.equal("human", Watch.RaceWord("Human"))
		assert.is_nil(Watch.RaceWord(nil))
	end)
end)
