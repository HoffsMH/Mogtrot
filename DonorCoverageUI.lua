local _, ns = ...

-- The bodies and reads behind DonorWatchUI's background checks: a stored
-- look as something to draw, each donor's bodies kept per form for the
-- session, the per-slot read of a drawn pair, and heritage locks read from
-- item tooltips. DonorCoverage classifies the reads.
local DonorCoverageUI = {}

local SCENE_W, SCENE_H = 80, 118
-- Bodies per form: one per LOOKS_PER_COPY looks, up to the cap.
local LOOKS_PER_COPY, DONOR_COPIES = 20, 3
local WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true }

local function Plain(value)
	if issecretvalue and issecretvalue(value) then return nil end
	return value
end

local function Copies(count, cap)
	return math.min(cap, math.max(1, math.ceil(count / LOOKS_PER_COPY)))
end

-- Looks -----------------------------------------------------------------------

local function Form(record)
	local body, Body = ns.RaceBody, ns.LibraryBody
	local shown, native = Body.Form(record, body.HasAlternateForm, body.VisageRace)
	if shown == nil then return nil end
	return Body.IdealKey(record, body.HasAlternateForm, body.VisageRace), {
		shown = shown, native = native, raceFile = record.raceFile, sex = record.sex,
		altered = record.nativeForm == false and body.HasAlternateForm(record.raceID) == true,
	}
end

-- One stored record as a look to draw, or nil when it cannot be drawn (no
-- look, no race or sex, nothing to dress).
function DonorCoverageUI.Look(record, archived)
	local codec, render = ns.LookCodec, ns.LookRender
	if not (codec and render and type(record) == "table") then return nil end
	local decoded = record.look ~= "" and record.look ~= nil and codec.Decode(record.look)
	local key, form = nil, nil
	if type(decoded) == "table" and record.sex and record.raceID then
		key, form = Form(record)
	end
	local list = key and render.TransmogList(decoded) or {}
	if not (key and next(list)) then return nil end
	local faction, inferred = record.faction, false
	if faction == nil and ns.DonorCoverage then
		faction, inferred = ns.DonorCoverage.RaceFaction(record.raceID), true
	end
	return { id = record.id, name = record.name, sex = record.sex,
		faction = faction, factionInferred = inferred, raceID = record.raceID,
		raceFile = record.raceFile, archived = archived, source = record.source,
		key = key, form = form, look = decoded, list = list }
end

-- Bodies ----------------------------------------------------------------------

local holder

local function Holder()
	if holder then return holder end
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(1, 1)
	holder:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -10, 10)
	holder:Hide()
	return holder
end

local function NewScene()
	local scene = CreateFrame("ModelScene", nil, Holder(), "ModelSceneMixinTemplate")
	scene:SetSize(SCENE_W, SCENE_H)
	scene:SetPoint("TOPLEFT")
	scene:EnableMouse(false)
	scene:EnableMouseWheel(false)
	return scene
end

-- unit's body in form, built as a library card builds it: the race override
-- is left off when it names the unit's own race, which would strip the
-- unit's customizations.
local function Build(scene, unit, form)
	local render = ns.LookRender
	if IsUnitModelReadyForUI and not IsUnitModelReadyForUI(unit) then return nil end
	local actor = render.PreparedActor(scene, form.raceFile, form.sex, form.altered)
	if not actor then return nil end
	local override = form.shown
	local _, ownFile, ownID = UnitRace(unit)
	if Plain(ownID) == form.shown then override = nil end
	if Plain(ownFile) == nil then override = form.shown end
	local ok, applied = pcall(actor.SetModelByUnit, actor, unit, false, false, false,
		form.native, false, override)
	if not ok or applied == false then return nil end
	return actor
end

DonorCoverageUI.NewScene = NewScene
DonorCoverageUI.Build = Build

-- Donors' bodies, one group per form their sex's looks need, built at ingest
-- while the donor is in reach and kept for the session. cap is the most
-- copies per form, DONOR_COPIES unless given; looks are the library's looks.
local kept = {}

