local _, ns = ...

-- The library window: every stored look, four to a row, each on a body of its
-- own race.
--
-- A card is a portrait. Left-click opens the detail pane on it, right-click
-- offers More info, Delete, and the two ways of showing a body. The outfits and
-- custom sets you own are deliberately not ingested, so what shows up here is
-- only what has been captured.
--
-- The grid is Blizzard's scroll box, the same one the mount picker uses, so
-- the wheel and the bar behave here the way they do there. Dragging a card
-- turns every model at once: a wall of portraits is for comparing them, and
-- comparing them means seeing them from one angle.
local LibraryUI = {}

local COLS = 4
local CARD_W, CARD_H = 210, 320
local GAP, MARGIN = 10, 14
local HEADER, FOOTER = 52, 12
local BAR_GUTTER, BAR_GAP = 14, 6
local ROWS_SHOWN = 2

-- Degrees of yaw per pixel dragged, slow enough to stop on a detail.
local TURN_PER_PIXEL = 0.6

-- The mount picker frames its cards by sliding the scene frame instead, which
-- suits it: those cards show a mount alone and the complaint there was dead
-- space under the name. Here the rider is the subject and has to be legible,
-- which is a distance problem, not a position one.
-- A fraction of whatever distance the scene shipped with, not a fixed number,
-- so it holds across mounts of very different sizes. Gentle on purpose: a big
-- mount pulled in hard leaves nothing but a wing in frame once it turns.
-- Tunable in game with /mogtrot mountzoom while debug is on.
local MOUNT_ZOOM = 0.85

local function MountZoom()
	local saved = MogtrotDB and tonumber(MogtrotDB.mountZoom)
	if saved and saved > 0.05 and saved <= 3 then return saved end
	return MOUNT_ZOOM
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
local ownBody = {}

-- Whether the wall shows people sitting on the mounts they were seen on.
--
-- The switch in the header is the default; a card can be told otherwise and
-- then keeps its own answer. A record with no mount recorded ignores all of
-- this, since there is nothing to sit on.
local showMounts = false
local onMount = {}

local function Mounted(record)
	if not record.mount then return false end
	local own = onMount[record.id]
	if own ~= nil then return own end
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

local function ApplyYaw()
	if not window or not window.Box then return end
	window.Box:ForEachFrame(function(card)
		TurnCard(card, yaw)
	end)
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
	return ("%s|%s|%s|%s"):format(tostring(shown), tostring(native),
		tostring(donorSex), tostring(record.raceFile))
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
	if not (wanted or preferredDonor or ownBody[record.id]) then
		return SetOwnBody(actor)
	end
	if not ownBody[record.id]
		and type(actor.SetModelByUnit) == "function" and type(raceID) == "number" then
		local sheathe, autoDress, hideWeapons, holdBowString = false, false, false, false
		-- usePlayerNativeForm asks for the viewer's own second body, so it is
		-- meaningful only for a race that has one. Passing a stored false for a
		-- race that does not renders the viewer's alternate form wearing the
		-- record, which looks like the race override was ignored.
		local native = true
		local shown = raceID
		if record.nativeForm == false and body.HasAlternateForm(raceID) then
			-- A visage is its own race, so it is asked for as that race in its
			-- own native form. Asking for race 52 altered instead alters the
			-- viewer and leaves the subject's armour hanging on a dragon.
			local visage = body.VisageRace(raceID)
			if visage then
				shown = visage
			else
				native = false
			end
		end
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
	local raceID = record.raceID
	if type(raceID) ~= "number" then return nil end
	local native, shown = true, raceID
	if record.nativeForm == false and body.HasAlternateForm(raceID) then
		local visage = body.VisageRace(raceID)
		if visage then shown = visage else native = false end
	end
	return BodyKey(record, shown, native, record.sex)
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
	entry.scene:SetParent(card)
	entry.scene:ClearAllPoints()
	entry.scene:SetPoint("TOPLEFT", 7, -7)
	entry.scene:SetPoint("BOTTOMRIGHT", -7, 44)
	entry.scene:Show()
	return entry
end

