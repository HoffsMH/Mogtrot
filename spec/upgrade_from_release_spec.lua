-- Saved data from every released tag must come through the current migration
-- and sync with nothing lost, nothing doubled, and nothing changed by a second
-- run.
--
-- How the fixtures were made: each tag was exported with git archive, and a
-- scratch script loaded that tag's own Database, Tree, CategoryColor,
-- MountPins, OutfitTitles, OutfitWearTime and Lint. It made a fresh store with
-- the tag's MigrateOrInit, wrote settings the way the tag's settings panel
-- does, pinned, unpinned and linked through the tag's modules, loaded the
-- store once more as a second login does, and printed it with sorted keys.
-- Colours come from the tag's CategoryColor.Random under math.randomseed(1).
-- 12.1.0-1 and 12.1.0-2 differ only in the release workflow, so they wrote
-- byte-identical stores and share one fixture. A pre-release "manual = true"
-- pin is absent on purpose: every tag rewrote it on each load, so none saved it.
require("spec.wow_stubs")
local Database = require("Database")
local Tree = require("Tree")
local CategoryColor = require("CategoryColor")
local Library = require("Library")
local OutfitLibrarySync = require("OutfitLibrarySync")
local OutfitTitles = require("OutfitTitles")
local Pins = require("Pins")

local NOW, DAY = 1790000000, 86400
local MAIN_GUID, ALT_GUID = "Player-1-00000001", "Player-1-00000002"

local TAG_1_AND_2 = {
		account = {
			announceEnabled = false,
			autoPinNewMountDays = 14,
			autoPinNewMounts = true,
			listHeight = 420,
			mountPins = {
				[101] = { acquiredAt = 1789913600, expiresAt = 1791123200 },
				[102] = { acquiredAt = 1787408000, expiresAt = 1788617600 },
				[103] = { permanent = true },
				[104] = { acquiredAt = 1789827200, suppressed = true },
			},
			position = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 120, y = -80 },
			previewEnabled = false,
			titleFallbackMode = "none",
			version = 1,
		},
		main = {
			assign = { [0] = 5, [1] = 5, [2] = 6, [3] = 1, [4] = 4, [5] = 5 },
			cats = {
				[1] = {
					children = {},
					collapsed = false,
					id = 1,
					items = { 3 },
					name = "Tier",
				},
				[2] = {
					children = {},
					collapsed = false,
					id = 2,
					items = {},
					name = "Non-tier sets",
				},
				[3] = {
					children = {},
					collapsed = false,
					id = 3,
					items = {},
					name = "Simple",
				},
				[4] = {
					children = {},
					collapsed = false,
					id = 4,
					items = { 4 },
					name = "Unsorted",
					protected = true,
				},
				[5] = {
					children = { 6 },
					collapsed = false,
					id = 5,
					items = { 0, 1, 5 },
					name = "Raid",
				},
				[6] = {
					children = {},
					collapsed = false,
					id = 6,
					items = { 2 },
					name = "Mythic",
					parent = 5,
				},
			},
			looks = {
				[0] = {
					[1] = { 1000, 0, 0 },
					[3] = { 2000, 2100, 0 },
					[16] = { 3000, 0, 500 },
				},
				[1] = {
					[1] = { 1001, 0, 0 },
					[3] = { 2001, 2101, 0 },
					[16] = { 3001, 0, 500 },
				},
				[2] = {
					[1] = { 1002, 0, 0 },
					[3] = { 2002, 2102, 0 },
					[16] = { 3002, 0, 500 },
				},
				[3] = {
					[1] = { 1003, 0, 0 },
					[3] = { 2003, 2103, 0 },
					[16] = { 3003, 0, 500 },
				},
				[5] = {
					[5] = { 4005, 0, 0 },
				},
			},
			mounts = {
				[0] = { [201] = true },
				[1] = { [202] = true, [203] = true },
			},
			nextID = 7,
			noPinnedShuffle = { true },
			roots = { 5, 1, 2, 3, 4 },
			slots = {
				[0] = {
					at = 120007,
					covered = 2,
					missing = {},
					total = 2,
				},
				[1] = {
					at = 120007,
					covered = 1,
					missing = {
						[1] = { equipped = true, name = "Shoulder" },
					},
					total = 2,
				},
			},
			titleRotation = {
				[0] = {
					serial = 1,
					used = { [11] = 1 },
				},
			},
			titles = {
				[0] = { [11] = true, [12] = true },
			},
			version = 3,
			wear = {
				[0] = { last = 1789740800, seconds = 3600 },
				[1] = { last = 1789827200, seconds = 900 },
			},
		},
		alt = {
			assign = { [0] = 1, [1] = 4 },
			cats = {
				[1] = {
					children = {},
					collapsed = false,
					id = 1,
					items = { 0 },
					name = "Tier",
				},
				[2] = {
					children = {},
					collapsed = false,
					id = 2,
					items = {},
					name = "Non-tier sets",
				},
				[3] = {
					children = {},
					collapsed = false,
					id = 3,
					items = {},
					name = "Simple",
				},
				[4] = {
					children = {},
					collapsed = false,
					id = 4,
					items = { 1 },
					name = "Unsorted",
					protected = true,
				},
			},
			looks = {
				[0] = {
					[1] = { 5000, 0, 0 },
				},
				[1] = {
					[5] = { 5001, 0, 0 },
				},
			},
			mounts = {},
			nextID = 5,
			noPinnedShuffle = {},
			roots = { 1, 2, 3, 4 },
			slots = {},
			titleRotation = {},
			titles = {},
			version = 3,
			wear = {},
		},
}

