local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Pure runtime filters for the outfit library.
--
-- Two exclusive modes. Snapshots are other players, recorded account-wide, and
-- race, class and armour are how you narrow a crowd of strangers. Everything
-- else belongs to one of your own characters, where choosing the characters
-- has already chosen their classes and armour, so those filters would only be
-- a second way to say the same thing.
local LibraryFilter = {}

local Library = ns.Library or require("Library")

LibraryFilter.ARMOR_TYPES = { "Cloth", "Leather", "Mail", "Plate" }

local CLASS_ARMOR = {
	[1] = "Plate", [2] = "Plate", [3] = "Mail", [4] = "Leather",
	[5] = "Cloth", [6] = "Plate", [7] = "Mail", [8] = "Cloth",
	[9] = "Cloth", [10] = "Leather", [11] = "Leather", [12] = "Leather",
	[13] = "Mail",
}

function LibraryFilter.New()
	return {
		-- Snapshots first: it is the only thing here that cannot be seen
		-- anywhere else in the game.
		mode = "snapshots",
		allRaces = true, races = {}, allClasses = true, classes = {},
		allArmorTypes = true, armorTypes = {},
		sources = { outfits = true, customSets = true },
		hideEmptyOutfits = true,
		allOwners = true, owners = {},
	}
end

function LibraryFilter.SetMode(state, mode)
	if type(state) ~= "table" then return end
	state.mode = mode == "mine" and "mine" or "snapshots"
end

function LibraryFilter.IsSnapshotMode(state)
	return type(state) ~= "table" or state.mode ~= "mine"
end

function LibraryFilter.SetHideEmptyOutfits(state, hide)
	if type(state) ~= "table" then return end
	state.hideEmptyOutfits = hide == true
end

function LibraryFilter.HidesEmptyOutfits(state)
	return type(state) ~= "table" or state.hideEmptyOutfits ~= false
end

function LibraryFilter.SetSource(state, source, selected)
	if type(state) ~= "table" then return end
	state.sources = type(state.sources) == "table" and state.sources or {}
	state.sources[source] = selected == true
end

function LibraryFilter.IsSourceSelected(state, source)
	if type(state) ~= "table" or type(state.sources) ~= "table" then return true end
	return state.sources[source] == true
end

function LibraryFilter.SourceOf(record)
	return type(record) == "table" and record.origin == "customSet"
		and "customSets" or "outfits"
end

function LibraryFilter.SelectAllOwners(state)
	state.allOwners, state.owners = true, {}
end

function LibraryFilter.SelectNoOwners(state)
	state.allOwners, state.owners = false, {}
end

function LibraryFilter.SetOwner(state, guid, selected)
	if type(state) ~= "table" or type(guid) ~= "string" then return end
	state.owners = type(state.owners) == "table" and state.owners or {}
	if state.allOwners ~= false then state.owners[guid] = selected and nil or false
	else state.owners[guid] = selected and true or nil end
end

function LibraryFilter.IsOwnerSelected(state, guid)
	if type(state) ~= "table" or state.allOwners == nil then return true end
	if state.allOwners then return state.owners[guid] ~= false end
	return state.owners[guid] == true
end

function LibraryFilter.ArmorType(classID)
	return CLASS_ARMOR[classID]
end

function LibraryFilter.SelectAll(state)
	if type(state) ~= "table" then return end
	state.allRaces = true
	state.races = {}
end

function LibraryFilter.SelectNone(state)
	if type(state) ~= "table" then return end
	state.allRaces = false
	state.races = {}
end

function LibraryFilter.SetRace(state, raceID, selected)
	if type(state) ~= "table" or type(raceID) ~= "number" then return end
	state.races = type(state.races) == "table" and state.races or {}
	if state.allRaces then
		state.races[raceID] = selected and nil or false
	else
		state.races[raceID] = selected and true or nil
	end
end

function LibraryFilter.IsRaceSelected(state, raceID)
	if type(state) ~= "table" then return true end
	if state.allRaces then return state.races[raceID] ~= false end
	return state.races[raceID] == true
end

function LibraryFilter.SelectAllClasses(state)
	if type(state) ~= "table" then return end
	state.allClasses = true
	state.classes = {}
end

function LibraryFilter.SelectNoClasses(state)
	if type(state) ~= "table" then return end
	state.allClasses = false
	state.classes = {}
end

