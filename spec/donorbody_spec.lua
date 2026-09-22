-- Borrowing a living body when a stored look is the other sex.
local DonorBody = require("DonorBody")

describe("DonorBody", function()
	-- read(token) -> exists, isPlayer, sex
	local function World(units)
		return function(token)
			local unit = units[token]
			if not unit then return false end
			return true, unit.isPlayer ~= false, unit.sex, unit.race
		end
	end

	describe("Tokens", function()
		it("looks at your own body first", function()
			assert.equal("player", DonorBody.Tokens()[1])
		end)

		it("prefers someone you are pointing at over the crowd", function()
			local tokens = DonorBody.Tokens()
			local position = {}
			for index, token in ipairs(tokens) do position[token] = index end
			assert.is_true(position.target < position.party1)
			assert.is_true(position.party1 < position.nameplate1)
		end)

		it("covers the whole nameplate range, which runs to 150", function()
			local seen = {}
			for _, token in ipairs(DonorBody.Tokens()) do seen[token] = true end
			assert.is_true(seen.nameplate40)
			assert.is_true(seen.nameplate150)
			assert.is_nil(seen.nameplate151)
		end)

		it("covers the whole raid and arena ranges", function()
			local seen = {}
			for _, token in ipairs(DonorBody.Tokens()) do seen[token] = true end
			assert.is_true(seen.raid40)
			assert.is_true(seen.arena5)
		end)

		it("asks the chains that reach people you never pointed at", function()
			local seen = {}
			for _, token in ipairs(DonorBody.Tokens()) do seen[token] = true end
			assert.is_true(seen.targettarget)
			assert.is_true(seen.focustarget)
			assert.is_true(seen.mouseovertarget)
			assert.is_true(seen.party1target)
		end)

		it("asks the soft and aggregate tokens, which need no targeting", function()
			local seen = {}
			for _, token in ipairs(DonorBody.Tokens()) do seen[token] = true end
			assert.is_true(seen.softfriend)
			assert.is_true(seen.softinteract)
			assert.is_true(seen.anyfriend)
		end)

		it("prefers group members over the crowd, since only they are never hidden",
			function()
				local position = {}
				for index, token in ipairs(DonorBody.Tokens()) do position[token] = index end
				assert.is_true(position.party1 < position.nameplate1)
				assert.is_true(position.raid1 < position.nameplate1)
			end)

		it("hands back a copy, so a caller cannot edit the order", function()
			local first = DonorBody.Tokens()
			first[1] = "nonsense"
			assert.equal("player", DonorBody.Tokens()[1])
		end)
	end)

	describe("Find", function()
		it("uses your own body when the sexes already agree", function()
			local read = World({ player = { sex = 3 }, target = { sex = 3 } })
			assert.equal("player", DonorBody.Find(3, read))
		end)

		it("borrows the target when you are the wrong sex", function()
			local read = World({ player = { sex = 2 }, target = { sex = 3 } })
			assert.equal("target", DonorBody.Find(3, read))
		end)

		it("falls through to the crowd when nobody nearer fits", function()
			local read = World({
				player = { sex = 2 }, target = { sex = 2 },
				nameplate7 = { sex = 3 },
			})
			assert.equal("nameplate7", DonorBody.Find(3, read))
		end)

		it("skips anything that is not a player", function()
			local read = World({
				player = { sex = 2 },
				target = { sex = 3, isPlayer = false },
				nameplate2 = { sex = 3 },
			})
			assert.equal("nameplate2", DonorBody.Find(3, read))
		end)

		it("answers nothing when no one of that sex is around", function()
			local read = World({ player = { sex = 2 }, target = { sex = 2 } })
			assert.is_nil(DonorBody.Find(3, read))
		end)

		it("refuses a sex it does not recognise", function()
			-- A unit the client would not answer for reads back a nil sex, so
			-- asking for nil must not quietly match every such unit.
			local read = World({ player = { sex = nil }, target = { sex = 2 } })
			assert.is_nil(DonorBody.Find(nil, read))
			assert.is_nil(DonorBody.Find(0, read))
			assert.is_nil(DonorBody.Find(1, read))
		end)

		it("survives being given no way to read a unit", function()
			assert.is_nil(DonorBody.Find(3, nil))
		end)
	end)
end)


-- The race override replaces the race but not the skin, hair or face, so a
-- donor of the wrong race lends a palette that lands wrong on the new one.
describe("DonorBody.Find race preference", function()
	local function World(units)
		return function(token)
			local unit = units[token]
			if not unit then return false end
			return true, unit.isPlayer ~= false, unit.sex, unit.race
		end
	end

	it("prefers a donor of the race being shown, even if further down the list", function()
		local read = World({
			player = { sex = 2, race = 52 },
			target = { sex = 3, race = 10 },
			nameplate9 = { sex = 3, race = 29 },
		})
		local token, exact = DonorBody.Find(3, read, 29)
		assert.equal("nameplate9", token)
		assert.is_true(exact)
	end)

	it("takes anybody of the right sex when that race is not around", function()
		local read = World({
			player = { sex = 2, race = 52 },
			target = { sex = 3, race = 10 },
		})
		local token, exact = DonorBody.Find(3, read, 29)
		assert.equal("target", token)
		assert.is_false(exact)
	end)

	it("keeps the plain order when no race is asked for", function()
		local read = World({
			player = { sex = 3, race = 1 },
			target = { sex = 3, race = 29 },
		})
		assert.equal("player", DonorBody.Find(3, read))
	end)

	it("still answers nothing when nobody of that sex is around", function()
		local read = World({ player = { sex = 2, race = 1 } })
		assert.is_nil(DonorBody.Find(3, read, 29))
	end)
end)
