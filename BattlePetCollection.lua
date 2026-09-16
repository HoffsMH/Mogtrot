local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Pure read layer over an injected battle-pet journal adapter. The adapter
-- stands in for C_PetJournal: getOwnedPetIDs(), getPetInfoByID(guid),
-- getSummonedPetGUID(), getSummonInfo(guid). Nothing here mutates journal
-- filters or the adapter's tables, and every read is event-independent: the
-- caller decides when to refresh by reading again.
local BattlePetCollection = {}

-- One record per owned copy: duplicate species stay separate records, each
-- carrying its exact GUID. displayName shows customName when the copy has
-- one, else the species name; the species name stays on the record as the
-- subtitle. Fresh row tables; the adapter's info tables are never shared.
function BattlePetCollection.OwnedRows(adapter)
	local rows = {}
	local owned = adapter.getOwnedPetIDs() or {}
	for _, guid in ipairs(owned) do
		local info = adapter.getPetInfoByID(guid)
		if info then
			rows[#rows + 1] = {
				guid = guid,
				speciesID = info.speciesID,
				creatureID = info.creatureID,
				displayID = info.displayID,
				icon = info.icon,
				isFavorite = info.isFavorite and true or false,
				customName = info.customName,
				name = info.name,
				displayName = info.customName or info.name,
			}
		end
	end
	return rows
end

-- Action-time summonability, straight from the journal's own answer:
-- summonable, enum reason, localized text.
function BattlePetCollection.SummonInfo(adapter, guid)
	return adapter.getSummonInfo(guid)
end

-- The copy that is out right now, compared by exact GUID.
function BattlePetCollection.IsSummoned(adapter, guid)
	return adapter.getSummonedPetGUID() == guid
end

ns.BattlePetCollection = BattlePetCollection
return BattlePetCollection
