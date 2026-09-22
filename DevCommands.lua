local _, ns = ...
local Pins = ns.Pins or require("Pins")

-- The development command surface: probes that dump what a client build
-- actually exposes, the target inspector, the body audit, and the tuning
-- commands behind the debug flag.
--
-- This file is listed in MogtrotDev.toc only. A release build has no probe
-- commands at all, and scripts/release refuses to publish an archive that
-- contains this file. Everything here answers a question about the client
-- rather than doing anything for a player, which is why none of it ships.
local DevCommands = {}

-- Diagnostics owns the form read because the capture path needs it too.
local function UseNativeForm(...)
	return ns.Diagnostics.UseNativeForm(...)
end

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


function DevCommands.ProbeLibraryTransfer(Addon, _deps)
	local transmog = _G.TransmogFrame
	local detail = _G.MogtrotLibraryDetail
	local button = detail and detail.Transfer
	local outfits = C_TransmogOutfitInfo
	local outfitID = outfits and outfits.GetCurrentlyViewedOutfitID
		and outfits.GetCurrentlyViewedOutfitID() or nil
	local lines = {
		("TransmogFrame exists=%s shown=%s outfit=%s"):format(
			tostring(transmog ~= nil),
			tostring(transmog and transmog:IsShown() or false), tostring(outfitID)),
		("detail exists=%s shown=%s top=%s bottom=%s height=%s"):format(
			tostring(detail ~= nil), tostring(detail and detail:IsShown() or false),
			tostring(detail and detail:GetTop()), tostring(detail and detail:GetBottom()),
			tostring(detail and detail:GetHeight())),
		("transfer exists=%s shown=%s top=%s bottom=%s outfit=%s status=%s"):format(
			tostring(button ~= nil), tostring(button and button:IsShown() or false),
			tostring(button and button:GetTop()), tostring(button and button:GetBottom()),
			tostring(button and button.outfitID),
			tostring(button and button.mogtrotStatus)),
	}
	local sync = Addon.OutfitLibrarySyncState and Addon.OutfitLibrarySyncState()
	local cached, mirrored = 0, 0
	for _ in pairs(MogtrotCharDB and MogtrotCharDB.looks or {}) do cached = cached + 1 end
	for _, record in pairs(MogtrotDB and MogtrotDB.library
		and MogtrotDB.library.records or {}) do
		if record.source == "mine" and record.origin == "outfit"
			and sync and record.guid == sync.ownerGUID then
			mirrored = mirrored + 1
		end
	end
	lines[#lines + 1] =
		("sync owner=%s api=%s cached=%d mirrored=%d missing=%s pruned=%s last=%s")
		:format(tostring(sync and sync.ownerGUID), tostring(sync and sync.apiCount),
			cached, mirrored, tostring(sync and sync.missing),
			tostring(sync and sync.pruned), tostring(sync and sync.syncedAt))
	for _, missing in ipairs(sync and sync.missingOutfits or {}) do
		lines[#lines + 1] = ("sync missing outfit=%s name=%s"):format(
			tostring(missing.outfitID), tostring(missing.name))
	end
	local customSync = Addon.CustomSetLibrarySyncState
		and Addon.CustomSetLibrarySyncState()
	local customMirrored = 0
	for _, record in pairs(MogtrotDB and MogtrotDB.library
		and MogtrotDB.library.records or {}) do
		if record.source == "mine" and record.origin == "customSet"
			and customSync and record.guid == customSync.ownerGUID then
			customMirrored = customMirrored + 1
		end
	end
	lines[#lines + 1] =
		("custom sync owner=%s api=%s mirrored=%d missing=%s pruned=%s last=%s reason=%s")
		:format(tostring(customSync and customSync.ownerGUID),
			tostring(customSync and customSync.apiCount), customMirrored,
			tostring(customSync and customSync.missing),
			tostring(customSync and customSync.pruned),
			tostring(customSync and customSync.syncedAt),
			tostring(customSync and customSync.reason))
	for _, missing in ipairs(customSync and customSync.missingSets or {}) do
		lines[#lines + 1] = ("custom sync missing set=%s name=%s"):format(
			tostring(missing.customSetID), tostring(missing.name))
	end
	local slots = {}
	for slotID in pairs(detail and detail.Slots or {}) do slots[#slots + 1] = slotID end
	table.sort(slots)
	for _, slotID in ipairs(slots) do
		local icon = detail.Slots[slotID]
		local entry = icon.entry
		if entry and not entry.empty then
			local info = C_TransmogCollection and C_TransmogCollection.GetSourceInfo
				and C_TransmogCollection.GetSourceInfo(entry.source) or nil
			local red, green, blue = icon.Texture:GetVertexColor()
			lines[#lines + 1] =
				("slot=%d source=%s collected=%s marked=%s color=%.2f,%.2f,%.2f")
				:format(slotID, tostring(entry.source),
					tostring(info and info.isCollected), tostring(entry.uncollected),
					red or -1, green or -1, blue or -1)
		end
	end
	local layerProbe = ns.LibraryUI and ns.LibraryUI.LayerProbe
		and ns.LibraryUI.LayerProbe() or nil
	local function AddLayer(label, data)
		lines[#lines + 1] = ("layer %s strata=%s level=%s fixedStrata=%s fixedLevel=%s")
			:format(label, tostring(data and data.strata), tostring(data and data.level),
				tostring(data and data.fixedStrata), tostring(data and data.fixedLevel))
	end
	AddLayer("transmog", transmog and {
		strata = transmog:GetFrameStrata(), level = transmog:GetFrameLevel(),
		fixedStrata = transmog:HasFixedFrameStrata(),
		fixedLevel = transmog:HasFixedFrameLevel(),
	} or nil)
	AddLayer("library", layerProbe and layerProbe.window)
	AddLayer("card", layerProbe and layerProbe.card)
	AddLayer("scene", layerProbe and layerProbe.scene)
	for _, line in ipairs(lines) do Addon:Say(line) end
	if ns.CopyBox then ns.CopyBox.Show("Mogtrot library transfer probe", lines) end
end

function DevCommands.ProbeOutfitIngest(Addon, _deps, requestedID)
	if requestedID then
		local captured = Addon.ingestDiagnostics and Addon.ingestDiagnostics[requestedID]
		if not captured then
			Addon:Warn("no scan-time diagnostic for outfit %d; press the ingest button first.",
				requestedID)
			return
		end
		local names = { [0] = "unassigned", [1] = "assigned", [2] = "equipped",
			[3] = "hidden", [4] = "disabled" }
		local lines = { ("scan-time outfit=%d"):format(requestedID) }
		for _, entry in ipairs(captured) do
			lines[#lines + 1] = ("slot=%d display=%s api=%s stored=%s"):format(
				entry.slotID, names[entry.displayType] or tostring(entry.displayType),
				tostring(entry.apiID), tostring(entry.storedID))
		end
		for _, line in ipairs(lines) do Addon:Say(line) end
		if ns.CopyBox then ns.CopyBox.Show("Mogtrot scan-time ingest probe", lines) end
		return
	end
	local capturedIDs = {}
	for outfitID in pairs(Addon.ingestDiagnostics or {}) do
		capturedIDs[#capturedIDs + 1] = outfitID
	end
	if #capturedIDs > 0 then
		table.sort(capturedIDs)
		local labels = {}
		for _, outfitID in ipairs(capturedIDs) do
			local info = Addon.outfitsByID and Addon.outfitsByID[outfitID]
			labels[#labels + 1] = ("%d=%s"):format(outfitID,
				info and info.name or "?")
		end
		local lines = { ("scan-time diagnostics: %d outfit(s)"):format(#capturedIDs),
			table.concat(labels, ", ") }
		for _, line in ipairs(lines) do Addon:Say(line) end
		if ns.CopyBox then ns.CopyBox.Show("Mogtrot scan-time ingest IDs", lines) end
		return
	end
	local frame = _G.TransmogFrame
	local preview = frame and frame.CharacterPreview
	local pool = preview and preview.CharacterAppearanceSlotFramePool
	local outfitID = C_TransmogOutfitInfo.GetCurrentlyViewedOutfitID()
	if not pool or not outfitID or outfitID == 0 then
		Addon:Warn("open Transmog and select the outfit that imported incorrectly.")
		return
	end

	local displayNames = { [0] = "unassigned", [1] = "assigned", [2] = "equipped",
		[3] = "hidden", [4] = "disabled" }
	local stored = MogtrotCharDB.looks and MogtrotCharDB.looks[outfitID] or {}
	local lines = { ("outfit=%s sweep=%s"):format(tostring(outfitID),
		tostring(Addon.sweep ~= nil)) }
	for slotFrame in pool:EnumerateActive() do
		local location = slotFrame:GetTransmogLocation()
		local slotID = location and location:GetSlotID()
		local info = slotFrame:GetSlotInfo()
		if slotID and info then
			local held = stored[slotID]
			lines[#lines + 1] = ("slot=%d display=%s api=%s stored=%s"):format(
				slotID, displayNames[info.displayType] or tostring(info.displayType),
				tostring(info.transmogID), tostring(held and held[1]))
		end
	end
	for _, line in ipairs(lines) do Addon:Say(line) end
	if ns.CopyBox then ns.CopyBox.Show("Mogtrot outfit ingest probe", lines) end
end

function DevCommands.ProbeLayer(Addon, _deps)
	if InCombatLockdown() then
		Addon:Warn("not while you are in combat.")
		return
	end
	local root = DevCommands.layerProbe
	if root then
		root:SetShown(not root:IsShown())
		return
	end

	root = CreateFrame("Frame", "MogtrotLayerProbe", UIParent, "BackdropTemplate")
	root:SetSize(300, 420)
	root:SetPoint("CENTER")
	root:SetFrameStrata("TOOLTIP")
	root:SetFrameLevel(9999)
	root:SetToplevel(true)
	root:SetFlattensRenderLayers(true)
	root:SetIsFrameBuffer(true)
	root:SetMovable(true)
	root:SetClampedToScreen(true)
	root:EnableMouse(true)
	root:RegisterForDrag("LeftButton")
	root:SetScript("OnDragStart", root.StartMoving)
	root:SetScript("OnDragStop", root.StopMovingOrSizing)
	root:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
	})
	root:SetBackdropColor(0, 0, 0, 0.85)
	root:SetBackdropBorderColor(1, 0, 0, 1)

	local scene = CreateFrame("ModelScene", nil, root, "ModelSceneMixinTemplate")
	scene:SetPoint("TOPLEFT", 2, -2)
	scene:SetPoint("BOTTOMRIGHT", -2, 2)
	scene:EnableMouse(false)
	scene:EnableMouseWheel(false)
	local sceneID = 596
	local transitioned = pcall(scene.TransitionToModelSceneID, scene, sceneID,
		CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
	local actor = transitioned and scene.GetPlayerActor and scene:GetPlayerActor() or nil
	local dressed = actor and actor.SetModelByUnit
		and pcall(actor.SetModelByUnit, actor, "player", false, true) or false

	DevCommands.layerProbe = root
	Addon:Say("layer probe open: scene=%s actor=%s dressed=%s; drag the red border.",
		tostring(transitioned), tostring(actor ~= nil), tostring(dressed))
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
function DevCommands.ProbeClient(Addon, _deps)
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
	local render = ns.ProbeRenderUI
	if type(render) ~= "table" then return {} end
	return render.TransmogList(look)
end

local INSPECT_INTERVAL = 0.5
local INSPECT_ATTEMPTS = 10

local inspectTicker
function DevCommands.ProbeBody(Addon, _deps, displayID)
	local render = ns.ProbeRenderUI
	if type(render) ~= "table" then
		Addon:Warn("probe body unavailable: the render module is not loaded.")
		return
	end
	if InCombatLockdown() then
		Addon:Warn("probe body unavailable during combat.")
		return
	end
	displayID = tonumber(displayID)
	if not displayID then
		Addon:Warn("usage: /mogtrot probe body <creature display ID>")
		return
	end

	local outfits = C_TransmogOutfitInfo
	local outfitID = outfits and outfits.GetActiveOutfitID
		and select(2, pcall(outfits.GetActiveOutfitID)) or nil
	local own = outfitID and MogtrotCharDB and MogtrotCharDB.looks
		and MogtrotCharDB.looks[outfitID] or nil
	local list = TransmogListFromLook(own)

	local function SetDisplay(actor, dress)
		if type(actor.SetModelByCreatureDisplayID) ~= "function" then return false end
		return (pcall(actor.SetModelByCreatureDisplayID, actor, displayID, false)), dress
	end

	render.Show({
		formNote = function()
			local count = 0
			for _ in pairs(list) do count = count + 1 end
			return ("display ID %d, dressing %d slot(s) from your active outfit")
				:format(displayID, count)
		end,
		plans = {
			{
				title = "1. bare body",
				note = "is it textured?",
				apply = function(actor)
					return SetDisplay(actor) and "set" or "call failed"
				end,
			},
			{
				title = "2. the same body, dressed",
				note = "your outfit on it",
				apply = function(actor, onStatus)
					if not SetDisplay(actor) then return "call failed" end
					return render.DressWhenLoaded(actor, list, onStatus)
				end,
			},
			{
				title = "3. you, for comparison",
				note = "same outfit, your body",
				apply = function(actor, onStatus)
					if type(actor.SetModelByUnit) ~= "function" then return "no call" end
					local sheathe, hide, bow = false, false, false
					local ok = pcall(actor.SetModelByUnit, actor, "player", sheathe, false,
						hide, UseNativeForm("player"), bow)
					return ok and render.DressWhenLoaded(actor, list, onStatus)
						or "call failed"
				end,
			},
		},
	})
	Addon:Say("probe body %d open.", displayID)
end

local SECRET_UNITS = { "player", "target", "party1", "party2", "party3", "party4",
	"raid1", "raid5", "nameplate1", "mouseover" }

-- Every call the documentation marks as going secret under identity
-- restriction, plus the ones capture depends on. The doc flag says a call CAN
-- be restricted, not that it is, so this asks the client directly.
local SECRET_CALLS = {
	{ "UnitGUID", function(u) return UnitGUID(u) end },
	{ "UnitName", function(u) return UnitName(u) end },
	{ "UnitFullName", function(u) return _G.UnitFullName and _G.UnitFullName(u) end },
	-- The realm arrives as the second return, and the schema stores it apart
	-- from the name, so it needs checking in its own right.
	{ "UnitFullName realm", function(u)
		return _G.UnitFullName and select(2, _G.UnitFullName(u)) end },
	{ "UnitPVPName", function(u) return _G.UnitPVPName and _G.UnitPVPName(u) end },
	{ "UnitRace", function(u) return UnitRace(u) end },
	{ "UnitRace raceID", function(u) return select(3, UnitRace(u)) end },
	{ "UnitSex", function(u) return UnitSex(u) end },
	{ "UnitClass", function(u) return UnitClass(u) end },
	{ "UnitClass classID", function(u) return select(3, UnitClass(u)) end },
	{ "UnitLevel", function(u) return _G.UnitLevel and _G.UnitLevel(u) end },
	{ "UnitFactionGroup", function(u)
		return _G.UnitFactionGroup and _G.UnitFactionGroup(u) end },
	{ "UnitIsPlayer", function(u) return UnitIsPlayer(u) end },
	{ "CanInspect", function(u) return _G.CanInspect and _G.CanInspect(u) end },
	{ "GetInspectSpecialization", function(u)
		return _G.GetInspectSpecialization and _G.GetInspectSpecialization(u) end },
	-- Decides which body a two-form race renders in, so it is a schema field
	-- and belongs in the same census as the rest.
	{ "WantsAlteredForm", function(u)
		return C_UnitAuras and C_UnitAuras.WantsAlteredForm
			and C_UnitAuras.WantsAlteredForm(u) end },
	{ "GUIDIsPlayer", function(u)
		local guid = UnitGUID(u)
		if not guid or (issecretvalue and issecretvalue(guid)) then return nil end
		return C_PlayerInfo and C_PlayerInfo.GUIDIsPlayer
			and C_PlayerInfo.GUIDIsPlayer(guid)
	end },
}

-- Describes one value without ever comparing or concatenating a secret one,
-- because doing either is the error this whole check exists to avoid.
local function Describe(ok, value)
	if not ok then return "ERROR" end
	if issecretvalue and issecretvalue(value) then return "SECRET" end
	if value == nil then return "nil" end
	if type(value) == "string" then return ("%q"):format(value) end
	return tostring(value)
end

-- Reports what this client will actually hand over for each unit, so the
-- cost of capturing somewhere restricted is measured rather than assumed.
local function SecretCensus(label)
	local lines = { "Mogtrot secret probe: " .. tostring(label),
		"build: " .. tostring(select(1, GetBuildInfo())),
		"inCombat: " .. tostring(InCombatLockdown() and true or false) }

	local inInstance, instanceType = false, "none"
	if _G.IsInInstance then
		local ok, isIn, kind = pcall(_G.IsInInstance)
		if ok then inInstance, instanceType = isIn, kind or "none" end
	end
	lines[#lines + 1] = ("inInstance=%s type=%s"):format(
		tostring(inInstance), tostring(instanceType))

	for _, unit in ipairs(SECRET_UNITS) do
		local exists = UnitExists and UnitExists(unit)
		lines[#lines + 1] = ""
		if not exists then
			lines[#lines + 1] = ("== %s: does not exist"):format(unit)
		else
			local restricted = "?"
			if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
				local ok, secret = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
				if ok then restricted = tostring(secret) end
			end
			lines[#lines + 1] = ("== %s  ShouldUnitIdentityBeSecret=%s")
				:format(unit, restricted)

			for _, call in ipairs(SECRET_CALLS) do
				lines[#lines + 1] = ("  %-26s %s"):format(call[1],
					Describe(pcall(call[2], unit)))
			end

			local scene = select(2, pcall(CreateFrame, "ModelScene", nil, UIParent,
				"ModelSceneMixinTemplate"))
			local actor = scene and scene.CreateActor
				and select(2, pcall(scene.CreateActor, scene)) or nil
			local rendered = "no actor"
			if actor and actor.SetModelByUnit then
				local ok = pcall(actor.SetModelByUnit, actor, unit, false, true,
					false, true, false)
				rendered = ok and "ok" or "ERROR"
			end
			if scene then scene:Hide() end
			lines[#lines + 1] = ("  %-26s %s"):format("SetModelByUnit", rendered)
		end
	end

	-- GetInspectItemTransmogInfoList takes no unit: it answers for whoever was
	-- inspected last. Reporting it per unit made three units look alike when
	-- only one had been inspected, so it is reported once and labelled.
	local okList, list = pcall(function()
		return C_TransmogCollection.GetInspectItemTransmogInfoList()
	end)
	local worn = 0
	if okList and type(list) == "table" then
		for _, info in pairs(list) do
			if type(info) == "table" and (info.appearanceID or 0) ~= 0 then
				worn = worn + 1
			end
		end
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = ("== last completed inspect: %s, %d worn")
		:format(okList and "ok" or "ERROR", worn)
	lines[#lines + 1] = "   (not per unit; GetInspectSpecialization is 0 until an"
	lines[#lines + 1] = "    inspect of that unit finishes, so run /mogtrot inspect first)"

	return lines
end

local combatWatcher

-- Combat is the one context the probe cannot be typed into, and the likeliest
-- place for identity restriction to actually fire, given UnitGUID's argument
-- type is named for PvP. So the census is taken by a listener on the way into
-- combat and shown on the way out.
function DevCommands.ProbeSecret(Addon, _deps, watch)
	if watch then
		if not combatWatcher then
			combatWatcher = CreateFrame("Frame")
			combatWatcher:SetScript("OnEvent", function(self, event)
				if event == "PLAYER_REGEN_DISABLED" then
					-- A frame in, so combat is genuinely established.
					C_Timer.After(0, function()
						self.sample = SecretCensus("sampled in combat")
					end)
				elseif event == "PLAYER_REGEN_ENABLED" and self.sample then
					local sample = self.sample
					self.sample = nil
					self:UnregisterAllEvents()
					combatWatcher = nil
					Addon:Say("combat sample taken, %d lines.", #sample)
					if ns.CopyBox then
						ns.CopyBox.Show("Mogtrot secret probe, in combat", sample)
					end
				end
			end)
		end
		combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
		combatWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
		Addon:Say("armed. Pull something; the sample opens when combat drops.")
		return
	end

	local lines = SecretCensus("now")
	Addon:Say("secret probe: %d lines. Run /mogtrot inspect on them first.", #lines)
	if ns.CopyBox then
		ns.CopyBox.Show("Mogtrot secret probe", lines)
	else
		for _, line in ipairs(lines) do print(line) end
	end
end

function DevCommands.InspectTargetLook(Addon, _deps)
	local Look = ns.InspectLook
	if type(Look) ~= "table" then
		Addon:Warn("inspect unavailable: the look module is not loaded.")
		return
	end
	-- Inspecting mid-fight is noise at best, and combat is the context the
	-- client restricts identity in, so the two rules coincide.
	if InCombatLockdown() then
		Addon:Warn("not while you are in combat.")
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

	-- UnitGUID and UnitName are marked SecretWhenUnitIdentityRestricted, so on
	-- an instanced map they hand back secret values rather than strings for
	-- anyone outside your group. Storing or comparing one of those is the
	-- cooldown-secret trap again, so identity is refused up front rather than
	-- carried around and blown up on later.
	-- Under identity restriction the client hands back secret values from
	-- UnitGUID, UnitRace, UnitSex and UnitClass alike, and SetModelByUnit
	-- errors outright. The outfit itself stays readable, so capture degrades
	-- to an anonymous record rather than refusing: the mog is the point, and
	-- a look seen again unrestricted can be named later.
	local identified = true
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		local ok, secret = pcall(C_Secrets.ShouldUnitIdentityBeSecret, unit)
		if ok and secret then identified = false end
	end

	local name = identified and UnitName(unit) or nil
	local race, raceID, sex
	if identified then
		race, _, raceID = UnitRace(unit)
		sex = UnitSex and UnitSex(unit) or nil
	end
	if not identified then
		Addon:Say("identity is hidden here; capturing the outfit only.")
	end
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
				:format(tostring(name), tostring(race), filled, empty,
					tostring(altered), tostring(formSource), wantsSelf,
					inAlternateSelf))
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
				return ("%s the %s: raceID=%s sex=%s, %d worn, %d empty,"
					.. " alteredForm=%s | %d rebuilt")
					:format(tostring(name), tostring(race), tostring(raceID),
						tostring(sex), filled, empty, tostring(altered),
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
				{
					title = "4. a generic " .. tostring(race) .. " body",
					note = "record and race only, nobody present",
					apply = function(actor, onStatus)
						-- The whole point: no unit token anywhere in this path.
						-- Race plus sex picks a static display row, and the
						-- record dresses it, which is what replaying a stored
						-- snap has to do once the wearer is gone.
						if type(actor.SetModelByCreatureDisplayID) ~= "function" then
							return "no call"
						end
						local body = ns.RaceBody
						if type(body) ~= "table" then return "no race table" end
						local displayID, why = body.Lookup(raceID, sex)
						if not displayID then return tostring(why) end
						local ok = pcall(actor.SetModelByCreatureDisplayID, actor,
							displayID, false)
						if not ok then return "call failed for id " .. tostring(displayID) end
						onStatus(("id=%d, dressing"):format(displayID))
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
function DevCommands.ProbeAuras(Addon, _deps)
	local auras = C_UnitAuras
	if not (auras and auras.GetAuraDataByIndex) then
		Addon:Warn("this client exposes no aura list.")
		return
	end

	local unit = "player"
	if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
		unit = "target"
	else
		Addon:Say("no player targeted; listing your own auras.")
	end

	local forms = ns.FormDefinitions
	local lines = {}
	local name = UnitName and UnitName(unit)
	if name and issecretvalue and issecretvalue(name) then name = nil end
	lines[#lines + 1] = ("auras on %s"):format(tostring(name))
	local _, raceFile = UnitRace(unit)
	lines[#lines + 1] = ("race=%s sex=%s class=%s"):format(tostring(raceFile),
		tostring(UnitSex and UnitSex(unit)), tostring(select(2, UnitClass(unit))))
	lines[#lines + 1] = ""

	for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
		lines[#lines + 1] = filter
		local found = 0
		for index = 1, 60 do
			local ok, aura = pcall(auras.GetAuraDataByIndex, unit, index, filter)
			if not ok or not aura then break end
			found = found + 1
			local spellID = aura.spellId
			local known = forms and spellID and forms.Lookup(spellID)
			lines[#lines + 1] = ("  %-8s %s%s"):format(tostring(spellID),
				tostring(aura.name),
				known and ("   <- known form: " .. known.kind) or "")
		end
		if found == 0 then lines[#lines + 1] = "  none" end
		lines[#lines + 1] = ""
	end

	Addon:Say("aura probe: %d lines.", #lines)
	if ns.CopyBox then
		ns.CopyBox.Show("Mogtrot auras: " .. tostring(name), lines)
	else
		for _, line in ipairs(lines) do print(line) end
	end
end

-- Every actor tag the dress-up scene defines, read off the mixin's own
-- tag-to-actor map. Which tags exist decides whether a record can be shown on
-- the right body at the right scale: a tag that is missing falls back to an
-- actor built for some other race, and armour ends up floating around a model
-- scaled for something else.
function DevCommands.ProbeActors(Addon, _deps)
	if InCombatLockdown() then
		Addon:Warn("not while you are in combat.")
		return
	end

	local scene = DevCommands.actorScene
	if not scene then
		scene = CreateFrame("ModelScene", nil, UIParent, "ModelSceneMixinTemplate")
		scene:SetSize(1, 1)
		scene:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
		scene:Hide()
		DevCommands.actorScene = scene
	end

	local SCENE_ID = 596
	local ok = pcall(scene.TransitionToModelSceneID, scene, SCENE_ID,
		CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
	if not ok then
		Addon:Warn("could not build model scene %d.", SCENE_ID)
		return
	end

	local tags = {}
	for tag in pairs(scene.tagToActor or {}) do
		if type(tag) == "string" then tags[#tags + 1] = tag end
	end
	table.sort(tags)

	local lines = { ("model scene %d defines %d actor tag(s)"):format(SCENE_ID, #tags), "" }
	for _, tag in ipairs(tags) do lines[#lines + 1] = "  " .. tag end

	local _, raceFile = UnitRace("player")
	lines[#lines + 1] = ""
	lines[#lines + 1] = ("you are %s sex=%s"):format(tostring(raceFile),
		tostring(UnitSex and UnitSex("player")))

	Addon:Say("actor probe: %d tag(s) in scene %d.", #tags, SCENE_ID)
	if ns.CopyBox then
		ns.CopyBox.Show(("Mogtrot actors: scene %d"):format(SCENE_ID), lines)
	else
		for _, line in ipairs(lines) do print(line) end
	end
end


function DevCommands.ProbeDonors(Addon, _deps)
	local donors = ns.DonorBody
	if type(donors) ~= "table" then
		Addon:Warn("probe donors unavailable: the donor module is not loaded.")
		return
	end

	local mine = UnitSex and UnitSex("player") or nil
	local lines = { ("you are sex=%s; a record of the other sex needs somebody"
		.. " below to lend a body"):format(tostring(mine)), "" }

	local found, players = 0, 0
	local bySex = {}
	for _, token in ipairs(donors.Tokens()) do
		local exists = UnitExists and UnitExists(token)
		if exists then
			found = found + 1
			local isPlayer = UnitIsPlayer and UnitIsPlayer(token) or false
			local secret = false
			if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
				local known, hidden = pcall(C_Secrets.ShouldUnitIdentityBeSecret, token)
				secret = known and hidden or false
			end
			local ok, sex = pcall(UnitSex, token)
			if not ok or (issecretvalue and issecretvalue(sex)) then sex = nil end
			if secret then sex = nil end
			local name = UnitName and UnitName(token)
			if name and issecretvalue and issecretvalue(name) then name = nil end
			if isPlayer then
				players = players + 1
				if sex then bySex[sex] = (bySex[sex] or 0) + 1 end
			end
			lines[#lines + 1] = ("  %-12s %-22s %s sex=%s%s"):format(token,
				tostring(name), isPlayer and "player" or "npc", tostring(sex),
				secret and "  identity restricted, cannot donate" or "")
		end
	end
	if found == 0 then lines[#lines + 1] = "  nothing resolves at all" end

	lines[#lines + 1] = ""
	lines[#lines + 1] = ("%d token(s) resolve, %d of them players: %d male, %d female")
		:format(found, players, bySex[2] or 0, bySex[3] or 0)

	for _, sex in ipairs({ 2, 3 }) do
		local pick = donors.Find(sex, function(token)
			if not (UnitExists and UnitExists(token)) then return false end
			if not (UnitIsPlayer and UnitIsPlayer(token)) then return true, false end
			if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
				local known, hidden = pcall(C_Secrets.ShouldUnitIdentityBeSecret, token)
				if known and hidden then return true, true, nil end
			end
			local ok, unitSex = pcall(UnitSex, token)
			if not ok or (issecretvalue and issecretvalue(unitSex)) then
				return true, true, nil
			end
			return true, true, unitSex
		end)
		lines[#lines + 1] = ("a %s body would come from: %s"):format(
			sex == 2 and "male" or "female", tostring(pick))
	end

	Addon:Say("donor probe: %d token(s) resolve, %d player(s).", found, players)
	if ns.CopyBox then
		ns.CopyBox.Show("Mogtrot donors", lines)
	else
		for _, line in ipairs(lines) do print(line) end
	end
end
-- What the client says about each appearance a stored look holds. Written
-- because a look can render wrong without anything in it looking wrong: a
-- hide visual, a source the player may not display, and a real piece all
-- arrive as the same plain number.
function DevCommands.ProbeLook(Addon, _deps, requestedID)
	local outfitID = requestedID or (C_TransmogOutfitInfo
		and C_TransmogOutfitInfo.GetActiveOutfitID and C_TransmogOutfitInfo.GetActiveOutfitID())
	local look = outfitID and MogtrotCharDB.looks and MogtrotCharDB.looks[outfitID]
	if not look then
		Addon:Warn("no stored look for outfit %s; wear it once, or name one with /mogt probe look <id>.",
			tostring(outfitID))
		return
	end

	local slots = {}
	for slotID in pairs(look) do
		if type(slotID) == "number" then slots[#slots + 1] = slotID end
	end
	table.sort(slots)

	local info = Addon.outfitsByID and Addon.outfitsByID[outfitID]
	local lines = { ("look outfit=%d name=%s"):format(outfitID,
		tostring(info and info.name or "?")) }
	for _, slotID in ipairs(slots) do
		local entry = look[slotID]
		local id = type(entry) == "table" and entry[1] or nil
		local label = ("%-10s %-7s"):format(ns.LibraryText.SlotName(slotID), tostring(id))
		if type(id) ~= "number" or id <= 0 then
			lines[#lines + 1] = label .. "empty"
		else
			local source = C_TransmogCollection and C_TransmogCollection.GetSourceInfo
				and select(2, pcall(C_TransmogCollection.GetSourceInfo, id)) or nil
			if type(source) ~= "table" then
				lines[#lines + 1] = label .. "no source info"
			else
				lines[#lines + 1] = ("%sitem=%s hide=%s display=%s valid=%s %s"):format(
					label, tostring(source.itemID), tostring(source.isHideVisual),
					tostring(source.canDisplayOnPlayer),
					tostring(source.isValidSourceForPlayer),
					tostring(source.name or source.useError or ""))
			end
		end
	end

	for _, line in ipairs(lines) do Addon:Say(line) end
	if ns.CopyBox then ns.CopyBox.Show("Mogtrot stored look probe", lines) end
end


-- Help rows Commands.lua appends to its own list when this file is loaded.
DevCommands.HELP = {
	{ "debug", "developer output, on or off" },
	{ "probe", "dump what this client build actually exposes" },
	{ "probe library", "why the library transfer button is hidden" },
	{ "probe ingest <id>", "show what the bulk importer read for one outfit" },
	{ "probe look <id>", "what the client says about each piece of a stored look" },
	{ "probe layer", "one draggable model above the Transmog window" },
	{ "probe body <id>", "render one creature display ID wearing your outfit" },
	{ "probe donors", "which units the library could borrow a body from now" },
	{ "probe actors", "which bodies the dress-up scene can actually pose" },
	{ "probe auras", "every aura on the player you target, for form research" },
	{ "probe secret", "what this client will tell you about each unit here" },
	{ "probe secret watch", "take that census in combat, shown when it drops" },
	{ "inspect", "capture the appearance list of the player you target" },
	{ "library bodies", "which model file each body key actually drew" },
}

-- Returns true when the command was one of ours, so Commands.lua can fall
-- through to its own "no such command" reply when it was not.
function DevCommands.Dispatch(Addon, deps, cmd)
	if cmd == "probe" then
		DevCommands.ProbeClient(Addon, deps)
		return true
	end
	if cmd == "probe library" then
		DevCommands.ProbeLibraryTransfer(Addon, deps)
		return true
	end
	if cmd == "probe ingest" then
		DevCommands.ProbeOutfitIngest(Addon, deps, nil)
		return true
	end
	local probeIngest = cmd:match("^probe ingest%s+(%d+)$")
	if probeIngest then
		DevCommands.ProbeOutfitIngest(Addon, deps, tonumber(probeIngest))
		return true
	end
	if cmd == "probe look" then
		DevCommands.ProbeLook(Addon, deps, nil)
		return true
	end
	local probeLook = cmd:match("^probe look%s+(%d+)$")
	if probeLook then
		DevCommands.ProbeLook(Addon, deps, tonumber(probeLook))
		return true
	end
	if cmd == "probe layer" then
		DevCommands.ProbeLayer(Addon, deps)
		return true
	end
	local probeBody = cmd:match("^probe body%s+(%S+)$")
	if probeBody then
		DevCommands.ProbeBody(Addon, deps, probeBody)
		return true
	end
	if cmd == "probe body" then
		DevCommands.ProbeBody(Addon, deps, nil)
		return true
	end
	if cmd == "probe donors" then
		DevCommands.ProbeDonors(Addon, deps)
		return true
	end
	if cmd == "probe actors" then
		DevCommands.ProbeActors(Addon, deps)
		return true
	end
	if cmd == "probe auras" then
		DevCommands.ProbeAuras(Addon, deps)
		return true
	end
	if cmd == "probe secret" then
		DevCommands.ProbeSecret(Addon, deps, false)
		return true
	end
	if cmd == "probe secret watch" then
		DevCommands.ProbeSecret(Addon, deps, true)
		return true
	end
	if cmd == "inspect" then
		DevCommands.InspectTargetLook(Addon, deps)
		return true
	end
	if cmd == "library bodies" then
		local ui = ns.LibraryUI
		if not (ui and ui.BodyAudit) then
			Addon:Warn("the library has not been opened yet.")
			return true
		end
		local lines = ui.BodyAudit()
		for _, line in ipairs(lines) do Addon:Say(line) end
		if ns.CopyBox then ns.CopyBox.Show("Mogtrot body audit", lines) end
		return true
	end

	if cmd == "debug" then
		MogtrotDB.debug = not MogtrotDB.debug
		Addon:Warn("debug output %s.", MogtrotDB.debug and "on" or "off")
		return true
	end

	local nudge = cmd:match("^nudge%s+(-?[%d%.]+)$")
	if MogtrotDB.debug and nudge then
		MogtrotDB.cardNudge = tonumber(nudge) or 0
		Addon:Debug("card nudge = %s", tostring(MogtrotDB.cardNudge))
		Addon:RepaintMountCards()
		return true
	end


	-- The library's mounted cards are framed by pulling the camera in by a
	-- fraction of the scene's own distance. The right fraction is a matter of
	-- looking at it, so it is tunable in game rather than guessed in a file.
	local mountZoom = cmd:match("^mountzoom%s+([%d%.]+)$")
	if MogtrotDB.debug and mountZoom then
		local value = tonumber(mountZoom)
		if not value or value <= 0.05 or value > 3 then
			Addon:Warn("mount zoom wants a number between 0.05 and 3.")
			return true
		end
		MogtrotDB.mountZoom = value
		Addon:Debug("mount zoom = %s (smaller is closer)", tostring(value))
		if ns.LibraryUI then ns.LibraryUI.Refresh() end
		return true
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
		return true
	end

	return false
end

ns.DevCommands = DevCommands
return DevCommands