local TAG_3 = {
		account = {
			announceEnabled = false,
			autoPinNewMountDays = 14,
			autoPinNewMounts = true,
			hideEmptyCategories = true,
			listHeight = 420,
			matchTargetMount = false,
			minimap = { hide = true },
			mountPins = {
				[101] = { acquiredAt = 1789913600, expiresAt = 1791123200 },
				[102] = { acquiredAt = 1787408000, expiresAt = 1788617600 },
				[103] = { permanent = true },
				[104] = { acquiredAt = 1789827200, suppressed = true },
			},
			position = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 120, y = -80 },
			previewEnabled = false,
			titleFallbackMode = "none",
			version = 1,
		},
		main = {
			assign = { [0] = 5, [1] = 5, [2] = 6, [3] = 1, [4] = 4, [5] = 5 },
			cats = {
				[1] = {
					children = {},
					collapsed = false,
					color = { b = 0.78842111830828, g = 0.36411164081256, r = 0.80661984475172 },
					id = 1,
					items = { 3 },
					name = "Tier",
				},
				[2] = {
					children = {},
					collapsed = false,
					color = { b = 0.68951027385868, g = 0.22208309576389, r = 0.59164981373851 },
					id = 2,
					items = {},
					name = "Non-tier sets",
				},
				[3] = {
					children = {},
					collapsed = false,
					color = { b = 0.25768369814549, g = 0.70555494216064, r = 0.25254817135495 },
					id = 3,
					items = {},
					name = "Simple",
				},
				[4] = {
					children = {},
					collapsed = false,
					color = { b = 0.77577418495238, g = 0.63274739248319, r = 0.33408772452205 },
					id = 4,
					items = { 4 },
					name = "Unsorted",
					protected = true,
				},
				[5] = {
					children = { 6 },
					collapsed = false,
					color = { b = 0.44609897057595, g = 0.84044594503494, r = 0.35437384148143 },
					id = 5,
					items = { 0, 1, 5 },
					name = "Raid",
				},
				[6] = {
					children = {},
					collapsed = false,
					color = { b = 0.55324673888353, g = 0.31029980292061, r = 0.79345938588654 },
					id = 6,
					items = { 2 },
					name = "Mythic",
					parent = 5,
				},
			},
			looks = {
				[0] = {
					[1] = { 1000, 0, 0 },
					[3] = { 2000, 2100, 0 },
					[16] = { 3000, 0, 500 },
				},
				[1] = {
					[1] = { 1001, 0, 0 },
					[3] = { 2001, 2101, 0 },
					[16] = { 3001, 0, 500 },
				},
				[2] = {
					[1] = { 1002, 0, 0 },
					[3] = { 2002, 2102, 0 },
					[16] = { 3002, 0, 500 },
				},
				[3] = {
					[1] = { 1003, 0, 0 },
					[3] = { 2003, 2103, 0 },
					[16] = { 3003, 0, 500 },
				},
				[5] = {
					[5] = { 4005, 0, 0 },
				},
			},
			mounts = {
				[0] = { [201] = true },
				[1] = { [202] = true, [203] = true },
			},
			nextID = 7,
			noPinnedShuffle = { true },
			roots = { 5, 1, 2, 3, 4 },
			slots = {
				[0] = {
					at = 120007,
					covered = 2,
					missing = {},
					total = 2,
				},
				[1] = {
					at = 120007,
					covered = 1,
					missing = {
						[1] = { equipped = true, name = "Shoulder" },
					},
					total = 2,
				},
			},
			titleRotation = {
				[0] = {
					serial = 1,
					used = { [11] = 1 },
				},
			},
			titles = {
				[0] = { [11] = true, [12] = true },
			},
			version = 4,
			wear = {
				[0] = { last = 1789740800, seconds = 3600 },
				[1] = { last = 1789827200, seconds = 900 },
			},
		},
		alt = {
			assign = { [0] = 1, [1] = 4 },
			cats = {
				[1] = {
					children = {},
					collapsed = false,
					color = { b = 0.26016592350485, g = 0.59414477499867, r = 0.65326011432487 },
					id = 1,
					items = { 0 },
					name = "Tier",
				},
				[2] = {
					children = {},
					collapsed = false,
					color = { b = 0.41814138953738, g = 0.8108353508454, r = 0.631248303506 },
					id = 2,
					items = {},
					name = "Non-tier sets",
				},
				[3] = {
					children = {},
					collapsed = false,
					color = { b = 0.30402154747777, g = 0.65366961932881, r = 0.67595808935629 },
					id = 3,
					items = {},
					name = "Simple",
				},
				[4] = {
					children = {},
					collapsed = false,
					color = { b = 0.20828191671169, g = 0.52515673644689, r = 0.69365138106218 },
					id = 4,
					items = { 1 },
					name = "Unsorted",
					protected = true,
				},
			},
			looks = {
				[0] = {
					[1] = { 5000, 0, 0 },
				},
				[1] = {
					[5] = { 5001, 0, 0 },
				},
			},
			mounts = {},
			nextID = 5,
			noPinnedShuffle = {},
			roots = { 1, 2, 3, 4 },
			slots = {},
			titleRotation = {},
			titles = {},
			version = 4,
			wear = {},
		},
}

