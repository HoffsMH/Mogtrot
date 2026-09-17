local _, ns = ...
local Pins = ns.Pins or require("Pins")

local function MountPinDomain()
	local db = MogtrotDB
	local pins = db and db.pins
	if type(pins) ~= "table" then return nil end
	local domain = pins.mounts
	if type(domain) ~= "table" or type(domain.records) ~= "table"
		or domain.autoNew == nil or domain.days == nil then
		return nil
	end
	return domain
end

-- Prints runtime state used in bug reports.
local Diagnostics = {}

function Diagnostics.ShowState(Addon, deps)
	local captureModel = deps.captureModel()
	local NO_TRANSMOG = deps.noTransmog
	local Wear = deps.Wear
	local WearSession = deps.wearSession
	local activeID = C_TransmogOutfitInfo.GetActiveOutfitID()
	local cached, links = 0, 0
	for _ in pairs(MogtrotCharDB.looks or {}) do cached = cached + 1 end
	for _ in pairs(MogtrotCharDB.mounts or {}) do links = links + 1 end

	local slots, list = 0, captureModel and captureModel:GetItemTransmogInfoList()
	if list then
		for _, entry in pairs(list) do
			if type(entry) == "table" and entry.appearanceID
				and entry.appearanceID ~= NO_TRANSMOG then
				slots = slots + 1
			end
		end
	end

	Addon:Say("active outfit %s, %d cached look(s), %d outfit(s) with mounts.",
		tostring(activeID), cached, links)
	Addon:Say("capture model %s, %d slot(s) readable.",
		captureModel and "ready" or "not created", slots)
	local measured, incomplete = 0, 0
	for outfitID in pairs(MogtrotCharDB.slots or {}) do
		if Addon:LintState(outfitID) ~= "unknown" then
			measured = measured + 1
			if Addon:LintState(outfitID) == "short" then incomplete = incomplete + 1 end
		end
	end
	Addon:Say("%d outfit(s) checked for slots, %d with something unset.", measured, incomplete)

	local wear = Addon:WearSnapshot()
	Addon:Say("wear time %s tracked across %d outfit(s), interval open on %s.",
		Wear.Format(wear.sum), wear.count, tostring(WearSession().id))

	Addon:Say(Addon:SummonBindingText())
	Addon:Say(Addon:SummonFallbackText())
end

local PROBE_WIDGETS = { "DressUpModel", "PlayerModel", "CinematicModel" }

local function Try(fn, ...)
	if type(fn) ~= "function" then return "no such function" end
	local ok, first = pcall(fn, ...)
	if not ok then return "error" end
	if type(first) == "table" then
		local count = 0
		for _ in pairs(first) do count = count + 1 end
		return ("table with %d entr%s"):format(count, count == 1 and "y" or "ies")
	end
	return tostring(first)
end

