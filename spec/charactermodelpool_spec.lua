local CharacterModelPool = require("CharacterModelPool")

describe("CharacterModelPool", function()
	local function NewPool(limit)
		return CharacterModelPool.New(limit, "holder")
	end

	it("keeps built bodies while recycling cards below the cap", function()
		local pool = NewPool(5)
		local cards = { {}, {} }

		for index, key in ipairs({ "body1", "body2", "body3", "body4" }) do
			local entry = pool:Acquire(cards[(index - 1) % #cards + 1], key)
			entry.key = key
		end

		for index = 1, 4 do
			assert.is_table(pool:Find("body" .. index))
		end
	end)

	it("reuses the requested body before another free entry", function()
		local pool = NewPool(4)
		local first = pool:Acquire({}, "wanted")
		first.key = "wanted"
		pool:Release(first.card)
		local other = pool:Acquire({}, "other")
		other.key = "other"
		pool:Release(other.card)

		assert.equal(first, pool:Acquire({}, "wanted"))
	end)

	it("evicts the oldest free body at the cap", function()
		local pool = NewPool(2)
		local first = pool:Acquire({}, "first")
		first.key = "first"
		pool:Release(first.card)
		local second = pool:Acquire({}, "second")
		second.key = "second"
		pool:Release(second.card)

		assert.equal(first, pool:Acquire({}, "third"))
	end)

	it("keeps pane twins separate from card entries", function()
		local pool = NewPool(4)
		local card = {}
		local body = pool:Acquire(card, "body")
		body.key = "body"
		pool:Release(card)
		local twin = pool:WarmPane("body")
		twin.key = "body"
		twin.actor = "actor"

		assert.equal(body, pool:Acquire({}, "body"))
		assert.equal(twin, pool:FindPane("body"))
		assert.is_true(twin.pane)
		assert.equal(twin, pool:BorrowPane("body"))
		assert.equal(twin, pool:ReturnPane())
	end)

	it("finds a reusable warm entry without replacing a built body", function()
		local pool = NewPool(3)
		local built = pool:Acquire({}, "built")
		built.key = "built"
		pool:Release(built.card)
		local empty = pool:Acquire({}, nil)
		pool:Release(empty.card)

		assert.equal(empty, pool:Warm("new"))
		assert.equal(built, pool:Find("built"))
	end)

	it("never inspects opaque values", function()
		local function Opaque(name)
			return setmetatable({}, {
				__index = function() error(name .. " was inspected") end,
			})
		end
		local holder = Opaque("holder")
		local actor = Opaque("actor")
		local card = Opaque("card")
		local pool = CharacterModelPool.New(1, holder)
		local entry = pool:Acquire(card, "body")
		entry.actor = actor
		entry.key = "body"
		assert.equal(holder, pool:Holder())
		assert.is_table(pool:Release(card))
	end)

	it("creates plain descriptors internally without exposing an allocator", function()
		local pool = NewPool(1)
		local entry = pool:Warm("body")
		assert.same({}, entry)
		assert.is_nil(pool.Add)
	end)

	it("refuses to grow past the cap when every descriptor is reserved", function()
		local pool = NewPool(1)
		assert.is_table(pool:Acquire({}, "first"))
		assert.is_nil(pool:Acquire({}, "second"))
	end)
end)

-- Two cards wanting the same body cannot share one: Acquire only hands over an
-- entry nothing else holds. So counting whether a key exists at all overstates
-- what is available, and the wall that relies on that count decides it has
-- nothing left to build while a card is still waiting.
describe("CharacterModelPool:CountByKey", function()
	local function Pool(limit)
		return CharacterModelPool.New(limit or 4, {})
	end

	it("counts nothing for an empty pool", function()
		assert.same({}, Pool():CountByKey())
	end)

	it("counts one entry per key it carries", function()
		local pool = Pool()
		local a = pool:Acquire("cardA", nil)
		a.key = "elf|female"
		local b = pool:Acquire("cardB", nil)
		b.key = "orc|male"
		assert.same({ ["elf|female"] = 1, ["orc|male"] = 1 }, pool:CountByKey())
	end)

	it("counts two bodies built for the same key separately", function()
		local pool = Pool()
		pool:Acquire("cardA", nil).key = "elf|female"
		pool:Acquire("cardB", nil).key = "elf|female"
		assert.same({ ["elf|female"] = 2 }, pool:CountByKey())
	end)

	-- Find answers yes for a body another card is already standing in, which
	-- is the whole difference.
	it("counts a held body the same as a free one", function()
		local pool = Pool()
		local held = pool:Acquire("cardA", nil)
		held.key = "elf|female"
		assert.is_table(pool:Find("elf|female"))
		assert.equal(1, pool:CountByKey()["elf|female"])
	end)
end)
