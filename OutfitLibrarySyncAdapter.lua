local _, ns = ...

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

function Adapter.Attach(Addon)
	local lastStats, lastSyncedAt
	local function Sync()
		local library = MogtrotDB and MogtrotDB.library
		local infos = C_TransmogOutfitInfo and C_TransmogOutfitInfo.GetOutfitsInfo
			and C_TransmogOutfitInfo.GetOutfitsInfo() or nil
		local now = time()
		local stats, why = ns.OutfitLibrarySync.Reconcile(library, OwnerFacts(), infos,
			MogtrotCharDB and MogtrotCharDB.looks, now)
		lastStats = stats
		lastStats.reason = why
		lastStats.apiCount = type(infos) == "table" and #infos or nil
		lastStats.ownerGUID = UnitGUID("player")
		if not why then lastSyncedAt = now end
		lastStats.syncedAt = lastSyncedAt
		if ns.LibraryUI then ns.LibraryUI.Refresh() end
		return stats, why
	end

	local function Later(delay)
		if C_Timer and C_Timer.After then C_Timer.After(delay or 0, Sync) end
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("TRANSMOG_OUTFITS_CHANGED")
	events:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then
			C_Timer.After(0, function()
				local _, why = Sync()
				if why == "outfits unavailable" then Later(5) end
			end)
		else
			Later(0)
		end
	end)

	Addon.SyncOutfitLibrary = Sync
	Addon.ScheduleOutfitLibrarySync = Later
	Addon.OutfitLibrarySyncState = function() return lastStats end
end

ns.OutfitLibrarySyncAdapter = Adapter
return Adapter