-- One throwaway frame per widget type, kept parented and hidden. Creating it
-- is the only way to ask what methods this build actually put on it.
local function WidgetFindings()
	local widgets = {}
	for _, kind in ipairs(PROBE_WIDGETS) do
		local ok, frame = pcall(CreateFrame, kind, nil, UIParent)
		if ok and frame then
			frame:Hide()
			widgets[#widgets + 1] = {
				name = kind,
				has = function(method) return type(frame[method]) == "function" end,
			}
		else
			widgets[#widgets + 1] = { name = kind, has = false }
		end
	end

	local scene = select(2, pcall(CreateFrame, "ModelScene", nil, UIParent))
	local actor = scene and scene.CreateActor and select(2, pcall(scene.CreateActor, scene))
	widgets[#widgets + 1] = {
		name = "ModelSceneActor",
		has = actor and function(method) return type(actor[method]) == "function" end or false,
	}
	if scene then scene:Hide() end
	return widgets
end

local function NamespaceFindings(Probe)
	local found = {}
	for _, name in ipairs(Probe.NAMESPACES) do
		local namespace = _G[name]
		local functions = false
		if type(namespace) == "table" then
			functions = {}
			for key, value in pairs(namespace) do
				if type(value) == "function" then functions[key] = true end
			end
		end
		found[#found + 1] = { name = name, functions = functions }
	end
	return found
end

-- Everything the record would have to carry to rebuild this body later.
local function UnitFindings()
	local units = {}
	for _, unit in ipairs({ "player", "target" }) do
		if UnitExists and UnitExists(unit) and UnitIsPlayer and UnitIsPlayer(unit) then
			local race, raceFile, raceID = UnitRace(unit)
			local class, classFile, classID = UnitClass(unit)
			units[#units + 1] = { label = unit, fields = {
				{ "name", UnitName(unit) },
				{ "race", race }, { "raceFilename", raceFile }, { "raceID", raceID },
				{ "class", class }, { "classFilename", classFile }, { "classID", classID },
				{ "UnitSex (2 or 3)", UnitSex and UnitSex(unit) },
				{ "guid", UnitGUID(unit) },
				{ "level", UnitLevel and UnitLevel(unit) },
			} }
		end
	end
	return units
end

-- Read-only calls whose answer is the point of the whole probe.
local function CallFindings()
	local calls = {}
	local barber = C_BarberShop
	calls[#calls + 1] = { "C_BarberShop.GetAvailableCustomizations()",
		Try(barber and barber.GetAvailableCustomizations) }
	calls[#calls + 1] = { "C_BarberShop.GetCurrentCharacterData()",
		Try(barber and barber.GetCurrentCharacterData) }

	local info = C_PlayerInfo
	local guid = UnitGUID and UnitGUID("target") or nil
	if info and info.GetRace and guid and PlayerLocation then
		local location = PlayerLocation:CreateFromGUID(guid)
		calls[#calls + 1] = { "C_PlayerInfo.GetRace(target location)",
			Try(info.GetRace, location) }
		calls[#calls + 1] = { "C_PlayerInfo.GetSex(target location)",
			Try(info.GetSex, location) }
	else
		calls[#calls + 1] = { "C_PlayerInfo location calls", "no player target" }
	end

	-- Display IDs are the one route left to a body that is not yours: an
	-- actor takes one directly, and the model widgets answered 0.
	if info then
		calls[#calls + 1] = { "C_PlayerInfo.GetDisplayID()", Try(info.GetDisplayID) }
		calls[#calls + 1] = { "C_PlayerInfo.GetNativeDisplayID()",
			Try(info.GetNativeDisplayID) }
		calls[#calls + 1] = { "C_PlayerInfo.GetAlternateFormInfo()",
			Try(info.GetAlternateFormInfo) }
		if guid and PlayerLocation then
			local location = PlayerLocation:CreateFromGUID(guid)
			calls[#calls + 1] = { "C_PlayerInfo.GetDisplayID(target location)",
				Try(info.GetDisplayID, location) }
			calls[#calls + 1] = { "C_PlayerInfo.GetName(target location)",
				Try(info.GetName, location) }
		end
	end

	-- The custom-set surface, which is the cap and the import path.
	local collection = C_TransmogCollection
	if collection then
		calls[#calls + 1] = { "C_TransmogCollection.GetNumMaxCustomSets()",
			Try(collection.GetNumMaxCustomSets) }
		calls[#calls + 1] = { "C_TransmogCollection.GetCustomSets()",
			Try(collection.GetCustomSets) }
	end
	local outfits = C_TransmogOutfitInfo
	if outfits then
		calls[#calls + 1] = { "C_TransmogOutfitInfo.GetMaxNumberOfUsableOutfits()",
			Try(outfits.GetMaxNumberOfUsableOutfits) }
		calls[#calls + 1] = { "C_TransmogOutfitInfo.GetMaxNumberOfTotalOutfitsForSource()",
			Try(outfits.GetMaxNumberOfTotalOutfitsForSource) }
	end

	-- What the barber shop will say about the current character outside the
	-- shop, field by field rather than as a count.
	if barber and barber.GetCurrentCharacterData then
		local okData, data = pcall(barber.GetCurrentCharacterData)
		if okData and type(data) == "table" then
			local keys = {}
			for key, value in pairs(data) do
				keys[#keys + 1] = ("%s=%s"):format(tostring(key), tostring(value))
			end
			table.sort(keys)
			calls[#calls + 1] = { "C_BarberShop.GetCurrentCharacterData fields",
				table.concat(keys, " ") }
		end
	end

	-- An actor is the only widget carrying the body setters, so ask it
	-- directly whether it will take a unit that is not the player.
	local okScene, scene = pcall(CreateFrame, "ModelScene", nil, UIParent,
		"ModelSceneMixinTemplate")
	if not (okScene and scene) then
		okScene, scene = pcall(CreateFrame, "ModelScene", nil, UIParent)
	end
	calls[#calls + 1] = { "ModelScene from ModelSceneMixinTemplate",
		scene and tostring(type(scene.TransitionToModelSceneID) == "function") or "no scene" }
	local actor = okScene and scene and scene.CreateActor
		and select(2, pcall(scene.CreateActor, scene)) or nil
	if actor and actor.SetModelByUnit then
		calls[#calls + 1] = { "actor:SetModelByUnit(player)",
			Try(actor.SetModelByUnit, actor, "player") }
		if UnitExists and UnitExists("target") then
			calls[#calls + 1] = { "actor:SetModelByUnit(target)",
				Try(actor.SetModelByUnit, actor, "target") }
		end
		-- Seventh argument is the customRaceID the docs describe; a thrown
		-- error here is the answer, which is why it runs inside Try.
		calls[#calls + 1] = { "actor:SetModelByUnit(player, nil, nil, nil, nil, nil, 6)",
			Try(actor.SetModelByUnit, actor, "player", false, false, false, false, false, 6) }
	end
	if scene then scene:Hide() end

	-- The decisive test, on a plain actor because rendering is not the
	-- question: does the dress API still work once the body came from a
	-- display ID rather than from a unit?
	if actor then
		local own = info and info.GetDisplayID and select(2, pcall(info.GetDisplayID)) or nil
		local targetID
		if guid and PlayerLocation and info and info.GetDisplayID then
			local location = PlayerLocation:CreateFromGUID(guid)
			targetID = select(2, pcall(info.GetDisplayID, location))
		end
		local displayID = tonumber(targetID) or tonumber(own)
		calls[#calls + 1] = { "display ID used for the body test", tostring(displayID) }
		if displayID then
			calls[#calls + 1] = { "actor:SetModelByCreatureDisplayID(displayID)",
				Try(actor.SetModelByCreatureDisplayID, actor, displayID) }
			calls[#calls + 1] = { "actor:Undress() on that body",
				Try(actor.Undress, actor) }
			local transmogInfo = ItemUtil and ItemUtil.CreateItemTransmogInfo
				and select(2, pcall(ItemUtil.CreateItemTransmogInfo, 0, 0, 0)) or nil
			calls[#calls + 1] = { "actor:SetItemTransmogInfo() on that body",
				transmogInfo and Try(actor.SetItemTransmogInfo, actor, transmogInfo, 1)
					or "could not build an ItemTransmogInfo" }
			calls[#calls + 1] = { "actor:SetAutoDress(false) on that body",
				Try(actor.SetAutoDress, actor, false) }
		end
	end

	-- Blizzard's own route, available only when the mixin template took.
	if scene and type(scene.TransitionToModelSceneID) == "function" then
		local sceneID = _G.DRESS_UP_FRAME_MODEL_SCENE_ID
		calls[#calls + 1] = { "DRESS_UP_FRAME_MODEL_SCENE_ID", tostring(sceneID) }
		if sceneID then
			pcall(scene.TransitionToModelSceneID, scene, sceneID,
				_G.CAMERA_TRANSITION_TYPE_IMMEDIATE,
				_G.CAMERA_MODIFICATION_TYPE_DISCARD, true)
			local playerActor = scene.GetPlayerActor
				and select(2, pcall(scene.GetPlayerActor, scene)) or nil
			calls[#calls + 1] = { "scene:GetPlayerActor() after transition",
				playerActor and "actor" or "nil" }
			if playerActor and UnitExists and UnitExists("target") then
				calls[#calls + 1] = { "playerActor:SetModelByUnit(target)",
					Try(playerActor.SetModelByUnit, playerActor, "target") }
			end
		end
	end

	local ok, model = pcall(CreateFrame, "DressUpModel", nil, UIParent)
	if ok and model then
		model:Hide()
		if model.SetUnit then pcall(model.SetUnit, model, "player") end
		calls[#calls + 1] = { "DressUpModel:GetDisplayInfo() after SetUnit(player)",
			Try(model.GetDisplayInfo, model) }
		if UnitExists and UnitExists("target") and model.SetUnit then
			pcall(model.SetUnit, model, "target")
			calls[#calls + 1] = { "DressUpModel:GetDisplayInfo() after SetUnit(target)",
				Try(model.GetDisplayInfo, model) }
		end
	end
	return calls
end

-- Dumps what this client build exposes, rather than what the pinned source
-- says it should. Read-only: nothing here changes a setting or uses an item.
function Diagnostics.ProbeClient(Addon, _deps)
	local Probe = ns.ClientProbe
	if type(Probe) ~= "table" then
		Addon:Warn("probe unavailable: the probe module is not loaded.")
		return
	end

	local lines = Probe.Lines({
		build = select(1, GetBuildInfo()),
		widgets = WidgetFindings(),
		namespaces = NamespaceFindings(Probe),
		units = UnitFindings(),
		calls = CallFindings(),
	})

	Addon:Say("probe: %d lines. Target a player first for the richest answer.",
		#lines)
	if ns.CopyBox then
		ns.CopyBox.Show("Mogtrot client probe", lines)
	else
		for _, line in ipairs(lines) do print(line) end
	end
end

local function TransmogListFromLook(look)
	local list = {}
	if type(look) ~= "table" or not (ItemUtil and ItemUtil.CreateItemTransmogInfo) then
		return list
	end
	for slotID, entry in pairs(look) do
		local empty = (entry[1] or 0) == 0 and (entry[2] or 0) == 0
			and (entry[3] or 0) == 0
		if type(slotID) == "number" and type(entry) == "table" and not empty then
			local ok, info = pcall(ItemUtil.CreateItemTransmogInfo,
				entry[1], entry[2], entry[3])
			if ok and info then list[slotID] = info end
		end
	end
	return list
end

-- The boolean SetModelByUnit wants for usePlayerNativeForm.
--
-- C_UnitAuras.WantsAlteredForm reads as a preference and is not one. Measured
-- against a Dracthyr in each form, it is the exact inverse of
-- GetAlternateFormInfo's inAlternateForm, which makes it the value to pass
-- straight through rather than negate:
--
--   in dragon form: WantsAlteredForm true,  inAlternateForm false
--   in visage form: WantsAlteredForm false, inAlternateForm true
--
-- GetAlternateFormInfo is authoritative but answers only for the player, so it
-- is preferred there and the aura flag covers everyone else.
local function UseNativeForm(unit)
	if unit == "player" and C_PlayerInfo and C_PlayerInfo.GetAlternateFormInfo then
		local ok, _hasAlternate, inAlternate = pcall(C_PlayerInfo.GetAlternateFormInfo)
		if ok then return not inAlternate, "GetAlternateFormInfo" end
	end
	if C_UnitAuras and C_UnitAuras.WantsAlteredForm then
		local ok, wants = pcall(C_UnitAuras.WantsAlteredForm, unit)
		if ok then return wants and true or false, "WantsAlteredForm" end
	end
	return true, "nothing answered, assuming native"
end

local INSPECT_INTERVAL = 0.5
local INSPECT_ATTEMPTS = 10

local inspectTicker

-- Rough draft: inspect the targeted player and report their appearance list.
-- The client answers asynchronously, so this polls on the same cadence Mogsnap
-- proved, and stops as soon as a slot carries a real appearance.
-- One outfit on differently set bodies, plus the test that separates "display
-- IDs do not work" from "player display IDs do not work".
function Diagnostics.ProbeRender(Addon, _deps)
	local render = ns.ProbeRenderUI
	if type(render) ~= "table" then
		Addon:Warn("probe render unavailable: the render module is not loaded.")
		return
	end
	if InCombatLockdown() then
		Addon:Warn("probe render unavailable during combat.")
		return
	end

	local info = C_PlayerInfo
	local outfits = C_TransmogOutfitInfo
	local outfitID = outfits and outfits.GetActiveOutfitID
		and select(2, pcall(outfits.GetActiveOutfitID)) or nil
	local own = outfitID and MogtrotCharDB and MogtrotCharDB.looks
		and MogtrotCharDB.looks[outfitID] or nil
	local list = TransmogListFromLook(own)

	local function Dress(actor, onStatus)
		return render.DressWhenLoaded(actor, list, onStatus)
	end
	local function SetUnitBody(actor, unit, autoDress)
		if type(actor.SetModelByUnit) ~= "function" then return false end
		local sheathe, hide, bow = false, false, false
		return (pcall(actor.SetModelByUnit, actor, unit, sheathe, autoDress,
			hide, UseNativeForm(unit), bow))
	end

	-- A live player has no static display row, which is why their own id
	-- renders bare. A mount does have one and its id is readable, so this
	-- separates the two cases without hardcoding a guessed number.
	local function AnyStaticDisplayID()
		local journal = C_MountJournal
		if not (journal and journal.GetMountIDs
			and journal.GetAllCreatureDisplayIDsForMountID) then
			return nil
		end
		local okIDs, mounts = pcall(journal.GetMountIDs)
		for _, mountID in ipairs(okIDs and mounts or {}) do
			local okInfo, ids = pcall(journal.GetAllCreatureDisplayIDsForMountID, mountID)
			if okInfo and type(ids) == "table" and ids[1] then
				return ids[1], "mount " .. tostring(mountID)
			end
		end
		return nil
	end

	local ownDisplayID = info and info.GetDisplayID
		and select(2, pcall(info.GetDisplayID)) or nil
	local staticID, staticFrom = AnyStaticDisplayID()

	render.Show({
		formNote = function()
			return ("your displayID=%s | a static displayID=%s from %s"):format(
				tostring(ownDisplayID), tostring(staticID), tostring(staticFrom))
		end,
		plans = {
			{
				title = "1. SetModelByUnit(player)",
				note = "control",
				apply = function(actor, onStatus)
					return SetUnitBody(actor, "player", false) and Dress(actor, onStatus)
						or "call failed"
				end,
			},
			{
				title = "2. your own displayID",
				note = "a player id, expected bare",
				apply = function(actor)
					if not ownDisplayID then return "no display ID" end
					if type(actor.SetModelByCreatureDisplayID) ~= "function" then
						return "no call"
					end
					local ok = pcall(actor.SetModelByCreatureDisplayID, actor,
						ownDisplayID, true)
					return ok and "set, undressed on purpose" or "call failed"
				end,
			},
			{
				title = "3. a static displayID",
				note = "does this one texture?",
				apply = function(actor)
					if not staticID then return "no static display ID found" end
					if type(actor.SetModelByCreatureDisplayID) ~= "function" then
						return "no call"
					end
					local ok = pcall(actor.SetModelByCreatureDisplayID, actor, staticID, false)
					return ok and ("%s, id=%d"):format(tostring(staticFrom), staticID)
						or "call failed"
				end,
			},
			{
				title = "4. SetModelByUnit(target)",
				note = "a live body that is not yours",
				apply = function(actor, onStatus)
					if not (UnitExists and UnitExists("target")) then return "no target" end
					return SetUnitBody(actor, "target", false) and Dress(actor, onStatus)
						or "call failed"
				end,
			},
		},
	})
	Addon:Say("probe render open. Panel 3 is the one that matters.")
end

function Diagnostics.InspectTargetLook(Addon, _deps)
	local Look = ns.InspectLook
	if type(Look) ~= "table" then
		Addon:Warn("inspect unavailable: the look module is not loaded.")
		return
	end
	-- Inspecting yourself is the only case with a known answer, so it is the
	-- control for everything the form flag claims about other people.
	local unit = "player"
	if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
		unit = "target"
	else
		Addon:Say("no player targeted; inspecting yourself.")
	end
	if not (C_TransmogCollection and C_TransmogCollection.GetInspectItemTransmogInfoList) then
		Addon:Warn("this client exposes no inspect appearance list.")
		return
	end

	local name = UnitName(unit)
	local race = UnitRace(unit)
	if inspectTicker then
		pcall(inspectTicker.Cancel, inspectTicker)
		inspectTicker = nil
	end
	if NotifyInspect then NotifyInspect(unit) end
	Addon:Say("inspecting %s...", tostring(name))

	local attempts = 0
	local function Finish(look, filled, empty)
		local native, formSource = UseNativeForm(unit)
		local altered = not native
		local wantsSelf, inAlternateSelf = "?", "?"
		if C_UnitAuras and C_UnitAuras.WantsAlteredForm then
			local ok, wants = pcall(C_UnitAuras.WantsAlteredForm, "player")
			if ok then wantsSelf = tostring(wants) end
		end
		if C_PlayerInfo and C_PlayerInfo.GetAlternateFormInfo then
			local ok, _has, inAlternate = pcall(C_PlayerInfo.GetAlternateFormInfo)
			if ok then inAlternateSelf = tostring(inAlternate) end
		end

		local lines = Look.Format(look,
			("%s the %s - %d worn, %d empty, alteredForm=%s via %s"
				.. " | you: WantsAlteredForm=%s GetAlternateFormInfo=%s")
				:format(tostring(name), tostring(race), filled, empty, tostring(altered),
					tostring(formSource), wantsSelf, inAlternateSelf))
		Addon:Say("captured %s: %d worn, %d empty.", tostring(name), filled, empty)

		local render = ns.ProbeRenderUI
		if not render or type(render.DressWhenLoaded) ~= "function" then
			if ns.CopyBox then
				ns.CopyBox.Show("Mogtrot inspect: " .. tostring(name), lines)
			end
			return
		end

		-- Panel one is the truth, panel two is the same body rebuilt from the
		-- record alone, panel three is that record on a different body. If one
		-- and two match, the capture lost nothing.
		local list = TransmogListFromLook(look)
		-- usePlayerNativeForm asks for the native body, so it is the inverse of
		-- the form that unit is standing in, read per unit rather than taken
		-- from whoever happens to be looking.
		local function SetBody(actor, bodyUnit, autoDress)
			if type(actor.SetModelByUnit) ~= "function" then return false end
			local sheatheWeapons, hideWeapons, holdBowString = false, false, false
			local usePlayerNativeForm = UseNativeForm(bodyUnit)
			return (pcall(actor.SetModelByUnit, actor, bodyUnit, sheatheWeapons, autoDress,
				hideWeapons, usePlayerNativeForm, holdBowString))
		end

		render.Show({
			formNote = function()
				return ("%s the %s: %d worn, %d empty, alteredForm=%s"
					.. " | you: wants=%s inAlt=%s | %d rebuilt")
					:format(tostring(name), tostring(race), filled, empty,
						tostring(altered), wantsSelf, inAlternateSelf,
						(function() local n = 0 for _ in pairs(list) do n = n + 1 end return n end)())
			end,
			plans = {
				{
					title = "1. " .. tostring(name) .. ", live",
					note = "what the game shows",
					apply = function(actor)
						return SetBody(actor, unit, true) and "untouched" or "call failed"
					end,
				},
				{
					title = "2. rebuilt from the record",
					note = "same body, record only",
					apply = function(actor, onStatus)
						if not SetBody(actor, unit, false) then return "call failed" end
						return render.DressWhenLoaded(actor, list, onStatus)
					end,
				},
				{
					title = "3. the same record on you",
					note = "your body, their outfit",
					apply = function(actor, onStatus)
						if not SetBody(actor, "player", false) then return "call failed" end
						return render.DressWhenLoaded(actor, list, onStatus)
					end,
				},
			},
		})
		if ns.CopyBox then
			ns.CopyBox.Show("Mogtrot inspect: " .. tostring(name), lines)
		end
	end

	inspectTicker = C_Timer.NewTicker(INSPECT_INTERVAL, function()
		attempts = attempts + 1
		local ok, list = pcall(C_TransmogCollection.GetInspectItemTransmogInfoList)
		local look, filled, empty = Look.FromTransmogList(ok and list or nil)

		if filled > 0 then
			if inspectTicker then
				pcall(inspectTicker.Cancel, inspectTicker)
				inspectTicker = nil
			end
			Finish(look, filled, empty)
			return
		end
		if attempts >= INSPECT_ATTEMPTS then
			if inspectTicker then
				pcall(inspectTicker.Cancel, inspectTicker)
				inspectTicker = nil
			end
			Addon:Warn("gave up after %d tries; stay in range and target them again.",
				attempts)
		end
	end)
end

function Diagnostics.Handle(Addon, deps, cmd)
	local Macro = deps.Macro
	local AccountMacroCount = deps.accountMacroCount
	if cmd == "debug" then
		MogtrotDB.debug = not MogtrotDB.debug
		Addon:Warn("debug output %s.", MogtrotDB.debug and "on" or "off")
		return
	end
	
	local nudge = cmd:match("^nudge%s+(-?[%d%.]+)$")
	if MogtrotDB.debug and nudge then
		MogtrotDB.cardNudge = tonumber(nudge) or 0
		Addon:Debug("card nudge = %s", tostring(MogtrotDB.cardNudge))
		Addon:RepaintMountCards()
		return
	end
	
	
	local why = cmd:match("^why%s+(.+)$")
	if MogtrotDB.debug and why then
		local index = ns.MountIndex.Build(MogtrotCharDB)
		local domain = MountPinDomain()
		local shown = 0
		for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
			local name, _spellID, _i, _a, _u, _s, _isFavorite, _fs, _f, hidden, collected =
				C_MountJournal.GetMountInfoByID(mountID)
			if collected and not hidden and shown < 8
				and name and strlower(name):find(why, 1, true) then
				shown = shown + 1
				Addon:Debug("%s: pairings=%d pinned=%s", name,
					#(index[mountID] or {}),
					tostring(domain and Pins.IsPinned(domain, mountID, time()) or false))
			end
		end
		if shown == 0 then Addon:Debug("no collected mount matching '%s'", why) end
		return
	end
	
	
	if cmd == "macro" then
		for _, command in ipairs(Macro.ORDER) do
			Addon:Say("wanted %s: %s", command, (Macro.Body(command):gsub("\n", " | ")))
		end
	
		local count = AccountMacroCount()
		local found = {}
		for index = 1, count do
			local body = GetMacroBody(index)
			local command = Macro.CommandOf(body)
			if command then
				found[command] = true
				local name, icon = GetMacroInfo(index)
				Addon:Say("slot %d %s: name=%s icon=%s", index, command,
					tostring(name), tostring(icon))
				for line in tostring(body):gmatch("[^\n]+") do
					Addon:Say("  line: %q", line)
				end
			end
		end
	
		for _, command in ipairs(Macro.ORDER) do
			if not found[command] then
				Addon:Say("no %s macro among %d general macros", command, count)
			end
		end
		return
	end
	
	return false
end

ns.Diagnostics = Diagnostics
return Diagnostics