local FIXTURES = {
	["12.1.0-1"] = TAG_1_AND_2,
	["12.1.0-2"] = TAG_1_AND_2,
	["12.1.0-3"] = TAG_3,
}

-- What the client lists for each character. Outfit 4 is a slot nobody used;
-- outfit 5 kept the default name but was filed by hand.
local MAIN_OUTFITS = {
	{ outfitID = 0, name = "Raid A" }, { outfitID = 1, name = "Raid B" },
	{ outfitID = 2, name = "Mythic" }, { outfitID = 3, name = "Tier set" },
	{ outfitID = 4, name = "Outfit" }, { outfitID = 5, name = "Outfit" },
}
local ALT_OUTFITS = { { outfitID = 0, name = "Alt one" }, { outfitID = 1, name = "Alt two" } }
local MAIN = { guid = MAIN_GUID, name = "Main", realm = "Realm", raceID = 1, sex = 2, classID = 1 }
local ALT = { guid = ALT_GUID, name = "Alt", realm = "Realm", raceID = 4, sex = 3, classID = 8 }

local function Copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[Copy(k)] = Copy(v) end
	return out
end

-- A logout and login: every integer 0, key or value, comes back as -0, the
-- client's habit that once split outfit 0 into two library records.
local function NegativeZero()
	local zero = 0
	return -zero
