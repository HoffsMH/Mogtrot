local Database = require("Database")
local Library = require("Library")

describe("Database.MigrateOrInit", function()
	it("initializes new account and character data", function()
		local account, char = Database.MigrateOrInit(nil, nil)

		assert.equal(3, account.version)
		assert.is_true(account.previewEnabled)
		assert.is_false(account.hideEmptyCategories)
		assert.equal("random", account.titleFallbackMode)
		assert.equal(6, char.version)
		assert.same({}, char.titles)
		assert.same({}, char.titleRotation)
		assert.same({ "Tier", "Non-tier sets", "Simple", "Unsorted" }, {
			char.cats[char.roots[1]].name,
			char.cats[char.roots[2]].name,
			char.cats[char.roots[3]].name,
			char.cats[char.roots[4]].name,
		})
		assert.is_true(char.cats[char.roots[4]].protected)
		assert.is_table(char.cats[char.roots[1]].color)
	end)

	it("adds safe colors while migrating version 3 categories", function()
		local old = {
			version = 3,
			cats = { [7] = { id = 7, name = "Kept", color = { r = 2 } } },
			roots = { 7 },
			assign = {},
		}
		local _, char = Database.MigrateOrInit({}, old)

		assert.equal(6, char.version)
		assert.is_true(char.cats[7].color.r <= 1)
		assert.equal("Kept", char.cats[7].name)
	end)

	it("preserves an unknown newer account schema", function()
		local pin = { acquiredAt = 1000, manual = true, future = "kept" }
		local account = {
			version = 99,
			mountPins = { [2747] = pin },
			future = { kept = true },
		}
		local migrated = Database.MigrateOrInit(account, {})

		assert.equal(account, migrated)
		assert.equal(99, migrated.version)
		assert.equal(pin, migrated.mountPins[2747])
		assert.is_true(migrated.mountPins[2747].manual)
		assert.same({ kept = true }, migrated.future)
	end)

	it("preserves an unknown newer character schema", function()
		local cats = { [7] = { id = 7, name = "Future category" } }
		local future = {
			version = 99,
			cats = cats,
			roots = { 7 },
			assign = { [42] = 7 },
			mounts = { [42] = 2747 },
			future = { kept = true },
		}
		local _, char = Database.MigrateOrInit({}, future)

		assert.equal(future, char)
		assert.equal(99, char.version)
		assert.equal(cats, char.cats)
		assert.same({ 7 }, char.roots)
		assert.same({ [42] = 7 }, char.assign)
		assert.equal(2747, char.mounts[42])
		assert.same({ kept = true }, char.future)
	end)

	it("preserves populated character data without a version", function()
		local cats = { [7] = { id = 7, name = "Legacy category" } }
		local old = {
			cats = cats,
			roots = { 7 },
			assign = { [42] = 7 },
			looks = { [42] = { [1] = { appearanceID = 100 } } },
			mounts = { [42] = { [2747] = true } },
			titles = { [42] = { [1] = true } },
			wear = { [42] = { seconds = 12 } },
		}
		local _, char = Database.MigrateOrInit({}, old)

		assert.equal(old, char)
		assert.equal(6, char.version)
		assert.equal(cats, char.cats)
		assert.same({ 7 }, char.roots)
		assert.same({ [42] = 7 }, char.assign)
		assert.same({ [2747] = true }, char.mounts[42])
		assert.same({ [1] = true }, char.titles[42])
		assert.same({ seconds = 12 }, char.wear[42])
	end)

	it("is idempotent after migrating current data", function()
		local account, char = Database.MigrateOrInit({
			mountPins = { [2747] = { acquiredAt = 1000, manual = true } },
		}, {
			version = 2,
			cats = { [7] = { id = 7, name = "Kept" } },
			roots = { 7 },
			assign = {},
		})
		assert.is_nil(account.mountPins) -- old key removed by the move
		local pin = account.pins.mounts.records[2747]

		local accountAgain, charAgain = Database.MigrateOrInit(account, char)

		assert.equal(account, accountAgain)
		assert.equal(char, charAgain)
		assert.equal(pin, accountAgain.pins.mounts.records[2747])
		assert.is_true(pin.permanent)
		assert.is_nil(pin.manual)
	end)

	it("preserves version 2 data while filling missing tables", function()
		local cats = { [7] = { id = 7, name = "Kept" } }
		local old = { version = 2, cats = cats, custom = { kept = true } }
		local account, char = Database.MigrateOrInit({}, old)

		assert.equal(old, char)
		assert.equal(6, char.version)
		assert.equal(cats, char.cats)
		assert.same({ kept = true }, char.custom)
		assert.same({}, char.roots)
		assert.same({}, char.assign)
		assert.same({}, char.looks)
		assert.same({}, char.slots)
		assert.same({}, char.mounts)
		assert.same({}, char.wear)
		assert.same({}, char.titles)
		assert.same({}, char.titleRotation)
		assert.is_true(account.previewEnabled)
	end)

	it("converts an old single mount link to a set", function()
		local _, char = Database.MigrateOrInit({}, { mounts = { [10] = 123 } })
		assert.same({ [123] = true }, char.mounts[10])
	end)

	it("migrates the old automatic pin to a fixed expiration", function()
		local account = { mountPins = {
			[2747] = { acquiredAt = 1000, autoExpiresAt = 2000 },
		} }
		account = Database.MigrateOrInit(account, {})
		assert.is_nil(account.mountPins) -- old key removed by the move
		assert.same({ acquiredAt = 1000, expiresAt = 1000 + 7 * 86400 },
			account.pins.mounts.records[2747])
	end)
end)

