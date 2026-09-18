local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local LookCodec = ns.LookCodec or require("LookCodec")

-- The account-wide outfit library: the store, its migration, and dedup.
-- Pure. Tables in, no frames, no C_ calls, no clock.
--
--   library = { version, nextID, records = { [id] = record } }
--
-- A record is flat and every field is a fact about the wearer, never about
-- whoever is looking. "Is this me" is a read-time comparison of guid against
-- the logged-in character, so the same store reads correctly from any of them.
local Library = {}

Library.VERSION = 1

-- Set membership, so a field the schema does not know cannot ride along into
-- saved variables on the strength of a typo.
local FIELDS = {
	id = true, source = true,
	origin = true, originID = true, originName = true, originIcon = true,
	look = true, hidden = true, variants = true,
	raceID = true, raceFile = true, sex = true, classID = true,
	altRaceID = true, nativeForm = true,
	name = true, realm = true, guid = true, title = true,
	faction = true, level = true, specID = true,
	zone = true, subZone = true, mapID = true, x = true, y = true,
	seenAt = true, lastSeen = true, seenCount = true, mount = true,
	form = true, mythicPlus = true, itemLevel = true,
	build = true, tocVersion = true, capturedBy = true,
	savedAt = true, updatedAt = true,
}

local SOURCES = { mine = true, snap = true }
local ORIGINS = { outfit = true, customSet = true, stored = true }

function Library.New()
	return { version = Library.VERSION, nextID = 1, records = {} }
end

-- Creates the library on an account store that has none. Additive: nothing
-- else moves, so the character store is untouched. A version newer than this
-- build knows is left alone and reported, so an older client gates the feature
-- off rather than migrating a shape it cannot understand.
function Library.Migrate(account)
	if type(account) ~= "table" then return nil, "no account store" end

	local library = account.library
	if type(library) ~= "table" then
		account.library = Library.New()
		return account.library
	end
	if type(library.version) ~= "number" then
		return nil, "library has no version"
	end
	if library.version > Library.VERSION then
		return nil, ("library is version %d, this build knows %d")
			:format(library.version, Library.VERSION)
	end

	library.records = type(library.records) == "table" and library.records or {}
	library.nextID = type(library.nextID) == "number" and library.nextID or 1
	-- Written last, so a crash before here re-runs the migration cleanly.
	library.version = Library.VERSION
	return library
end

-- Rejects a record rather than storing something the reader cannot trust.
function Library.Validate(record)
	if type(record) ~= "table" then return false, "not a table" end
	if not SOURCES[record.source] then return false, "unknown source" end
	if type(record.look) ~= "string" then return false, "look must be encoded" end
	if record.source == "mine" and not ORIGINS[record.origin] then
		return false, "a record of yours needs an origin"
	end
	if record.source == "snap" and record.origin ~= nil then
		return false, "a snap was never in a container"
	end
	for field in pairs(record) do
		if not FIELDS[field] then return false, "unknown field " .. tostring(field) end
	end
	return true
end

-- Everything a snap carries beyond the four fields the builder sets itself.
-- A fact the client refused to answer stays nil rather than being guessed.
local SNAP_FIELDS = {
	"raceID", "raceFile", "sex", "classID", "altRaceID", "nativeForm",
	"name", "realm", "guid", "title", "faction", "level", "specID",
	"zone", "subZone", "mapID", "x", "y", "mount", "form",
	"mythicPlus", "itemLevel",
	"build", "tocVersion", "capturedBy", "hidden", "variants",
}

-- Builds a record from what the client answered about someone standing in
-- front of you. A look with nothing in it is refused: a capture of a
-- character wearing no transmog is the failure case, not a record.
function Library.Snap(facts, now)
	if type(facts) ~= "table" then return nil, "no facts" end

	local look = type(facts.look) == "string" and facts.look
		or LookCodec.Encode(facts.look)
	if type(look) ~= "string" then return nil, "no look" end
	if look == "" then return nil, "nothing worn" end

	local seen = facts.seenAt or now
	local record = {
		source = "snap",
		look = look,
		seenAt = seen,
		lastSeen = seen,
		seenCount = 1,
	}
	for _, field in ipairs(SNAP_FIELDS) do
		record[field] = facts[field]
	end

	local ok, why = Library.Validate(record)
	if not ok then return nil, why end
	return record
end

function Library.KeyOf(record)
	if type(record) ~= "table" then return nil end
	return LookCodec.Key(record.look, record.raceID, record.sex)
end

-- Built when the browser opens and dropped when it closes, never saved.
function Library.BuildIndex(library)
	local index = {}
	if type(library) ~= "table" or type(library.records) ~= "table" then
		return index
	end
	for id, record in pairs(library.records) do
		local key = Library.KeyOf(record)
		if key then index[key] = id end
	end
	return index
end

-- Returns id, isNew. A look already seen on the same race and sex carries no
-- new information, so the sighting is counted and nothing else is touched.
function Library.Add(library, record, now, index)
	local ok, why = Library.Validate(record)
	if not ok then return nil, false, why end

	local key = Library.KeyOf(record)
	if not key then return nil, false, "record has no key" end

	index = index or Library.BuildIndex(library)
	local existing = index[key]
	if existing and library.records[existing] then
		local held = library.records[existing]
		held.lastSeen = now or held.lastSeen
		held.seenCount = (held.seenCount or 1) + 1
		held.updatedAt = now or held.updatedAt
		return existing, false
	end

	local id = library.nextID or 1
	library.nextID = id + 1
	record.id = id
	record.savedAt = record.savedAt or now
	record.updatedAt = now
	library.records[id] = record
	index[key] = id
	return id, true
end

function Library.Delete(library, id)
	if type(library) ~= "table" or type(library.records) ~= "table" then
		return false
	end
	if library.records[id] == nil then return false end
	library.records[id] = nil
	return true
end

-- Newest first, which is what a browser wants and what an id ordering gives
-- for free.
function Library.Sorted(library)
	local list = {}
	if type(library) ~= "table" or type(library.records) ~= "table" then
		return list
	end
	for _, record in pairs(library.records) do list[#list + 1] = record end
	table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
	return list
end

ns.Library = Library
return Library
