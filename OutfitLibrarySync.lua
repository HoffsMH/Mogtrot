local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local Library = ns.Library or require("Library")
local LookCodec = ns.LookCodec or require("LookCodec")

local OutfitLibrarySync = {}

local function Record(owner, info, look)
	return {
		source = "mine", origin = "outfit", originID = info.outfitID,
		originName = info.name, originIcon = info.icon,
		look = type(look) == "string" and look or LookCodec.Encode(look),
		guid = owner.guid, name = owner.name, realm = owner.realm,
		raceID = owner.raceID, raceFile = owner.raceFile,
		sex = owner.sex, classID = owner.classID, nativeForm = owner.nativeForm,
	}
end

function OutfitLibrarySync.Reconcile(library, owner, infos, looks, now)
	local stats = { added = 0, updated = 0, pruned = 0, missing = 0, missingOutfits = {} }
	if type(library) ~= "table" or type(owner) ~= "table" or not owner.guid then
		return stats, "owner GUID unavailable"
	end
	if type(infos) ~= "table" or #infos == 0 then return stats, "outfits unavailable" end
	looks = type(looks) == "table" and looks or {}
	local alive, index = {}, Library.BuildIndex(library)
	for _, info in ipairs(infos) do
		if type(info) == "table" and info.outfitID ~= nil then
			alive[info.outfitID] = true
			local look = looks[info.outfitID]
			local encoded = type(look) == "string" and look or LookCodec.Encode(look)
			-- nil is "nobody has read this outfit"; "" is "it was read and it
			-- assigns nothing". Only the first is missing.
			local record
			if encoded == nil then
				stats.missing = stats.missing + 1
				stats.missingOutfits[#stats.missingOutfits + 1] = {
					outfitID = info.outfitID, name = info.name,
				}
				record = Record(owner, info, "")
				local existingID = index[Library.KeyOf(record)]
				local held = existingID and library.records[existingID]
				-- A read that failed does not discard what an earlier one got.
				-- With nothing on file there is nothing worth storing either:
				-- a record holding no appearance is a card that can only say
				-- "wear this once", and a wall of those is noise for outfits
				-- that may never be ingested. It still counts as missing, so
				-- the header reports it.
				if not (held and held.look ~= "") then record = nil end
				if record then record.look = held.look end
			else
				record = Record(owner, info, encoded)
			end
			if record then record.scanned = record.look ~= "" or encoded == "" end
			if record then
				local id, isNew = Library.Upsert(library, record, now, index)
				if id then
					if isNew then stats.added = stats.added + 1
					else stats.updated = stats.updated + 1 end
				end
			end
		end
	end
	for id, record in pairs(library.records) do
		if record.source == "mine" and record.origin == "outfit"
			and record.guid == owner.guid and not alive[record.originID] then
			library.records[id] = nil
			stats.pruned = stats.pruned + 1
		end
	end
	library.owners = type(library.owners) == "table" and library.owners or {}
	local facts = library.owners[owner.guid] or {}
	facts.name, facts.realm, facts.syncedAt = owner.name, owner.realm, now
	library.owners[owner.guid] = facts
	return stats
end

ns.OutfitLibrarySync = OutfitLibrarySync
return OutfitLibrarySync
