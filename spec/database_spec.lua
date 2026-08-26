local Database = require("Database")

describe("Database.MigrateOrInit", function()
	it("initializes new account and character data", function()
		local account, char = Database.MigrateOrInit(nil, nil)

		assert.equal(1, account.version)
		assert.is_true(account.previewEnabled)
		assert.is_false(account.hideEmptyCategories)
		assert.equal("random", account.titleFallbackMode)
		assert.equal(4, char.version)
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

		assert.equal(4, char.version)
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
		assert.equal(4, char.version)
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
		local pin = account.mountPins[2747]

		local accountAgain, charAgain = Database.MigrateOrInit(account, char)

		assert.equal(account, accountAgain)
		assert.equal(char, charAgain)
		assert.equal(pin, accountAgain.mountPins[2747])
		assert.is_true(pin.permanent)
		assert.is_nil(pin.manual)
	end)

	it("preserves version 2 data while filling missing tables", function()
		local cats = { [7] = { id = 7, name = "Kept" } }
		local old = { version = 2, cats = cats, custom = { kept = true } }
		local account, char = Database.MigrateOrInit({}, old)

		assert.equal(old, char)
		assert.equal(4, char.version)
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
		assert.same({ acquiredAt = 1000, expiresAt = 1000 + 7 * 86400 },
			account.mountPins[2747])
	end)
end)
