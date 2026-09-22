local Sync = require("CustomSetLibrarySync")
local Library = require("Library")

describe("CustomSetLibrarySync", function()
	local owner = { guid = "Player-1", name = "Alpha", realm = "Aegwynn",
		raceID = 1, raceFile = "Human", sex = 3, classID = 1 }
	local function Sets()
		return { { customSetID = 7, name = "Red", icon = 44,
			look = { [1] = { 101, 0, 0 } } } }
	end

	it("adds then updates a character-local custom set", function()
		local library = Library.New()
		local sets = Sets()
		local first = Sync.Reconcile(library, owner, sets, 10, true)
		assert.equal(1, first.added)
		sets[1].name = "Blue"
		sets[1].look[1][1] = 202
		local second = Sync.Reconcile(library, owner, sets, 20, true)
		assert.equal(1, second.updated)
		assert.equal("customSet", library.records[1].origin)
		assert.equal("Blue", library.records[1].originName)
		assert.equal("1:202,0,0", library.records[1].look)
	end)

	-- Set IDs restart at zero on every character, so the same number names a
	-- different set on each of them.
	it("keeps two characters' custom sets apart under one ID", function()
		local library = Library.New()
		Sync.Reconcile(library, owner, Sets(), 10, true)
		Sync.Reconcile(library, { guid = "Player-2", name = "Beta" }, Sets(), 10, true)
		assert.equal(2, #Library.Sorted(library))
	end)

	it("leaves another character's custom sets alone", function()
		local library = Library.New()
		Sync.Reconcile(library, owner, Sets(), 10, true)
		local stats = Sync.Reconcile(library, { guid = "Player-2", name = "Beta" },
			{ { customSetID = 9, name = "Green", look = { [1] = { 303, 0, 0 } } } },
			20, true)
		assert.equal(0, stats.pruned)
		assert.equal(2, #Library.Sorted(library))
	end)

	it("only prunes on a trustworthy empty enumeration", function()
		local library = Library.New()
		Sync.Reconcile(library, owner, Sets(), 10, true)
		local uncertain, why = Sync.Reconcile(library, owner, {}, 20, false)
		assert.equal("custom sets unavailable", why)
		assert.equal(0, uncertain.pruned)
		local certain = Sync.Reconcile(library, owner, {}, 30, true)
		assert.equal(1, certain.pruned)
	end)

	it("counts a set whose item list is unavailable", function()
		local library = Library.New()
		local sets = Sets()
		sets[1].look = nil
		local stats = Sync.Reconcile(library, owner, sets, 10, true)
		assert.equal(1, stats.missing)
		assert.same({ { customSetID = 7, name = "Red" } }, stats.missingSets)
		assert.same({}, library.records)
	end)
end)