-- Version 2 account / version 5 character contracts (corrected plan audit).
describe("Database.MigrateOrInit v2/v5", function()
	local function FreshDomains()
		return Database.MigrateOrInit(nil, nil)
	end

	-- Structural snapshot for no-mutation proofs: captures the input as an
	-- independent deep copy so post-call equality means nothing changed.
	local function DeepCopy(value)
		if type(value) ~= "table" then return value end
		local copy = {}
		for k, v in pairs(value) do copy[k] = DeepCopy(v) end
		return copy
	end

	it("targets account version 3 and character version 5", function()
		local account, char = FreshDomains()
		assert.equal(3, account.version)
		assert.equal(6, char.version)
	end)

	it("initializes three distinct pin domains with no baseline records", function()
		local account = FreshDomains()
		local pins = account.pins
		assert.is_table(pins)
		assert.is_table(pins.mounts)
		assert.is_table(pins.hearthstones)
		assert.not_equal(pins.mounts, pins.hearthstones)
		for _, domain in pairs(pins) do
			assert.is_true(domain.autoNew)
			assert.same({}, domain.records)
		end
		-- A mount pin is a shortcut that goes stale; a hearthstone pin says
		-- which stone belongs with a look, which does not.
		assert.equal(7, pins.mounts.days)
		assert.equal(0, pins.hearthstones.days)
		assert.is_nil(account.mountPins)
		assert.is_nil(account.autoPinNewMounts)
		assert.is_nil(account.autoPinNewMountDays)
	end)

	it("initializes character link, opt-out and rotation tables distinctly", function()
		local _, char = FreshDomains()
		assert.same({}, char.hearthstones)
		assert.is_table(char.pinOptOut)
		assert.is_table(char.pinOptOut.mounts)
		assert.is_table(char.pinOptOut.hearthstones)
		assert.not_equal(char.pinOptOut.mounts, char.pinOptOut.hearthstones)
		assert.is_table(char.rotations)
		assert.is_table(char.rotations.hearthstones)
		assert.is_nil(char.noPinnedShuffle)
	end)

	it("moves mountPins by reference and preserves false and zero exactly", function()
		local records = { [2747] = { acquiredAt = 1000, expiresAt = 2000 } }
		local account = Database.MigrateOrInit({
			version = 1,
			mountPins = records,
			autoPinNewMounts = false,
			autoPinNewMountDays = 0,
		}, {})

		assert.equal(3, account.version)
		assert.equal(records, account.pins.mounts.records)
		assert.is_false(account.pins.mounts.autoNew)
		assert.equal(0, account.pins.mounts.days)
		assert.is_nil(account.mountPins)
		assert.is_nil(account.autoPinNewMounts)
		assert.is_nil(account.autoPinNewMountDays)
	end)

	it("initializes the other pin domains when migrating v1", function()
		local account = Database.MigrateOrInit({
			version = 1,
			mountPins = { [2747] = { acquiredAt = 1000 } },
		}, {})
		assert.same({}, account.pins.hearthstones.records)
	end)

	it("preserves unknown record fields through the v1 move", function()
		local account = Database.MigrateOrInit({
			version = 1,
			mountPins = { [2747] = { acquiredAt = 1000, expiresAt = 2000, label = "kept" } },
		}, {})
		assert.equal("kept", account.pins.mounts.records[2747].label)
	end)

	it("converts legacy manual and autoExpiresAt records before moving", function()
		local account = Database.MigrateOrInit({
			mountPins = {
				[1] = { acquiredAt = 1000, manual = true },
				[2] = { acquiredAt = 1000, autoExpiresAt = 2000 },
			},
		}, {})
		assert.is_nil(account.pins.mounts.records[1].manual)
		assert.is_true(account.pins.mounts.records[1].permanent)
		assert.same({ acquiredAt = 1000, expiresAt = 1000 + 7 * 86400 },
			account.pins.mounts.records[2])
		assert.is_nil(account.pins.mounts.records[2].autoExpiresAt)
	end)

	it("moves noPinnedShuffle by reference into pinOptOut.mounts", function()
		local noPinnedShuffle = { [7] = true }
		local cats = { [7] = { id = 7, name = "Kept" } }
		local _, char = Database.MigrateOrInit({}, {
			version = 4,
			cats = cats,
			roots = { 7 },
			assign = {},
			noPinnedShuffle = noPinnedShuffle,
		})
		assert.equal(6, char.version)
		assert.equal(noPinnedShuffle, char.pinOptOut.mounts)
		assert.is_nil(char.noPinnedShuffle)
	end)

	it("preserves existing character tables by reference through v5", function()
		local cats = { [7] = { id = 7, name = "Kept", color = { r = 0.5, g = 0.5, b = 0.5 } } }
		local refs = {
			looks = { [42] = { [1] = { appearanceID = 100 } } },
			slots = { [1] = {} },
			mounts = { [42] = { [2747] = true } },
			wear = { [42] = { seconds = 12 } },
			titles = { [42] = { [1] = true } },
			titleRotation = { 1 },
			assign = { [42] = 7 },
		}
		local _, char = Database.MigrateOrInit({}, {
			version = 4,
			cats = cats,
			roots = { 7 },
			mounts = refs.mounts,
			looks = refs.looks,
			slots = refs.slots,
			wear = refs.wear,
			titles = refs.titles,
			titleRotation = refs.titleRotation,
			assign = refs.assign,
		})
		assert.equal(6, char.version)
		assert.equal(cats, char.cats)
		assert.equal(refs.looks, char.looks)
		assert.equal(refs.slots, char.slots)
		assert.equal(refs.mounts, char.mounts)
		assert.equal(refs.wear, char.wear)
		assert.equal(refs.titles, char.titles)
		assert.equal(refs.titleRotation, char.titleRotation)
		assert.equal(refs.assign, char.assign)
		assert.same({}, char.hearthstones)
		assert.is_table(char.pinOptOut.mounts)
		assert.is_table(char.pinOptOut.hearthstones)
		assert.is_table(char.rotations.hearthstones)
	end)

	it("keeps the full character chain: unversioned saved tree reaches v5", function()
		local cats = { [7] = { id = 7, name = "Kept", color = { r = 2 } } }
		local _, char = Database.MigrateOrInit({}, {
			cats = cats,
			roots = { 7 },
			assign = {},
			mounts = { [42] = 2747 },
		})
		assert.equal(6, char.version)
		assert.is_true(char.cats[7].color.r <= 1)
		assert.same({ [2747] = true }, char.mounts[42])
	end)

	it("keeps unknown future account and character schemas byte-for-byte", function()
		local account = { version = 99, mountPins = {}, future = { kept = true } }
		local char = { version = 99, cats = { [7] = { id = 7 } }, future = { kept = true } }
		local expectedAccount, expectedChar = DeepCopy(account), DeepCopy(char)
		local migratedAccount, migratedChar = Database.MigrateOrInit(account, char)
		assert.equal(account, migratedAccount)
		assert.equal(char, migratedChar)
		assert.same(expectedAccount, migratedAccount)
		assert.same(expectedChar, migratedChar)
		assert.is_nil(migratedAccount.pins)
		assert.is_nil(migratedAccount.library)
		assert.is_nil(migratedChar.pinOptOut)
		assert.is_nil(migratedChar.rotations)
		assert.is_nil(migratedChar.battlePets)
		assert.is_nil(migratedChar.hearthstones)
	end)

	it("aborts the account store on a mixed source/destination collision", function()
		local records = { [2747] = { acquiredAt = 1000 } }
		local existing = { records = { [1] = { acquiredAt = 5 } } }
		local input = {
			version = 1,
			mountPins = records,
			pins = { mounts = existing },
		}
		local expected = DeepCopy(input)
		local account = Database.MigrateOrInit(input, {})
		assert.same(expected, account)
		assert.equal(records, account.mountPins)
		assert.equal(existing, account.pins.mounts)
		assert.equal(1, account.version)
	end)

	it("allows an identical-reference collision and migrates idempotently", function()
		local records = { [2747] = { acquiredAt = 1000 } }
		local account = Database.MigrateOrInit({
			version = 1,
			mountPins = records,
			pins = { mounts = { records = records } },
		}, {})
		assert.equal(3, account.version)
		assert.equal(records, account.pins.mounts.records)

		local again = Database.MigrateOrInit(account, {})
		assert.equal(account, again)
		assert.equal(records, again.pins.mounts.records)
		assert.equal(3, again.version)
	end)
	it("keeps the v2 chain: color normalization and numeric mount conversion before v5", function()
		local cats = { [7] = { id = 7, name = "Kept", color = { r = 2 } } }
		local _, char = Database.MigrateOrInit({}, {
			version = 2,
			cats = cats,
			roots = { 7 },
			assign = {},
			mounts = { [42] = 2747 },
		})
		assert.equal(6, char.version)
		assert.is_true(char.cats[7].color.r <= 1)
		assert.equal("Kept", char.cats[7].name)
		assert.same({ [2747] = true }, char.mounts[42])
	end)

	it("keeps the v3 chain: numeric mount-link conversion before v5", function()
		local _, char = Database.MigrateOrInit({}, {
			version = 3,
			cats = { [7] = { id = 7, name = "Kept", color = { r = 0.5, g = 0.5, b = 0.5 } } },
			roots = { 7 },
			assign = {},
			mounts = { [42] = 2747 },
		})
		assert.equal(6, char.version)
		assert.same({ [2747] = true }, char.mounts[42])
	end)


	it("aborts the character store on a mixed source/destination collision", function()
		local noPinnedShuffle = { [7] = true }
		local existing = { [1] = true }
		local input = {
			version = 4,
			cats = { [7] = { id = 7, name = "Kept", color = { r = 0.5, g = 0.5, b = 0.5 } } },
			roots = { 7 },
			assign = {},
			noPinnedShuffle = noPinnedShuffle,
			pinOptOut = { mounts = existing },
		}
		local expected = DeepCopy(input)
		local _, char = Database.MigrateOrInit({}, input)
		assert.same(expected, char)
		assert.equal(noPinnedShuffle, char.noPinnedShuffle)
		assert.equal(existing, char.pinOptOut.mounts)
		assert.equal(4, char.version)
	end)

	-- v5 looks may hold equipped gear rendered through slots the outfit leaves
	-- empty, and nothing records which, so every definition is read again once.
	it("moves v5 to v6 keeping every store and asking for one re-read of looks", function()
		local input = {
			version = 5,
			nextID = 8,
			cats = { [7] = { id = 7, name = "Kept", color = { r = 0.5, g = 0.5, b = 0.5 },
				items = { 3 } } },
			roots = { 7 },
			assign = { [3] = 7 },
			looks = { [3] = { [1] = { 302897, 0, 0 }, [4] = { 83202, 0, 0 } } },
			slots = { [3] = { covered = 9, total = 14, missing = {}, at = 120100 } },
			mounts = { [3] = { [2747] = true } },
			wear = { [3] = { seconds = 60, last = 1 } },
		}
		local expected = DeepCopy(input)
		local _, char = Database.MigrateOrInit({}, input)

		assert.equal(6, char.version)
		assert.is_true(char.rereadLooks)
		assert.same({}, char.worn)
		assert.same({ 7 }, char.roots)
		for _, key in ipairs({ "nextID", "cats", "assign", "looks", "slots", "mounts", "wear" }) do
			assert.same(expected[key], char[key], key)
		end
	end)

	it("asks a fresh character for no re-read", function()
		local _, char = Database.MigrateOrInit({}, nil)
		assert.is_nil(char.rereadLooks)
		assert.same({}, char.worn)
	end)

	it("leaves a v6 character alone", function()
		local input = { version = 6, looks = {}, worn = { [3] = {} }, cats = {}, roots = {} }
		local _, char = Database.MigrateOrInit({}, input)
		assert.is_nil(char.rereadLooks)
		assert.same({ [3] = {} }, char.worn)
	end)
end)

