local _, ns = ...

-- The library window: every stored look, four to a row, each on a body of its
-- own race.
--
-- A card is a portrait. Left-click opens the detail pane on it, right-click
-- offers More info, Delete, and the two ways of showing a body. Snapshots and
-- mirrored Blizzard outfits share the wall and can be filtered by source.
--
-- The grid is Blizzard's scroll box, the same one the mount picker uses, so
-- the wheel and the bar behave here the way they do there. Dragging a card
-- moves every model at once, side to side to turn and up and down to zoom: a
-- wall of portraits is for comparing them, and comparing them means seeing
-- them the same way.
local LibraryUI = {}

local COLS = 4
local CARD_W, CARD_H = 210, 320
local GAP, MARGIN = 10, 14
local HEADER, FOOTER = 88, 12
local BAR_GUTTER, BAR_GAP = 14, 6
local ROWS_SHOWN = 2
local LIBRARY_STRATA = "DIALOG"

-- Degrees of yaw per pixel dragged, slow enough to stop on a detail.
local TURN_PER_PIXEL = 0.6

-- A mount scene is framed for the mount journal's big panel, so in a card it
-- reads as a distant speck until it is brought closer, while a dress-up scene
-- is already framed for something card-shaped. Correcting for that is a
-- property of the scene rather than a matter of taste, so it is a fraction of
-- whatever distance the scene shipped with and it holds across mounts of very
-- different sizes. Gentle on purpose: a big mount pulled in hard leaves
-- nothing but a wing in frame once it turns.
--
-- The mount picker frames its cards by sliding the scene frame instead, which
-- suits it: those cards show a mount alone and the complaint there was dead
-- space under the name. Here the rider is the subject and has to be legible,
-- which is a distance problem, not a position one.
local MOUNT_FRAMING = 0.85

-- What the wall is zoomed to on top of that framing, so one at the default
-- means every card shows what it was framed to show. Dragging a card up and
-- down moves it, the zoom buttons step it, and it is saved.
local DEFAULT_ZOOM = 1

-- Saved under mountZoom. The bounds read back here are wider than the ones
-- the controls write: LibraryZoom clamps inside them.
local function Zoom()
	local saved = MogtrotDB and tonumber(MogtrotDB.mountZoom)
	if saved and saved > 0.05 and saved <= 3 then return saved end
	return DEFAULT_ZOOM
end

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local window

-- One angle for the whole wall, kept while the window lives.
local yaw = 0

-- What the last render of each record reported, per slot. Runtime only: it
-- describes this client's answer now, not the record.
local lastApply = {}
-- Whether each slot was drawn, as opposed to accepted.
local lastVisible = {}
-- The line the card printed, kept whole. The card truncates it, and the half
-- that falls off the end is the half that says why.
local lastNote = {}

-- A decision note says what the code chose, not what the client drew, so it
-- reads innocent whenever the choice was right and the draw was not.
--
-- This is the readback. A body key already names a race, a form and a sex, and
-- each of those is a different model file, so one key must only ever be one
-- file. A key seen carrying two is proof that some card rendered a body other
-- than the one it asked for, and it holds without knowing a single file ID in
-- advance: the wall calibrates itself from its own first correct render.
local bodySeen = {}

