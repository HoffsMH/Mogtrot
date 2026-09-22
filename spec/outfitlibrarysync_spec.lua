local Sync = require("OutfitLibrarySync")
local Library = require("Library")

describe("OutfitLibrarySync", function()
	local owner = { guid = "Player-1", name = "Alpha", realm = "Aegwynn",
		raceID = 1, raceFile = "Human", sex = 3, classID = 1 }
	local function Infos() return { { outfitID = 7, name = "Red", icon = 44 } } end
	local function Looks() return { [7] = { [1] = { 101, 0, 0 } } } end

	it("adds then updates and renames a mirrored outfit", function()
		local library = Library.New()
		local infos, looks = Infos(), Looks()
		local first = Sync.Reconcile(library, owner, infos, looks, 10)
		assert.equal(1, first.added)
		infos[1].name = "Blue"
		looks[7][1][1] = 202
		local second = Sync.Reconcile(library, owner, infos, looks, 20)
		assert.equal(1, second.updated)
		assert.equal("Blue", library.records[1].originName)
		assert.equal("1:202,0,0", library.records[1].look)
		assert.equal(10, library.records[1].savedAt)
	end)

	it("keeps the owner's alternate-form state", function()
		local library = Library.New()
		local visage = {
			guid = owner.guid, name = owner.name, realm = owner.realm,
			raceID = 52, raceFile = "Dracthyr", sex = 2, classID = 9,
			nativeForm = false,
		}
		Sync.Reconcile(library, visage, Infos(), Looks(), 10)
		assert.is_false(library.records[1].nativeForm)
	end)

	-- A record with nothing in it is a card that says "wear this once", and a
	-- wall of them is noise for outfits the user may never ingest. It is
	-- counted as missing, which is what the header reports, but not stored.
	it("stores nothing for an outfit nobody has read", function()
		local library = Library.New()
		local stats = Sync.Reconcile(library, owner, Infos(), {}, 10)
		assert.equal(1, stats.missing)
		assert.equal(0, stats.added)
		assert.same({}, library.records)
	end)

	it("keeps a record it already has when a later read finds nothing", function()
		local library = Library.New()
		Sync.Reconcile(library, owner, Infos(), Looks(), 10)
		local stats = Sync.Reconcile(library, owner, Infos(), {}, 20)
		assert.equal(1, stats.missing)
		assert.equal(0, stats.pruned)
		assert.equal("1:101,0,0", library.records[1].look)
	end)

	it("marks an outfit read as empty scanned, and does not call it missing", function()
		local library = Library.New()
		local stats = Sync.Reconcile(library, owner, Infos(), { [7] = {} }, 10)
		assert.equal(0, stats.missing)
		assert.same({}, stats.missingOutfits)
		assert.is_true(library.records[1].scanned)
		assert.equal("", library.records[1].look)
	end)

	it("marks an outfit with pieces scanned", function()
		local library = Library.New()
		Sync.Reconcile(library, owner, Infos(), Looks(), 10)
		assert.is_true(library.records[1].scanned)
	end)

	it("prunes only absent outfits belonging to this owner", function()
		local library = Library.New()
		local infos, looks = Infos(), Looks()
		Sync.Reconcile(library, owner, infos, looks, 10)
		Sync.Reconcile(library, { guid = "Player-2", name = "Beta" },
			{ { outfitID = 8, name = "Other" } },
			{ [8] = { [1] = { 303, 0, 0 } } }, 10)
		Library.Add(library, { source = "snap", look = "1:404,0,0", raceID = 1, sex = 2 }, 10)
		local stats = Sync.Reconcile(library, owner, { { outfitID = 9, name = "New" } },
			{ [9] = { [1] = { 505, 0, 0 } } }, 20)
		assert.equal(1, stats.pruned)
		assert.equal(3, #Library.Sorted(library))
	end)

	it("treats nil and empty enumerations as no information", function()
		local library = Library.New()
		local infos, looks = Infos(), Looks()
		Sync.Reconcile(library, owner, infos, looks, 10)
		assert.truthy(select(2, Sync.Reconcile(library, owner, nil, looks, 20)))
		assert.truthy(select(2, Sync.Reconcile(library, owner, {}, looks, 20)))
		assert.is_table(library.records[1])
	end)

	-- Named so the header can say which outfits still want ingesting, without
	-- putting an empty card in the wall for each of them.
	it("names a missing outfit without mirroring it", function()
		local library = Library.New()
		local stats = Sync.Reconcile(library, owner, Infos(), {}, 10)
		assert.equal(1, stats.missing)
		assert.same({ { outfitID = 7, name = "Red" } }, stats.missingOutfits)
		assert.equal(0, stats.added)
		assert.same({}, library.records)
	end)
end)