end

local function Reload(value)
	if type(value) == "number" and value == 0 then return NegativeZero() end
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in pairs(value) do out[Reload(k)] = Reload(v) end
	return out
end

-- Stable text for a whole store, so "unchanged" can be checked byte for byte.
local function Dump(value)
	if type(value) == "string" then return ("%q"):format(value) end
	if type(value) ~= "table" then return tostring(value) end
	local keys = {}
	for k in pairs(value) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) == "number"
	end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = Dump(k) .. "=" .. Dump(value[k]) end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- What a login runs over saved data, in Core's order.
local function Login(account, char, owner, outfits, now)
	account, char = Database.MigrateOrInit(account, char)
	local byID = Tree.SyncOutfits(char, Copy(outfits), "Outfit")
	OutfitTitles.Clean(char, byID)
	Library.EvictArchived(account.library, account.archiveDays, now)
	local stats = OutfitLibrarySync.Reconcile(account.library, owner, Copy(outfits),
		char.looks, now)
	return account, char, stats
end

local function RecordsOf(library, guid)
	local list = {}
	for _, record in pairs(library.records) do
		if record.guid == guid then list[#list + 1] = record end
	end
	return list
end

-- One record per outfit per character, however the ID came back.
local function AssertOnePerOutfit(library, guid, expected)
	local seen = {}
	for _, record in ipairs(RecordsOf(library, guid)) do
		local id = ("%d"):format(record.originID)
		assert.is_nil(seen[id], guid .. " holds outfit " .. id .. " twice")
		seen[id] = true
	end
	local count = 0
	for _ in pairs(seen) do count = count + 1 end
	assert.equal(expected, count)
end

for _, tag in ipairs({ "12.1.0-1", "12.1.0-2", "12.1.0-3" }) do
	describe("upgrading saved data written by " .. tag, function()
		local fixture, account, main, alt, mainStats, altStats

		before_each(function()
			fixture = FIXTURES[tag]
			local saved = Reload(Copy(fixture))
			account, main, mainStats = Login(saved.account, saved.main, MAIN, MAIN_OUTFITS, NOW)
			account, alt, altStats = Login(account, saved.alt, ALT, ALT_OUTFITS, NOW)
		end)

		it("reaches the current versions and asks for one re-read", function()
			assert.equal(3, account.version)
			assert.equal(Library.VERSION, account.library.version)
			assert.equal(8, main.version)
			assert.equal(8, alt.version)
			assert.is_true(main.rereadLooks)
			assert.is_true(alt.rereadLooks)
		end)

		it("keeps every setting and adds the new defaults", function()
			local old = fixture.account
			assert.is_false(account.previewEnabled)
			assert.equal("none", account.titleFallbackMode)
			assert.same(old.position, account.position)
			assert.equal(420, account.listHeight)
			assert.is_false(account.announceEnabled)
			assert.equal(old.hideEmptyCategories or false, account.hideEmptyCategories)
			assert.equal(old.minimap ~= nil and old.minimap.hide or false, account.minimap.hide)
			-- Unset means never changed, so the new default applies; false stays.
			if old.matchTargetMount == nil then
				assert.is_true(account.matchTargetMount)
			else
				assert.equal(old.matchTargetMount, account.matchTargetMount)
			end
			assert.equal("pinned", account.hearthFallbackMode)
			assert.equal(30, account.archiveDays)
		end)

		it("moves the mount pins whole and drops the old keys", function()
			local mounts = account.pins.mounts
			assert.same(fixture.account.mountPins, mounts.records)
			assert.equal(14, mounts.days)
			assert.is_true(mounts.autoNew)
			assert.same({ [101] = true, [103] = true }, Pins.ActiveSet(mounts, NOW))
			assert.is_nil(account.mountPins)
			assert.is_nil(account.autoPinNewMounts)
			assert.is_nil(account.autoPinNewMountDays)
		end)

		it("moves the shuffle opt-out", function()
			assert.is_nil(main.noPinnedShuffle)
			assert.same({ [1] = true }, main.pinOptOut.mounts)
		end)

		it("keeps filing, links, titles, wear, slot checks and looks", function()
			local old = fixture.main
			local raid, mythic, tier
			for id, cat in pairs(main.cats) do
				if cat.name == "Raid" then raid = id end
				if cat.name == "Mythic" then mythic = id end
				if cat.name == "Tier" then tier = id end
			end
			assert.same({ 0, 1, 5 }, main.cats[raid].items)
			assert.same({ 2 }, main.cats[mythic].items)
			assert.same({ 3 }, main.cats[tier].items)
			assert.equal(raid, main.cats[mythic].parent)
			-- The untouched slot gets no row; the hand-filed one keeps its place.
			assert.is_nil(main.assign[4])
			assert.equal(raid, main.assign[5])
			for _, key in ipairs({ "mounts", "titles", "titleRotation", "wear", "slots", "looks" }) do
				assert.same(old[key], main[key], key)
			end
			-- Tags before 12.1.0-3 stored no colour; the migration gives one.
			for id, cat in pairs(old.cats) do
				if cat.color then
					assert.same(cat.color, main.cats[id].color, "colour of " .. cat.name)
				else
					assert.is_true(CategoryColor.IsValid(main.cats[id].color), cat.name)
				end
			end
		end)

		it("makes one library record per read outfit per character", function()
			AssertOnePerOutfit(account.library, MAIN_GUID, 5)
			AssertOnePerOutfit(account.library, ALT_GUID, 2)
			assert.equal(1, mainStats.missing)
			assert.equal(4, mainStats.missingOutfits[1].outfitID)
			assert.equal(0, altStats.missing)
		end)

		describe("then played on", function()
			local freshID, oldID

			before_each(function()
				local library = account.library
				freshID = Library.Add(library, assert(Library.Snap({ look = { [1] = { 7001, 0, 0 } },
					raceID = 2, sex = 2, name = "Stranger" }, NOW)), NOW)
				oldID = Library.Add(library, assert(Library.Snap({ look = { [1] = { 7002, 0, 0 } },
					raceID = 5, sex = 3, name = "Old" }, NOW - 50 * DAY)), NOW - 50 * DAY)
				-- Archived in the order the clock allows.
				assert.is_true(Library.Archive(library, oldID, NOW - 40 * DAY))
				assert.is_true(Library.Archive(library, freshID, NOW))

				for _ = 1, 2 do
					account, main, alt = Reload(account), Reload(main), Reload(alt)
					account, main = Login(account, main, MAIN, MAIN_OUTFITS, NOW + 60)
					account, alt = Login(account, alt, ALT, ALT_OUTFITS, NOW + 60)
				end
			end)

			it("adds nothing on later logins", function()
				AssertOnePerOutfit(account.library, MAIN_GUID, 5)
				AssertOnePerOutfit(account.library, ALT_GUID, 2)
				local count = 0
				for _ in pairs(account.library.records) do count = count + 1 end
				assert.equal(7, count)
			end)

			it("evicts only what has been archived longer than the window", function()
				assert.equal(1, #account.library.archive)
				assert.equal(freshID, account.library.archive[1].id)
			end)

			it("restores an archived snapshot under its own id", function()
				assert.same({ freshID, true }, { Library.Restore(account.library, freshID) })
				assert.equal("Stranger", account.library.records[freshID].name)
			end)

			it("changes nothing on one more login", function()
				local before = Dump({ account, main, alt })
				account, main, alt = Reload(account), Reload(main), Reload(alt)
				account, main = Login(account, main, MAIN, MAIN_OUTFITS, NOW + 60)
				account, alt = Login(account, alt, ALT, ALT_OUTFITS, NOW + 60)
				assert.equal(before, Dump({ account, main, alt }))
			end)
		end)

		it("changes nothing when the migration runs again", function()
			local before = Dump({ account, main, alt })
			account, main = Database.MigrateOrInit(account, main)
			account, alt = Database.MigrateOrInit(account, alt)
			assert.equal(before, Dump({ account, main, alt }))
		end)
	end)
end
