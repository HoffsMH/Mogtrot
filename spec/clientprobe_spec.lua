-- The probe exists because the pinned Blizzard source can lag the live build,
-- so its job is to report what is there rather than assert what should be.
-- These cover the reporting contract; the lookups themselves are the caller's.
local ClientProbe = require("ClientProbe")

describe("ClientProbe", function()
	describe("Presence", function()
		it("splits candidates into present and absent", function()
			local present, absent = ClientProbe.Presence({ "b", "a", "c" }, function(name)
				return name == "a" or name == "c"
			end)
			assert.same({ "a", "c" }, present)
			assert.same({ "b" }, absent)
		end)

		it("sorts both sides so two builds diff as plain text", function()
			local present = ClientProbe.Presence({ "z", "m", "a" }, function() return true end)
			assert.same({ "a", "m", "z" }, present)
		end)

		it("calls everything absent when there is no lookup", function()
			local present, absent = ClientProbe.Presence({ "a", "b" }, nil)
			assert.same({}, present)
			assert.same({ "a", "b" }, absent)
		end)

		it("survives an empty candidate list", function()
			local present, absent = ClientProbe.Presence(nil, function() return true end)
			assert.same({}, present)
			assert.same({}, absent)
		end)
	end)

	describe("method groups", function()
		it("asks about the calls that decide body fidelity", function()
			local body = {}
			for _, name in ipairs(ClientProbe.WIDGET_METHODS.body) do body[name] = true end
			assert.is_true(body.SetCustomRace)
			assert.is_true(body.SetRaceGenderOptions)
			assert.is_true(body.SetModelByUnit)
			assert.is_true(body.GetDisplayInfo)
		end)

		it("enumerates namespaces rather than guessing their contents", function()
			local seen = {}
			for _, name in ipairs(ClientProbe.NAMESPACES) do seen[name] = true end
			assert.is_true(seen.C_BarberShop)
			assert.is_true(seen.C_PlayerInfo)
			assert.is_true(seen.C_TransmogSets)
		end)
	end)

	describe("Lines", function()
		local function Findings()
			return {
				build = "12.1.0",
				widgets = { {
					name = "DressUpModel",
					has = function(method) return method == "SetUnit" end,
				} },
				namespaces = {
					{ name = "C_BarberShop", functions = { GetAvailableCustomizations = true } },
					{ name = "C_CharacterCustomization", functions = false },
				},
				units = { { label = "player", fields = { { "race", "Human" }, { "sex", 2 } } } },
				calls = { { "C_BarberShop.GetAvailableCustomizations()", "nil" } },
			}
		end

		local function Joined(findings)
			return table.concat(ClientProbe.Lines(findings), "\n")
		end

		it("reports a present method and a missing one", function()
			local text = Joined(Findings())
			assert.truthy(text:find("body present (1): SetUnit", 1, true))
			assert.truthy(text:find("SetCustomRace", 1, true))
			assert.truthy(text:find("body MISSING", 1, true))
		end)

		it("names an absent namespace instead of leaving it out", function()
			local text = Joined(Findings())
			assert.truthy(text:find("namespace C_CharacterCustomization", 1, true))
			assert.truthy(text:find("absent", 1, true))
		end)

		it("lists namespace functions sorted", function()
			local text = Joined({ namespaces = { {
				name = "C_Thing", functions = { Zed = true, Alpha = true },
			} } })
			assert.truthy(text:find("functions (2): Alpha Zed", 1, true))
		end)

		it("carries unit fields and call results", function()
			local text = Joined(Findings())
			assert.truthy(text:find("race = Human", 1, true))
			assert.truthy(text:find("sex = 2", 1, true))
			assert.truthy(text:find("-> nil", 1, true))
		end)

		it("says so when a widget could not be created", function()
			local text = Joined({ widgets = { { name = "ModelScene", has = false } } })
			assert.truthy(text:find("could not be created", 1, true))
		end)

		it("produces a report from nothing without erroring", function()
			local lines = ClientProbe.Lines(nil)
			assert.is_true(#lines >= 2)
			assert.truthy(lines[2]:find("unknown", 1, true))
		end)
	end)
end)

describe("ClientProbe try-on tallies", function()
	it("names each reason the client can return", function()
		assert.equal("ok", ClientProbe.TRY_ON_REASON[0])
		assert.equal("wrongRace", ClientProbe.TRY_ON_REASON[1])
		assert.equal("notEquippable", ClientProbe.TRY_ON_REASON[2])
		assert.equal("pending", ClientProbe.TRY_ON_REASON[3])
	end)

	it("counts slots by reason rather than by call", function()
		local tally, retryable, total = ClientProbe.TryOnTally({
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
		local _, retryable = ClientProbe.TryOnTally({ [1] = 1, [2] = 2, [3] = 0 })
		assert.equal(0, retryable)
	end)

	it("keeps an unknown reason visible instead of dropping it", function()
		local tally = ClientProbe.TryOnTally({ [1] = 9 })
		assert.equal(1, tally["reason 9"])
	end)

	it("orders tally text by count, then name", function()
		assert.equal("ok=3 pending=2 wrongRace=1",
			ClientProbe.TallyText({ ok = 3, pending = 2, wrongRace = 1 }))
	end)

	it("says so when nothing applied", function()
		assert.equal("nothing applied", ClientProbe.TallyText({}))
		assert.equal("nothing applied", ClientProbe.TallyText(nil))
	end)

	it("survives an empty result set", function()
		local tally, retryable, total = ClientProbe.TryOnTally(nil)
		assert.same({}, tally)
		assert.equal(0, retryable)
		assert.equal(0, total)
	end)
end)