-- The outfit library arrives additively: no other store moves, and a character
-- never sees it.
describe("Database.MigrateOrInit library", function()
	it("gives a fresh account an empty library", function()
		local account = Database.MigrateOrInit(nil, nil)
		assert.is_table(account.library)
		assert.equal(Library.VERSION, account.library.version)
		assert.equal(1, account.library.nextID)
		assert.same({}, account.library.records)
	end)

	it("adds the library to a version 2 account and leaves its data alone", function()
		local records = { [2747] = { acquiredAt = 1000 } }
		local account = Database.MigrateOrInit({
			version = 2,
			previewEnabled = false,
			pins = { mounts = { autoNew = false, days = 3, records = records } },
		}, {})
		assert.equal(3, account.version)
		assert.is_table(account.library)
		assert.equal(records, account.pins.mounts.records)
		assert.is_false(account.pins.mounts.autoNew)
		assert.equal(3, account.pins.mounts.days)
		assert.is_false(account.previewEnabled)
	end)

	it("keeps an existing library's records across a reload", function()
		local account = Database.MigrateOrInit(nil, nil)
		account.library.records[1] = { id = 1, source = "snap", look = "1:5,0,0" }
		account.library.nextID = 2
		local again = Database.MigrateOrInit(account, {})
		assert.equal(2, again.library.nextID)
		assert.equal("snap", again.library.records[1].source)
	end)

	it("does not touch a library written by a newer build", function()
		local future = { version = 99, nextID = 8, records = { [7] = { kept = true } } }
		local account = Database.MigrateOrInit({ version = 2, library = future }, {})
		assert.equal(future, account.library)
		assert.equal(99, account.library.version)
		assert.is_true(account.library.records[7].kept)
	end)

	it("keeps the library off the character store", function()
		local _, char = Database.MigrateOrInit(nil, nil)
		assert.is_nil(char.library)
	end)
end)

describe("Database.MigrateOrInit archive retention", function()
	it("keeps archived snapshots for a month by default", function()
		local account = Database.MigrateOrInit(nil, nil)
		assert.equal(30, account.archiveDays)
	end)

	it("leaves a chosen retention alone, including never", function()
		local account = Database.MigrateOrInit({ version = 3, archiveDays = 0 }, nil)
		assert.equal(0, account.archiveDays)
	end)
end)