local function Paint(card, record)
	local render = ns.ProbeRenderUI
	local codec = ns.LookCodec
	local body = ns.RaceBody
	card.mountActor = nil
	-- Cleared here rather than where it is read: several paths below leave
	-- early, and a note about this record's mount must never end up under the
	-- next record that recycles this card.
	card.mountNote = nil
	if not (render and codec and body) then
		card.actor = nil
		card.Status:SetText("modules not loaded")
		return
	end

	-- Whose body this card is meant to show. Everything below follows from it:
	-- which stored body may be reused, and which scene actor is asked for.
	local wantRecordBody = ownBody[record.id]
		or (viewMode == "original" and fullFidelity)
	if Mounted(record) then wantRecordBody = false end

	local ideal = IdealBodyKey(record, body)

	-- Ask for a keyed body only when a keyed body is what this card will
	-- produce. A creature row and a mounted card both key nothing, so handing
	-- them a borrowed body means destroying it: the key is wiped, the record
	-- counts as missing again, and the whole wall drops back to showing
	-- everything on you because one card's right-click menu was used.
	local keyed = wantRecordBody and not ownBody[record.id] and not Mounted(record)
	local entry = Acquire(card, keyed and ideal or nil)
	if not entry then
		card.actor = nil
		card.Status:SetText("character model pool full")
		return
	end
	if ownBody[record.id] then entry.key = nil end

	-- A body that is already exactly right is never rebuilt: rebuilding it
	-- anywhere the right donor is absent would hand back a worse one. A card
	-- asked to show your body reuses nothing, because a borrowed body is not
	-- what was asked for.
	if wantRecordBody and not ownBody[record.id]
		and entry.actor and ideal and entry.key == ideal then
		local look = codec.Decode(record.look)
		if type(look) == "table" then
			card.actor = entry.actor
			-- A body taken back out of the pool is still facing wherever it was
			-- left, so it is turned to whatever the wall is facing now.
			TurnCard(card, yaw)
			card.Status:SetText(entry.note or "")
			render.DressWhenLoaded(entry.actor, render.TransmogList(look),
				function(text, reasons)
					card.Status:SetText(("%s | %s"):format(entry.note or "", text or ""))
					lastApply[record.id] = reasons
				end)
			return
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
			TurnCard(card, yaw)
			card.Status:SetText("they became the mount, so there is nobody to dress")
			return
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
				render.ZoomBy(entry.scene, MountZoom())
				card.mountActor = mount
				TurnCard(card, yaw)

				local note = ("mounted | %s"):format(how)
				entry.note = note
				card.Status:SetText(note)
				render.DressWhenLoaded(rider, render.TransmogList(mounted),
					function(text, reasons)
						-- Dressing puts the weapons back in hand, so they go
						-- away again after every pass, not only the first.
						Sheathe()
						card.Status:SetText(("%s | %s"):format(note, text or ""))
						lastApply[record.id] = reasons
					end)
				return
			end
		end

		card.mountNote = mount and "could not be seated" or tostring(why)
		card.actor, card.mountActor = nil, nil
	end

	-- The actor has to match the body about to be put in it, not the record.
	-- Each actor carries the scale and framing its race needs, so asking for a
	-- Dwarf's actor and then standing your own Dracthyr in it is what makes a
	-- card look zoomed into somebody's chest.
	local tagRace, tagSex, altered
	if wantRecordBody then
		tagRace, tagSex = record.raceFile, record.sex
		-- A record of a race with two bodies, captured in the second one, needs
		-- the scene's alternate-form actor: that actor is built for the
		-- humanoid body, and the everyday one is built for the dragon.
		altered = record.nativeForm == false and body.HasAlternateForm(record.raceID)
	else
		tagRace = select(2, UnitRace("player"))
		tagSex = UnitSex and UnitSex("player") or nil
		local diagnostics = ns.Diagnostics
		if diagnostics and type(diagnostics.UseNativeForm) == "function" then
			altered = not diagnostics.UseNativeForm("player")
		end
	end
	local actor, why, route = render.PreparedActor(entry.scene, tagRace, tagSex,
		altered)
	if not actor then
		card.Status:SetText(tostring(why))
		return
	end
	card.actor = actor
	entry.actor = actor

	local how = SetBody(actor, record, body)
	if not how then
		card.Status:SetText("no body for this record")
		return
	end
	TurnCard(card, yaw)

	local look = codec.Decode(record.look)
	if type(look) ~= "table" then
		card.Status:SetText("stored look does not parse")
		return
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
	card.Status:SetText(where)
	local id = record.id
	render.DressWhenLoaded(actor, render.TransmogList(look), function(text, reasons)
		card.Status:SetText(("%s | %s"):format(where, text or ""))
		lastApply[id] = reasons
	end)
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

	local lines = { "", "last render on this body" }
	for _, slot in ipairs(slots) do
		local reason = reasons[slot]
		lines[#lines + 1] = ("  slot %-3d %s"):format(slot,
			names[reason] or ("reason " .. tostring(reason)))
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

