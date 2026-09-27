-- The unit tokens a living body may be borrowed from.
local DonorBody = require("DonorBody")

describe("DonorBody", function()
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
end)

-- In a battleground or arena the client hands back enemy GUIDs as secret
-- values, and comparing one is a Lua error.
describe("DonorBody.TokenFor", function()
	-- A stand-in for a secret: comparing it errors, as the client's does.
	local guidMeta = {}
	guidMeta.__eq = function(a, b)
		if a.secret or b.secret then error("attempt to compare a secret value") end
		return a[1] == b[1]
	end
	local function GUID(text, secret)
		return setmetatable({ text, secret = secret }, guidMeta)
	end

	before_each(function()
		_G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
	end)
	after_each(function() _G.issecretvalue = nil end)

	it("finds the token whose GUID matches, skipping secret ones", function()
		local guids = { target = GUID("Player-9", true), party1 = GUID("Player-1") }
		local token = DonorBody.TokenFor(GUID("Player-1"), function(unit) return guids[unit] end)
		assert.equal("party1", token)
	end)

	it("answers nil when nobody matches", function()
		assert.is_nil(DonorBody.TokenFor(GUID("Player-1"), function() return nil end))
	end)
end)