function LibraryFilter.SetClass(state, classID, selected)
	if type(state) ~= "table" or type(classID) ~= "number" then return end
	state.classes = type(state.classes) == "table" and state.classes or {}
	if state.allClasses ~= false then
		state.classes[classID] = selected and nil or false
	else
		state.classes[classID] = selected and true or nil
	end
end

function LibraryFilter.IsClassSelected(state, classID)
	if type(state) ~= "table" or state.allClasses == nil then return true end
	if state.allClasses then return state.classes[classID] ~= false end
	return state.classes[classID] == true
end

function LibraryFilter.SelectAllArmorTypes(state)
	if type(state) ~= "table" then return end
	state.allArmorTypes = true
	state.armorTypes = {}
end

function LibraryFilter.SelectNoArmorTypes(state)
	if type(state) ~= "table" then return end
	state.allArmorTypes = false
	state.armorTypes = {}
end

function LibraryFilter.SetArmorType(state, armorType, selected)
	if type(state) ~= "table" or type(armorType) ~= "string" then return end
	state.armorTypes = type(state.armorTypes) == "table" and state.armorTypes or {}
	if state.allArmorTypes ~= false then
		state.armorTypes[armorType] = selected and nil or false
	else
		state.armorTypes[armorType] = selected and true or nil
	end
end

function LibraryFilter.IsArmorTypeSelected(state, armorType)
	if type(state) ~= "table" or state.allArmorTypes == nil then return true end
	if state.allArmorTypes then return state.armorTypes[armorType] ~= false end
	return state.armorTypes[armorType] == true
end

function LibraryFilter.SelectAllFilters(state)
	LibraryFilter.SelectAll(state)
	LibraryFilter.SelectAllClasses(state)
	LibraryFilter.SelectAllArmorTypes(state)
	LibraryFilter.SetSource(state, "outfits", true)
	LibraryFilter.SetSource(state, "customSets", true)
	LibraryFilter.SelectAllOwners(state)
end

function LibraryFilter.SelectNoFilters(state)
	LibraryFilter.SelectNone(state)
	LibraryFilter.SelectNoClasses(state)
	LibraryFilter.SelectNoArmorTypes(state)
	LibraryFilter.SetSource(state, "outfits", false)
	LibraryFilter.SetSource(state, "customSets", false)
	LibraryFilter.SelectNoOwners(state)
end

