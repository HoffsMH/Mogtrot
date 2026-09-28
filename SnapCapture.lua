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

-- How long the confirmation waits before keeping the capture by itself.
SnapCapture.CONFIRM_SECONDS = 3

-- How far the Confirm button's fill has run, 0 at the start and 1 at the end.
function SnapCapture.ConfirmFraction(elapsed, duration)
	if type(duration) ~= "number" or duration <= 0 then return 1 end
	if type(elapsed) ~= "number" then return 1 end
	local done = elapsed / duration
	if done < 0 then return 0 end
	if done > 1 then return 1 end
	return done
end

-- Quiet means quiet, and a pop-up in the middle of a fight is noise.
function SnapCapture.ShouldConfirm(quiet, inCombat)
	return not quiet and not inCombat
end

-- Whether the pop-up may build its body from the unit the capture read: only
-- while that unit is still the player pinned, with a readable identity and a
-- model the client says is ready.
function SnapCapture.LiveBodyAllowed(pinnedGUID, currentGUID, identitySecret, modelReady)
	if identitySecret or not modelReady then return false end
	if type(pinnedGUID) ~= "string" or type(currentGUID) ~= "string" then return false end
	return currentGUID == pinnedGUID
end

-- While the pop-up is up without the live body, it asks again every
-- LIVE_RETRY_EVERY seconds until LIVE_RETRY_FOR. Answers "check", "wait" or
-- "stop" for the time since the pop-up opened and since the last ask.
SnapCapture.LIVE_RETRY_FOR = 1
SnapCapture.LIVE_RETRY_EVERY = 0.1

function SnapCapture.LiveRetry(elapsed, sinceLast)
	if type(elapsed) ~= "number" or elapsed > SnapCapture.LIVE_RETRY_FOR then
		return "stop"
	end
	if type(sinceLast) == "number" and sinceLast < SnapCapture.LIVE_RETRY_EVERY then
		return "wait"
	end
	return "check"
end

-- A capture shown on the confirmation and not yet written. Held in memory
-- only, so a /reload or logout while it is up loses it.
local pending
local pendingToken = 0

function SnapCapture.Pending()
	return pending
end

-- Writes the capture to the library and says so in chat.
local function Save(addon, library, record, filled)
	local Library = ns.Library
	local id, isNew, failed = Library.Add(library, record, record.seenAt)
	if not id then
		addon:Warn("nothing saved: %s.", tostring(failed))
		return
	end
	local who = record.name or "someone whose name is hidden here"
	if isNew then
		addon:Say("saved the look of %s (%d piece%s).", who, filled, filled == 1 and "" or "s")
	else
		addon:Say("the look of %s is already in your library.", who)
	end
	if ns.LibraryUI and ns.LibraryUI.Refresh then ns.LibraryUI.Refresh() end
	return id, isNew
end

-- Settles the pending capture: keep writes it, otherwise it is dropped. A
-- token that is not the pending one is a late click or timer and does nothing.
function SnapCapture.Resolve(token, keep)
	if not pending or token ~= pending.token then return false end
	local held = pending
	pending = nil
	local ui = ns.SnapConfirmUI
	if ui and ui.HideConfirm then pcall(ui.HideConfirm, token) end
	if keep then
		Save(held.addon, held.library, held.record, held.filled)
	else
		held.addon:Say("discarded the capture of %s; nothing saved.",
			held.record.name or "someone whose name is hidden here")
	end
	return true
end

-- Shows the capture and holds it until Confirm, Cancel or the time running
-- out, which keeps it. Anything that stops the pop-up showing saves at once.
local function Offer(addon, library, record, filled, liveUnit, recheck)
	local ui = ns.SnapConfirmUI
	local Library = ns.Library
	pendingToken = pendingToken + 1
	local token = pendingToken
	pending = { token = token, addon = addon, library = library,
		record = record, filled = filled }

	local existing = Library.Find and Library.Find(library, record) or nil
	local shown = library.records[existing] or record
	local ok = pcall(ui.ConfirmSnap, shown, existing == nil, token, liveUnit, recheck)
	if not ok then
		SnapCapture.Resolve(token, true)
		return
	end
	C_Timer.After(SnapCapture.CONFIRM_SECONDS, function()
		SnapCapture.Resolve(token, true)
	end)
end

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

-- The unit the pop-up may build its body from, or nil for the rendering the
-- library would give it.
local function LiveBodyUnit(unit, pinnedGUID)
	if not Get(UnitExists, unit) then return nil end
	local current = Plain(Get(UnitGUID, unit))
	local ready = Plain(Get(IsUnitModelReadyForUI, unit))
	if SnapCapture.LiveBodyAllowed(pinnedGUID, current, IdentityIsSecret(unit),
		ready == true) then
		return unit
	end
	return nil
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
		facts.specID = Plain(Get(C_SpecializationInfo
			and C_SpecializationInfo.GetInspectSpecialization, unit))
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
		if body and body.HasAlternateForm(facts.raceID) then
			local native = body.UseNativeForm(unit)
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
	if type(MogtrotDB) ~= "table" then return nil, "Mogtrot is not ready yet; try again in a moment" end
	local library = MogtrotDB.library
	if type(library) ~= "table" or type(library.records) ~= "table" then
		return nil, "this account has no library yet; /reload once"
	end
	if select(2, Library.Writable(library)) == "newer" then
		return nil, "your library was saved by a newer version of Mogtrot, "
			.. "so it is read-only until you update Mogtrot"
	end
	return library
end

-- Captures the targeted player. Self is allowed and is the control: it is the
-- one capture whose answer you can check by looking at your own character.
function SnapCapture.Target(Addon)
	-- A capture still on the confirmation was going to be kept by default, so
	-- a new snap keeps it before starting.
	if pending then SnapCapture.Resolve(pending.token, true) end

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
		Addon:Warn("can't snap on this game version.")
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
	-- Identity not flagged secret can still leave the GUID secret or empty.
	-- Either way there is nothing to pin, so nothing is captured.
	if not pinnedGUID then
		Addon:Warn("can't snap your target; the game won't say who they are right now.")
		return
	end

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

		-- A snap borrows no body for the library: only passive donors do.

		local ui = ns.SnapConfirmUI
		if ui and ui.ConfirmSnap and SnapCapture.ShouldConfirm(MogtrotDB.quiet,
			InCombatLockdown and InCombatLockdown()) then
			-- The snapped player is usually still in front of you, so the pop-up
			-- can show their own body rather than one the library would lend.
			Offer(Addon, library, record, filled, LiveBodyUnit(unit, pinnedGUID),
				function() return LiveBodyUnit(unit, pinnedGUID) end)
		else
			Save(Addon, library, record, filled)
		end
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
		Addon:Warn("couldn't inspect %s; stay close and try again.", tostring(facts.name))
	end)
	waiter:SetScript("OnEvent", function(_self, _event, inspecteeGUID)
		-- Another addon's inspect of an enemy can arrive here with a secret GUID.
		local guid = Plain(inspecteeGUID)
		if guid == nil or guid ~= pinnedGUID then return end
		Cancel(false)

		local ok, list = pcall(C_TransmogCollection.GetInspectItemTransmogInfoList)
		local look, filled = Look.FromTransmogList(ok and list or nil)
		if ClearInspectPlayer then pcall(ClearInspectPlayer) end
		if filled == 0 then
			Addon:Warn("%s isn't wearing any transmog to save.", tostring(facts.name))
			return
		end
		Finish(look, filled)
	end)
end

ns.SnapCapture = SnapCapture
return SnapCapture
