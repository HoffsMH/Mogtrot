local _, ns = ...

-- The library's bodies: which body a record is drawn on, building it, the pool
-- that keeps it, and lending it to a card, the detail pane or the snap pop-up.
-- Also the view every body shares: whose body the wall asks for, whether it
-- may have it, and the angle every body faces.
local LibraryBodies = {}

-- A card's size. Pooled scenes are built to it; the cards and the window read
-- it here.
local CARD_W, CARD_H = 210, 320
LibraryBodies.CARD_W, LibraryBodies.CARD_H = CARD_W, CARD_H

-- One angle for the whole wall, kept while the window lives.
local yaw = 0

function LibraryBodies.Yaw()
	return yaw
end

function LibraryBodies.SetYaw(degrees)
	yaw = degrees
end

-- Turns one card to the shared angle. The card turns its model, which spins in
-- place and is the motion people expect.
local function TurnCard(card, degrees)
	local actor = card.actor
	if type(actor) ~= "table" or type(actor.SetYaw) ~= "function" then return end
	pcall(actor.SetYaw, actor, math.rad(degrees))
end

LibraryBodies.TurnCard = TurnCard

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

-- "Alliance", "Horde", "Neutral" or nil when the client will not say.
local function FactionOf(unit)
	if not UnitFactionGroup then return nil end
	local ok, faction = pcall(UnitFactionGroup, unit)
	if not ok or (issecretvalue and issecretvalue(faction)) then return nil end
	return faction
end

-- How the client answers about a unit. A unit the client refuses is reported
-- as absent rather than guessed at.
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
	return true, true, sex, raceID, FactionOf(token)
end

-- The wall is all one thing or all the other.
--
-- Half the cards on somebody else's body and half on yours reads as broken
-- rather than as a compromise, and invites you to wonder which half is lying.
-- So until every live look has a body known to draw it whole
-- (DonorWatchUI.Offered) and every record that needs a borrowed body has one,
-- no record gets one: every card shows your own body, wearing that outfit.
-- Then the whole wall turns over at once. LibraryUI.Refresh decides it.
local fullFidelity = false

function LibraryBodies.FullFidelity()
	return fullFidelity
end

function LibraryBodies.SetFullFidelity(granted)
	fullFidelity = granted
end

-- What you asked to see, as opposed to what can be shown. Original race is the
-- default because it is the point of the library; it is granted only once
-- every body has been borrowed, and until then the wall stands every look on
-- you and turns over the moment the last body arrives. You can always ask for
-- your own body instead and keep it.
local viewMode = "original"

function LibraryBodies.ViewMode()
	return viewMode
end

function LibraryBodies.SetViewMode(mode)
	viewMode = mode
end

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
	local native = ns.RaceBody.UseNativeForm("player")
	local sheathe, autoDress, hideWeapons, holdBowString = false, false, false, false
	local ok, applied = pcall(actor.SetModelByUnit, actor, "player", sheathe,
		autoDress, hideWeapons, native, holdBowString)
	if not ok or applied == false then return nil end
	actor.mogtrotDonorFaction = FactionOf("player")
	return true
end