-- Makes or refreshes the donor's entry and returns it with the builds it
-- wants, one { key, index } per body. With staged set the entry stays out of
-- Kept until SettleDonor.
function DonorCoverageUI.KeepPlan(donor, cap, looks, staged)
	if type(donor) ~= "table" then return nil, {} end
	local id = donor.guid or donor.name
	local entry
	for _, row in ipairs(kept) do
		if id ~= nil and row.donor.id == id then entry = row end
	end
	if not entry then
		entry = { groups = {} }
		kept[#kept + 1] = entry
	end
	entry.staged = staged or nil
	entry.donor = { id = id, guid = donor.guid, name = donor.name, race = donor.race,
		raceFile = donor.raceFile, raceID = donor.raceID, sex = donor.sex,
		faction = donor.faction }
	local counts, forms = {}, {}
	for _, look in ipairs(looks or {}) do
		if look.sex == donor.sex then
			counts[look.key] = (counts[look.key] or 0) + 1
			forms[look.key] = look.form
		end
	end
	local steps = {}
	for key, count in pairs(counts) do
		local group = entry.groups[key] or { form = forms[key], scenes = {} }
		entry.groups[key] = group
		group.actors, group.sceneOf = {}, {}
		for index = 1, Copies(count, cap or DONOR_COPIES) do
			steps[#steps + 1] = { key = key, index = index }
		end
	end
	table.sort(steps, function(a, b)
		if a.key ~= b.key then return tostring(a.key) < tostring(b.key) end
		return a.index < b.index
	end)
	return entry, steps
end

-- Builds one planned body from unit. Returns whether it was built.
function DonorCoverageUI.KeepStep(entry, step, unit)
	local group = entry.groups[step.key]
	group.scenes[step.index] = group.scenes[step.index] or NewScene()
	local actor = Build(group.scenes[step.index], unit, group.form)
	if not actor then return false end
	group.actors[#group.actors + 1] = actor
	group.sceneOf[actor] = group.scenes[step.index]
	return true
end

function DonorCoverageUI.SettleDonor(entry)
	if entry then entry.staged = nil end
end

-- Forgets a staged donor; its scenes stay parked and unused.
function DonorCoverageUI.DropDonor(entry)
	for index = #kept, 1, -1 do
		if kept[index] == entry then table.remove(kept, index) end
	end
end

-- Donors whose bodies are all built.
function DonorCoverageUI.Kept()
	local out = {}
	for _, entry in ipairs(kept) do
		if not entry.staged then out[#out + 1] = entry end
	end
	return out
end

-- Piece facts ----------------------------------------------------------------

local sourceFacts = {}

local function SourceFacts(source)
	local cached = sourceFacts[source]
	if cached then return cached end
	local facts = { item = 0, appearance = 0, hidden = false }
	local collection = C_TransmogCollection
	local ok, info = pcall(collection.GetSourceInfo, source)
	if ok and type(info) == "table" then
		facts.item = info.itemID or 0
		facts.appearance = info.visualID or 0
		if facts.appearance > 0 and collection.IsAppearanceHiddenVisual then
			local got, hidden = pcall(collection.IsAppearanceHiddenVisual, facts.appearance)
			facts.hidden = got and hidden == true
		end
		sourceFacts[source] = facts
	end
	return facts
end

local function RacesPrefix()
	local format = ITEM_RACES_ALLOWED
	return type(format) == "string" and format:match("^(.-)%%s") or nil
end

-- source -> { races } when its tooltip limits it to some races, false when it
-- does not, nil while the item is not cached.
local heritageBySource = {}

local function Heritage(source)
	local cached = heritageBySource[source]
	if cached ~= nil then return cached end
	local item = SourceFacts(source).item
	if not (item and item > 0 and C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, item)
	local lines = ok and type(data) == "table" and data.lines or nil
	if type(lines) ~= "table" or #lines < 2 then return nil end
	local prefix = RacesPrefix()
	if not prefix then return nil end
	local lock = false
	for _, line in ipairs(lines) do
		local races = ns.DonorCoverage.ParseRaces(Plain(line.leftText), prefix)
		if races then
			lock = { races = races }
			break
		end
	end
	heritageBySource[source] = lock
	return lock
end

local function RequestItem(source)
	local item = SourceFacts(source).item
	if item > 0 and C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, item)
	end
end

DonorCoverageUI.Heritage = Heritage
DonorCoverageUI.RequestItem = RequestItem

-- Reads ---------------------------------------------------------------------------

local function ReadSlots(job)
	local actor, slots = job.actor, {}
	for slot, entry in pairs(job.look.look) do
		if job.look.list[slot] and not WEAPON_SLOTS[slot] and type(entry) == "table" then
			-- A split shoulder may carry only its second source.
			local source = (entry[1] or 0) > 0 and entry[1] or (entry[2] or 0)
			local facts = SourceFacts(source)
			local okVisible, visible = pcall(actor.IsSlotVisible, actor, slot)
			local okHeld, held = pcall(actor.GetItemTransmogInfo, actor, slot)
			slots[#slots + 1] = { slot = slot, source = source, item = facts.item,
				appearance = facts.appearance, hidden = facts.hidden,
				visible = okVisible and visible == true, held = okHeld and held ~= nil }
		end
	end
	table.sort(slots, function(a, b) return a.slot < b.slot end)
	return slots
end

-- The per-slot read of one drawn pair, for DonorWatchUI.
function DonorCoverageUI.ReadSlots(actor, look)
	return ReadSlots({ actor = actor, look = look })
end

ns.DonorCoverageUI = DonorCoverageUI
return DonorCoverageUI
