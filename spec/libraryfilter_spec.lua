local LibraryFilter = require("LibraryFilter")

describe("LibraryFilter", function()
	local records = {
		{ id = 3, raceID = 6, classID = 1 },
		{ id = 2, raceID = 4, classID = 8 },
		{ id = 1, raceID = 6, classID = 3 },
	}

	it("shows every race by default", function()
		local state = LibraryFilter.New()
		assert.same(records, LibraryFilter.Apply(records, state))
	end)

	it("selects more than one race", function()
		local state = LibraryFilter.New()
		LibraryFilter.SelectNone(state)
		LibraryFilter.SetRace(state, 4, true)
		LibraryFilter.SetRace(state, 6, true)
		assert.same(records, LibraryFilter.Apply(records, state))
	end)

	it("filters records to selected races without reordering them", function()
		local state = LibraryFilter.New()
		LibraryFilter.SelectNone(state)
		LibraryFilter.SetRace(state, 6, true)
		assert.same({ records[1], records[3] }, LibraryFilter.Apply(records, state))
	end)

	it("supports all and none actions", function()
		local state = LibraryFilter.New()
		LibraryFilter.SelectNone(state)
		assert.same({}, LibraryFilter.Apply(records, state))
		LibraryFilter.SelectAll(state)
		assert.same(records, LibraryFilter.Apply(records, state))
	end)

	it("can remove one race from the default all selection", function()
		local state = LibraryFilter.New()
		LibraryFilter.SetRace(state, 6, false)
		assert.same({ records[2] }, LibraryFilter.Apply(records, state))
	end)

	it("lists each numeric race once in stable order", function()
		local mixed = { records[1], { raceID = "4" }, {}, records[2], records[3] }
		assert.same({ 4, 6 }, LibraryFilter.Races(mixed))
	end)

	it("counts selected races for a visible diagnostic", function()
		local state = LibraryFilter.New()
		LibraryFilter.SelectNone(state)
		LibraryFilter.SetRace(state, 6, true)
		assert.equal(1, LibraryFilter.SelectionCount(state, { 4, 6 }))
	end)

	it("selects more than one class", function()
		local state = LibraryFilter.New()
		LibraryFilter.SelectNoClasses(state)
		LibraryFilter.SetClass(state, 1, true)
		LibraryFilter.SetClass(state, 3, true)
		assert.same({ records[1], records[3] }, LibraryFilter.Apply(records, state))
	end)

	it("can remove one class from the default all selection", function()
		local state = LibraryFilter.New()
		LibraryFilter.SetClass(state, 8, false)
		assert.same({ records[1], records[3] }, LibraryFilter.Apply(records, state))
	end)

	it("composes race and class selections", function()
		local state = LibraryFilter.New()
		LibraryFilter.SelectNone(state)
		LibraryFilter.SetRace(state, 6, true)
		LibraryFilter.SelectNoClasses(state)
		LibraryFilter.SetClass(state, 3, true)
		assert.same({ records[3] }, LibraryFilter.Apply(records, state))
	end)

	it("supports class all and none independently from race", function()
		local state = LibraryFilter.New()
		LibraryFilter.SetRace(state, 4, false)
		LibraryFilter.SelectNoClasses(state)
		assert.same({}, LibraryFilter.Apply(records, state))
		LibraryFilter.SelectAllClasses(state)
		assert.same({ records[1], records[3] }, LibraryFilter.Apply(records, state))
	end)

	it("lists and counts numeric classes for a visible diagnostic", function()
		local mixed = { records[1], { classID = "8" }, {}, records[2], records[3] }
		assert.same({ 1, 3, 8 }, LibraryFilter.Classes(mixed))
		local state = LibraryFilter.New()
		LibraryFilter.SelectNoClasses(state)
		LibraryFilter.SetClass(state, 3, true)
		assert.equal(1, LibraryFilter.ClassSelectionCount(state, { 1, 3, 8 }))
	end)

	it("maps every playable class to its armor type", function()
		assert.same({
			"Plate", "Plate", "Mail", "Leather", "Cloth", "Plate", "Mail",
			"Cloth", "Cloth", "Leather", "Leather", "Leather", "Mail",
		}, (function()
			local types = {}
			for classID = 1, 13 do
				types[#types + 1] = LibraryFilter.ArmorType(classID)
			end
			return types
		end)())
	end)

	it("multi-selects armor types and composes them with class", function()
		local state = LibraryFilter.New()
		LibraryFilter.SelectNoArmorTypes(state)
		LibraryFilter.SetArmorType(state, "Plate", true)
		LibraryFilter.SetArmorType(state, "Mail", true)
		LibraryFilter.SetClass(state, 3, false)
		assert.same({ records[1] }, LibraryFilter.Apply(records, state))
	end)

	it("supports armor all, none, and visible selection count", function()
		local state = LibraryFilter.New()
		LibraryFilter.SelectNoArmorTypes(state)
		assert.same({}, LibraryFilter.Apply(records, state))
		LibraryFilter.SetArmorType(state, "Leather", true)
		assert.equal(1, LibraryFilter.ArmorSelectionCount(state))
		LibraryFilter.SelectAllArmorTypes(state)
		assert.same(records, LibraryFilter.Apply(records, state))
	end)

	it("checks and unchecks every filter domain together", function()
		local state = LibraryFilter.New()
		LibraryFilter.SelectNoFilters(state)
		assert.same({}, LibraryFilter.Apply(records, state))
		assert.is_false(LibraryFilter.IsRaceSelected(state, 6))
		assert.is_false(LibraryFilter.IsClassSelected(state, 1))
		assert.is_false(LibraryFilter.IsArmorTypeSelected(state, "Plate"))
		LibraryFilter.SelectAllFilters(state)
		assert.same(records, LibraryFilter.Apply(records, state))
	end)

	-- The two modes are exclusive: snapshots are other people, recorded
	-- account-wide, and everything else belongs to one of your characters.
	describe("modes", function()
		local mixed = {
			{ id = 1, source = "snap", raceID = 1, classID = 1 },
			{ id = 2, source = "mine", origin = "outfit", guid = "P1",
				look = "1:9,0,0", scanned = true, raceID = 1, classID = 1 },
			{ id = 3, source = "mine", origin = "customSet", guid = "P2",
				look = "1:9,0,0", raceID = 1, classID = 1 },
		}

		local function Mine()
			local state = LibraryFilter.New()
			LibraryFilter.SetMode(state, "mine")
			return state
		end

		it("starts on snapshots", function()
			assert.is_true(LibraryFilter.IsSnapshotMode(LibraryFilter.New()))
			assert.same({ mixed[1] }, LibraryFilter.Apply(mixed, LibraryFilter.New()))
		end)

		it("shows outfits and custom sets together on my characters", function()
			assert.same({ mixed[2], mixed[3] }, LibraryFilter.Apply(mixed, Mine()))
		end)

		it("turns either of my sources off without touching the other", function()
			local state = Mine()
			LibraryFilter.SetSource(state, "customSets", false)
			assert.same({ mixed[2] }, LibraryFilter.Apply(mixed, state))
			LibraryFilter.SetSource(state, "customSets", true)
			LibraryFilter.SetSource(state, "outfits", false)
			assert.same({ mixed[3] }, LibraryFilter.Apply(mixed, state))
		end)

		-- Picking characters already picks their classes and armour, so those
		-- filters would only be a second way to say the same thing.
		it("ignores race, class and armour on my own characters", function()
			local state = Mine()
			LibraryFilter.SelectNone(state)
			LibraryFilter.SelectNoClasses(state)
			LibraryFilter.SelectNoArmorTypes(state)
			assert.same({ mixed[2], mixed[3] }, LibraryFilter.Apply(mixed, state))
		end)

		it("applies race to snapshots", function()
			local state = LibraryFilter.New()
			LibraryFilter.SelectNone(state)
			assert.same({}, LibraryFilter.Apply(mixed, state))
		end)

		it("ignores which characters are chosen while showing snapshots", function()
			local state = LibraryFilter.New()
			LibraryFilter.SelectNoOwners(state)
			assert.same({ mixed[1] }, LibraryFilter.Apply(mixed, state))
		end)

		it("multi-selects owners on my characters", function()
			local state = Mine()
			LibraryFilter.SelectNoOwners(state)
			LibraryFilter.SetOwner(state, "P2", true)
			assert.same({ mixed[3] }, LibraryFilter.Apply(mixed, state))
			assert.same({ "P1", "P2" }, LibraryFilter.Owners(mixed))
			assert.equal(1, LibraryFilter.OwnerSelectionCount(state, { "P1", "P2" }))
		end)
	end)

	describe("outfits with nothing set", function()
		local outfits = {
			{ id = 1, source = "mine", origin = "outfit", guid = "P1",
				look = "1:9,0,0", scanned = true },
			{ id = 2, source = "mine", origin = "outfit", guid = "P1",
				look = "", scanned = true },
			{ id = 3, source = "mine", origin = "outfit", guid = "P1",
				look = "", scanned = false },
		}

		local function Mine()
			local state = LibraryFilter.New()
			LibraryFilter.SetMode(state, "mine")
			return state
		end

		-- An outfit nobody has read yet is still worth showing: it is the one
		-- you would click to go and read it.
		it("hides an outfit read as empty but keeps an unread one", function()
			assert.same({ outfits[1], outfits[3] },
				LibraryFilter.Apply(outfits, Mine()))
		end)

		it("shows the empty one when asked", function()
			local state = Mine()
			LibraryFilter.SetHideEmptyOutfits(state, false)
			assert.same(outfits, LibraryFilter.Apply(outfits, state))
		end)
	end)

	it("searches character names without case sensitivity", function()
		assert.is_true(LibraryFilter.NameMatches({ name = "Thunderhoof" }, "hoof"))
		assert.is_true(LibraryFilter.NameMatches({ name = "Thunderhoof" }, "THUNDER"))
		assert.is_false(LibraryFilter.NameMatches({ name = "Thunderhoof" }, "elf"))
	end)

	describe("OwnerEntries", function()
		local owned = {
			{ source = "mine", guid = "P2", name = "Bravo", realm = "Aegwynn", classID = 8 },
			{ source = "mine", guid = "P1", name = "Alpha", realm = "Aegwynn", classID = 4 },
			{ source = "mine", guid = "P1", name = "Alpha", realm = "Aegwynn", classID = 4 },
			{ source = "snap", guid = "P9", name = "Stranger", classID = 1 },
		}

		it("lists each owner once, sorted by name then realm", function()
			assert.same({
				{ guid = "P1", name = "Alpha", realm = "Aegwynn", classID = 4 },
				{ guid = "P2", name = "Bravo", realm = "Aegwynn", classID = 8 },
			}, LibraryFilter.OwnerEntries(owned))
		end)

		it("leaves out anyone who only appears in a snapshot", function()
			for _, entry in ipairs(LibraryFilter.OwnerEntries(owned)) do
				assert.not_equal("P9", entry.guid)
			end
		end)

		it("falls back to the GUID when a record carries no name", function()
			local entries = LibraryFilter.OwnerEntries({
				{ source = "mine", guid = "P7" },
			})
			assert.equal("P7", entries[1].name)
		end)
	end)

	-- The box searches whatever the card is titled with, which is the set name
	-- on your own characters and the player's name on a snapshot.
	describe("NameMatches", function()
		it("matches a snapshot on the player's name", function()
			local snap = { source = "snap", name = "Gsxr" }
			assert.is_true(LibraryFilter.NameMatches(snap, "gsx"))
			assert.is_false(LibraryFilter.NameMatches(snap, "tier"))
		end)

		it("matches one of mine on the set name, not the character", function()
			local mine = { source = "mine", origin = "outfit",
				originName = "Nax necromancer", name = "Bitwise" }
			assert.is_true(LibraryFilter.NameMatches(mine, "necro"))
			assert.is_false(LibraryFilter.NameMatches(mine, "bitwise"))
		end)

		it("matches everything on an empty query", function()
			assert.is_true(LibraryFilter.NameMatches({ source = "snap" }, ""))
			assert.is_true(LibraryFilter.NameMatches({ source = "snap" }, nil))
		end)
	end)

	describe("custom set ownership", function()
		local sets = {
			{ id = 1, source = "mine", origin = "customSet", guid = "Player-1" },
			{ id = 2, source = "mine", origin = "customSet", guid = "Player-2" },
		}

		local function ShowOnlyCustomSets()
			local state = LibraryFilter.New()
			LibraryFilter.SetMode(state, "mine")
			LibraryFilter.SetSource(state, "outfits", false)
			return state
		end

		it("lists the characters that own custom sets", function()
			assert.same({ "Player-1", "Player-2" }, LibraryFilter.Owners(sets))
		end)

		it("hides a custom set whose character is unselected", function()
			local state = ShowOnlyCustomSets()
			LibraryFilter.SelectNoOwners(state)
			LibraryFilter.SetOwner(state, "Player-1", true)
			local shown = LibraryFilter.Apply(sets, state)
			assert.equal(1, #shown)
			assert.equal(1, shown[1].id)
		end)
	end)

end)

-- The wall opens on the character you are playing, in the order that
-- character's own outfit list uses, because that is the order the user has
-- already learned. Everyone else keeps the order they arrived in.
describe("LibraryFilter.Order", function()
	local function Mine(guid, originID, origin)
		return { source = "mine", origin = origin or "outfit",
			originID = originID, guid = guid }
	end
	local snap = { source = "snap", look = "1:1,0,0" }

	it("puts the current character ahead of the others", function()
		local ordered = LibraryFilter.Order(
			{ Mine("P2", 1), snap, Mine("P1", 2) }, "P1", nil)
		assert.equal("P1", ordered[1].guid)
	end)

	it("orders that character's outfits by the given rank", function()
		local a, b, c = Mine("P1", 10), Mine("P1", 20), Mine("P1", 30)
		local ordered = LibraryFilter.Order({ a, b, c }, "P1",
			{ [30] = 1, [10] = 2, [20] = 3 })
		assert.same({ c, a, b }, ordered)
	end)

	-- A custom set has an originID of its own that means nothing to the
	-- outfit tree, so it must not be ranked by it.
	it("leaves custom sets after the ranked outfits", function()
		local set = Mine("P1", 1, "customSet")
		local outfit = Mine("P1", 10)
		local ordered = LibraryFilter.Order({ set, outfit }, "P1", { [10] = 1 })
		assert.same({ outfit, set }, ordered)
	end)

	it("keeps the order it was given where nothing else decides", function()
		local x, y, z = Mine("P2", 1), Mine("P3", 2), Mine("P2", 3)
		assert.same({ x, y, z }, LibraryFilter.Order({ x, y, z }, "P1", nil))
	end)

	it("changes nothing without a character to favour", function()
		local list = { Mine("P1", 1), snap }
		assert.same(list, LibraryFilter.Order(list, nil, nil))
	end)
end)

-- The header says "50 of 247 looks from my characters", so the 247 has to be
-- the wall you are on. The other mode's looks are not 247 minus 50; they are a
-- different collection that this sentence is not about.
describe("LibraryFilter.ModeCount", function()
	local records = {
		{ id = 1, source = "mine", guid = "P1" },
		{ id = 2, source = "mine", guid = "P2" },
		{ id = 3, raceID = 6, classID = 1 },
	}

	it("counts only your own characters' looks in that mode", function()
		local state = LibraryFilter.New()
		LibraryFilter.SetMode(state, "mine")
		assert.equal(2, LibraryFilter.ModeCount(records, state))
	end)

	it("counts only snapshots in snapshot mode", function()
		local state = LibraryFilter.New()
		LibraryFilter.SetMode(state, "snapshots")
		assert.equal(1, LibraryFilter.ModeCount(records, state))
	end)

	-- Whatever else is selected, this is the size of the wall before the
	-- filters narrow it, or the count would compare a number against itself.
	it("ignores the narrowing filters", function()
		local state = LibraryFilter.New()
		LibraryFilter.SetMode(state, "snapshots")
		LibraryFilter.SelectNone(state)
		assert.equal(1, LibraryFilter.ModeCount(records, state))
	end)

	it("counts nothing where there is nothing", function()
		assert.equal(0, LibraryFilter.ModeCount({}, LibraryFilter.New()))
		assert.equal(0, LibraryFilter.ModeCount(nil, nil))
	end)
end)