-- Puts a body of the record's race under the actor. True when it built one.
--
-- Neither body is right. The player model wears the whole outfit but carries
-- the viewer's sex and customizations, so a woman renders as a man with your
-- hair. The creature row is the subject's own race and sex with its own face,
-- but it is a creature model, so it takes attachments and drops every
-- composited piece. Which one is closer depends on the outfit: a look made
-- mostly of hidden pieces loses almost nothing on the creature row, while a
-- full plate set loses nearly all of it.
--
-- The creature display row shows the right race but renders only attachments:
-- a helm and weapons appear, and every composited piece is silently dropped
-- even though each slot reports ItemTryOnReason 0. Armor needs a player-type
-- model, which is what SetModelByUnit builds, and its customRaceID argument
-- swaps the race without needing that race to be standing in front of you.
-- Blizzard drives its own shop previews the same way. The creature row stays
-- as the fallback: the right race with no armor beats no body at all.
local function SetBody(actor, record, body, preferredDonor)
	local raceID = record.raceID
	-- Cleared first: whatever this actor was holding is about to stop being
	-- true, and a stale key would hand the wrong body to the next card.
	actor.mogtrotBodyKey = nil
	actor.mogtrotDonorFaction = nil

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
		-- from whichever unit the model is built from: the donor handed in, else
		-- yours when the sexes agree. Live units are never searched here; a
		-- donor is only ever somebody the player ingested.
		local from = ns.LibraryBody.Donor(preferredDonor, record.sex,
			UnitSex and UnitSex("player") or nil)
		if not from then return nil end

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
			return nil
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
			actor.mogtrotBorrowed = from ~= "player"
			actor.mogtrotDonorFaction = FactionOf(from)
			actor.mogtrotDonorGUID = from ~= "player" and UnitGUID and UnitGUID(from) or nil
			if actor.mogtrotDonorGUID and issecretvalue
				and issecretvalue(actor.mogtrotDonorGUID) then
				actor.mogtrotDonorGUID = nil
			end
			return true
		end
	end

	local displayID = body.Lookup(raceID, record.sex)
	if not displayID or type(actor.SetModelByCreatureDisplayID) ~= "function" then
		return nil
	end
	if not pcall(actor.SetModelByCreatureDisplayID, actor, displayID, false) then
		return nil
	end
	return true
end

LibraryBodies.SetBody = SetBody

-- The body this record deserves: its own race, its own form, its own sex. A
-- card already holding this has nothing to gain from being rebuilt and
-- everything to lose, since the donor who made it possible may be a zone away.
local function IdealBodyKey(record, body)
	return ns.LibraryBody.IdealKey(record, body.HasAlternateForm, body.VisageRace)
end

LibraryBodies.IdealBodyKey = IdealBodyKey

-- Distinct bodies are bounded by race, sex and form, times the donors who
-- lent them. The cap only guards against a pathological account growing this
-- without end.
local POOL_LIMIT = 120

local function Pool()
	if characterPool then return characterPool end
	local holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	holder:Hide()
	characterPool = ns.CharacterModelPool.New(POOL_LIMIT, holder)
	return characterPool
end

LibraryBodies.Pool = Pool

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
		card.body, card.actor = nil, nil
		return
	end
	card.body, card.actor = nil, nil
	entry.scene:SetParent(Pool():Holder())
	entry.scene:ClearAllPoints()
	entry.scene:SetPoint("TOPLEFT")
	entry.scene:Hide()
end

LibraryBodies.Release = Release

local function CardLayout()
	return ns.LibraryText.CardLayout()
end

-- Among several donors' bodies of the key, a donor known to draw the record
-- whole wins, then the record's race, then its faction (LibraryBody.DonorRank).
local function RankFor(record)
	if type(record) ~= "table" then return nil end
	local watch = ns.DonorWatchUI
	local covering = watch and watch.Covering(record.id) or nil
	return function(entry) return ns.LibraryBody.DonorRank(entry, record, covering) end
end

LibraryBodies.RankFor = RankFor

-- The scene a card should use for this body.
--
-- The order matters more than it looks. A free scene already holding the
-- wanted body is taken as it is. Otherwise only an empty scene is taken, never
-- one holding a body somebody else may want: handing out any free scene means
-- scrolling destroys the bodies it just built, which is the pool eating
-- itself. A new scene is made instead, because a hidden one is free. Only at
-- the cap does it fall back to taking a built body, oldest first.
function LibraryBodies.Acquire(card, wantedKey, record)
	Release(card)
	local entry = AttachScene(Pool():Acquire(card, wantedKey, RankFor(record)))
	if not entry then return nil end
	card.body = entry
	entry.scene:SetFixedFrameStrata(false)
	entry.scene:SetFixedFrameLevel(false)
	entry.scene:SetParent(card)
	entry.scene:SetFixedFrameStrata(true)
	entry.scene:SetFixedFrameLevel(true)
	entry.scene:ClearAllPoints()
	entry.scene:SetPoint("TOPLEFT", 7, -7)
	entry.scene:SetPoint("BOTTOMRIGHT", -7, CardLayout().scene)
	entry.scene:Show()
	return entry
end