local function NoteBody(recordID, key, actor)
	if type(key) ~= "string" or actor == nil then return end
	if type(actor.GetModelFileID) ~= "function" then return end
	local ok, fileID = pcall(actor.GetModelFileID, actor)
	if not ok or fileID == nil then return end
	local loaded = true
	if type(actor.IsLoaded) == "function" then
		local gotLoaded, value = pcall(actor.IsLoaded, actor)
		loaded = (not gotLoaded) or value ~= false
	end
	local seen = bodySeen[key]
	if not seen then
		seen = { files = {}, order = {} }
		bodySeen[key] = seen
	end
	local file = seen.files[fileID]
	if not file then
		file = { count = 0, firstRecord = recordID, loaded = loaded }
		seen.files[fileID] = file
		seen.order[#seen.order + 1] = fileID
	end
	file.count = file.count + 1
	file.lastRecord = recordID
end

-- Every key the wall has drawn, and every model file each was drawn with.
--
-- The naive rule, "a file under more than one key is suspect", is wrong in
-- both directions. A model loads asynchronously, so a sample can catch a
-- placeholder that then shows up under every key at once. And a wrongly drawn
-- body is a real body, so it appears under its own key as well as the one it
-- leaked into, which a "more than one key" rule would discount as noise: it
-- would hide precisely the thing being hunted.
--
-- Sex is the discriminator. A file drawn under two keys that disagree about
-- sex cannot be right for both, whatever else it is. Two keys that differ
-- only by faction race ID are the same body and are left alone.
local PLACEHOLDER_KEYS = 4

local function KeySex(key)
	return select(3, strsplit("|", key))
end

function LibraryUI.BodyAudit()
	local keys = {}
	for key in pairs(bodySeen) do keys[#keys + 1] = key end
	table.sort(keys)

	local where = {}
	for _, key in ipairs(keys) do
		for _, fileID in ipairs(bodySeen[key].order) do
			where[fileID] = where[fileID] or {}
			table.insert(where[fileID], key)
		end
	end

	local placeholder, leaked = {}, {}
	for fileID, holders in pairs(where) do
		if #holders >= PLACEHOLDER_KEYS then
			placeholder[fileID] = #holders
		elseif #holders > 1 then
			local sex = KeySex(holders[1])
			for _, key in ipairs(holders) do
				if KeySex(key) ~= sex then leaked[fileID] = holders break end
			end
		end
	end

	-- A pipe is WoW's escape prefix, so a raw key prints as nonsense: the "|t"
	-- in "|true" is eaten as a texture and "|N" starts a new line.
	local function Show(text) return (tostring(text):gsub("|", "||")) end

	local lines, anomalies = { "body key -> model files actually drawn" }, 0
	for _, key in ipairs(keys) do
		local seen, parts, bad = bodySeen[key], {}, false
		for _, fileID in ipairs(seen.order) do
			if not placeholder[fileID] then
				local file = seen.files[fileID]
				local leak = leaked[fileID] and " WRONG SEX" or ""
				if leak ~= "" then bad = true end
				parts[#parts + 1] = ("%s x%d (records %s..%s)%s"):format(
					tostring(fileID), file.count, tostring(file.firstRecord),
					tostring(file.lastRecord), leak)
			end
		end
		if bad then anomalies = anomalies + 1 end
		lines[#lines + 1] = ("%s%s: %s"):format(bad and "ANOMALY " or "", Show(key),
			#parts > 0 and table.concat(parts, " | ") or "placeholder only, not drawn yet")
	end

	for fileID, holders in pairs(leaked) do
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("%s was drawn under keys of different sex:"):format(
			tostring(fileID))
		for _, key in ipairs(holders) do lines[#lines + 1] = "   " .. Show(key) end
	end

	local discounted = {}
	for fileID, count in pairs(placeholder) do
		discounted[#discounted + 1] = ("%s (%d keys)"):format(tostring(fileID), count)
	end
	table.sort(discounted)
	if #discounted > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "discounted as placeholders: " .. table.concat(discounted, ", ")
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = ("%d key(s), %d drawn with a body of the wrong sex")
		:format(#keys, anomalies)
	return lines
end

-- Bodies outlive the cards that show them.
--
-- A card is recycled as you scroll, and rebuilding its body somewhere empty
-- finds nobody to borrow a sex from, which is how a room full of women turned
-- back into men on the way to a dungeon. Measured in game, a hidden model
-- scene costs nothing: thirty of them moved the framerate by minus two frames
-- against a hundred and forty seven, while thirty drawn cost half of it. So
-- bodies are built once and kept, hidden, and the scene holding one is
-- reparented into whichever card needs it. Nothing is copied, because nothing
-- can be: a model cannot move between actors, only the scene around it can
-- move between parents.
--
-- Keyed by what a body is, not by whose record it was, so two women of the
-- same race share one and a library of hundreds needs only a handful.
local characterPool

-- The one body currently lent to the detail pane, if any. Two bodies for one
-- record can never be guaranteed to agree, so there is only ever one and it
-- moves between the wall and the pane.
-- The twin scene currently parented into the detail pane.
-- Which body a card is asked to use, by record id. Runtime only: it is a way
-- of looking, not a fact about the wearer.
--
-- Neither body is right. The player model wears the whole outfit but carries
-- the viewer's sex and customizations, so a woman renders as a man with your
-- hair. The creature row is the subject's own race and sex with its own face,
-- but it is a creature model, so it takes attachments and drops every
-- composited piece. Which one is closer depends on the outfit: a look made
-- mostly of hidden pieces loses almost nothing on the creature row, while a
-- full plate set loses nearly all of it.

-- Whether the wall shows people sitting on the mounts they were seen on.
--
-- The switch in the header is the default; a card can be told otherwise and
-- then keeps its own answer. A record with no mount recorded ignores all of
-- this, since there is nothing to sit on.
local showMounts = false
local raceFilter
local nameQuery

local function Mounted(record)
	if not record.mount then return false end
	return showMounts
end

local function Library()
	if type(MogtrotDB) ~= "table" then return nil end
	local library = MogtrotDB.library
	if type(library) ~= "table" or type(library.records) ~= "table" then return nil end
	return library
end

local function Records()
	local Store = ns.Library
	local library = Library()
	if not library or type(Store) ~= "table" then return {} end
	return Store.Sorted(library)
end

-- The client owns the class palette and players expect it, so it is read
-- rather than invented. Returns nothing for a class the client will not name,
-- which leaves the caller at its ordinary colour.
local function ClassInfoFor(classID)
	if type(classID) ~= "number" then return nil end
	local classes = C_CreatureInfo
	local info = classes and classes.GetClassInfo and classes.GetClassInfo(classID)
	if not info then return nil end
	return info.className, RAID_CLASS_COLORS and RAID_CLASS_COLORS[info.classFile]
end

-- Shared with the detail pane, which titles itself with the same colour the
-- card uses.
LibraryUI.ClassInfoFor = ClassInfoFor

-- Blizzard's own class icon, by the name they build it from
-- (SharedConstants.lua: GetClassAtlas). Nil for a class the client will not
-- name, which leaves the row with no icon rather than a broken one.
local function ClassAtlas(classID)
	if type(classID) ~= "number" then return nil end
	local classes = C_CreatureInfo
	local info = classes and classes.GetClassInfo and classes.GetClassInfo(classID)
	if not (info and info.classFile and GetClassAtlas) then return nil end
	return GetClassAtlas(strlower(info.classFile))
end

local function ClassRGB(classID)
	local _className, color = ClassInfoFor(classID)
	if not color then return nil end
	return { color.r, color.g, color.b }
end

-- The character list is the longest filter here and the only one worth typing
-- at, so it gets the shared search-select window instead of a submenu.
local function OpenCharacterPicker()
	local Filter = ns.LibraryFilter
	if not (Filter and raceFilter and ns.OpenSearchPicker) then return end

	local items = {}
	for _, entry in ipairs(Filter.OwnerEntries(Records())) do
		local label = entry.name
		if entry.realm and entry.realm ~= "" then
			label = label .. "-" .. entry.realm
		end
		items[#items + 1] = {
			name = label,
			guid = entry.guid,
			iconAtlas = ClassAtlas(entry.classID),
			nameColor = ClassRGB(entry.classID),
			preselected = Filter.IsOwnerSelected(raceFilter, entry.guid),
		}
	end

	ns.OpenSearchPicker({
		strata = LIBRARY_STRATA,
		title = "Characters",
		searchHint = "Search character name",
		emptyText = "No character here owns an outfit or a custom set yet.",
		items = items,
		multi = true,
		bulkSelect = true,
		buttons = { {
			text = "Show",
			width = 90,
			allowEmpty = true,
			tipTitle = "Show these characters",
			tipBody = "Only the ticked characters' outfits and custom sets appear.",
			onClick = function(chosen)
				-- Everyone ticked means "all", not "these five": a character who
				-- logs in later should arrive shown rather than hidden.
				if #chosen == #items then
					Filter.SelectAllOwners(raceFilter)
				else
					Filter.SelectNoOwners(raceFilter)
					for _, item in ipairs(chosen) do
						Filter.SetOwner(raceFilter, item.guid, true)
					end
				end
				LibraryUI.Refresh()
			end,
		} },
	})
end

-- What the changeable word in the header sentence does. How it looks is
-- PairingHeaderUI's, and what it says is PairingHeader's.
--
-- A menu of the two rather than a toggle, the same as the pairing window's
-- domain word: the two walls are unrelated collections, and a word that hides
-- the other one makes you click it to find out what it was.
local function HeaderAction(action, segment)
	if action ~= "libraryMode" then return end
	local Filter = ns.LibraryFilter
	if not (Filter and raceFilter) then return end
	ns.PairingHeaderUI.ShowMenu(segment, action, function(mode)
		Filter.SetMode(raceFilter, mode)
		LibraryUI.Refresh()
	end)
end

-- Turns one card to the shared angle.
--
-- An unmounted card turns its model, which spins in place and is the motion
-- people expect. A mounted card turns its camera instead: a mount is long, and
-- spinning a serpent about its middle sweeps most of it out of the frame,
-- while orbiting keeps whatever the scene was framed around in the middle.
local function TurnCard(card, degrees)
	if card.mountActor and card.body and card.body.scene then
		local render = ns.ProbeRenderUI
		if render then render.TurnCamera(card.body.scene, degrees) end
		return
	end
	local actor = card.actor
	if type(actor) ~= "table" or type(actor.SetYaw) ~= "function" then return end
	pcall(actor.SetYaw, actor, math.rad(degrees))
end

-- Zooms one card to the shared factor. Always the camera, mounted or not: an
-- actor has no distance of its own to move, and the scene is what draws it.
-- A mounted card folds its framing correction into the same call, so one zoom
-- answers for both kinds of card.
local function ZoomCard(card, factor)
	local scene = card.body and card.body.scene
	local render = ns.ProbeRenderUI
	if not (scene and render) then return end
	render.ZoomTo(scene, card.mountActor and factor * MOUNT_FRAMING or factor)
end

-- One card put the way the whole wall is: same angle, same distance.
local function FrameCard(card)
	TurnCard(card, yaw)
	ZoomCard(card, Zoom())
end

local function ApplyFraming()
	if not window or not window.Box then return end
	window.Box:ForEachFrame(FrameCard)
end

-- What the zoom controls say, in a number that grows as the models do.
local function ShowZoom()
	local Zooms = ns.LibraryZoom
	if not (window and window.ZoomLevel and Zooms) then return end
	local percent = Zooms.Magnification(Zoom())
	window.ZoomLevel.Text:SetText(percent and ("%d%%"):format(percent) or "--")
end

-- The one way in for every control: the drag, the buttons and the readout all
-- go through here, so the saved value, the wall and the readout cannot
-- disagree. A factor it cannot use leaves the zoom alone and still re-frames,
-- because the drag turns the wall on the same call.
local function SetZoom(factor)
	local Zooms = ns.LibraryZoom
	local value = Zooms and Zooms.Clamp(factor)
	if value and MogtrotDB then MogtrotDB.mountZoom = value end
	ShowZoom()
	ApplyFraming()
end

-- How the client answers about a unit, for DonorBody. A unit the client
-- refuses is reported as absent rather than guessed at.
--
-- SetModelByUnit is marked as requiring declassified unit identity, and the
-- donor technique hands it a stranger's token, which is exactly the case that
-- gate exists for. A unit whose identity is restricted is therefore refused as
-- a donor up front, rather than found, chosen, and then failing inside the
-- model call where the failure reads as a body that would not build.
local function ReadUnit(token)
	if not (UnitExists and UnitExists(token)) then return false end
	if not (UnitIsPlayer and UnitIsPlayer(token)) then return true, false end
	if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
		local known, secret = pcall(C_Secrets.ShouldUnitIdentityBeSecret, token)
		if known and secret then return true, true, nil end
	end
	local ok, sex = pcall(UnitSex, token)
	if not ok or issecretvalue and issecretvalue(sex) then return true, true, nil end
	local gotRace, _, _, raceID = pcall(UnitRace, token)
	if not gotRace or (issecretvalue and issecretvalue(raceID)) then raceID = nil end
	return true, true, sex, raceID
end

-- The wall is all one thing or all the other.
--
-- Half the cards on somebody else's body and half on yours reads as broken
-- rather than as a compromise, and invites you to wonder which half is lying.
-- So until every record that needs a borrowed body has one, no record gets
-- one: every card shows your own body, as you are standing right now, wearing
-- that outfit. The moment the last body is in the pool the whole wall turns
-- over to full fidelity at once.
local fullFidelity = false
-- Whether any card is still without a body of its own, as opposed to whether
-- every shape of body has been built at least once.
local bodiesWanted = false

-- What you asked to see, as opposed to what can be shown. Original race is the
-- default because it is the point of the library, but it is only reachable
-- once every body has been borrowed, and you can always ask for your own body
-- instead.
local viewMode = "original"

local SWITCH_H = 22

-- What a built body is, so a card can tell whether the one it is already
-- holding still fits the record in front of it.
--
-- A body is loaded geometry, not a live link to whoever donated it, so it
-- survives that person walking away and survives you leaving the zone. What
-- loses it is rebuilding, and rebuilding somewhere empty finds nobody to
-- borrow from. So a card that already holds the right body keeps it and only
-- changes clothes: open the library once where there are people, and those
-- bodies last the rest of the session.
local function BodyKey(record, shown, native, donorSex)
	return ns.LibraryBody.Key(record, shown, native, donorSex)
end

-- Your own body exactly as it is now, including whichever form you are
-- standing in. No race override at all: this is the honest degraded view, and
-- pretending otherwise by keeping the race but not the sex is what made the
-- wall look broken.
local function SetOwnBody(actor)
	if type(actor.SetModelByUnit) ~= "function" then return nil end
	local diagnostics = ns.Diagnostics
	local native = true
	if diagnostics and type(diagnostics.UseNativeForm) == "function" then
		native = diagnostics.UseNativeForm("player")
	end
	local sheathe, autoDress, hideWeapons, holdBowString = false, false, false, false
	local ok, applied = pcall(actor.SetModelByUnit, actor, "player", sheathe,
		autoDress, hideWeapons, native, holdBowString)
	if not ok or applied == false then return nil end
	return "on you"
end

-- Puts a body of the record's race under the actor, and says which way it
-- managed it.
--
-- The creature display row shows the right race but renders only attachments:
-- a helm and weapons appear, and every composited piece is silently dropped
-- even though each slot reports ItemTryOnReason 0. Armor needs a player-type
-- model, which is what SetModelByUnit builds, and its customRaceID argument
-- swaps the race without needing that race to be standing in front of you.
-- Blizzard drives its own shop previews the same way. The creature row stays
-- as the fallback: the right race with no armor beats no body at all.
local function SetBody(actor, record, body, preferredDonor, preferRace)
	local raceID = record.raceID
	-- Cleared first: whatever this actor was holding is about to stop being
	-- true, and a stale key would hand the wrong body to the next card.
	actor.mogtrotBodyKey = nil

	local wanted = viewMode == "original" and fullFidelity
	if not (wanted or preferredDonor) then
		return SetOwnBody(actor)
	end
	if type(actor.SetModelByUnit) == "function" and type(raceID) == "number" then
		local sheathe, autoDress, hideWeapons, holdBowString = false, false, false, false
		-- usePlayerNativeForm asks for the viewer's own second body, so it is
		-- meaningful only for a race that has one. Passing a stored false for a
		-- race that does not renders the viewer's alternate form wearing the
		-- record, which looks like the race override was ignored.
		local shown, native = ns.LibraryBody.Form(record, body.HasAlternateForm,
			body.VisageRace)
		-- The race override replaces the race and nothing else, so the sex comes
		-- from whichever unit the model is built from. Yours when the sexes
		-- agree, and otherwise anybody of the right sex who is standing about.
		local donors = ns.DonorBody
		local from, sameRace = preferredDonor, nil
		if not from then
			-- The skin comes from the donor, so a donor of the race being shown
			-- is asked for first and anybody of the right sex is the fallback.
			if donors and record.sex then
				-- preferRace lets a second view of the same record ask for the
				-- donor race the first one used, so the two agree. Without it
				-- one can be built from a Void Elf and the other from an
				-- Earthen, and the same person has two different skins.
				from, sameRace = donors.Find(record.sex, ReadUnit, preferRace or shown)
			end
		end
		from = from or "player"

		-- Passing a race override that matches the source unit's own race is not
		-- a no-op: it loads a base race stripped of customizations, which
		-- renders a Dracthyr visage white and makes usePlayerNativeForm inert.
		-- Hand it nil instead and the unit's real body comes through.
		local override = shown
		local _, fromRaceFile, fromRaceID = UnitRace(from)
		if fromRaceID == shown then override = nil end
		if fromRaceFile == nil then override = shown end

		-- Blizzard gates every one of its own SetModelByUnit calls on this.
		if IsUnitModelReadyForUI and not IsUnitModelReadyForUI(from) then
			return nil, "their model is not loaded yet"
		end

		local ok, applied = pcall(actor.SetModelByUnit, actor, from, sheathe,
			autoDress, hideWeapons, native, holdBowString, override)
		if ok and applied ~= false then
			local donorSex = UnitSex and UnitSex(from) or nil
			actor.mogtrotBodyKey = BodyKey(record, shown, native, donorSex)
			-- Remembered so another view of this record can be built from the
			-- same person. The race alone is not enough: two Draenei have
			-- different skin and hair, and borrowing from a different one
			-- produces the same outfit on a visibly different woman.
			actor.mogtrotDonorRace = select(3, UnitRace(from))
			actor.mogtrotDonorGUID = from ~= "player" and UnitGUID and UnitGUID(from) or nil
			if actor.mogtrotDonorGUID and issecretvalue
				and issecretvalue(actor.mogtrotDonorGUID) then
				actor.mogtrotDonorGUID = nil
			end
			local note = ("race %d%s%s"):format(shown, override and "" or " (no override)",
				native and "" or ", altered")
			local mine = UnitSex and UnitSex("player") or nil
			if from ~= "player" then
				-- Whose body this is matters: the race override does not carry
				-- their skin, so a donor of another race lends a palette that
				-- lands wrong here, and the card says so rather than looking
				-- like a bad render.
				local lender = select(2, UnitRace(from)) or from
				if sameRace == false then
					return ("%s, body borrowed from a %s, so the skin is theirs")
						:format(note, tostring(lender))
				end
				return ("%s, body borrowed from a %s"):format(note, tostring(lender))
			end
			if record.sex and mine and record.sex ~= mine then
				return note .. ", sex is yours, nobody to borrow from"
			end
			return note .. ", your body"
		end
	end

	local displayID, missing = body.Lookup(raceID, record.sex)
	if not displayID or type(actor.SetModelByCreatureDisplayID) ~= "function" then
		return nil, missing
	end
	if not pcall(actor.SetModelByCreatureDisplayID, actor, displayID, false) then
		return nil, ("body %d refused"):format(displayID)
	end
	return ("their own body, creature %d, attachments only"):format(displayID)
end

-- The body this record deserves: its own race, its own form, its own sex. A
-- card already holding this has nothing to gain from being rebuilt and
-- everything to lose, since the donor who made it possible may be a zone away.
-- Anything else is worth rebuilding, because a donor may have arrived since.
-- The race this record is rendered as, which is not always the race it was
-- captured as: a visage is its own race.
local function IdealShownRace(record, body)
	local raceID = record.raceID
	if type(raceID) ~= "number" then return nil end
	if record.nativeForm == false and body.HasAlternateForm(raceID) then
		return body.VisageRace(raceID) or raceID
	end
	return raceID
end

local function IdealBodyKey(record, body)
	return ns.LibraryBody.IdealKey(record, body.HasAlternateForm, body.VisageRace)
end

-- Distinct bodies are bounded by race, sex and form. The cap only guards
-- against a pathological account growing this without end.
local POOL_LIMIT = 60

local function Pool()
	if characterPool then return characterPool end
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	holder:Hide()
	characterPool = ns.CharacterModelPool.New(POOL_LIMIT, holder)
	return characterPool
end

local function AttachScene(entry)
	if not entry or entry.scene then return entry end
	local holder = Pool():Holder()
	local scene = CreateFrame("ModelScene", nil, holder, "ModelSceneMixinTemplate")
	scene:SetSize(CARD_W - 14, CARD_H - 51)
	scene:SetPoint("TOPLEFT")
	-- Its own handlers would turn wall scrolling into zoom and panning.
	scene:EnableMouse(false)
	scene:EnableMouseWheel(false)
	scene:Hide()
	entry.scene = scene
	return entry
end

-- Hands a scene back, hidden and out of the way, so another card can take it.
local function Release(card)
	local entry = card.body
	if not entry then return end
	-- Only the card's own entry may be released. If something else has already
	-- taken it, reparenting it here would tear the scene out of that card.
	local released = Pool():Release(card)
	if released ~= entry then
		card.body, card.actor, card.mountActor = nil, nil, nil
		return
	end
	card.body, card.actor, card.mountActor = nil, nil, nil
	entry.scene:SetParent(Pool():Holder())
	entry.scene:ClearAllPoints()
	entry.scene:SetPoint("TOPLEFT")
	entry.scene:Hide()
end

-- The scene a card should use for this body.
--
-- The order matters more than it looks. A free scene already holding the
-- wanted body is taken as it is. Otherwise only an empty scene is taken, never
-- one holding a body somebody else may want: handing out any free scene means
-- scrolling destroys the bodies it just built, which is the pool eating
-- itself. A new scene is made instead, because a hidden one is free. Only at
-- the cap does it fall back to taking a built body, oldest first.
local function Acquire(card, wantedKey)
	Release(card)
	local entry = AttachScene(Pool():Acquire(card, wantedKey))
	if not entry then return nil end
	card.body = entry
	entry.scene:SetFixedFrameStrata(false)
	entry.scene:SetFixedFrameLevel(false)
	entry.scene:SetParent(card)
	entry.scene:SetFixedFrameStrata(true)
	entry.scene:SetFixedFrameLevel(true)
	entry.scene:ClearAllPoints()
	entry.scene:SetPoint("TOPLEFT", 7, -7)
	entry.scene:SetPoint("BOTTOMRIGHT", -7, 44)
	entry.scene:Show()
	return entry
end

-- Everything the planner needs that has to be asked of the client.
local function BodyPlan(record, body)
	local altered = false
	local diagnostics = ns.Diagnostics
	if diagnostics and type(diagnostics.UseNativeForm) == "function" then
		altered = not diagnostics.UseNativeForm("player")
	end
	return ns.LibraryBody.Plan({
		record = record,
		viewMode = viewMode,
		fullFidelity = fullFidelity,
		mounted = Mounted(record),
		viewer = {
			raceFile = select(2, UnitRace("player")),
			sex = UnitSex and UnitSex("player") or nil,
			altered = altered,
		},
		hasAlternateForm = body.HasAlternateForm,
		visageRace = body.VisageRace,
	})
end

-- Draws one card and returns the line that describes what it drew. It writes
-- no status of its own: Paint owns that, so there is exactly one place the
-- card's status can come from and no path can leave the previous record's
-- there. Later text from a dress callback is a separate, honest overwrite.
local function RenderCard(card, record)
	local status
	local render = ns.ProbeRenderUI
	local codec = ns.LookCodec
	local body = ns.RaceBody
	if record.look == "" then
		Release(card)
		card.Placeholder:Show()
		return "wear once to capture its appearance"
	end
	if not (render and codec and body) then
		card.actor = nil
		return "modules not loaded"
	end

	-- Whose body this card is meant to show, which form it is in, which actor
	-- will hold it and what a reusable body must be keyed with: one answer,
	-- computed before anything is touched.
	--
	-- Asking for a keyed body only when a keyed body is what this card will
	-- produce matters more than it looks. A creature row and a mounted card
	-- both key nothing, so handing them a borrowed body destroys it: the key
	-- is wiped, the record counts as missing again, and the whole wall drops
	-- back to showing everything on you because one card's menu was used.
	local plan = BodyPlan(record, body)
	local entry = Acquire(card, plan.keyed and plan.idealKey or nil)
	if not entry then
		card.actor = nil
		return "character model pool full"
	end

	-- A body that is already exactly right is never rebuilt: rebuilding it
	-- anywhere the right donor is absent would hand back a worse one. A card
	-- asked to show your body reuses nothing, because a borrowed body is not
	-- what was asked for.
	if ns.LibraryBody.CanReuse(plan, entry.key, entry.actor ~= nil) then
		local look = codec.Decode(record.look)
		if type(look) == "table" then
			card.actor = entry.actor
			-- A body taken back out of the pool is still facing wherever it was
			-- left, so it is put the way the wall is now.
			FrameCard(card)
			status = entry.note or ""
			local reusedID = record.id
			render.DressWhenLoaded(entry.actor, render.TransmogList(look),
				function(text, reasons)
					if plan.wantRecordBody then
						NoteBody(reusedID, plan.idealKey, entry.actor)
					end
					card.Status:SetText(("%s | %s"):format(entry.note or "", text or ""))
					lastApply[record.id] = reasons
				end)
			return status
		end
	end

	-- Riding is its own scene, its own camera and its own seating animation, so
	-- it does not share the pooled body: the mount scene replaces whatever the
	-- scene held, and a body built inside it is not reusable elsewhere.
	--
	-- A mount that will not render falls through to the unmounted path rather
	-- than leaving the card half built. A half-built card keeps whatever its
	-- scene held for the record before it, which reads as somebody else's mount
	-- and outfit wandering onto it.
	if Mounted(record) then
		entry.key = nil
		local mount, why, rider, animID, kitID, isSelfMount =
			render.PreparedMount(entry.scene, record.mount)

		if mount and (isSelfMount or not rider) then
			-- Still the thing to turn, even with nobody riding it.
			card.actor, card.mountActor = mount, mount
			FrameCard(card)
			return "they became the mount, so there is nobody to dress"
		end

		if mount and rider then
			card.actor, entry.actor = rider, rider
			local how = SetBody(rider, record, body)
			local mounted = codec.Decode(record.look)
			if how and type(mounted) == "table" then
				-- Weapons go away in the saddle. Blizzard sheathes the rider in
				-- its own mount previews, and a drawn two-hander on horseback
				-- reads as a bug.
				local function Sheathe()
					if type(rider.SetSheathed) == "function" then
						pcall(rider.SetSheathed, rider, true, false)
					end
				end
				Sheathe()

				render.Seat(mount, rider, animID, kitID)
				card.mountActor = mount
				FrameCard(card)

				local note = ("mounted | %s"):format(how)
				entry.note = note
				status = note
				render.DressWhenLoaded(rider, render.TransmogList(mounted),
					function(text, reasons)
						-- Dressing puts the weapons back in hand, so they go
						-- away again after every pass, not only the first.
						Sheathe()
						card.Status:SetText(("%s | %s"):format(note, text or ""))
						lastApply[record.id] = reasons
					end)
				return status
			end
		end

		card.mountNote = mount and "could not be seated" or tostring(why)
		card.actor, card.mountActor = nil, nil
	end

	-- The actor has to match the body about to be put in it, not the record.
	-- Each actor carries the scale and framing its race needs, so asking for a
	-- Dwarf's actor and then standing your own Dracthyr in it is what makes a
	-- card look zoomed into somebody's chest.
	-- A record of a race with two bodies, captured in the second one, needs the
	-- scene's alternate-form actor: that actor is built for the humanoid body
	-- and the everyday one is built for the dragon. The planner already
	-- decided this, so the actor asked for here and the body built above can
	-- no longer disagree.
	local actor, why, route = render.PreparedActor(entry.scene, plan.tagRace,
		plan.tagSex, plan.altered)
	if not actor then
		return tostring(why)
	end
	card.actor = actor
	entry.actor = actor

	local how = SetBody(actor, record, body)
	if not how then
		return "no body for this record"
	end
	FrameCard(card)

	local look = codec.Decode(record.look)
	if type(look) ~= "table" then
		return "stored look does not parse"
	end
	local where = ("%s | %s"):format(tostring(route), how)
	if card.mountNote then
		where = ("%s, shown unmounted: %s"):format(where, card.mountNote)
		card.mountNote = nil
	end
	entry.key = actor.mogtrotBodyKey
	entry.donorRace = actor.mogtrotDonorRace
	entry.donorGUID = actor.mogtrotDonorGUID
	entry.note = where
	status = where
	local id = record.id
	render.DressWhenLoaded(actor, render.TransmogList(look), function(text, reasons)
		card.Status:SetText(("%s | %s"):format(where, text or ""))
		lastApply[id] = reasons
		lastVisible[id] = render.SlotVisibility(actor, render.TransmogList(look))
		if plan.wantRecordBody then NoteBody(id, plan.idealKey, actor) end
	end)
	return status
end

-- Cards are pooled, so one arrives still holding whoever it last drew. Every
-- field that varies per record is cleared here, in one place, and RenderCard
-- cannot skip it by leaving early. That is the whole point: correctness used
-- to mean checking that all nine exits set all of it.
local function ResetCard(card)
	card.actor = nil
	card.mountActor = nil
	card.mountNote = nil
	card.Placeholder:Hide()
end

local function Paint(card, record)
	ResetCard(card)
	local status = RenderCard(card, record) or ""
	lastNote[record.id] = status
	card.Status:SetText(status)
end

-- Slot by slot, what the client said the last time this record was drawn. The
-- answer separates a bug in how the outfit is applied from an appearance this
-- body is refused.
local function ApplyLines(record)
	local reasons = lastApply[record.id]
	if type(reasons) ~= "table" then return {} end

	local Probe = ns.ClientProbe
	local names = Probe and Probe.TRY_ON_REASON or {}
	local slots = {}
	for slot in pairs(reasons) do slots[#slots + 1] = slot end
	if #slots == 0 then return {} end
	table.sort(slots)

	local drawn = lastVisible[record.id]
	local lines = { "", "last render on this body" }
	for _, slot in ipairs(slots) do
		local reason = reasons[slot]
		-- Accepted and not drawn is the interesting case, and the one a
		-- reason code alone will never show you.
		local seen = ""
		if type(drawn) == "table" and drawn[slot] ~= nil then
			seen = drawn[slot] and ", drawn" or ", NOT DRAWN"
		end
		lines[#lines + 1] = ("  slot %-3d %s%s"):format(slot,
			names[reason] or ("reason " .. tostring(reason)), seen)
	end
	return lines
end

-- Names each stored appearance. The look holds itemModifiedAppearanceIDs, and
-- the client will name one even when the wearer is long gone, which is what
-- separates "this slot did not render" from "this slot is a hidden piece".
local function PieceLines(record)
	local codec = ns.LookCodec
	local collection = C_TransmogCollection
	if not (codec and collection) then return {} end
	local look = codec.Decode(record.look)
	if type(look) ~= "table" then return {} end

	local slots = {}
	for slot in pairs(look) do slots[#slots + 1] = slot end
	if #slots == 0 then return {} end
	table.sort(slots)

	local function Name(sourceID)
		if type(sourceID) ~= "number" or sourceID <= 0 then return nil end
		if collection.GetAppearanceSourceInfo then
			local ok, info = pcall(collection.GetAppearanceSourceInfo, sourceID)
			if ok and type(info) == "table" and info.itemLink then return info.itemLink end
		end
		if collection.GetSourceInfo then
			local ok, info = pcall(collection.GetSourceInfo, sourceID)
			if ok and type(info) == "table" then
				return info.name or (info.itemID and ("item " .. info.itemID))
			end
		end
		return nil
	end

	local lines = { "", "what each slot is" }
	for _, slot in ipairs(slots) do
		local entry = look[slot]
		lines[#lines + 1] = ("  slot %-3d %s"):format(slot,
			Name(entry[1]) or "the client would not name it")
	end
	return lines
end

-- Names the things a record stores as bare numbers. The mount especially: a
-- line reading "mount 866" tells you nothing, and whether that mount has one
-- appearance or several is the difference between a card that renders and one
-- that does not.
local function NamedLines(record)
	local lines = {}
	local journal = C_MountJournal
	if record.mount and journal and journal.GetMountInfoByID then
		local ok, mountName = pcall(function()
			return (journal.GetMountInfoByID(record.mount))
		end)
		local name = ok and mountName or nil

		local displays = 0
		if journal.GetAllCreatureDisplayIDsForMountID then
			local gotAll, all = pcall(journal.GetAllCreatureDisplayIDsForMountID,
				record.mount)
			if gotAll and type(all) == "table" then displays = #all end
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("mount %d is %s, with %d appearance(s)"):format(
			record.mount, tostring(name), displays)
		if displays > 1 then
			lines[#lines + 1] = "  which one they were riding is not something the"
			lines[#lines + 1] = "  client will say, so the first is used"
		end
	end

	local forms = ns.FormDefinitions
	if record.form and forms then
		local entry = forms.Lookup(record.form)
		if entry then
			lines[#lines + 1] = ""
			lines[#lines + 1] = ("form %d is %s, which %s the transmog"):format(
				record.form, entry.name,
				entry.kind == "replaced" and "hides" or "keeps")
		end
	end
	return lines
end

local function NoteLines(record)
	local note = lastNote[record.id]
	if type(note) ~= "string" or note == "" then return {} end
	return { "", "last render note", note }
end

local function ShowDetails(record)
	local Text = ns.LibraryText
	if not (Text and ns.CopyBox) then return end
	local lines = Text.Details(record)
	for _, line in ipairs(NamedLines(record)) do lines[#lines + 1] = line end
	for _, line in ipairs(PieceLines(record)) do lines[#lines + 1] = line end
	for _, line in ipairs(NoteLines(record)) do lines[#lines + 1] = line end
	for _, line in ipairs(ApplyLines(record)) do lines[#lines + 1] = line end
	ns.CopyBox.Show("Mogtrot library: " .. Text.Title(record), lines)
end

local function Delete(record)
	local Store = ns.Library
	local library = Library()
	if not (Store and library) then return end
	Store.Delete(library, record.id)
	if ns.LibraryDetailUI and ns.LibraryDetailUI.Shown() == record then
		ns.LibraryDetailUI.Hide()
	end
	lastApply[record.id] = nil
	LibraryUI.Refresh()
end

-- Drag to turn and zoom: side to side turns the wall, up and down brings it
-- closer. The card owns the drag rather than the scene, so the wheel stays
-- with the list and a left-press never reaches the scene's own zoom.
local function EndDrag(card)
	card.dragging = false
	card:SetScript("OnUpdate", nil)
end

local function BeginDrag(card)
	local startX, startY = GetCursorPosition()
	local startYaw, startZoom = yaw, Zoom()
	card.dragging = true
	card:SetScript("OnUpdate", function(self)
		if not self.dragging then return end
		local x, y = GetCursorPosition()
		-- Deliberately not wrapped into 0-360. An angle that jumps from 359 to
		-- 1 is the same direction to a mathematician and a lurch to anybody
		-- watching, because the model takes the long way round to get there.
		-- Radians do not care how large the number is.
		yaw = startYaw + (x - startX) * TURN_PER_PIXEL
		-- Both axes read from where the drag began rather than from the last
		-- frame. Zoom multiplies, so a step per frame compounds sixty times a
		-- second and ends inside the model.
		local Zooms = ns.LibraryZoom
		SetZoom(Zooms and Zooms.Drag(startZoom, startY, y))
	end)
end

local function BuildCard(card)
	if card.built then return end
	card.built = true

	-- The scroll box builds a plain Button, so there is no backdrop to set;
	-- the card paints its own background and border, as mount cards do.
	card.Bg = card:CreateTexture(nil, "BACKGROUND")
	card.Bg:SetAllPoints()
	card.Bg:SetColorTexture(0, 0, 0, 0.55)

	-- Top left, mirroring the archive button opposite it. Blizzard's own
	-- class icon rather than ours, so it matches every other class icon the
	-- player sees.
	card.ClassIcon = card:CreateTexture(nil, "OVERLAY")
	card.ClassIcon:SetSize(18, 18)
	card.ClassIcon:SetPoint("TOPLEFT", 4, -4)
	card.ClassIcon:Hide()

	-- Snapshots only. An outfit or a custom set is re-read from the client
	-- whenever you ask, so there is nothing to protect and nothing to undo;
	-- a stranger you captured once is the only thing here you cannot get
	-- back, which is exactly why it is archived rather than deleted.
	card.Archive = CreateFrame("Button", nil, card)
	card.Archive:SetSize(18, 18)
	card.Archive:SetPoint("TOPRIGHT", -4, -4)
	-- The same small x the search boxes use. Atlas names are not checked at
	-- runtime: an unknown one leaves the button textureless but still
	-- clickable, which is worse than absent.
	card.Archive:SetNormalAtlas("common-search-clearbutton")
	card.Archive:SetHighlightAtlas("common-search-clearbutton", "ADD")
	-- Red because this is the only control on a card that takes something
	-- away. The grey x is tinted rather than swapped for another atlas so it
	-- keeps the shape and the hit area it already had.
	local archiveNormal = card.Archive:GetNormalTexture()
	if archiveNormal then archiveNormal:SetVertexColor(0.9, 0.2, 0.2) end
	local archiveHighlight = card.Archive:GetHighlightTexture()
	if archiveHighlight then archiveHighlight:SetVertexColor(1, 0.4, 0.4) end
	card.Archive:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Archive this snapshot")
		GameTooltip:AddLine("Takes it off the wall without deleting it.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	card.Archive:SetScript("OnLeave", GameTooltip_Hide)
	card.Archive:SetScript("OnClick", function(self)
		local record = self:GetParent().record
		local Store, library = ns.Library, Library()
		if not (record and Store and library) then return end
		if Store.Archive(library, record.id, time()) then
			if ns.LibraryDetailUI and ns.LibraryDetailUI.Shown() == record then
				ns.LibraryDetailUI.Hide()
			end
			lastApply[record.id] = nil
			lastNote[record.id] = nil
			LibraryUI.Refresh()
		end
	end)

	card.Edges = {}
	for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local line = card:CreateTexture(nil, "BORDER")
		line:SetColorTexture(0.3, 0.3, 0.3, 1)
		if edge == "TOP" or edge == "BOTTOM" then
			line:SetHeight(1)
			line:SetPoint(edge .. "LEFT")
			line:SetPoint(edge .. "RIGHT")
		else
			line:SetWidth(1)
			line:SetPoint("TOP" .. edge)
			line:SetPoint("BOTTOM" .. edge)
		end
		card.Edges[#card.Edges + 1] = line
	end

	card.Title = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	card.Title:SetPoint("BOTTOMLEFT", 9, 28)
	card.Title:SetPoint("BOTTOMRIGHT", -9, 28)
	card.Title:SetJustifyH("LEFT")
	card.Title:SetWordWrap(false)

	card.Sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	card.Sub:SetPoint("BOTTOMLEFT", 9, 16)
	card.Sub:SetPoint("BOTTOMRIGHT", -9, 16)
	card.Sub:SetJustifyH("LEFT")
	card.Sub:SetWordWrap(false)

	card.Status = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	card.Status:SetPoint("BOTTOMLEFT", 9, 5)
	card.Status:SetPoint("BOTTOMRIGHT", -9, 5)
	card.Status:SetJustifyH("LEFT")
	card.Status:SetWordWrap(false)

	card.Placeholder = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
	card.Placeholder:SetPoint("CENTER", 0, 10)
	card.Placeholder:SetWidth(CARD_W - 32)
	card.Placeholder:SetJustifyH("CENTER")
	card.Placeholder:SetText("Appearance not captured\nWear this outfit once")
	card.Placeholder:Hide()

	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", BeginDrag)
	card:SetScript("OnDragStop", EndDrag)
	card:SetScript("OnHide", EndDrag)

	-- The wheel belongs to the list, not to the model under the pointer.
	card:EnableMouseWheel(true)
	card:SetScript("OnMouseWheel", function(_self, delta)
		if window and window.Box then window.Box:OnMouseWheel(delta) end
	end)

	card:SetScript("OnClick", function(self, button)
		local record = self.record
		if not record then return end
		if button == "LeftButton" then
			-- One inspector follows whichever card was selected most recently.
			local detail = ns.LibraryDetailUI
			if not detail then return end
			detail.Show(window, record)
			return
		end
		if not MenuUtil then return end
		local Text = ns.LibraryText
		MenuUtil.CreateContextMenu(self, function(_owner, root)
			root:CreateTitle(Text and Text.Title(record) or "Look")
			root:CreateButton("More info", function() ShowDetails(record) end)
			root:CreateDivider()
			root:CreateButton("Delete", function() Delete(record) end)
		end)
	end)
end

local function InitCard(card, record)
	BuildCard(card)
	card.record = record
	card.Archive:SetShown(record.source ~= "mine")
	local classAtlas = ClassAtlas(record.classID)
	if classAtlas then card.ClassIcon:SetAtlas(classAtlas, false) end
	card.ClassIcon:SetShown(classAtlas ~= nil)

	local Text = ns.LibraryText
	local title = Text and Text.Title(record) or ""
	local className, color = ClassInfoFor(record.classID)
	if Text and className and color then
		title = Text.CardTitle(record, className, color.colorStr)
	end
	card.Title:SetText(title)
	card.Sub:SetText(Text and Text.Subtitle(record) or "")
	card.Status:SetText("")
	Paint(card, record)
end

local function Ensure()
	if window then return window end

	window = CreateFrame("Frame", "MogtrotLibrary", UIParent, "BackdropTemplate")
	window:SetSize(MARGIN * 2 + CARD_W * COLS + GAP * (COLS - 1) + BAR_GUTTER,
		HEADER + CARD_H * ROWS_SHOWN + GAP * (ROWS_SHOWN - 1) + MARGIN + FOOTER)
	window:SetPoint("CENTER")
	window:SetFrameStrata(LIBRARY_STRATA)
	window:SetToplevel(true)
	window:SetFlattensRenderLayers(true)
	window:SetIsFrameBuffer(true)
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	window:SetBackdrop(BACKDROP)
	window:SetBackdropColor(0, 0, 0, 0.94)

	window.Close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	window.Close:SetPoint("TOPRIGHT", -4, -4)

	local Addon, Macro = ns.Addon, ns.Macro
	if Addon and Addon.CreateMacroDrag and Macro then
		window.SnapDrag = Addon:CreateMacroDrag(window, Macro.SNAP,
			"Capture macro for the action bar",
			"Drag to a bar. Makes one general macro that captures your target's look,"
				.. " and reuses that same macro every time after.")
	end

	-- The header is one sentence and the word that can change is its control,
	-- so there is no window title and no tabs: "Showing my characters - 50 of
	-- 247 looks" is both. Laid out from PairingHeader's segments, the same as
	-- the pairing windows'.
	window.HeaderRow = CreateFrame("Frame", nil, window)
	window.HeaderRow:SetPoint("TOPLEFT", MARGIN + 2, -12)
	window.HeaderRow:SetHeight(SWITCH_H)
	window.PaintHeader = ns.PairingHeaderUI.New(window.HeaderRow, SWITCH_H,
		HeaderAction, ns.PairingHeader.LibrarySegments)

	window.Status = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.Status:SetPoint("TOPLEFT", MARGIN + 2, -68)
	window.Status:SetJustifyH("LEFT")

	window.Search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
	window.Search:SetSize(250, 20)
	window.Search:SetAutoFocus(false)
	window.Search:SetPoint("TOPLEFT", MARGIN + 2, -40)
	if window.Search.Instructions then
		window.Search.Instructions:SetText("Search character name")
	end
	window.Search:HookScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or "")
		nameQuery = text ~= "" and text or nil
		LibraryUI.Refresh()
	end)

	local Filter = ns.LibraryFilter
	raceFilter = Filter and Filter.New() or nil
	window.FilterDropdown = CreateFrame("DropdownButton", nil, window,
		"WowStyle1FilterDropdownTemplate")
	window.FilterDropdown:SetPoint("LEFT", window.Search, "RIGHT", 14, 0)
	window.FilterDropdown:SetScript("OnEnter", function(self)
		if self:IsMenuOpen() then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Filters")
		GameTooltip:AddLine(self.mogtrotStatus
			or "Race: All | Class: All | Armor: All",
			0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	window.FilterDropdown:SetScript("OnLeave", GameTooltip_Hide)
	window.FilterDropdown:HookScript("OnMouseDown", function()
		GameTooltip:Hide()
	end)
	window.FilterDropdown:SetupMenu(function(_dropdown, root)
		if not (Filter and raceFilter) then return end
		local records = Records()
		local races = Filter.Races(records)
		local classes = Filter.Classes(records)
		local function Changed()
			LibraryUI.Refresh()
			return MenuResponse.Refresh
		end
		root:CreateButton(CHECK_ALL or "Check All", function()
			Filter.SelectAllFilters(raceFilter)
			return Changed()
		end)
		root:CreateButton(UNCHECK_ALL or "Uncheck All", function()
			Filter.SelectNoFilters(raceFilter)
			return Changed()
		end)
		root:CreateDivider()

		-- The menu answers whichever question the mode is asking. Race, class
		-- and armour narrow a crowd of strangers; on your own characters the
		-- character list has already narrowed all three.
		if not Filter.IsSnapshotMode(raceFilter) then
			root:CreateTitle("Show:")
			for _, entry in ipairs({ { "outfits", "Outfits" },
				{ "customSets", "Custom sets" } }) do
				local source, label = entry[1], entry[2]
				root:CreateCheckbox(label, function()
					return Filter.IsSourceSelected(raceFilter, source)
				end, function()
					Filter.SetSource(raceFilter, source,
						not Filter.IsSourceSelected(raceFilter, source))
					return Changed()
				end)
			end
			root:CreateDivider()
			root:CreateCheckbox("Hide outfits with nothing set", function()
				return Filter.HidesEmptyOutfits(raceFilter)
			end, function()
				Filter.SetHideEmptyOutfits(raceFilter,
					not Filter.HidesEmptyOutfits(raceFilter))
				return Changed()
			end)
			return
		end

		local raceMenu = root:CreateButton("Race")
		raceMenu:CreateButton(CHECK_ALL or "All", function()
			Filter.SelectAll(raceFilter)
			return Changed()
		end)
		raceMenu:CreateButton(UNCHECK_ALL or "None", function()
			Filter.SelectNone(raceFilter)
			return Changed()
		end)
		raceMenu:CreateDivider()
		for _, raceID in ipairs(races) do
			local id = raceID
			local info = C_CreatureInfo and C_CreatureInfo.GetRaceInfo
				and C_CreatureInfo.GetRaceInfo(id)
			local label = info and info.raceName or ("Race " .. id)
			raceMenu:CreateCheckbox(label, function()
				return Filter.IsRaceSelected(raceFilter, id)
			end, function()
				Filter.SetRace(raceFilter, id,
					not Filter.IsRaceSelected(raceFilter, id))
				return Changed()
			end)
		end
		local classMenu = root:CreateButton("Class")
		classMenu:CreateButton(CHECK_ALL or "All", function()
			Filter.SelectAllClasses(raceFilter)
			return Changed()
		end)
		classMenu:CreateButton(UNCHECK_ALL or "None", function()
			Filter.SelectNoClasses(raceFilter)
			return Changed()
		end)
		classMenu:CreateDivider()
		for _, classID in ipairs(classes) do
			local id = classID
			local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo
				and C_CreatureInfo.GetClassInfo(id)
			local label = info and info.className or ("Class " .. id)
			classMenu:CreateCheckbox(label, function()
				return Filter.IsClassSelected(raceFilter, id)
			end, function()
				Filter.SetClass(raceFilter, id,
					not Filter.IsClassSelected(raceFilter, id))
				return Changed()
			end)
		end
		local armorMenu = root:CreateButton("Armor type")
		armorMenu:CreateButton(CHECK_ALL or "All", function()
			Filter.SelectAllArmorTypes(raceFilter)
			return Changed()
		end)
		armorMenu:CreateButton(UNCHECK_ALL or "None", function()
			Filter.SelectNoArmorTypes(raceFilter)
			return Changed()
		end)
		armorMenu:CreateDivider()
		for _, armorType in ipairs(Filter.ARMOR_TYPES) do
			local label = armorType
			armorMenu:CreateCheckbox(label, function()
				return Filter.IsArmorTypeSelected(raceFilter, label)
			end, function()
				Filter.SetArmorType(raceFilter, label,
					not Filter.IsArmorTypeSelected(raceFilter, label))
				return Changed()
			end)
		end
	end)
	if window.SnapDrag then
		window.SnapDrag:ClearAllPoints()
		window.SnapDrag:SetPoint("LEFT", window.CharacterButton, "RIGHT", 12, 0)
	end

	-- Two exclusive buttons in the header, the same shape as the mount
	-- picker's mode switch. Original race is disabled rather than hidden while
	-- no body has been borrowed, because a control you cannot use still has to
	-- say what it would do and why it will not.
	local function BuildSwitch(label, width)
		local button = CreateFrame("Button", nil, window, "BackdropTemplate")
		button:SetSize(width, SWITCH_H)
		button:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		button.Text:SetPoint("CENTER")
		button.Text:SetText(label)
		button:SetScript("OnLeave", GameTooltip_Hide)
		return button
	end

	window.CharacterButton = BuildSwitch("Characters: All", 150)
	window.CharacterButton:SetPoint("LEFT", window.FilterDropdown, "RIGHT", 8, 0)
	window.CharacterButton:SetBackdropBorderColor(1, 0.82, 0, 1)
	window.CharacterButton.Text:SetTextColor(1, 0.82, 0)
	window.CharacterButton:SetScript("OnClick", OpenCharacterPicker)
	window.CharacterButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Characters")
		GameTooltip:AddLine("Whose outfits and custom sets the library shows.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)

	window.Original = BuildSwitch("Original race", 110)
	window.Original:SetScript("OnClick", function()
		if not fullFidelity then return end
		viewMode = "original"
		LibraryUI.Refresh()
	end)
	window.Original:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Original race and sex")
		if fullFidelity then
			GameTooltip:AddLine("Every look on the body of whoever wore it.",
				0.6, 0.6, 0.6, true)
		else
			GameTooltip:AddLine("Not available yet.", 1, 0.3, 0.3)
			GameTooltip:AddLine("A body of the other sex can only be built from a"
				.. " living player, and none is in reach. Hover or target anyone of"
				.. " the other sex and every look switches over at once.",
				0.9, 0.9, 0.9, true)
			GameTooltip:AddLine("Friendly player nameplates are off by default, so"
				.. " a crowd does not count. Turning on nameplateShowFriendlyPlayers"
				.. " makes this happen on its own. So does being in a group.",
				0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
	end)

	window.Mounted = BuildSwitch("Mounted", 76)
	window.Mounted:SetScript("OnClick", function()
		if not window.anyMounts then return end
		showMounts = not showMounts
		LibraryUI.Refresh()
	end)
	window.Mounted:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("On their mount")
		if window.anyMounts then
			GameTooltip:AddLine("Everyone captured while riding, back on the mount"
				.. " they were riding.", 0.6, 0.6, 0.6, true)
			GameTooltip:AddLine("A card can be told otherwise on its own; using this"
				.. " switch takes them all back.", 0.6, 0.6, 0.6, true)
		else
			GameTooltip:AddLine("Nothing to mount.", 1, 0.3, 0.3)
			GameTooltip:AddLine("No look here was captured on a mount. Snap somebody"
				.. " while they are riding and this turns on.", 0.9, 0.9, 0.9, true)
		end
		GameTooltip:Show()
	end)

	window.Mine = BuildSwitch("My race", 82)
	window.Mine:SetScript("OnClick", function()
		viewMode = "mine"
		LibraryUI.Refresh()
	end)
	window.Mine:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Your race and sex")
		GameTooltip:AddLine("Every look on your own body, as you are standing now.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)

	-- Zoom, on the row under the view switches. Dragging a card up and down
	-- does the same thing, but a drag is invisible until somebody tries it,
	-- and it cannot offer the way back: the readout is that, and says how far
	-- from its normal framing the wall has been taken.
	local function BuildZoomButton(label, width, steps)
		local button = BuildSwitch(label, width)
		button:SetBackdropBorderColor(1, 0.82, 0, 1)
		button.Text:SetTextColor(1, 0.82, 0)
		button:SetScript("OnClick", function()
			local Zooms = ns.LibraryZoom
			if not Zooms then return end
			SetZoom(Zooms.Step(Zoom(), steps))
		end)
		return button
	end

	window.ZoomOut = BuildZoomButton("-", 24, -1)
	window.ZoomOut:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Zoom out")
		GameTooltip:AddLine("Every model a step further away. Dragging a card"
			.. " down does the same.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)

	window.ZoomIn = BuildZoomButton("+", 24, 1)
	window.ZoomIn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Zoom in")
		GameTooltip:AddLine("Every model a step closer. Dragging a card up"
			.. " does the same.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)

	window.ZoomLevel = BuildSwitch("", 54)
	window.ZoomLevel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
	window.ZoomLevel.Text:SetTextColor(0.7, 0.7, 0.7)
	window.ZoomLevel:SetScript("OnClick", function()
		SetZoom(DEFAULT_ZOOM)
	end)
	window.ZoomLevel:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Zoom")
		GameTooltip:AddLine("How close the wall is against the way a card is"
			.. " normally framed. Kept until you change it.", 0.6, 0.6, 0.6, true)
		GameTooltip:AddLine("Click to put it back.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)

	window.ZoomLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.ZoomLabel:SetText("Zoom:")

	window.ShowLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.ShowLabel:SetText("Show:")
	window.OrLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.OrLabel:SetText("or")

	window.Box = CreateFrame("Frame", nil, window, "WowScrollBoxList")
	window.Box:SetPoint("TOPLEFT", MARGIN, -HEADER)
	window.Box:SetPoint("BOTTOMRIGHT", -(MARGIN + BAR_GUTTER), FOOTER)

	window.Bar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
	window.Bar:SetPoint("TOPLEFT", window.Box, "TOPRIGHT", BAR_GAP, 0)
	window.Bar:SetPoint("BOTTOMLEFT", window.Box, "BOTTOMRIGHT", BAR_GAP, 0)

	window.View = CreateScrollBoxListGridView(COLS, 0, 0, 0, 0, GAP, GAP)
	window.View:SetElementSize(CARD_W, CARD_H)
	-- A wheel notch moves a whole row.
	window.View:SetPanExtent(CARD_H + GAP)
	window.View:SetElementInitializer("Button", InitCard)
	-- A recycled card hands its body back rather than taking it out of
	-- circulation, so the next card that wants that body finds it waiting.
	window.View:SetElementResetter(function(card)
		Release(card)
	end)

	ScrollUtil.InitScrollBoxListWithScrollBar(window.Box, window.Bar, window.View)
	window.BarVisibility = ScrollUtil.AddManagedScrollBarVisibilityBehavior(
		window.Box, window.Bar)

	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_self, delta)
		window.Box:OnMouseWheel(delta)
	end)

	-- Anchored once all three exist, right to left from the close button.
	window.Mine:SetPoint("TOPRIGHT", window.Close, "TOPLEFT", -6, -8)
	window.OrLabel:SetPoint("RIGHT", window.Mine, "LEFT", -6, 0)
	window.Original:SetPoint("RIGHT", window.OrLabel, "LEFT", -6, 0)
	window.ShowLabel:SetPoint("RIGHT", window.Original, "LEFT", -8, 0)
	window.Mounted:SetPoint("TOPRIGHT", window.Close, "TOPLEFT", -6, -34)
	window.ZoomIn:SetPoint("RIGHT", window.Mounted, "LEFT", -8, 0)
	window.ZoomLevel:SetPoint("RIGHT", window.ZoomIn, "LEFT", -4, 0)
	window.ZoomOut:SetPoint("RIGHT", window.ZoomLevel, "LEFT", -4, 0)
	window.ZoomLabel:SetPoint("RIGHT", window.ZoomOut, "LEFT", -8, 0)
	-- The sentence shares its row with the body switches, so it ends where
	-- they begin. The zoom controls are on the row below, with the body
	-- switch, so neither row has to make space for the other.
	window.HeaderRow:SetPoint("RIGHT", window.ShowLabel, "LEFT", -10, 0)

	-- A body can only be borrowed from somebody the client will name, and in a
	-- crowd that is almost never a nameplate: friendly player nameplates are
	-- off by default, so the only reliable donors are whoever you point at.
	-- Pointing at one is therefore treated as an offer, and the cards that
	-- still want a body of that sex are rebuilt on the spot. Cards that already
	-- have the right body keep it, so this only ever improves the wall.
	window.Watcher = CreateFrame("Frame", nil, window)
	window.Watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
	window.Watcher:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	-- Changing form changes the body every card is standing on while the wall
	-- is showing you, so the wall follows you into and out of it.
	window.Watcher:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
	window.Watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	-- Party and raid members are the only units whose identity is never
	-- restricted, so a group forming is the most reliable donor moment there is.
	window.Watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
	window.Watcher:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	window.Watcher:SetScript("OnEvent", function(_self, event, ...)
		if not window:IsShown() then return end
		if event == "UNIT_MODEL_CHANGED" or event == "UPDATE_SHAPESHIFT_FORM" then
			-- Borrowed bodies are somebody else's and are kept; only the ones
			-- built from you are rebuilt.
			LibraryUI.Soon()
			return
		end
		if event == "GROUP_ROSTER_UPDATE" then
			local mine = UnitSex and UnitSex("player") or nil
			local wanted = mine == 2 and 3 or 2
			local donors = ns.DonorBody
			local from = donors and donors.Find(wanted, ReadUnit)
			if from and LibraryUI.WarmAll(from) > 0 then LibraryUI.Soon() end
			return
		end

		local unit = event == "PLAYER_TARGET_CHANGED" and "target" or "mouseover"
		if event == "NAME_PLATE_UNIT_ADDED" then unit = select(1, ...) end
		if type(unit) ~= "string" then return end
		if not (UnitExists and UnitExists(unit)) then return end
		if not (UnitIsPlayer and UnitIsPlayer(unit)) then return end
		local ok, sex = pcall(UnitSex, unit)
		if not ok or issecretvalue and issecretvalue(sex) then return end
		local mine = UnitSex and UnitSex("player") or nil
		if sex == mine then return end
		-- One person of the other sex is enough for every body the library
		-- wants, so take all of them while they are standing there.
		if LibraryUI.WarmAll(unit) > 0 then
			LibraryUI.Soon()
		end
	end)

	tinsert(UISpecialFrames, "MogtrotLibrary")
	window:Hide()
	return window
end

-- Builds the body a record wants, from a named unit, and keeps it.
--
-- The moment a look is captured is the best moment there will ever be to
-- borrow a body for it: the wearer is standing right there and is, by
-- definition, the right race and sex. Waiting until the library is opened
-- means hoping somebody of that sex happens to be nearby, which in a city with
-- friendly nameplates off means hoping you have targeted one.
--
-- Returns true only when a body was actually built. A body already in the pool
-- is not news: in a city, hovering people and turning the camera fire these
-- events many times a second, and answering "yes, done" to each one would
-- repaint the whole wall every time, which the viewer sees as every model
-- flinching in unison.
--
-- Does nothing at all for a record whose sex matches yours, since your own
-- unit can build that anywhere.
function LibraryUI.WarmBody(record, donorUnit)
	local body = ns.RaceBody
	local render = ns.ProbeRenderUI
	if not (body and render and type(record) == "table") then return false end
	if record.look == "" then return false end
	if InCombatLockdown and InCombatLockdown() then return false end

	local mine = UnitSex and UnitSex("player") or nil
	if record.sex == nil or record.sex == mine then return false end

	local ideal = IdealBodyKey(record, body)
	if not ideal then return false end

	local entry = AttachScene(Pool():Warm(ideal))
	if not entry then return false end

	-- Only build when somebody of the right sex is actually there. Without this
	-- the fallback quietly builds the body on your own unit, produces the wrong
	-- sex, calls it done, and burns a pool slot doing it, over and over, every
	-- time the camera moves past somebody.
	local donors = ns.DonorBody
	local from = donorUnit
	if not from then
		from = donors and donors.Find(record.sex, ReadUnit, IdealShownRace(record, body))
	end
	if not from then return false end
	local ok, donorSex = pcall(UnitSex, from)
	if not ok or donorSex ~= record.sex then return false end

	local altered = record.nativeForm == false and body.HasAlternateForm(record.raceID)
	local actor = render.PreparedActor(entry.scene, record.raceFile, record.sex, altered)
	if not actor then return false end

	local how = SetBody(actor, record, body, from)
	if not how then return false end
	entry.key = actor.mogtrotBodyKey
	if entry.key == nil then
		-- The creature-row path builds a body but keys nothing, and an entry
		-- holding an actor with no key breaks the rule the pool relies on:
		-- keyless means reusable.
		entry.actor, entry.note = nil, nil
		return false
	end
	entry.actor = actor
	entry.note = how
	if entry.key ~= ideal then return false end

	-- The twin, from the same person while they are still there. Without it the
	-- detail pane would have to rebuild later from whoever is left, which is a
	-- different face in the same clothes.
	local twin = AttachScene(Pool():WarmPane(ideal))
	if twin and twin.key ~= ideal then
		twin.pane = true
		local twinActor = render.PreparedActor(twin.scene, record.raceFile, record.sex,
			altered)
		if twinActor and SetBody(twinActor, record, body, from) then
			twin.actor = twinActor
			twin.key = twinActor.mogtrotBodyKey
		end
	end
	return true
end

-- Every distinct body the library still wants, built from one donor in one go.
--
-- A donor lends only sex, and the race comes from the override, so a single
-- woman standing in front of you can supply every female body in the library
-- at once. That is what turns this from "target the right person for each
-- look" into "point at one person, once".
function LibraryUI.WarmAll(donorUnit)
	local Store = ns.Library
	local body = ns.RaceBody
	if not (Store and body) then return 0 end
	-- Nothing is waiting, so there is nothing to look for. This runs on every
	-- mouseover and every nameplate, so it has to be cheap when it is pointless.
	-- Gated on whether a card still wants a body, not on whether the wall looks
	-- complete: those stopped being the same question.
	if not bodiesWanted then return 0 end

	local built = 0
	for _, record in ipairs(Records()) do
		if LibraryUI.WarmBody(record, donorUnit) then built = built + 1 end
	end
	return built
end

-- How many records still want a body nobody has lent. Zero means the wall can
-- go to full fidelity.
local function Missing(list)
	local body = ns.RaceBody
	local mine = UnitSex and UnitSex("player") or nil
	if not body then return 0 end

	-- Without knowing your own sex there is no way to tell which records need a
	-- borrowed body, and answering "none" would declare full fidelity with
	-- nothing built. Count them all as waiting instead.
	if not mine then return #list end

	-- Two counts, because two different questions were being answered by one.
	--
	--   keys    is any shape of body still unbuilt? The wall shows every card
	--           on its own race or none of them, so this one decides that, and
	--           it is deliberately forgiving: one body of a shape is enough to
	--           prove the shape can be built.
	--   bodies  is any card still without a body of its own? A body belongs to
	--           one card at a time, so two cards wanting one shape need two.
	--           This one decides whether to keep looking for donors.
	--
	-- Answering both with the forgiving count is what stranded a card: the
	-- wall called itself complete, WarmAll gave up, and a card built during a
	-- donor-less moment kept the wrong body until the next reload.
	local supply = Pool():CountByKey()
	local keys, bodies = 0, 0
	for _, record in ipairs(list) do
		if record.look ~= "" and record.sex and record.sex ~= mine then
			local ideal = IdealBodyKey(record, body)
			local stock = ideal and supply[ideal] or 0
			if not (ideal and Pool():Find(ideal)) then keys = keys + 1 end
			if stock > 0 then
				supply[ideal] = stock - 1
			else
				bodies = bodies + 1
			end
		end
	end
	return keys, bodies
end

-- A burst of unit events would otherwise repaint the wall several times in a
-- frame, and every repaint undresses and redresses every model, which reads as
-- the cards flickering and their status lines arguing with themselves.
local refreshPending = false

function LibraryUI.Soon()
	if refreshPending then return end
	refreshPending = true
	C_Timer.After(0.1, function()
		refreshPending = false
		LibraryUI.Refresh()
	end)
end

-- The detail pane gets a body of its own, built from the same donor at the
-- same moment as the wall's.
--
-- Two bodies for one record only agree if they were borrowed from the same
-- person, and the only moment that is certain is while that person is still
-- standing there. So whenever a body is built for the wall, a twin is built
-- beside it and set aside for the pane. Cards never touch a twin and the pane
-- never touches a card's, so neither can be rebuilt out from under the other.
--
-- Hidden scenes cost nothing measurable, which is what makes keeping two
-- affordable.
function LibraryUI.PaneBody(record, parent, inset)
	local body = ns.RaceBody
	if not (body and type(record) == "table" and parent) then return nil end

	local ideal = IdealBodyKey(record, body)
	if not ideal then return nil end

	local twin, previous = Pool():BorrowPane(ideal)
	if not twin then return nil end

	if previous and previous ~= twin then
		previous.scene:SetParent(Pool():Holder())
		previous.scene:ClearAllPoints()
		previous.scene:SetPoint("TOPLEFT")
		previous.scene:Hide()
	end
	twin.scene:SetFixedFrameStrata(false)
	twin.scene:SetFixedFrameLevel(false)
	twin.scene:SetParent(parent)
	twin.scene:SetFixedFrameStrata(true)
	twin.scene:SetFixedFrameLevel(true)
	twin.scene:ClearAllPoints()
	twin.scene:SetPoint("TOPLEFT", inset.left, -inset.top)
	twin.scene:SetPoint("BOTTOMRIGHT", -inset.right, inset.bottom)
	twin.scene:Show()

	-- A twin is built as a body and nothing more: it is put aside the moment
	-- its donor is in reach, long before anybody asks to look at it. The
	-- clothes go on here, when it is actually being shown.
	local render = ns.ProbeRenderUI
	local codec = ns.LookCodec
	local look = codec and codec.Decode(record.look)
	if render and type(look) == "table" then
		render.DressWhenLoaded(twin.actor, render.TransmogList(look), function() end)
	end
	TurnCard({ actor = twin.actor }, yaw)
	return twin.actor
end

-- Whether a second view of this record is guaranteed to come out the same as
-- the first. It is when the body is built from your own unit: nothing is
-- borrowed, so nothing can have walked away. Only a body borrowed from
-- somebody else needs a twin set aside at build time.
function LibraryUI.BodyIsDeterministic(record)
	if type(record) ~= "table" then return false end
	if not (viewMode == "original" and fullFidelity) then return true end
	local mine = UnitSex and UnitSex("player") or nil
	return record.sex == nil or record.sex == mine
end

function LibraryUI.ReturnPaneBody()
	local entry = characterPool and characterPool:ReturnPane()
	if not entry then return end
	entry.scene:SetParent(Pool():Holder())
	entry.scene:ClearAllPoints()
	entry.scene:SetPoint("TOPLEFT")
	entry.scene:Hide()
end

function LibraryUI.LayerProbe()
	local entry
	for _, candidate in ipairs(characterPool and characterPool.entries or {}) do
		if candidate.card and candidate.scene and candidate.scene:IsShown() then
			entry = candidate
			break
		end
	end
	local function Read(frame)
		if not frame then return nil end
		return {
			strata = frame:GetFrameStrata(), level = frame:GetFrameLevel(),
			fixedStrata = frame:HasFixedFrameStrata(),
			fixedLevel = frame:HasFixedFrameLevel(),
		}
	end
	return {
		window = Read(window),
		card = Read(entry and entry.card),
		scene = Read(entry and entry.scene),
	}
end

-- Builds a record's body into a scene somebody else owns, and dresses it.
-- Same rules as a card: the same view mode, the same donor, the same actor
-- choice. Exposed so the detail pane can show the same person the wall is
-- showing without a second copy of any of that.
function LibraryUI.RenderInto(scene, record)
	local render = ns.ProbeRenderUI
	local codec = ns.LookCodec
	local body = ns.RaceBody
	if not (render and codec and body and type(record) == "table") then return nil end

	local wantRecordBody = viewMode == "original" and fullFidelity
	local tagRace, tagSex, altered
	if wantRecordBody then
		tagRace, tagSex = record.raceFile, record.sex
		altered = record.nativeForm == false and body.HasAlternateForm(record.raceID)
	else
		tagRace = select(2, UnitRace("player"))
		tagSex = UnitSex and UnitSex("player") or nil
		local diagnostics = ns.Diagnostics
		if diagnostics and type(diagnostics.UseNativeForm) == "function" then
			altered = not diagnostics.UseNativeForm("player")
		end
	end

	-- If the wall already built a body for this record, try to build from the
	-- very same person, so the two views are the same woman rather than two
	-- women of the same race. Falls back to the race, then to anybody.
	local ideal = IdealBodyKey(record, body)
	local preferRace, wantGUID
	local stored = ideal and Pool():Find(ideal)
	if stored then preferRace, wantGUID = stored.donorRace, stored.donorGUID end

	local sameDonor
	if wantGUID then
		local donors = ns.DonorBody
		for _, token in ipairs(donors and donors.Tokens() or {}) do
			if UnitExists and UnitExists(token) and UnitGUID then
				local ok, guid = pcall(UnitGUID, token)
				if ok and guid == wantGUID then
					sameDonor = token
					break
				end
			end
		end
	end

	local actor = render.PreparedActor(scene, tagRace, tagSex, altered)
	if not actor then return nil end
	local how = SetBody(actor, record, body, sameDonor, preferRace)
	if not how then return nil end

	local look = codec.Decode(record.look)
	if type(look) ~= "table" then return actor, how end
	render.DressWhenLoaded(actor, render.TransmogList(look), function() end)
	return actor, how
end

function LibraryUI.Refresh()
	if not window or not window:IsShown() then return end

	local allRecords = Records()
	local Filter = ns.LibraryFilter
	local searched = {}
	for _, record in ipairs(allRecords) do
		if not Filter or Filter.NameMatches(record, nameQuery) then
			searched[#searched + 1] = record
		end
	end
	local list = Filter and Filter.Apply(searched, raceFilter) or searched
	-- On your own characters the wall opens where you are, in the order your
	-- own outfit list already uses. Snapshot mode is other people, so there
	-- is no "current character" to lead with and the recency order stands.
	if Filter and not Filter.IsSnapshotMode(raceFilter) then
		local rank
		local tree = ns.Tree
		if tree and type(MogtrotCharDB) == "table" then
			rank = {}
			for position, choice in ipairs(
				tree.OutfitChoices(MogtrotCharDB, ns.Addon and ns.Addon.outfitsByID)) do
				rank[choice.outfitID] = position
			end
		end
		list = Filter.Order(list, UnitGUID and UnitGUID("player") or nil, rank)
	end
	if Filter and window.FilterDropdown then
		local races = Filter.Races(allRecords)
		local classes = Filter.Classes(allRecords)
		local selectedRaces = Filter.SelectionCount(raceFilter, races)
		local selectedClasses = Filter.ClassSelectionCount(raceFilter, classes)
		local selectedArmor = Filter.ArmorSelectionCount(raceFilter)
		local owners = Filter.Owners(allRecords)
		local selectedOwners = Filter.OwnerSelectionCount(raceFilter, owners)
		local selectedSources = Filter.SourceSelectionCount(raceFilter)
		local raceLabel = selectedRaces == #races and "All"
			or selectedRaces == 0 and "None" or (selectedRaces .. "/" .. #races)
		local classLabel = selectedClasses == #classes and "All"
			or selectedClasses == 0 and "None"
			or (selectedClasses .. "/" .. #classes)
		local armorTotal = #Filter.ARMOR_TYPES
		local armorLabel = selectedArmor == armorTotal and "All"
			or selectedArmor == 0 and "None"
			or (selectedArmor .. "/" .. armorTotal)
		local ownerLabel = selectedOwners == #owners and "All"
			or selectedOwners == 0 and "None"
			or (selectedOwners .. "/" .. #owners)
		local sourceTotal = #Filter.SOURCES()
		local sourceLabel = selectedSources == sourceTotal and "All"
			or selectedSources == 0 and "None"
			or (selectedSources .. "/" .. sourceTotal)
		local addon = ns.Addon
		local sync = addon and addon.OutfitLibrarySyncState
			and addon.OutfitLibrarySyncState()
		local customSync = addon and addon.CustomSetLibrarySyncState
			and addon.CustomSetLibrarySyncState()
		local missing = sync and sync.missing or 0
		local customMissing = customSync and customSync.missing or 0
		-- Each mode reports only the filters it actually applies, so a line
		-- saying "Race: All" can never be read as a filter that did nothing.
		if Filter.IsSnapshotMode(raceFilter) then
			window.FilterDropdown.mogtrotStatus =
				("Race: %s | Class: %s | Armor: %s"):format(raceLabel, classLabel,
					armorLabel)
		else
			window.FilterDropdown.mogtrotStatus =
				("Show: %s | Character: %s | Missing outfits: %d | Missing custom sets: %d")
				:format(sourceLabel, ownerLabel, missing, customMissing)
		end
		if window.CharacterButton then
			window.CharacterButton.Text:SetText(("Characters: %s"):format(ownerLabel))
		end
	end
	-- The wall stays apples to apples on the forgiving count, and the search
	-- for donors keeps running on the honest one.
	local waiting, unbuilt = Missing(list)
	fullFidelity = waiting == 0
	bodiesWanted = unbuilt > 0

	-- The mounted switch is only meaningful if something here was captured
	-- riding, so it reports that rather than sitting there doing nothing.
	window.anyMounts = false
	for _, record in ipairs(list) do
		if record.mount then window.anyMounts = true break end
	end
	window.Mounted:SetEnabled(window.anyMounts)
	if not window.anyMounts then
		window.Mounted:SetBackdropBorderColor(0.4, 0.3, 0.3, 1)
		window.Mounted.Text:SetTextColor(0.5, 0.45, 0.45)
	elseif showMounts then
		window.Mounted:SetBackdropBorderColor(1, 0.82, 0, 1)
		window.Mounted.Text:SetTextColor(1, 0.82, 0)
	else
		window.Mounted:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
		window.Mounted.Text:SetTextColor(0.7, 0.7, 0.7)
	end

	ShowZoom()

	local snapshotMode = not Filter or Filter.IsSnapshotMode(raceFilter)
	-- The sentence says which wall you are on and how much of it is showing;
	-- the line under it says why that is not all of it.
	window.PaintHeader({
		mode = snapshotMode and "snapshots" or "mine",
		shown = #list,
		total = Filter and Filter.ModeCount(allRecords, raceFilter) or #allRecords,
	})

	-- Only one mode has characters to choose between, and the box searches a
	-- different thing in each.
	if window.CharacterButton then
		window.CharacterButton:SetShown(not snapshotMode)
		-- A hidden frame keeps its place, so whatever sits after it has to be
		-- re-anchored or it leaves a hole.
		if window.SnapDrag then
			window.SnapDrag:ClearAllPoints()
			window.SnapDrag:SetPoint("LEFT", snapshotMode and window.FilterDropdown
				or window.CharacterButton, "RIGHT", 12, 0)
		end
	end
	if window.Search.Instructions then
		window.Search.Instructions:SetText(snapshotMode
			and "Search character name" or "Search set name")
	end

	-- Selected is gold, available is dim, unavailable is red-grey and unclickable.
	local showing = fullFidelity and viewMode == "original"
	window.Original:SetEnabled(fullFidelity)
	if not fullFidelity then
		window.Original:SetBackdropBorderColor(0.4, 0.3, 0.3, 1)
		window.Original.Text:SetTextColor(0.5, 0.45, 0.45)
	elseif showing then
		window.Original:SetBackdropBorderColor(1, 0.82, 0, 1)
		window.Original.Text:SetTextColor(1, 0.82, 0)
	else
		window.Original:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
		window.Original.Text:SetTextColor(0.7, 0.7, 0.7)
	end
	if showing then
		window.Mine:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
		window.Mine.Text:SetTextColor(0.7, 0.7, 0.7)
	else
		window.Mine:SetBackdropBorderColor(1, 0.82, 0, 1)
		window.Mine.Text:SetTextColor(1, 0.82, 0)
	end

	window.Box:SetDataProvider(CreateDataProvider(list),
		ScrollBoxConstants.RetainScrollPosition)

	-- The count is in the sentence above, so this line is only the filters and
	-- the bodies. Saying either of those twice would make the header look like
	-- it disagreed with itself.
	local filterStatus = window.FilterDropdown
		and window.FilterDropdown.mogtrotStatus
		or "Race: All | Class: All | Armor: All"
	if #list == 0 then
		if #allRecords == 0 then
			window.Status:SetText("nothing captured yet: target someone and /mogtrot snap")
		else
			window.Status:SetText(filterStatus)
		end
	elseif showing then
		window.Status:SetText(("%s | each on their own race and sex."
			.. " Right-click a card, drag to turn them all."):format(filterStatus))
	elseif fullFidelity then
		window.Status:SetText(("%s | all shown on you by choice."
			.. " Right-click a card, drag to turn them all."):format(filterStatus))
	else
		window.Status:SetText(("%s | all shown on you. Hover or target"
			.. " anyone of the other sex to see them on their own bodies"
			.. " (%d still need one)."):format(filterStatus, waiting))
	end
end

-- On screen right now, which is what a shortcut to it needs to know.
-- IsVisible rather than IsShown: IsShown answers only for the frame's own
-- flag and stays true under a hidden parent.
function LibraryUI.IsOpen()
	return window ~= nil and window:IsVisible()
end

-- The library and the pairing window are both full-size and both about the
-- same outfits, so two of them open is two places to look and one of them
-- covering the other.
local function CloseOthers()
	local addon = ns.Addon
	if not addon then return end
	if addon.ClosePicker then addon:ClosePicker() end
	if addon.CloseHearthstonePicker then addon.CloseHearthstonePicker() end
end

function LibraryUI.Show()
	CloseOthers()
	local frame = Ensure()
	frame:Show()
	LibraryUI.Refresh()
	return frame
end

function LibraryUI.Hide()
	if window then window:Hide() end
end

function LibraryUI.Toggle()
	local frame = Ensure()
	if frame:IsShown() then
		frame:Hide()
	else
		LibraryUI.Show()
	end
	return frame
end

ns.LibraryUI = LibraryUI
return LibraryUI
