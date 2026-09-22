local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local Adapter = {}

local function NativeForm(raceID)
	local body = ns.RaceBody
	if not (body and body.HasAlternateForm(raceID)) then return nil end
	local info = C_PlayerInfo
	if not (info and info.GetAlternateFormInfo) then return nil end
	local ok, _hasAlternate, inAlternate = pcall(info.GetAlternateFormInfo)
	if ok then return not inAlternate end
	return nil
end

local function OwnerFacts()
	local guid = UnitGUID("player")
	if not guid then return nil end
	local name, realm = UnitFullName("player")
	local _, raceFile, raceID = UnitRace("player")
	local _, _, classID = UnitClass("player")
	return {
		guid = guid, name = name, realm = realm,
		raceID = raceID, raceFile = raceFile,
		sex = UnitSex("player"), classID = classID,
		nativeForm = NativeForm(raceID),
	}
end

function Adapter.ReadSets(api, fromTransmogList)
	if not (api and api.GetCustomSets and api.GetCustomSetInfo
		and api.GetCustomSetItemTransmogInfoList) then return nil, false end
	local ok, ids = pcall(api.GetCustomSets)
	if not ok or type(ids) ~= "table" then return nil, false end
	local sets = {}
	for _, customSetID in ipairs(ids) do
		local name, icon = api.GetCustomSetInfo(customSetID)
		local list = api.GetCustomSetItemTransmogInfoList(customSetID)
		local look = type(list) == "table" and fromTransmogList(list)
		sets[#sets + 1] = {
			customSetID = customSetID, name = name, icon = icon, look = look,
		}
	end
	return sets, true
end

function Adapter.Attach(Addon)
	local lastStats, lastSyncedAt
	local function Sync()
		local sets, trustworthyEmpty = Adapter.ReadSets(C_TransmogCollection,
			ns.InspectLook.FromTransmogList)
		local now = time()
		local stats, why = ns.CustomSetLibrarySync.Reconcile(
			MogtrotDB and MogtrotDB.library, OwnerFacts(), sets, now, trustworthyEmpty)
		lastStats = stats
		lastStats.reason = why
		lastStats.apiCount = type(sets) == "table" and #sets or nil
		lastStats.ownerGUID = UnitGUID("player")
		if not why then lastSyncedAt = now end
		lastStats.syncedAt = lastSyncedAt
		if ns.LibraryUI then ns.LibraryUI.Refresh() end
		return stats, why
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_LOGIN")
	events:RegisterEvent("TRANSMOG_CUSTOM_SETS_CHANGED")
	events:SetScript("OnEvent", function() Sync() end)

	Addon.SyncCustomSetLibrary = Sync
	Addon.CustomSetLibrarySyncState = function() return lastStats end
	return { Sync = Sync }
end

ns.CustomSetLibrarySyncAdapter = Adapter
return Adapter
