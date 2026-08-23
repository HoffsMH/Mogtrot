local LinkedMountShuffle = require("LinkedMountShuffle")

local function First() return 1 end

describe("LinkedMountShuffle", function()
	it("allows the only viable mount every time", function()
		local shuffle = LinkedMountShuffle.New(First)
		for index = 1, 2 do
			assert.equals(101, shuffle:Choose(7, { 101 }, index))
			shuffle:Stage(7, 101, 1001, index)
			shuffle:Confirm(1001, "cast-" .. index, index)
		end
	end)

	it("does not consume a staged mount before cast start", function()
		local shuffle = LinkedMountShuffle.New(First)
		local mountID = shuffle:Choose(7, { 101, 102 }, 0)
		shuffle:Stage(7, mountID, 1001, 0)
		assert.equals(mountID, shuffle:Choose(7, { 101, 102 }, 1))
	end)

	it("consumes a mount when its cast starts", function()
		local shuffle = LinkedMountShuffle.New(First)
		local first = shuffle:Choose(7, { 101, 102 }, 0)
		shuffle:Stage(7, first, 1001, 0)
		assert.is_true(shuffle:Confirm(1001, "cast-1", 1))
		assert.not_equals(first, shuffle:Choose(7, { 101, 102 }, 2))
	end)

	it("a cancellation after start leaves the mount consumed", function()
		local shuffle = LinkedMountShuffle.New(First)
		local first = shuffle:Choose(7, { 101, 102 }, 0)
		shuffle:Stage(7, first, 1001, 0)
		shuffle:Confirm(1001, "cast-1", 1)
		shuffle:Cancel(1001, "cast-1")
		assert.not_equals(first, shuffle:Choose(7, { 101, 102 }, 2))
	end)

	it("a cancellation before start does not consume", function()
		local shuffle = LinkedMountShuffle.New(First)
		local first = shuffle:Choose(7, { 101, 102 }, 0)
		shuffle:Stage(7, first, 1001, 0)
		assert.is_true(shuffle:Cancel(1001))
		assert.equals(first, shuffle:Choose(7, { 101, 102 }, 1))
	end)

	it("ignores an unrelated spell start", function()
		local shuffle = LinkedMountShuffle.New(First)
		local first = shuffle:Choose(7, { 101, 102 }, 0)
		shuffle:Stage(7, first, 1001, 0)
		assert.is_false(shuffle:Confirm(2002, "cast-2", 1))
		assert.equals(first, shuffle:Choose(7, { 101, 102 }, 2))
	end)

	it("expires stale pending requests without consuming", function()
		local shuffle = LinkedMountShuffle.New(First, 10)
		local first = shuffle:Choose(7, { 101, 102 }, 0)
		shuffle:Stage(7, first, 1001, 0)
		assert.equals(first, shuffle:Choose(7, { 101, 102 }, 10))
		assert.is_nil(shuffle.pending)
	end)

	it("uses success only as an instant-cast fallback", function()
		local shuffle = LinkedMountShuffle.New(First)
		local first = shuffle:Choose(7, { 101, 102 }, 0)
		shuffle:Stage(7, first, 1001, 0)
		assert.is_true(shuffle:Confirm(1001, "cast-1", 1))
		assert.not_equals(first, shuffle:Choose(7, { 101, 102 }, 2))
	end)

	it("matches a sent cast GUID when one was observed", function()
		local shuffle = LinkedMountShuffle.New(First)
		local first = shuffle:Choose(7, { 101, 102 }, 0)
		shuffle:Stage(7, first, 1001, 0)
		assert.is_true(shuffle:Sent(1001, "cast-1"))
		assert.is_false(shuffle:Confirm(1001, "cast-2", 1))
		assert.is_true(shuffle:Confirm(1001, "cast-1", 1))
	end)

	it("returns every candidate once before repeating", function()
		local shuffle = LinkedMountShuffle.New(First)
		local seen = {}
		for index = 1, 4 do
			local mountID = shuffle:Choose(7, { 101, 102, 103, 104 }, index)
			seen[mountID] = true
			shuffle:Stage(7, mountID, mountID + 1000, index)
			shuffle:Confirm(mountID + 1000, "cast-" .. index, index)
		end
		assert.same({ [101] = true, [102] = true, [103] = true, [104] = true }, seen)
	end)

	it("does not repeat across refill with pathological random", function()
		local shuffle = LinkedMountShuffle.New(First)
		local previous
		for index = 1, 8 do
			local mountID = shuffle:Choose(7, { 101, 102 }, index)
			assert.not_equals(previous, mountID)
			shuffle:Stage(7, mountID, mountID + 1000, index)
			shuffle:Confirm(mountID + 1000, "cast-" .. index, index)
			previous = mountID
		end
	end)

	it("resets safely for candidate and outfit changes", function()
		local shuffle = LinkedMountShuffle.New(First)
		assert.equals(101, shuffle:Choose(7, { 101, 102 }, 0))
		assert.equals(103, shuffle:Choose(7, { 103 }, 1))
		assert.equals(101, shuffle:Choose(8, { 101, 102 }, 2))
	end)

	it("avoids the last consumed mount when candidates change", function()
		local shuffle = LinkedMountShuffle.New(First)
		local first = shuffle:Choose(7, { 101, 102 }, 0)
		shuffle:Stage(7, first, 1001, 0)
		shuffle:Confirm(1001, "cast-1", 1)
		assert.not_equals(first, shuffle:Choose(7, { 101, 102, 103 }, 2))
	end)

	it("does not stage target, fallback, LiteMount, or refusal plans", function()
		local shuffle = LinkedMountShuffle.New(First)
		for _, plan in ipairs({
			{ action = "summon", from = "target", mountID = 900 },
			{ action = "summon", from = "favourite", mountID = 901 },
			{ action = "litemount" },
			{ action = "refuse", reason = "unusable" },
		}) do
			shuffle:Select(7, plan, 0)
			assert.is_nil(shuffle.pending)
		end
	end)
end)