function LibraryFilter.Owners(records)
	local found, owners = {}, {}
	for _, record in ipairs(type(records) == "table" and records or {}) do
		if record.source == "mine" and type(record.guid) == "string" then
			found[record.guid] = true
		end
	end
	for guid in pairs(found) do owners[#owners + 1] = guid end
	table.sort(owners)
	return owners
end

-- One entry per character that owns something here, carrying what the picker
-- needs to label and colour a row. Class comes off the records because the
-- owners table only keeps a name and a realm.
function LibraryFilter.OwnerEntries(records)
	local byGUID, entries = {}, {}
	for _, record in ipairs(type(records) == "table" and records or {}) do
		if record.source == "mine" and type(record.guid) == "string" then
			local entry = byGUID[record.guid]
			if not entry then
				entry = { guid = record.guid }
				byGUID[record.guid] = entry
				entries[#entries + 1] = entry
			end
			entry.name = entry.name or record.name
			entry.realm = entry.realm or record.realm
			entry.classID = entry.classID or record.classID
		end
	end
	for _, entry in ipairs(entries) do
		entry.name = entry.name or entry.guid
	end
	table.sort(entries, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return (a.realm or "") < (b.realm or "")
	end)
	return entries
end

function LibraryFilter.Races(records)
	local found = {}
	for _, record in ipairs(type(records) == "table" and records or {}) do
		if type(record.raceID) == "number" then found[record.raceID] = true end
	end
	local races = {}
	for raceID in pairs(found) do races[#races + 1] = raceID end
	table.sort(races)
	return races
end

function LibraryFilter.Classes(records)
	local found = {}
	for _, record in ipairs(type(records) == "table" and records or {}) do
		if type(record.classID) == "number" then found[record.classID] = true end
	end
	local classes = {}
	for classID in pairs(found) do classes[#classes + 1] = classID end
	table.sort(classes)
	return classes
end

function LibraryFilter.Apply(records, state)
	local snapshotMode = LibraryFilter.IsSnapshotMode(state)
	local hideEmpty = LibraryFilter.HidesEmptyOutfits(state)
	local filtered = {}
	for _, record in ipairs(type(records) == "table" and records or {}) do
		local mine = record.source == "mine"
		local keep
		if snapshotMode then
			keep = not mine
				and LibraryFilter.IsRaceSelected(state, record.raceID)
				and LibraryFilter.IsClassSelected(state, record.classID)
				and LibraryFilter.IsArmorTypeSelected(state,
					LibraryFilter.ArmorType(record.classID))
		else
			-- An outfit nobody has read yet stays: it is the one you click to
			-- go and read it. One read as empty is just noise.
			keep = mine
				and LibraryFilter.IsSourceSelected(state,
					LibraryFilter.SourceOf(record))
				and LibraryFilter.IsOwnerSelected(state, record.guid)
				and not (hideEmpty and Library.IsEmptyOutfit(record))
		end
		if keep then filtered[#filtered + 1] = record end
	end
	return filtered
end

function LibraryFilter.SOURCES()
	return { "outfits", "customSets" }
end

-- The character you are playing first, and that character's outfits in the
-- order its own list uses. Everything else keeps the order it arrived in.
--
-- rank maps an outfitID to its position in that list, and applies only to
-- outfits: a custom set's originID is a set number that means nothing to the
-- outfit tree, so ranking by it would interleave the two at random.
--
-- table.sort is not stable, so the arrival index is the final tiebreak
-- rather than something to be assumed.
function LibraryFilter.Order(records, guid, rank)
	local out = {}
	for index, record in ipairs(type(records) == "table" and records or {}) do
		out[index] = record
	end
	if guid == nil then return out end

	local arrived = {}
	for index, record in ipairs(out) do arrived[record] = index end

	local function Rank(record)
		if not rank or record.origin ~= "outfit" then return math.huge end
		return rank[record.originID] or math.huge
	end
	local function Mine(record)
		return (record.source == "mine" and record.guid == guid) and 0 or 1
	end

	table.sort(out, function(a, b)
		local mineA, mineB = Mine(a), Mine(b)
		if mineA ~= mineB then return mineA < mineB end
		if mineA == 0 then
			local rankA, rankB = Rank(a), Rank(b)
			if rankA ~= rankB then return rankA < rankB end
		end
		return arrived[a] < arrived[b]
	end)
	return out
end

function LibraryFilter.SourceSelectionCount(state)
	local count = 0
	for _, source in ipairs(LibraryFilter.SOURCES()) do
		if LibraryFilter.IsSourceSelected(state, source) then count = count + 1 end
	end
	return count
end

function LibraryFilter.OwnerSelectionCount(state, owners)
	local count = 0
	for _, guid in ipairs(owners or {}) do
		if LibraryFilter.IsOwnerSelected(state, guid) then count = count + 1 end
	end
	return count
end

function LibraryFilter.ArmorSelectionCount(state)
	local selected = 0
	for _, armorType in ipairs(LibraryFilter.ARMOR_TYPES) do
		if LibraryFilter.IsArmorTypeSelected(state, armorType) then
			selected = selected + 1
		end
	end
	return selected
end

function LibraryFilter.ClassSelectionCount(state, classes)
	local selected = 0
	for _, classID in ipairs(type(classes) == "table" and classes or {}) do
		if LibraryFilter.IsClassSelected(state, classID) then selected = selected + 1 end
	end
	return selected
end

function LibraryFilter.SelectionCount(state, races)
	local selected = 0
	for _, raceID in ipairs(type(races) == "table" and races or {}) do
		if LibraryFilter.IsRaceSelected(state, raceID) then selected = selected + 1 end
	end
	return selected
end

-- Whatever the card is titled with: the set's name on one of mine, the
-- player's name on a snapshot.
function LibraryFilter.SearchText(record)
	if type(record) ~= "table" then return nil end
	if record.source == "mine" and type(record.originName) == "string" then
		return record.originName
	end
	return type(record.name) == "string" and record.name or nil
end

function LibraryFilter.NameMatches(record, query)
	if type(query) ~= "string" or query == "" then return true end
	local text = LibraryFilter.SearchText(record)
	if not text then return false end
	return string.find(string.lower(text), string.lower(query), 1, true) ~= nil
end

ns.LibraryFilter = LibraryFilter
return LibraryFilter
