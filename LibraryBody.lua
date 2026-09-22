local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- The questions a library card answers before it touches a frame: whose body
-- it is showing, which form that body is in, which actor tag will hold it, and
-- what key a stored body must carry to be reused.
--
-- Pure. Race and form facts arrive as functions so this never reads RaceBody,
-- the saved variables or a unit; the viewer's own race and sex arrive as
-- values for the same reason.
--
-- These four used to be answered in three places each, and a disagreement
-- between two copies is what put a card's camera inside somebody's chest: the
-- actor was picked for one race and the body built for another.
local LibraryBody = {}

-- Which race to render and whether to ask for the viewer's native form.
--
-- A visage is its own race ID, so it is asked for as that race in its own
-- native form. Asking for the dragon race in an altered form instead alters
-- the viewer rather than the subject, and leaves the record's armour hanging
-- on a dragon.
function LibraryBody.Form(record, hasAlternateForm, visageRace)
	local raceID = type(record) == "table" and record.raceID or nil
	if type(raceID) ~= "number" then return nil, true end
	if record.nativeForm ~= false then return raceID, true end
	if type(hasAlternateForm) ~= "function" or not hasAlternateForm(raceID) then
		return raceID, true
	end
	local visage = type(visageRace) == "function" and visageRace(raceID) or nil
	if visage then return visage, true end
	return raceID, false
end

-- What a built body must match to be handed back out. The donor's sex is in
-- here because SetModelByUnit takes no sex override: the sex is whatever the
-- donor unit was, so a body built from the wrong donor must not satisfy a
-- request for the right one.
function LibraryBody.Key(record, shownRace, native, sex)
	if type(record) ~= "table" then return nil end
	return ("%s|%s|%s|%s"):format(tostring(shownRace), tostring(native),
		tostring(sex), tostring(record.raceFile))
end

-- The key a card wants, as opposed to the key a body carries.
function LibraryBody.IdealKey(record, hasAlternateForm, visageRace)
	local shown, native = LibraryBody.Form(record, hasAlternateForm, visageRace)
	if shown == nil then return nil end
	return LibraryBody.Key(record, shown, native, record.sex)
end

-- One answer per card, computed before anything is touched.
--
--   record            the record being drawn
--   viewMode          "original" or "mine"
--   fullFidelity      every record on the wall can be built as captured
--   mounted           this card is drawing the record on its mount
--   viewer            { raceFile, sex, altered } for the logged-in character
--   hasAlternateForm  raceID -> boolean
--   visageRace        raceID -> raceID or nil
function LibraryBody.Plan(input)
	input = type(input) == "table" and input or {}
	local record = type(input.record) == "table" and input.record or {}
	local mounted = input.mounted == true

	-- Riding is its own scene with its own camera, so a mounted card never
	-- shows the record's own pooled body however the wall is set.
	local wantRecordBody = not mounted
		and input.viewMode == "original" and input.fullFidelity == true

	local shown, native = LibraryBody.Form(record, input.hasAlternateForm,
		input.visageRace)

	-- Only a borrowed body is worth keying. The header switches decide this
	-- for the whole wall, so every card asks the same question.
	local keyed = wantRecordBody

	-- The actor has to match the body about to be put in it, not the record:
	-- every actor carries the scale and framing its own race needs.
	local tagRace, tagSex, altered
	if wantRecordBody then
		tagRace, tagSex = record.raceFile, record.sex
		altered = record.nativeForm == false
			and type(input.hasAlternateForm) == "function"
			and input.hasAlternateForm(record.raceID) == true
	else
		local viewer = type(input.viewer) == "table" and input.viewer or {}
		tagRace, tagSex, altered = viewer.raceFile, viewer.sex, viewer.altered == true
	end

	return {
		mounted = mounted,
		wantRecordBody = wantRecordBody,
		keyed = keyed,
		shownRace = shown,
		nativeForm = native,
		idealKey = shown ~= nil
			and LibraryBody.Key(record, shown, native, record.sex) or nil,
		tagRace = tagRace,
		tagSex = tagSex,
		altered = altered == true,
	}
end

-- A stored body is reused only when it is exactly the one asked for. Anywhere
-- the right donor is absent, rebuilding would hand back a worse body than the
-- one already standing there.
function LibraryBody.CanReuse(plan, heldKey, hasActor)
	if type(plan) ~= "table" then return false end
	if not plan.wantRecordBody then return false end
	if not hasActor or plan.idealKey == nil then return false end
	return heldKey == plan.idealKey
end

ns.LibraryBody = LibraryBody
return LibraryBody