-- Everything the planner needs that has to be asked of the client.
function LibraryBodies.BodyPlan(record, body)
	local altered = not ns.RaceBody.UseNativeForm("player")
	return ns.LibraryBody.Plan({
		record = record,
		viewMode = viewMode,
		fullFidelity = fullFidelity,
		viewer = {
			raceFile = select(2, UnitRace("player")),
			sex = UnitSex and UnitSex("player") or nil,
			altered = altered,
		},
		hasAlternateForm = body.HasAlternateForm,
		visageRace = body.VisageRace,
	})
end

-- Forgets the body an entry held, once it is gone or was never right.
function LibraryBodies.EmptyEntry(entry)
	entry.key, entry.actor, entry.borrowed = nil, nil, nil
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
--
-- staging, when given, marks the body and its twin as not yet usable until
-- LibraryBodies.SettleDonor (CharacterModelPool:Settle).
function LibraryBodies.WarmBody(record, donorUnit, want, staging)
	local body = ns.RaceBody
	local render = ns.LookRender
	if not (body and render and type(record) == "table") then return false end
	if record.look == "" then return false end
	if InCombatLockdown and InCombatLockdown() then return false end

	local mine = UnitSex and UnitSex("player") or nil
	if record.sex == nil or record.sex == mine then return false end

	local ideal = IdealBodyKey(record, body)
	if not ideal then return false end

	-- Only the unit handed in, and only when it is of the right sex. Without
	-- this the fallback quietly builds the body on your own unit, produces the
	-- wrong sex and burns a pool slot doing it.
	local from = donorUnit
	if not from then return false end
	local ok, donorSex = pcall(UnitSex, from)
	if not ok or donorSex ~= record.sex then return false end

	-- Each donor keeps a body of every shape it can lend, beside other donors'.
	local gotGUID, donorGUID = pcall(UnitGUID, from)
	if not gotGUID or (issecretvalue and issecretvalue(donorGUID)) then donorGUID = nil end
	local entry = AttachScene(Pool():Warm(ideal, want, donorGUID))
	if not entry then return false end

	local altered = record.nativeForm == false and body.HasAlternateForm(record.raceID)
	local actor = render.PreparedActor(entry.scene, record.raceFile, record.sex, altered)
	if not actor then return false end

	if not SetBody(actor, record, body, from) then return false end
	entry.key = actor.mogtrotBodyKey
	if entry.key == nil then
		-- The creature-row path builds a body but keys nothing, and an entry
		-- holding an actor with no key breaks the rule the pool relies on:
		-- keyless means reusable.
		entry.actor = nil
		return false
	end
	entry.actor = actor
	entry.borrowed = actor.mogtrotBorrowed
	entry.donorRace = actor.mogtrotDonorRace
	entry.donorGUID = actor.mogtrotDonorGUID
	entry.donorFaction = actor.mogtrotDonorFaction
	entry.staging = staging
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
			twin.staging = staging
		end
	end
	return true, ideal
end

-- A passive donor's card bodies become usable, or are emptied.
function LibraryBodies.SettleDonor(guid)
	Pool():Settle(guid)
end

function LibraryBodies.DropDonor(guid)
	Pool():Drop(guid)
end

