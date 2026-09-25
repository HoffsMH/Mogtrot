local _, ns = ...

-- Records the player you are looking at into the account-wide library.
--
-- Everything here is a read: the client is asked what it will say about that
-- unit, and whatever it refuses is left nil. Library.Snap builds the record
-- and Library.Add decides whether it is new, so this file holds only the
-- gathering and the asynchronous wait the inspect API forces.
local SnapCapture = {}

-- How long to wait for the client to answer an inspect before giving up. A
-- capture that times out saves nothing rather than saving whatever the shared
-- inspect list happens to hold.
local INSPECT_TIMEOUT = 5

local waiter

local function Cancel(clearInspect)
	if not waiter then return end
	waiter:UnregisterAllEvents()
	waiter:SetScript("OnEvent", nil)
	waiter:SetScript("OnUpdate", nil)
	waiter = nil
	if clearInspect and ClearInspectPlayer then pcall(ClearInspectPlayer) end
end

local function Get(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c
end

-- A value the client marked secret cannot be stored, compared or even
-- concatenated, so it never leaves this function.
local function Plain(value)
	if value == nil then return nil end
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function IdentityIsSecret(unit)
	if not (C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret) then return false end
	local secret = Get(C_Secrets.ShouldUnitIdentityBeSecret, unit)
	return secret and true or false
end

-- The title as the game draws it. UnitPVPName decorates the name, so the name
-- itself is stripped back out and only a real title survives.
local function TitleOf(unit, name)
	local decorated = Plain(Get(UnitPVPName, unit))
	if type(decorated) ~= "string" or type(name) ~= "string" then return nil end
	if decorated == name then return nil end
	return decorated
end

-- One pass over a unit's buffs, because both things worth reading are auras.
-- A mount is an aura carrying the mount's own spell, which is the only thing
-- another player's mount can be read from. A form is an aura that changes the
-- body the transmog is drawn on, so it is part of how they looked.
local function AurasOf(unit)
	local spellIDs = {}

	-- Blizzard's own iterator, which has no ceiling. Indexing by hand needs a
	-- bound, and any bound is wrong: a well-buffed player can carry more
	-- helpful auras than any number worth guessing, and the one that would be
	-- dropped is the form, which is the half of a capture that cannot be
	-- recovered later. BUFF_MAX_DISPLAY is a display limit, not an aura limit.
	local collected = false
	if AuraUtil and AuraUtil.ForEachAura then
		collected = pcall(AuraUtil.ForEachAura, unit, "HELPFUL", nil, function(aura)
			local spellID = type(aura) == "table" and Plain(aura.spellId) or nil
			if spellID then spellIDs[#spellIDs + 1] = spellID end
		end, true)
	end

	local auras = C_UnitAuras
	if not collected then
		if not (auras and auras.GetAuraDataByIndex) then return nil, nil end
		local index = 1
		while true do
			local aura = Get(auras.GetAuraDataByIndex, unit, index, "HELPFUL")
			if not aura then break end
			local spellID = Plain(aura.spellId)
			if spellID then spellIDs[#spellIDs + 1] = spellID end
			index = index + 1
		end
	end

	local mountID
	local journal = C_MountJournal
	if journal and journal.GetMountFromSpell then
		for _, spellID in ipairs(spellIDs) do
			mountID = Get(journal.GetMountFromSpell, spellID)
			if mountID then break end
		end
	end

	local forms = ns.FormDefinitions
	local form = forms and forms.FromSpellIDs(spellIDs) or nil
	return mountID, form
end

local function WhereWeAre()
	local where = {}
	where.zone = Plain(Get(GetZoneText))
	where.subZone = Plain(Get(GetSubZoneText))
	if where.subZone == "" then where.subZone = nil end
	local map = C_Map
	if map then
		where.mapID = Get(map.GetBestMapForUnit, "player")
		if where.mapID then
			local position = Get(map.GetPlayerMapPosition, where.mapID, "player")
			if position and type(position.GetXY) == "function" then
				local x, y = Get(position.GetXY, position)
				-- Two decimals is a street corner, which is all a sighting is.
				if x then where.x = math.floor(x * 10000 + 0.5) / 10000 end
				if y then where.y = math.floor(y * 10000 + 0.5) / 10000 end
			end
		end
	end
	return where
end

-- Returns the facts table Library.Snap wants, minus the look, which the
-- caller fills in once the client answers. Called the moment the capture
-- starts, so it describes the unit being pointed at rather than whoever is
-- targeted when the answer lands.
local function Gather(unit)
	local facts = { seenAt = time and time() or nil }

	local identified = not IdentityIsSecret(unit)
	if identified then
		-- Plain answers with one value, so the realm has to be filtered on its
		-- own or it is thrown away with the rest of UnitName's returns.
		local rawName, rawRealm = Get(UnitName, unit)
		local name = Plain(rawName)
		facts.name = name
		facts.realm = Plain(rawRealm)
		if facts.realm == "" then facts.realm = nil end
		facts.guid = Plain(Get(UnitGUID, unit))
		facts.title = TitleOf(unit, name)

		local _race, raceFile, raceID = Get(UnitRace, unit)
		facts.raceFile = Plain(raceFile)
		facts.raceID = Plain(raceID)
		facts.sex = Plain(Get(UnitSex, unit))

		local _class, _classFile, classID = Get(UnitClass, unit)
		facts.classID = Plain(classID)
		facts.level = Plain(Get(UnitLevel, unit))
		facts.faction = Plain(Get(UnitFactionGroup, unit))
		facts.specID = Plain(Get(GetInspectSpecialization, unit))
		if facts.specID == 0 then facts.specID = nil end
		facts.mount, facts.form = AurasOf(unit)

		-- Both are read straight off the unit and both are a fact about them at
		-- that moment, which is the same kind of thing as their level or zone.
		local info = C_PlayerInfo
		if info and info.GetPlayerMythicPlusRatingSummary then
			local summary = Get(info.GetPlayerMythicPlusRatingSummary, unit)
			if type(summary) == "table" then
				local score = Plain(summary.currentSeasonScore)
				if type(score) == "number" and score > 0 then facts.mythicPlus = score end
			end
		end
		local paperDoll = C_PaperDollInfo
		if paperDoll and paperDoll.GetInspectItemLevel then
			local level = Plain(Get(paperDoll.GetInspectItemLevel, unit))
			if type(level) == "number" and level > 0 then facts.itemLevel = level end
		end

		-- Only for a race that has a second body to be in. The form flag answers
		-- false for everyone else, and storing that would claim an orc was
		-- transformed.
		local body = ns.RaceBody
		local diagnostics = ns.Diagnostics
		if body and body.HasAlternateForm(facts.raceID)
			and diagnostics and type(diagnostics.UseNativeForm) == "function" then
			local native = diagnostics.UseNativeForm(unit)
			-- The form they were standing in, which is how they were seen and
			-- so how they should be shown again.
			facts.nativeForm = native and true or false
		end
	end

	local where = WhereWeAre()
	facts.zone = where.zone
	facts.subZone = where.subZone
	facts.mapID = where.mapID
	facts.x = where.x
	facts.y = where.y

	local version, _build, _date, tocVersion = Get(GetBuildInfo)
	facts.build = version
	facts.tocVersion = tocVersion
	facts.capturedBy = Plain(Get(UnitGUID, "player"))

	return facts, identified
end

local function LibraryStore()
	local Library = ns.Library
	if type(Library) ~= "table" then return nil, "the library module is not loaded" end
	if type(MogtrotDB) ~= "table" then return nil, "saved variables are not ready" end
	local library = MogtrotDB.library
	if type(library) ~= "table" or type(library.records) ~= "table" then
		return nil, "this account has no library yet; /reload once"
	end
	return library
end

-- Captures the targeted player. Self is allowed and is the control: it is the
-- one capture whose answer you can check by looking at your own character.
function SnapCapture.Target(Addon)
	local Look = ns.InspectLook
	local Library = ns.Library
	if type(Look) ~= "table" or type(Library) ~= "table" then
		Addon:Warn("capture unavailable: a module is not loaded.")
		return
	end
	-- Combat is the context the client hides identity in, and inspecting
	-- mid-fight is noise regardless.
	if InCombatLockdown() then
		Addon:Warn("not while you are in combat.")
		return
	end
	if not (C_TransmogCollection and C_TransmogCollection.GetInspectItemTransmogInfoList) then
		Addon:Warn("this client exposes no inspect appearance list.")
		return
	end

	local library, why = LibraryStore()
	if not library then
		Addon:Warn("capture unavailable: %s.", tostring(why))
		return
	end

	local unit = "player"
	if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
		unit = "target"
	else
		Addon:Say("no player targeted; capturing you.")
	end
	Cancel(true)

	-- Identity is read now, from the unit actually being pointed at, and the
	-- GUID is held for the rest of the capture. Reading it when the answer
	-- arrives instead would describe whoever is targeted by then.
	local facts, identified = Gather(unit)
	-- Without a GUID to pin, an answer about anybody would pass the check in
	-- the event handler, so a hidden identity is refused rather than guessed.
	if not identified then
		Addon:Warn("can't snap your target here; their identity is hidden.")
		return
	end
	local pinnedGUID = facts.guid

	-- The inspect list is global: it holds whoever was last inspected, with no
	-- unit argument to ask with. Left alone, the first read can hand back the
	-- previous player's outfit under this player's name. Clearing it first
	-- means an answer can only be this capture's.
	if ClearInspectPlayer then pcall(ClearInspectPlayer) end
	if NotifyInspect then NotifyInspect(unit) end

	local function Finish(look, filled)
		facts.look = look
		local record, refused = Library.Snap(facts, time and time() or 0)
		if not record then
			Addon:Warn("nothing captured: %s.", tostring(refused))
			return
		end

		local id, isNew, failed = Library.Add(library, record, record.seenAt)
		if not id then
			Addon:Warn("nothing saved: %s.", tostring(failed))
			return
		end

		local who = record.name or "someone whose name is hidden here"
		if isNew then
			Addon:Say("saved %s as look #%d: %d slot(s).", who, id, filled)
		else
			Addon:Say("%s wears look #%d, already in the library; seen %d time(s).",
				who, id, library.records[id].seenCount or 1)
		end
		-- Borrow while they are still standing there. A donor lends only sex,
		-- so this one person supplies every body of theirs the library wants,
		-- not just the record they are in.
		if ns.LibraryUI and ns.LibraryUI.WarmAll then
			pcall(ns.LibraryUI.WarmAll, unit)
		end
		if ns.LibraryUI then ns.LibraryUI.Refresh() end
	end

	-- INSPECT_READY names the player it answers for, which is the only thing
	-- that ties the shared list to a unit. Polling the list instead asks "is
	-- there an answer" when the question is "is there an answer about them".
	waiter = CreateFrame("Frame")
	waiter:RegisterEvent("INSPECT_READY")
	local elapsed = 0
	waiter:SetScript("OnUpdate", function(_self, delta)
		elapsed = elapsed + delta
		if elapsed < INSPECT_TIMEOUT then return end
		Cancel(true)
		Addon:Warn("no answer about %s in %d seconds; stay in range and try again.",
			tostring(facts.name), INSPECT_TIMEOUT)
	end)
	waiter:SetScript("OnEvent", function(_self, _event, inspecteeGUID)
		if pinnedGUID and inspecteeGUID ~= pinnedGUID then return end
		Cancel(false)

		local ok, list = pcall(C_TransmogCollection.GetInspectItemTransmogInfoList)
		local look, filled = Look.FromTransmogList(ok and list or nil)
		if ClearInspectPlayer then pcall(ClearInspectPlayer) end
		if filled == 0 then
			Addon:Warn("%s answered with nothing worn.", tostring(facts.name))
			return
		end
		Finish(look, filled)
	end)
end

ns.SnapCapture = SnapCapture
return SnapCapture
