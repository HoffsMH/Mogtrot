-- The account-wide library: its migration, its dedup, and what it refuses.
local Library = require("Library")

describe("Library", function()
	local function Snap(look, raceID, sex)
		return { source = "snap", look = look or "1:5,0,0",
			raceID = raceID or 6, sex = sex or 2, seenCount = 1 }
	end
	local function Mine(origin)
		return { source = "mine", origin = origin or "outfit", originID = 14,
			look = "1:9,0,0", raceID = 11, sex = 3 }
	end

	describe("Migrate", function()
		it("creates the library on an account that has none", function()
			local account = {}
			local library = Library.Migrate(account)
			assert.equal(library, account.library)
			assert.equal(Library.VERSION, library.version)
			assert.equal(1, library.nextID)
			assert.same({}, library.records)
		end)

		it("leaves an existing library's records alone", function()
			local account = { library = { version = 1, nextID = 7,
				records = { [3] = Snap() } } }
			local library = Library.Migrate(account)
			assert.equal(7, library.nextID)
			assert.is_table(library.records[3])
		end)

		it("refuses a library newer than this build knows", function()
			local account = { library = { version = 99, nextID = 1, records = {} } }
			local library, why = Library.Migrate(account)
			assert.is_nil(library)
			assert.truthy(why:find("99", 1, true))
			-- and it did not touch it
			assert.equal(99, account.library.version)
		end)

		it("refuses a library carrying no version at all", function()
			local account = { library = { records = {} } }
			assert.is_nil(Library.Migrate(account))
		end)

		it("repairs a library missing its records or counter", function()
			local account = { library = { version = 1 } }
			local library = Library.Migrate(account)
			assert.same({}, library.records)
			assert.equal(1, library.nextID)
		end)

		it("is idempotent", function()
			local account = {}
			Library.Migrate(account)
			account.library.nextID = 5
			Library.Migrate(account)
			assert.equal(5, account.library.nextID)
		end)

		it("refuses anything that is not an account store", function()
			assert.is_nil(Library.Migrate(nil))
			assert.is_nil(Library.Migrate("db"))
		end)
	end)

	describe("Validate", function()
		it("accepts the four shapes", function()
			assert.is_true(Library.Validate(Snap()))
			assert.is_true(Library.Validate(Mine("outfit")))
			assert.is_true(Library.Validate(Mine("customSet")))
			assert.is_true(Library.Validate(Mine("stored")))
		end)

		it("refuses an unknown source", function()
			local r = Snap(); r.source = "alt"
			assert.is_false(Library.Validate(r))
		end)

		it("refuses a look that was not encoded", function()
			local r = Snap(); r.look = { [1] = { 5, 0, 0 } }
			local ok, why = Library.Validate(r)
			assert.is_false(ok)
			assert.truthy(why:find("encoded", 1, true))
		end)

		it("refuses one of yours with no container", function()
			local r = Mine(); r.origin = nil
			assert.is_false(Library.Validate(r))
		end)

		it("refuses a snap that claims a container", function()
			local r = Snap(); r.origin = "outfit"
			local ok, why = Library.Validate(r)
			assert.is_false(ok)
			assert.truthy(why:find("never in a container", 1, true))
		end)

		it("refuses a field the schema does not know", function()
			local r = Snap(); r.favourite = true
			local ok, why = Library.Validate(r)
			assert.is_false(ok)
			assert.truthy(why:find("favourite", 1, true))
		end)
	end)

	describe("Add", function()
		it("assigns an id and counts the first sighting", function()
			local library = Library.New()
			local id, isNew = Library.Add(library, Snap(), 100)
			assert.equal(1, id)
			assert.is_true(isNew)
			assert.equal(2, library.nextID)
			assert.equal(100, library.records[1].updatedAt)
		end)

		it("prunes a second character who looks identical", function()
			local library = Library.New()
			Library.Add(library, Snap("1:5,0,0", 6, 2), 100)
			local id, isNew = Library.Add(library, Snap("1:5,0,0", 6, 2), 200)
			assert.equal(1, id)
			assert.is_false(isNew)
			assert.equal(2, library.nextID)
		end)

		it("bumps only the sighting fields on a repeat", function()
			local library = Library.New()
			Library.Add(library, Snap(), 100)
			local held = library.records[1]
			held.name = "Thunderhoof"
			Library.Add(library, Snap(), 200)
			assert.equal(200, held.lastSeen)
			assert.equal(2, held.seenCount)
			assert.equal("Thunderhoof", held.name)
		end)

		it("keeps the same look on a different race apart", function()
			local library = Library.New()
			Library.Add(library, Snap("1:5,0,0", 6, 2), 100)
			local id, isNew = Library.Add(library, Snap("1:5,0,0", 4, 2), 100)
			assert.equal(2, id)
			assert.is_true(isNew)
		end)

		it("keeps the same look on a different sex apart", function()
			local library = Library.New()
			Library.Add(library, Snap("1:5,0,0", 6, 2), 100)
			local _, isNew = Library.Add(library, Snap("1:5,0,0", 6, 3), 100)
			assert.is_true(isNew)
		end)

		it("refuses a record that does not validate, without storing it", function()
			local library = Library.New()
			local r = Snap(); r.source = "nonsense"
			local id, isNew, why = Library.Add(library, r, 100)
			assert.is_nil(id)
			assert.is_false(isNew)
			assert.truthy(why)
			assert.equal(1, library.nextID)
		end)
	end)

	describe("BuildIndex and Delete", function()
		it("indexes every record by what it looks like", function()
			local library = Library.New()
			Library.Add(library, Snap("1:5,0,0", 6, 2), 100)
			Library.Add(library, Snap("1:9,0,0", 4, 3), 100)
			local index = Library.BuildIndex(library)
			assert.equal(1, index["1:5,0,0|6|2"])
			assert.equal(2, index["1:9,0,0|4|3"])
		end)

		it("removes a record and reports whether it was there", function()
			local library = Library.New()
			Library.Add(library, Snap(), 100)
			assert.is_true(Library.Delete(library, 1))
			assert.is_nil(library.records[1])
			assert.is_false(Library.Delete(library, 1))
		end)

		it("does not reuse the id of a deleted record", function()
			local library = Library.New()
			Library.Add(library, Snap("1:5,0,0"), 100)
			Library.Delete(library, 1)
			local id = Library.Add(library, Snap("1:7,0,0"), 100)
			assert.equal(2, id)
		end)

		it("lists newest first", function()
			local library = Library.New()
			Library.Add(library, Snap("1:5,0,0"), 100)
			Library.Add(library, Snap("1:7,0,0"), 100)
			local list = Library.Sorted(library)
			assert.equal(2, list[1].id)
			assert.equal(1, list[2].id)
		end)

		it("survives an empty or absent library", function()
			assert.same({}, Library.BuildIndex(nil))
			assert.same({}, Library.Sorted(nil))
			assert.is_false(Library.Delete(nil, 1))
		end)
	end)
end)

