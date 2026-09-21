local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local Library = ns.Library or require("Library")
local LookCodec = ns.LookCodec or require("LookCodec")

local CustomSetLibrarySync = {}

local function Record(owner, set)
	return {
		source = "mine", origin = "customSet", originID = set.customSetID,
		originName = set.name, originIcon = set.icon,
		look = type(set.look) == "string" and set.look or LookCodec.Encode(set.look),
		guid = owner.guid, name = owner.name, realm = owner.realm,
		raceID = owner.raceID, raceFile = owner.raceFile,
		sex = owner.sex, classID = owner.classID, nativeForm = owner.nativeForm,
	}
end

function CustomSetLibrarySync.Reconcile(library, owner, sets, now, trustworthyEmpty)
	local stats = { added = 0, updated = 0, pruned = 0, missing = 0,
		missingSets = {} }
	if type(library) ~= "table" or type(owner) ~= "table" or not owner.guid then
		return stats, "owner GUID unavailable"
	end
	if type(sets) ~= "table" or (#sets == 0 and not trustworthyEmpty) then
		return stats, "custom sets unavailable"
	end
	local alive, index = {}, Library.BuildIndex(library)
	for _, set in ipairs(sets) do
		if type(set) == "table" and set.customSetID ~= nil then
			alive[set.customSetID] = true
			local encoded = type(set.look) == "string" and set.look
				or LookCodec.Encode(set.look)
			if encoded == nil then
				stats.missing = stats.missing + 1
				stats.missingSets[#stats.missingSets + 1] = {
					customSetID = set.customSetID, name = set.name,
				}
			else
				local id, isNew = Library.Upsert(library, Record(owner, set), now, index)
				if id then
					if isNew then stats.added = stats.added + 1
					else stats.updated = stats.updated + 1 end
				end
			end
		end
	end
	for id, record in pairs(library.records) do
		if record.source == "mine" and record.origin == "customSet"
			and record.guid == owner.guid and not alive[record.originID] then
			library.records[id] = nil
			stats.pruned = stats.pruned + 1
		end
	end
	library.owners = type(library.owners) == "table" and library.owners or {}
	local facts = library.owners[owner.guid] or {}
	facts.name, facts.realm, facts.customSetsSyncedAt = owner.name, owner.realm, now
	library.owners[owner.guid] = facts
	return stats
end

ns.CustomSetLibrarySync = CustomSetLibrarySync
return CustomSetLibrarySync