local function ShowDetails(record)
	local Text = ns.LibraryText
	if not (Text and ns.CopyBox) then return end
	local lines = Text.Details(record)
	for _, line in ipairs(NamedLines(record)) do lines[#lines + 1] = line end
	for _, line in ipairs(PieceLines(record)) do lines[#lines + 1] = line end
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
	ownBody[record.id] = nil
	onMount[record.id] = nil
	LibraryUI.Refresh()
end

-- Drag to turn. The card owns the drag rather than the scene, so the wheel
-- stays with the list and a left-press never reaches the scene's own zoom.
local function EndTurn(card)
	card.turning = false
	card:SetScript("OnUpdate", nil)
end

local function BeginTurn(card)
	local startX = GetCursorPosition()
	local startYaw = yaw
	card.turning = true
	card:SetScript("OnUpdate", function(self)
		if not self.turning then return end
		local x = GetCursorPosition()
		-- Deliberately not wrapped into 0-360. An angle that jumps from 359 to
		-- 1 is the same direction to a mathematician and a lurch to anybody
		-- watching, because the model takes the long way round to get there.
		-- Radians do not care how large the number is.
		yaw = startYaw + (x - startX) * TURN_PER_PIXEL
		ApplyYaw()
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

	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card:RegisterForDrag("LeftButton")
	card:SetScript("OnDragStart", BeginTurn)
	card:SetScript("OnDragStop", EndTurn)
	card:SetScript("OnHide", EndTurn)

	-- The wheel belongs to the list, not to the model under the pointer.
	card:EnableMouseWheel(true)
	card:SetScript("OnMouseWheel", function(_self, delta)
		if window and window.Box then window.Box:OnMouseWheel(delta) end
	end)

	card:SetScript("OnClick", function(self, button)
		local record = self.record
		if not record then return end
		if button == "LeftButton" then
			-- Left-click opens the detail pane on this look. Clicking the one
			-- already shown closes it, so the same gesture puts it away.
			local detail = ns.LibraryDetailUI
			if not detail then return end
			if detail.Shown() == record then
				detail.Hide()
			else
				detail.Show(window, record)
			end
			return
		end
		if not MenuUtil then return end
		local Text = ns.LibraryText
		MenuUtil.CreateContextMenu(self, function(_owner, root)
			root:CreateTitle(Text and Text.Title(record) or "Look")
			root:CreateButton("More info", function() ShowDetails(record) end)
			root:CreateButton(ownBody[record.id] and "Show the full outfit"
				or "Show their own body", function()
				ownBody[record.id] = not ownBody[record.id] or nil
				LibraryUI.Refresh()
			end)
			if record.mount then
				local riding = Mounted(record)
				root:CreateButton(riding and "Take them off the mount"
					or "Show on their mount", function()
					-- An explicit answer for this card, which then stops
					-- following the switch in the header.
					onMount[record.id] = not riding
					LibraryUI.Refresh()
				end)
			end
			root:CreateDivider()
			root:CreateButton("Delete", function() Delete(record) end)
		end)
	end)
end

local function InitCard(card, record)
	BuildCard(card)
	card.record = record

	local Text = ns.LibraryText
	card.Title:SetText(Text and Text.Title(record) or "")
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
	window:SetFrameStrata("DIALOG")
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		-- The pane is anchored to the window, so it follows on its own; this
		-- only matters if a side was chosen relative to the screen.
		if ns.LibraryDetailUI then ns.LibraryDetailUI.Reanchor() end
	end)
	window:SetBackdrop(BACKDROP)
	window:SetBackdropColor(0, 0, 0, 0.94)

	window.Close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	window.Close:SetPoint("TOPRIGHT", -4, -4)

	window.Title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.Title:SetPoint("TOPLEFT", MARGIN + 2, -16)
	window.Title:SetText("Mogtrot library")

	window.Count = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.Count:SetPoint("TOPLEFT", MARGIN + 2, -32)
	window.Count:SetJustifyH("LEFT")

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
		-- The switch speaks for every card again, including ones told otherwise.
		wipe(onMount)
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
	window.Mounted:SetPoint("TOPRIGHT", window.Close, "TOPLEFT", -6, -2)
	window.Mine:SetPoint("TOPRIGHT", window.Mounted, "TOPLEFT", -4, 0)
	window.Original:SetPoint("TOPRIGHT", window.Mine, "TOPLEFT", -4, 0)

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
	-- Nothing is missing, so there is nothing to look for. This runs on every
	-- mouseover and every nameplate, so it has to be cheap when it is pointless.
	if fullFidelity then return 0 end

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

	local waiting = 0
	for _, record in ipairs(list) do
		if record.sex and record.sex ~= mine and not ownBody[record.id] then
			local ideal = IdealBodyKey(record, body)
			if not (ideal and Pool():Find(ideal)) then waiting = waiting + 1 end
		end
	end
	return waiting
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
	twin.scene:SetParent(parent)
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

	local list = Records()
	local waiting = Missing(list)
	fullFidelity = waiting == 0

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

	if #list == 0 then
		window.Count:SetText("nothing captured yet: target someone and /mogtrot snap")
	else
		if showing then
			window.Count:SetText(("%d look(s), each on their own race and sex."
				.. " Right-click a card, drag to turn them all."):format(#list))
		elseif fullFidelity then
			window.Count:SetText(("%d look(s), all shown on you by choice."
				.. " Right-click a card, drag to turn them all."):format(#list))
		else
			window.Count:SetText(("%d look(s), all shown on you. Hover or target"
				.. " anyone of the other sex to see them on their own bodies"
				.. " (%d still need one)."):format(#list, waiting))
		end
	end
end

function LibraryUI.Show()
	local frame = Ensure()
	frame:Show()
	LibraryUI.Refresh()
	return frame
end

function LibraryUI.Toggle()
	local frame = Ensure()
	if frame:IsShown() then
		if ns.LibraryDetailUI then ns.LibraryDetailUI.Hide() end
		frame:Hide()
	else
		LibraryUI.Show()
	end
	return frame
end

ns.LibraryUI = LibraryUI
return LibraryUI
