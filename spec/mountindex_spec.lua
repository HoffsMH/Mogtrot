local MountIndex = require("MountIndex")
local H = require("spec.helpers")

describe("MountIndex.Build", function()
	local db

	before_each(function()
		db = H.NewDB()
	end)

	it("returns nothing for an empty or absent mount table", function()
		assert.same({}, MountIndex.Build(db))
		db.mounts = nil
		assert.same({}, MountIndex.Build(db))
	end)

	it("lists an outfit under each of its mounts", function()
		db.mounts = { [7] = { [101] = true, [102] = true } }
		assert.same({ [101] = { 7 }, [102] = { 7 } }, MountIndex.Build(db))
	end)

	it("lists every outfit sharing a mount, ascending", function()
		-- These three ids do not come out of pairs in order on either 5.1 or LuaJIT.
		db.mounts = { [5] = { [101] = true }, [12] = { [101] = true }, [7] = { [101] = true } }
		assert.same({ [101] = { 5, 7, 12 } }, MountIndex.Build(db))
	end)

	it("keeps outfits with no mounts out of the index", function()
		db.mounts = { [7] = {}, [8] = { [101] = true } }
		assert.same({ [101] = { 8 } }, MountIndex.Build(db))
	end)
end)
