-- The account-wide library: its migration, its dedup, and what it refuses.
local Library = require("Library")

-- Saved variables hand an integer 0 back as -0, and tostring tells them apart.
local NEGATIVE_ZERO = loadstring("return -0")()

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

		it("keeps two characters' outfits sharing one ID through the migration", function()
			local account = { library = { version = 2, nextID = 3, records = {
				[1] = { id = 1, source = "mine", origin = "outfit",
					originID = 7, guid = "Player-1", look = "1:10,0,0" },
				[2] = { id = 2, source = "mine", origin = "outfit",
					originID = 7, guid = "Player-2", look = "1:10,0,0" },
			} } }
			local library = Library.Migrate(account)
			assert.is_table(library.records[1])
			assert.is_table(library.records[2])
		end)

		it("collapses one character's outfit duplicated by a signed zero", function()
			local account = { library = { version = 3, nextID = 3, records = {
				[1] = { id = 1, source = "mine", origin = "outfit",
					originID = 0, guid = "Player-1", look = "1:10,0,0" },
				[2] = { id = 2, source = "mine", origin = "outfit",
					originID = NEGATIVE_ZERO, guid = "Player-1", look = "1:10,0,0" },
			} } }
			local library = Library.Migrate(account)
			assert.is_table(library.records[1])
			assert.is_nil(library.records[2])
		end)

		it("drops custom sets so each character rebuilds its own", function()
			local account = { library = { version = 3, nextID = 4, records = {
				[1] = { id = 1, source = "mine", origin = "customSet",
					originID = 7, guid = "Player-1", look = "1:10,0,0" },
				[2] = { id = 2, source = "mine", origin = "outfit",
					originID = 7, guid = "Player-1", look = "1:11,0,0" },
				[3] = { id = 3, source = "snap", look = "1:12,0,0",
					raceID = 1, sex = 2 },
			} } }
			local library = Library.Migrate(account)
			assert.is_nil(library.records[1])
			assert.is_table(library.records[2])
			assert.is_table(library.records[3])
		end)

		-- The sync used to mirror every outfit whether or not anything had
		-- read it, which filled the wall with cards that could only say
		-- "wear this once". It no longer writes them; these clears the ones
		-- it already wrote. An outfit read and found empty is not one of
		-- them and stays.
		it("drops outfits that were mirrored before anything read them", function()
			local account = { library = { version = 4, nextID = 5, records = {
				[1] = { id = 1, source = "mine", origin = "outfit", originID = 1,
					guid = "P1", look = "", scanned = false },
				[2] = { id = 2, source = "mine", origin = "outfit", originID = 2,
					guid = "P1", look = "", scanned = true },
				[3] = { id = 3, source = "mine", origin = "outfit", originID = 3,
					guid = "P1", look = "1:9,0,0", scanned = true },
				[4] = { id = 4, source = "snap", look = "1:8,0,0", raceID = 1, sex = 2 },
			} } }
			local library = Library.Migrate(account)
			assert.is_nil(library.records[1])
			assert.is_table(library.records[2])
			assert.is_table(library.records[3])
			assert.is_table(library.records[4])
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

	-- An outfit nobody has read and an outfit that assigns nothing both store an
	-- empty look, so only the flag tells them apart.
	describe("scan state", function()
		local function Outfit(look, scanned)
			return { source = "mine", origin = "outfit", originID = 1,
				guid = "P1", look = look, scanned = scanned }
		end

		it("accepts the scanned flag as a known field", function()
			assert.is_true(Library.Validate(Outfit("", false)))
		end)

		it("calls an empty look nobody has read unscanned", function()
			assert.is_true(Library.IsUnscanned(Outfit("", false)))
			assert.is_false(Library.IsEmptyOutfit(Outfit("", false)))
		end)

		it("calls an empty look that was read empty", function()
			assert.is_true(Library.IsEmptyOutfit(Outfit("", true)))
			assert.is_false(Library.IsUnscanned(Outfit("", true)))
		end)

		-- A record written before the flag existed almost always came from an
		-- ingest that did run, because the ingest is what created it. Reading
		-- the absence as "never read" labels every genuinely empty outfit as
		-- missing and puts a wall of them in front of the user.
		it("treats a record written before the flag as read and empty", function()
			assert.is_false(Library.IsUnscanned(Outfit("", nil)))
			assert.is_true(Library.IsEmptyOutfit(Outfit("", nil)))
		end)

		it("calls an outfit with pieces neither", function()
			assert.is_false(Library.IsUnscanned(Outfit("1:9,0,0", true)))
			assert.is_false(Library.IsEmptyOutfit(Outfit("1:9,0,0", true)))
		end)

		it("says nothing about a custom set or a snapshot", function()
			assert.is_false(Library.IsUnscanned({ source = "mine",
				origin = "customSet", originID = 1, guid = "P1", look = "" }))
			assert.is_false(Library.IsEmptyOutfit({ source = "snap", look = "" }))
		end)
	end)

	-- The window opens on this order, and the reason it exists is to put the
	-- capture you just took at the top.
	describe("Sorted", function()
		it("puts a brand new record first", function()
			local library = Library.New()
			Library.Add(library, Snap("1:1,0,0"), 100)
			Library.Add(library, Snap("1:2,0,0"), 200)
			assert.equal(2, Library.Sorted(library)[1].id)
		end)

		it("lifts a record seen again above newer ones", function()
			local library = Library.New()
			Library.Add(library, Snap("1:1,0,0"), 100)
			Library.Add(library, Snap("1:2,0,0"), 200)
			Library.Add(library, Snap("1:1,0,0"), 300)
			local sorted = Library.Sorted(library)
			assert.equal(1, sorted[1].id)
			assert.equal(2, sorted[2].id)
		end)

		-- A login sync stamps every mirrored outfit at once, so the tie has to
		-- break on something stable or the wall reshuffles for no reason.
		it("breaks a tie on the newer id", function()
			local library = Library.New()
			Library.Add(library, Snap("1:1,0,0"), 100)
			Library.Add(library, Snap("1:2,0,0"), 100)
			local sorted = Library.Sorted(library)
			assert.equal(2, sorted[1].id)
			assert.equal(1, sorted[2].id)
		end)
	end)

	describe("custom sets", function()
		local function Set(guid, customSetID)
			return { source = "mine", origin = "customSet", originID = customSetID,
				guid = guid, look = "1:10,0,0" }
		end

		it("keeps character-local custom set IDs separate by owner", function()
			local library = Library.New()
			Library.Add(library, Set("Player-1", 7), 10)
			local id, isNew = Library.Add(library, Set("Player-2", 7), 10)
			assert.equal(2, id)
			assert.is_true(isNew)
		end)

		it("keys a set ID of zero the same however its sign survived saving", function()
			assert.equal(Library.KeyOf(Set("Player-1", 0)),
				Library.KeyOf(Set("Player-1", NEGATIVE_ZERO)))
		end)
	end)

	describe("mirrored outfits", function()
		local function Outfit(guid, outfitID, look)
			return { source = "mine", origin = "outfit", originID = outfitID,
				guid = guid, look = look or "1:9,0,0" }
		end

		it("keeps character-local outfit IDs separate by owner", function()
			local library = Library.New()
			Library.Add(library, Outfit("Player-1", 4), 10)
			local id, isNew = Library.Add(library, Outfit("Player-2", 4), 10)
			assert.equal(2, id)
			assert.is_true(isNew)
		end)

		it("keeps a mirror separate from an identical snapshot", function()
			local library = Library.New()
			Library.Add(library, Snap("1:9,0,0", 11, 3), 10)
			local id = Library.Add(library, Outfit("Player-1", 4), 10)
			assert.equal(2, id)
		end)

		it("updates mutable fields while retaining identity and saved time", function()
			local library = Library.New()
			Library.Add(library, Outfit("Player-1", 4), 10)
			local changed = Outfit("Player-1", 4, "1:12,0,0")
			changed.originName = "Renamed"
			local id, isNew = Library.Upsert(library, changed, 20)
			assert.equal(1, id)
			assert.is_false(isNew)
			assert.equal(10, library.records[id].savedAt)
			assert.equal(20, library.records[id].updatedAt)
			assert.equal("Renamed", library.records[id].originName)
			assert.equal("1:12,0,0", library.records[id].look)
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

-- Archiving is a single unconfirmed click, and a snapshot is the one record
-- here that cannot be read back from the client. So archiving never destroys
-- anything: it moves the record aside and starts a clock.
describe("Library archive", function()
	local function Snap(look)
		return { source = "snap", look = look or "1:5,0,0", raceID = 6, sex = 2 }
	end

	local DAY = 86400

	it("moves a record out of the wall and stamps when", function()
		local library = Library.New()
		local id = Library.Add(library, Snap(), 100)
		assert.is_true(Library.Archive(library, id, 500))
		assert.is_nil(library.records[id])
		assert.equal(1, #library.archive)
		assert.equal(500, library.archive[1].archivedAt)
		assert.equal("1:5,0,0", library.archive[1].look)
	end)

	it("refuses to archive something that is not there", function()
		local library = Library.New()
		assert.is_false(Library.Archive(library, 99, 500))
	end)

	-- Time only moves forward, so appending keeps the list ordered and
	-- eviction never has to sort or decode anything but the front.
	it("keeps the archive oldest first", function()
		local library = Library.New()
		Library.Archive(library, Library.Add(library, Snap("1:1,0,0"), 10), 100)
		Library.Archive(library, Library.Add(library, Snap("1:2,0,0"), 20), 200)
		assert.equal(100, library.archive[1].archivedAt)
		assert.equal(200, library.archive[2].archivedAt)
	end)

	it("evicts only what is older than the window", function()
		local library = Library.New()
		Library.Archive(library, Library.Add(library, Snap("1:1,0,0"), 1), 0)
		Library.Archive(library, Library.Add(library, Snap("1:2,0,0"), 2), 20 * DAY)
		local dropped = Library.EvictArchived(library, 30, 40 * DAY)
		assert.equal(1, dropped)
		assert.equal(1, #library.archive)
		assert.equal(20 * DAY, library.archive[1].archivedAt)
	end)

	it("keeps everything when the window is zero", function()
		local library = Library.New()
		Library.Archive(library, Library.Add(library, Snap(), 1), 0)
		assert.equal(0, Library.EvictArchived(library, 0, 999 * DAY))
		assert.equal(1, #library.archive)
	end)

	it("survives an archive that is not there yet", function()
		assert.equal(0, Library.EvictArchived(Library.New(), 30, 100))
		assert.equal(0, Library.EvictArchived(nil, 30, 100))
	end)
end)

-- The archive can be read back: restored onto the wall, or deleted for good.
describe("Library archive, read back", function()
	local function Snap(look)
		return { source = "snap", look = look or "1:5,0,0", raceID = 6, sex = 2,
			seenCount = 1 }
	end

	it("lists the archive newest archived first", function()
		local library = Library.New()
		local a = Library.Add(library, Snap("1:1,0,0"), 10)
		local b = Library.Add(library, Snap("1:2,0,0"), 20)
		Library.Archive(library, a, 100)
		Library.Archive(library, b, 200)
		local list = Library.Archived(library)
		assert.equal(2, #list)
		assert.equal(b, list[1].id)
		assert.equal(a, list[2].id)
		assert.same({}, Library.Archived(nil))
	end)

	it("restores a record to the wall under its own id", function()
		local library = Library.New()
		local id = Library.Add(library, Snap(), 10)
		Library.Archive(library, id, 100)
		local restored, fresh = Library.Restore(library, id)
		assert.equal(id, restored)
		assert.is_true(fresh)
		assert.equal("1:5,0,0", library.records[id].look)
		assert.is_nil(library.records[id].archivedAt)
		assert.equal(0, #library.archive)
	end)

	it("restores only the one asked for", function()
		local library = Library.New()
		local a = Library.Add(library, Snap("1:1,0,0"), 10)
		local b = Library.Add(library, Snap("1:2,0,0"), 20)
		Library.Archive(library, a, 100)
		Library.Archive(library, b, 200)
		Library.Restore(library, a)
		assert.equal(1, #library.archive)
		assert.equal(b, library.archive[1].id)
		assert.is_nil(library.records[b])
	end)

	-- Snapped again while archived, the same look is already on the wall; a
	-- second card for it would be a duplicate the index cannot see.
	it("folds into the same look captured again since", function()
		local library = Library.New()
		local old = Library.Add(library, Snap(), 10)
		Library.Archive(library, old, 100)
		local new = Library.Add(library, Snap(), 300)
		local restored, fresh = Library.Restore(library, old)
		assert.equal(new, restored)
		assert.is_false(fresh)
		assert.is_nil(library.records[old])
		assert.equal(0, #library.archive)
		assert.equal(10, library.records[new].savedAt)
		assert.equal(2, library.records[new].seenCount)
	end)

	it("refuses to restore what is not archived", function()
		local library = Library.New()
		local id = Library.Add(library, Snap(), 10)
		assert.is_nil(Library.Restore(library, id))
		assert.is_nil(Library.Restore(library, 99))
		assert.is_nil(Library.Restore(nil, 1))
	end)

	it("deletes an archived record for good", function()
		local library = Library.New()
		local a = Library.Add(library, Snap("1:1,0,0"), 10)
		local b = Library.Add(library, Snap("1:2,0,0"), 20)
		Library.Archive(library, a, 100)
		Library.Archive(library, b, 200)
		assert.is_true(Library.Delete(library, a))
		assert.equal(1, #library.archive)
		assert.equal(b, library.archive[1].id)
		assert.is_nil(library.records[a])
		assert.is_false(Library.Delete(library, a))
	end)

	it("gives a wall card the X and an archived card Restore and Delete", function()
		local library = Library.New()
		local id = Library.Add(library, Snap(), 10)
		assert.same({ archive = true, restore = false, delete = false },
			Library.CardControls(library.records[id]))
		Library.Archive(library, id, 100)
		assert.same({ archive = false, restore = true, delete = true },
			Library.CardControls(library.archive[1]))
		assert.same({ archive = false, restore = false, delete = false },
			Library.CardControls({ source = "mine", look = "" }))
	end)
end)