describe("Library.Snap", function()
	it("builds a record from a look table and the facts around it", function()
		local record = Library.Snap({
			look = { [1] = { 5, 0, 0 }, [3] = { 0, 0, 0 } },
			raceID = 6, sex = 2, name = "Thunderhoof", realm = "Aegwynn",
			zone = "Silvermoon City", level = 80,
		}, 1000)
		assert.equal("snap", record.source)
		assert.equal("1:5,0,0", record.look)
		assert.equal("Thunderhoof", record.name)
		assert.equal(1000, record.seenAt)
		assert.equal(1000, record.lastSeen)
		assert.equal(1, record.seenCount)
		assert.is_true(Library.Validate(record))
	end)

	it("takes an already encoded look unchanged", function()
		local record = Library.Snap({ look = "1:5,0,0;16:9,0,4", raceID = 1, sex = 2 }, 1)
		assert.equal("1:5,0,0;16:9,0,4", record.look)
	end)

	it("prefers the moment of sighting over the moment of saving", function()
		local record = Library.Snap({ look = "1:5,0,0", seenAt = 50 }, 1000)
		assert.equal(50, record.seenAt)
		assert.equal(50, record.lastSeen)
	end)

	it("keeps an anonymous capture, with the unanswered facts left nil", function()
		local record = Library.Snap({ look = "1:5,0,0" }, 1000)
		assert.is_table(record)
		assert.is_nil(record.name)
		assert.is_nil(record.raceID)
		assert.is_nil(record.guid)
	end)

	it("refuses a capture of someone wearing no transmog", function()
		local record, why = Library.Snap({ look = {}, raceID = 6, sex = 2 }, 1)
		assert.is_nil(record)
		assert.equal("nothing worn", why)
	end)

	it("refuses facts with no look at all", function()
		assert.is_nil(Library.Snap({ name = "Nobody" }, 1))
		assert.is_nil(Library.Snap(nil, 1))
	end)

	it("drops a fact the schema does not know rather than storing it", function()
		local record = Library.Snap({ look = "1:5,0,0", favourite = true }, 1)
		assert.is_table(record)
		assert.is_nil(record.favourite)
	end)
end)
