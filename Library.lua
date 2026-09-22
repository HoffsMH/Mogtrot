local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local LookCodec = ns.LookCodec or require("LookCodec")

-- The account-wide outfit library: the store, its migration, and dedup.
-- Pure. Tables in, no frames, no C_ calls, no clock.
--
--   library = { version, nextID, records = { [id] = record }, owners = {} }
--
-- A record is flat and every field is a fact about the wearer, never about
-- whoever is looking. "Is this me" is a read-time comparison of guid against
-- the logged-in character, so the same store reads correctly from any of them.
local Library = {}

Library.VERSION = 5

-- Set membership, so a field the schema does not know cannot ride along into
-- saved variables on the strength of a typo.
local FIELDS = {
	id = true, source = true,
	origin = true, originID = true, originName = true, originIcon = true,
	look = true, hidden = true, variants = true, scanned = true,
	archivedAt = true,
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
	return { version = Library.VERSION, nextID = 1, records = {}, owners = {},
		archive = {} }
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
	library.owners = type(library.owners) == "table" and library.owners or {}
	library.archive = type(library.archive) == "table" and library.archive or {}
	library.nextID = type(library.nextID) == "number" and library.nextID or 1
	if library.version < 4 then
		-- Custom sets were stored as if they were account-wide. They are not:
		-- every character numbers its own from zero, so one character's sync
		-- overwrote another's. What is stored cannot be told apart any more,
		-- and each set is readable again the first time its own character logs
		-- in, so they go rather than stay as fiction.
		for id, record in pairs(library.records) do
			if record.source == "mine" and record.origin == "customSet" then
				library.records[id] = nil
			end
		end

		-- One record per key is what BuildIndex assumes, and a zero ID coming
		-- back from saving with a sign on it split one record into two keys.
		local kept = {}
		for id, record in pairs(library.records) do
			local key = Library.KeyOf(record)
			if key then
				local prior = kept[key]
				if prior == nil or id < prior then
					if prior ~= nil then library.records[prior] = nil end
					kept[key] = id
				else
					library.records[id] = nil
				end
			end
		end
	end
	-- The sync used to mirror an outfit whether or not anything had read it,
	-- which put a card saying only "wear this once" in the wall for every
	-- outfit on every character. It writes none now; this clears the ones it
	-- already wrote. An outfit that was read and found empty is a different
	-- thing and stays: it is hidden by a filter, not deleted.
	if library.version < 5 then
		for id, record in pairs(library.records) do
			if record.source == "mine" and record.origin == "outfit"
				and record.look == "" and record.scanned == false then
				library.records[id] = nil
			end
		end
	end

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

-- An outfit whose contents have never been read and an outfit that assigns
-- nothing both store an empty look, so the flag is the only thing that tells
-- them apart.
--
-- Only an explicit false means never read, and the sync is the only thing
-- that writes it. A record from before the flag existed is treated as read
-- and empty, because the ingest is what created the record in the first
-- place: reading the absence the other way labels every genuinely empty
-- outfit as missing, and puts a wall of "wear this once" in front of someone
-- who already did.
local function IsEmptyOutfitRecord(record)
	return type(record) == "table" and record.source == "mine"
		and record.origin == "outfit" and record.look == ""
end

function Library.IsUnscanned(record)
	return IsEmptyOutfitRecord(record) and record.scanned == false
end

function Library.IsEmptyOutfit(record)
	return IsEmptyOutfitRecord(record) and record.scanned ~= false
end

-- Saved variables hand an integer 0 back as -0, which is equal to 0 but
-- stringifies differently, so a raw tostring gives one ID two keys.
local function IDKey(value)
	if type(value) == "number" and value == math.floor(value)
		and value > -2147483648 and value < 2147483648 then
		return ("%d"):format(value)
	end
	return tostring(value)
end

-- Outfits and custom sets both number from zero on each character, so an ID
-- only identifies one of them alongside the character that owns it.
function Library.KeyOf(record)
	if type(record) ~= "table" then return nil end
	if record.source == "mine" then
		if not record.guid or not record.origin or record.originID == nil then return nil end
		return table.concat({ record.origin, record.guid, IDKey(record.originID) }, "|")
	end
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

function Library.Upsert(library, record, now, index)
	local ok, why = Library.Validate(record)
	if not ok then return nil, false, why end
	local key = Library.KeyOf(record)
	if not key then return nil, false, "record has no key" end
	index = index or Library.BuildIndex(library)
	local id = index[key]
	local held = id and library.records[id]
	if held then
		local savedAt = held.savedAt
		for field in pairs(held) do
			if field ~= "id" and field ~= "savedAt" then held[field] = nil end
		end
		for field, value in pairs(record) do
			if field ~= "id" and field ~= "savedAt" then held[field] = value end
		end
		held.id, held.savedAt, held.updatedAt = id, savedAt, now
		return id, false
	end
	return Library.Add(library, record, now, index)
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
-- Recent first, so a capture just taken is waiting at the top of the window,
-- and seeing somebody again counts as recent.
--
-- Deliberately not updatedAt: a login sync stamps every mirrored outfit it
-- touches, which would shuffle the whole wall on every login and leave the
-- order arbitrary among the ones sharing a stamp. savedAt survives an Upsert
-- and lastSeen only moves when somebody is actually seen again.
local function Recency(record)
	return record.lastSeen or record.savedAt or 0
end

function Library.Sorted(library)
	local list = {}
	if type(library) ~= "table" or type(library.records) ~= "table" then
		return list
	end
	for _, record in pairs(library.records) do list[#list + 1] = record end
	table.sort(list, function(a, b)
		local recentA, recentB = Recency(a), Recency(b)
		if recentA ~= recentB then return recentA > recentB end
		return (a.id or 0) > (b.id or 0)
	end)
	return list
end

-- Archiving is one unconfirmed click and a snapshot cannot be re-read from
-- the client, so nothing is destroyed here: the record moves off the wall
-- into a list of its own and a clock starts. Kept as a separate list rather
-- than a flag on the record, so every reader of `records` is right by
-- default instead of having to remember to exclude archived ones.
function Library.Archive(library, id, now)
	if type(library) ~= "table" or type(library.records) ~= "table" then
		return false
	end
	local record = library.records[id]
	if record == nil then return false end
	library.archive = type(library.archive) == "table" and library.archive or {}
	record.archivedAt = tonumber(now) or 0
	library.records[id] = nil
	-- Appended, never inserted: time only moves forward, so the list is
	-- ordered by construction and eviction only ever looks at the front.
	library.archive[#library.archive + 1] = record
	return true
end

-- Drops whatever has been archived longer than the window, oldest first.
-- A window of zero keeps everything, which is how a user says "never expire".
function Library.EvictArchived(library, days, now)
	if type(library) ~= "table" or type(library.archive) ~= "table" then
		return 0
	end
	days = tonumber(days) or 0
	if days <= 0 then return 0 end
	local cutoff = (tonumber(now) or 0) - days * 86400
	local dropped = 0
	while library.archive[1] ~= nil
		and (tonumber(library.archive[1].archivedAt) or 0) < cutoff do
		table.remove(library.archive, 1)
		dropped = dropped + 1
	end
	return dropped
end

ns.Library = Library
return Library
