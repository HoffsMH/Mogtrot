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

describe("CharacterModelPool:Take", function()
	local function Pool()
		return CharacterModelPool.New(5, "holder")
	end

	it("hands over a free built body of exactly that key", function()
		local pool = Pool()
		local built = pool:Warm("elf|female")
		built.key, built.actor = "elf|female", "actor"
		assert.equal(built, pool:Take("popup", "elf|female"))
		assert.equal("popup", built.card)
	end)

	it("never builds, and never hands over another key", function()
		local pool = Pool()
		local built = pool:Warm("orc|male")
		built.key, built.actor = "orc|male", "actor"
		assert.is_nil(pool:Take("popup", "elf|female"))
		assert.equal(1, #pool.entries)
	end)

	it("leaves a body a card or the pane is holding", function()
		local pool = Pool()
		local held = pool:Acquire("card", "elf|female")
		held.key, held.actor = "elf|female", "actor"
		local twin = pool:WarmPane("elf|female")
		twin.key, twin.actor = "elf|female", "actor"
		assert.is_nil(pool:Take("popup", "elf|female"))
	end)

	it("hands back nothing without an actor", function()
		local pool = Pool()
		pool:Warm("elf|female").key = "elf|female"
		assert.is_nil(pool:Take("popup", "elf|female"))
	end)
end)

-- Each card holds its own body, so a key two cards want needs two bodies
-- warmed while the donor is in reach, not one.
describe("CharacterModelPool:Warm with a count", function()
	local function Pool(limit)
		return CharacterModelPool.New(limit or 5, "holder")
	end

	it("warms a second body when a card wants one more than exists", function()
		local pool = Pool()
		local first = pool:Warm("elf|female", 1)
		first.key = "elf|female"
		local second = pool:Warm("elf|female", 2)
		assert.is_table(second)
		assert.are_not.equal(first, second)
	end)

	it("warms nothing once the key has that many bodies", function()
		local pool = Pool()
		pool:Warm("elf|female", 1).key = "elf|female"
		assert.is_nil(pool:Warm("elf|female", 1))
		assert.is_nil(pool:Warm("elf|female"))
	end)

	it("counts a body a card is holding", function()
		local pool = Pool()
		pool:Acquire("card", "elf|female").key = "elf|female"
		assert.is_nil(pool:Warm("elf|female", 1))
		assert.is_table(pool:Warm("elf|female", 2))
	end)

	-- A twin belongs to the detail pane; no card can stand in it.
	it("does not count a pane twin", function()
		local pool = Pool()
		local twin = pool:WarmPane("elf|female")
		twin.key = "elf|female"
		assert.is_table(pool:Warm("elf|female", 1))
	end)

	it("stops at the cap", function()
		local pool = Pool(1)
		pool:Warm("elf|female", 1).key = "elf|female"
		assert.is_nil(pool:Warm("elf|female", 2))
	end)
end)

describe("CharacterModelPool:CountByKey and pane twins", function()
	it("leaves out twins, which no card can take", function()
		local pool = CharacterModelPool.New(5, "holder")
		pool:Acquire("card", nil).key = "elf|female"
		pool:WarmPane("elf|female").key = "elf|female"
		assert.same({ ["elf|female"] = 1 }, pool:CountByKey())
	end)
end)

-- At the cap a card takes a built body. One built on your own unit can be
-- built again anywhere; a borrowed one needs its donor back.
describe("CharacterModelPool:Acquire at the cap", function()
	it("evicts a body built on you before a borrowed one", function()
		local pool = CharacterModelPool.New(2, "holder")
		local borrowed = pool:Acquire("a", "elf|female")
		borrowed.key, borrowed.borrowed = "elf|female", true
		pool:Release("a")
		local own = pool:Acquire("b", "orc|male")
		own.key = "orc|male"
		pool:Release("b")
		assert.equal(own, pool:Acquire("c", "human|male"))
	end)

	it("evicts a borrowed body when nothing else is free", function()
		local pool = CharacterModelPool.New(1, "holder")
		local borrowed = pool:Acquire("a", "elf|female")
		borrowed.key, borrowed.borrowed = "elf|female", true
		pool:Release("a")
		assert.equal(borrowed, pool:Acquire("c", "human|male"))
	end)
end)

-- Bodies are kept per donor: a second donor builds a body of every shape
-- beside the first donor's, never counted as already covered by it.
describe("CharacterModelPool:Warm per donor", function()
	local function Built(pool, key, donor)
		local entry = pool:Warm(key, 1, donor)
		entry.key, entry.donorGUID, entry.actor = key, donor, "actor"
		return entry
	end

	it("warms a body for a second donor of a shape the first already filled", function()
		local pool = CharacterModelPool.New(5, "holder")
		Built(pool, "elf|female", "G1")
		assert.is_nil(pool:Warm("elf|female", 1, "G1"))
		assert.is_table(pool:Warm("elf|female", 1, "G2"))
	end)

	it("still warms extra bodies for more cards, counted across donors", function()
		local pool = CharacterModelPool.New(5, "holder")
		Built(pool, "elf|female", "G1")
		Built(pool, "elf|female", "G2")
		assert.is_nil(pool:Warm("elf|female", 2, "G2"))
		assert.is_table(pool:Warm("elf|female", 3, "G2"))
	end)
end)

-- A card of a shape several donors lent picks the best of them: the record's
-- own race first, then its faction, then any.
describe("CharacterModelPool:Acquire with a preference", function()
	local function Rank(entry)
		return entry.rank or 0
	end

	local function Free(pool, rank)
		local entry = pool:Warm("elf|female", 1, "G" .. rank)
		entry.key, entry.actor, entry.rank, entry.donorGUID = "elf|female", "actor",
			rank, "G" .. rank
		return entry
	end

	it("hands a card the best-ranked free body of its key", function()
		local pool = CharacterModelPool.New(5, "holder")
		Free(pool, 0)
		local best = Free(pool, 2)
		Free(pool, 1)
		assert.equal(best, pool:Acquire("card", "elf|female", Rank))
	end)

	it("takes the best-ranked body for the pop-up too", function()
		local pool = CharacterModelPool.New(5, "holder")
		Free(pool, 1)
		local best = Free(pool, 3)
		assert.equal(best, pool:Take("popup", "elf|female", Rank))
	end)
end)

describe("CharacterModelPool bodies still being built", function()
	local function Staged(pool, key, donor, pane)
		local entry = pane and pool:WarmPane(key) or pool:Warm(key, 1, donor)
		entry.key, entry.actor, entry.donorGUID, entry.borrowed = key, {}, donor, true
		entry.staging = donor
		return entry
	end

	it("hands no card, pop-up or pane a body whose donor is still building", function()
		local pool = CharacterModelPool.New(8, "holder")
		Staged(pool, "k", "G1")
		Staged(pool, "k", "G1", true)
		assert.is_nil(pool:Take({}, "k"))
		assert.is_nil(pool:FindPane("k"))
		assert.equal(0, pool:CountByKey().k or 0)
		local got = pool:Acquire({}, "k")
		assert.is_nil(got.key)
	end)

	it("does not evict a staged body at the cap", function()
		local pool = CharacterModelPool.New(1, "holder")
		Staged(pool, "k", "G1")
		assert.is_nil(pool:Acquire({}, "other"))
	end)

	it("still counts a staged body when its own donor warms, so it is not built twice", function()
		local pool = CharacterModelPool.New(8, "holder")
		Staged(pool, "k", "G1")
		assert.is_nil(pool:Warm("k", 1, "G1"))
	end)

	it("settles a donor's bodies for use, or drops them for reuse", function()
		local pool = CharacterModelPool.New(8, "holder")
		local kept = Staged(pool, "k", "G1")
		local dropped = Staged(pool, "j", "G2")
		local twin = Staged(pool, "j", "G2", true)
		pool:Settle("G1")
		assert.equal(kept, pool:Take({}, "k"))
		pool:Drop("G2")
		assert.is_nil(dropped.key)
		assert.is_nil(dropped.actor)
		assert.is_nil(dropped.staging)
		assert.is_nil(twin.key)
		assert.equal(0, pool:CountByKey().j or 0)
		assert.equal(dropped, pool:Warm("j", 1, "G3"))
	end)
end)
