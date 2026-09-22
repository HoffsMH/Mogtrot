-- Fail-first tests for the pure Rotation API (plan checkpoint 22).
--
-- The contract: the caller owns the state table (persisted plain data, no
-- methods), candidates come in as a list in any order, random is injected as
-- `random(n) -> 1..n`, and choosing is separate from committing so a failed or
-- abandoned choice leaves no trace. The spec requires only Rotation itself --
-- no WoW stubs -- which is also the proof that the module touches no globals,
-- no WoW API and no clock.
local Rotation = require("Rotation")

-- Deterministic shuffles: always draw the lowest index, always the highest.
local function First(_) return 1 end
local function Last(_) return _ end

local function CountKeys(t)
	local count = 0
	for _ in pairs(t) do count = count + 1 end
	return count
end

describe("Rotation", function()
	it("returns nil for empty candidates and leaves the state untouched", function()
		local state = {}
		assert.is_nil(Rotation.Choose(state, {}, First))
		assert.is_nil(state.last)
		assert.is_nil(state.remaining)
	end)

	it("chooses a candidate from the provided set", function()
		local state = {}
		local id = Rotation.Choose(state, { 11, 22, 33 }, First)
		assert.is_true(id == 11 or id == 22 or id == 33)
	end)

	it("an uncommitted choice consumes nothing and records no last", function()
		local state = {}
		local candidates = { 11, 22, 33 }
		local id = Rotation.Choose(state, candidates, First)
		assert.equals(id, Rotation.Choose(state, candidates, First))
		assert.is_nil(state.last)
	end)

	it("commit removes the chosen candidate and records it as last", function()
		local state = {}
		local id = Rotation.Choose(state, { 11, 22, 33 }, First)
		Rotation.Commit(state, id)
		assert.equals(id, state.last)
		assert.not_equals(id, Rotation.Choose(state, { 11, 22, 33 }, First))
	end)

	it("persists into the caller-provided state table by identity", function()
		local state = {}
		Rotation.Commit(state, Rotation.Choose(state, { 11, 22, 33 }, First))
		assert.is_table(state.signature)
		assert.is_table(state.remaining)
	end)

	it("uses every candidate once before refilling", function()
		local state = {}
		local candidates = { 11, 22, 33 }
		for _ = 1, 2 do
			local seen = {}
			for _ = 1, 3 do
				local id = Rotation.Choose(state, candidates, First)
				assert.is_nil(seen[id], "candidate " .. tostring(id) .. " repeated within a cycle")
				seen[id] = true
				Rotation.Commit(state, id)
			end
			assert.equals(3, CountKeys(seen))
		end
	end)

	it("repeats the only candidate after exhaustion", function()
		local state = {}
		for _ = 1, 3 do
			assert.equals(7, Rotation.Choose(state, { 7 }, First))
			Rotation.Commit(state, 7)
		end
	end)

	it("a refill avoids the last committed candidate when two or more exist", function()
		for _, random in ipairs({ First, Last }) do
			local state = {}
			local candidates = { 11, 22, 33 }
			for _ = 1, 3 do
				Rotation.Commit(state, Rotation.Choose(state, candidates, random))
			end
			assert.not_equals(state.last, Rotation.Choose(state, candidates, random))
		end
	end)

	it("a candidate-set change restarts the cycle", function()
		local state = {}
		for _ = 1, 3 do
			Rotation.Commit(state, Rotation.Choose(state, { 11, 22, 33 }, First))
		end

		local seen = {}
		for _ = 1, 3 do
			local id = Rotation.Choose(state, { 11, 22, 44 }, First)
			assert.is_nil(seen[id], "stale cycle leaked candidate " .. tostring(id))
			seen[id] = true
			Rotation.Commit(state, id)
		end
		assert.is_true(seen[11] and seen[22] and seen[44])
	end)

	it("reordering the same candidates does not restart the cycle", function()
		local state = {}
		local seen = {}
		for _ = 1, 2 do
			local id = Rotation.Choose(state, { 11, 22, 33 }, First)
			seen[id] = true
			Rotation.Commit(state, id)
		end
		assert.equals(2, CountKeys(seen))
		-- Same set, different order: the one uncommitted candidate from the
		-- original cycle is still next under First.
		local id = Rotation.Choose(state, { 33, 11, 22 }, First)
		assert.is_nil(seen[id], "reordered candidates triggered a refill")
		assert.is_true(id == 11 or id == 22 or id == 33)
		assert.equals(33, id)
	end)

	it("supports numeric IDs as a homogeneous domain", function()
		local state = {}
		local seen = {}
		for _ = 1, 2 do
			for _ = 1, 3 do
				local id = Rotation.Choose(state, { 11, 22, 33 }, First)
				seen[id] = true
				Rotation.Commit(state, id)
			end
		end
		assert.equals(3, CountKeys(seen))
	end)

	it("supports exact string IDs as a homogeneous domain", function()
		local state = {}
		local seen = {}
		for _ = 1, 2 do
			for _ = 1, 3 do
				local id = Rotation.Choose(state, { "alpha", "beta", "gamma" }, First)
				seen[id] = true
				Rotation.Commit(state, id)
			end
		end
		assert.equals(3, CountKeys(seen))
	end)

	it("keeps separate domains independent through separate state", function()
		local numbers = {}
		local strings = {}
		for _ = 1, 3 do
			Rotation.Commit(numbers, Rotation.Choose(numbers, { 11, 22, 33 }, First))
			Rotation.Commit(strings, Rotation.Choose(strings, { "alpha", "beta", "gamma" }, First))
		end
		assert.is_true(numbers.last == 11 or numbers.last == 22 or numbers.last == 33)
		assert.is_true(strings.last == "alpha"
			or strings.last == "beta"
			or strings.last == "gamma")
	end)

	it("excludes the current ID while an alternative exists", function()
		local state = {}
		local candidates = { 11, 22, 33 }
		for _ = 1, 6 do
			local id = Rotation.Choose(state, candidates, First, 11)
			assert.not_equals(11, id)
			Rotation.Commit(state, id)
		end
	end)

	it("returns the current ID when it is the only candidate", function()
		local state = {}
		assert.equals(7, Rotation.Choose(state, { 7 }, First, 7))
	end)

	it("treats the injected random as the only randomness source", function()
		local realRandom = math.random
		rawset(math, "random", function()
			error("math.random must not be called when random is injected")
		end)
		local ok, err = pcall(function()
			local state = {}
			for _ = 1, 3 do
				Rotation.Commit(state, Rotation.Choose(state, { 11, 22, 33 }, First))
			end
		end)
		rawset(math, "random", realRandom)
		assert.is_true(ok, err)
	end)

	it("produces expected sequences under injected First and Last draws", function()
		local function Run(random)
			local state = {}
			local sequence = {}
			for _ = 1, 3 do
				sequence[#sequence + 1] =
					Rotation.Choose(state, { 11, 22, 33 }, random)
				Rotation.Commit(state, sequence[#sequence])
			end
			return table.concat(sequence, ",")
		end
		assert.equals("11,22,33", Run(First))
		assert.equals("33,22,11", Run(Last))
	end)
end)