-- How many records still want a body nobody has lent. Zero means the wall can
-- go to full fidelity.
function LibraryBodies.Missing(list)
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
	--           This one says how many cards still show text.
	--
	-- Answering both with the forgiving count is what stranded a card: the
	-- wall called itself complete, the build gave up, and a card built during a
	-- donor-less moment kept the wrong body until the next reload.
	local ideals, unkeyed = {}, 0
	for _, record in ipairs(list) do
		if record.look ~= "" and record.sex and record.sex ~= mine then
			local ideal = IdealBodyKey(record, body)
			if ideal then ideals[#ideals + 1] = ideal else unkeyed = unkeyed + 1 end
		end
	end
	local keys, bodies = ns.LibraryBody.Shortfall(ideals, Pool():CountByKey())
	return keys + unkeyed, bodies + unkeyed
end

-- A passive donor's facts, or nil and why the unit is refused. Builds nothing.
function LibraryBodies.DonorFacts(unit)
	local facts = { combat = InCombatLockdown and InCombatLockdown() or false }
	facts.exists = UnitExists and UnitExists(unit) or false
	if facts.exists then
		facts.isPlayer = UnitIsPlayer and UnitIsPlayer(unit) or false
		local same = UnitIsUnit and select(2, pcall(UnitIsUnit, unit, "player"))
		facts.isSelf = same == true
		local _, _, sex = ReadUnit(unit)
		facts.secret = facts.isPlayer and sex == nil
		facts.ready = not IsUnitModelReadyForUI or IsUnitModelReadyForUI(unit) == true
	end
	local refused = ns.DonorWatch.Refusal(facts)
	if refused then return nil, refused end

	local _, _, sex, raceID, faction = ReadUnit(unit)
	local race, raceFile = UnitRace(unit)
	local name = UnitName and UnitName(unit) or nil
	local guid = UnitGUID and UnitGUID(unit) or nil
	if issecretvalue then
		if issecretvalue(name) then name = nil end
		if issecretvalue(guid) then guid = nil end
		if issecretvalue(race) then race, raceFile = nil, nil end
	end
	return { guid = guid, name = name, race = race, raceFile = raceFile,
		raceID = raceID, sex = sex, faction = faction, keys = {} }
end

-- key -> { [donor GUID] = true } for every built card body lent by a donor,
-- for DonorWatch.Status.
function LibraryBodies.PooledKeys()
	local pooled = {}
	for _, entry in ipairs(characterPool and characterPool.entries or {}) do
		if entry.key ~= nil and not entry.pane and not entry.staging and entry.actor
			and entry.donorGUID then
			pooled[entry.key] = pooled[entry.key] or {}
			pooled[entry.key][entry.donorGUID] = true
		end
	end
	return pooled
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
function LibraryBodies.PaneBody(record, parent, inset)
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
	local render = ns.LookRender
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
function LibraryBodies.BodyIsDeterministic(record)
	if type(record) ~= "table" then return false end
	if not (viewMode == "original" and fullFidelity) then return true end
	local mine = UnitSex and UnitSex("player") or nil
	return record.sex == nil or record.sex == mine
end

function LibraryBodies.ReturnPaneBody()
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
-- showing without a second copy of any of that. A donor, when given, builds
-- the record's own race from that unit whatever the wall is showing.
function LibraryBodies.RenderInto(scene, record, donor)
	local render = ns.LookRender
	local codec = ns.LookCodec
	local body = ns.RaceBody
	if not (render and codec and body and type(record) == "table") then return nil end

	local wantRecordBody = donor ~= nil or (viewMode == "original" and fullFidelity)
	local tagRace, tagSex, altered
	if wantRecordBody then
		tagRace, tagSex = record.raceFile, record.sex
		altered = record.nativeForm == false and body.HasAlternateForm(record.raceID)
	else
		tagRace = select(2, UnitRace("player"))
		tagSex = UnitSex and UnitSex("player") or nil
		altered = not body.UseNativeForm("player")
	end

	-- If the wall already built a body for this record, try to build from the
	-- very same person, so the two views are the same woman rather than two
	-- women of the same race. Falls back to the race, then to anybody.
	local ideal = IdealBodyKey(record, body)
	local stored = ideal and Pool():Find(ideal)
	local wantGUID = stored and stored.donorGUID

	local sameDonor
	if wantGUID and ns.DonorBody then
		sameDonor = ns.DonorBody.TokenFor(wantGUID, function(token)
			if not (UnitExists and UnitExists(token) and UnitGUID) then return nil end
			local ok, guid = pcall(UnitGUID, token)
			return ok and guid or nil
		end)
	end

	local actor = render.PreparedActor(scene, tagRace, tagSex, altered)
	if not actor then return nil end
	local built = SetBody(actor, record, body, donor or sameDonor)
	if not built then return nil end
	TurnCard({ actor = actor }, yaw)

	local look = codec.Decode(record.look)
	if type(look) ~= "table" then return actor, built end
	render.DressWhenLoaded(actor, render.TransmogList(look), function() end)
	return actor, built
end

ns.LibraryBodies = LibraryBodies
return LibraryBodies
