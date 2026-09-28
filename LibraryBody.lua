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
--   viewer            { raceFile, sex, altered } for the logged-in character
--   hasAlternateForm  raceID -> boolean
--   visageRace        raceID -> raceID or nil
--   bodyHeld          false when no body of the record's shape is held yet
function LibraryBody.Plan(input)
	input = type(input) == "table" and input or {}
	local record = type(input.record) == "table" and input.record or {}
	local viewerSex = type(input.viewer) == "table" and input.viewer.sex or nil
	-- A look of the other sex whose shape nobody has lent stays on you.
	local unlent = input.bodyHeld == false and record.sex ~= nil and record.sex ~= viewerSex
	local wantRecordBody = input.viewMode == "original" and input.fullFidelity == true
		and not unlent

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

-- The unit a record's body is built from: the donor found, else your own unit
-- when your sex is the record's or the record's is unknown. nil otherwise:
-- SetModelByUnit takes no sex override, so your unit would draw the look on
-- the wrong sex, and a card shows text instead.
function LibraryBody.Donor(found, recordSex, viewerSex)
	if found ~= nil then return found end
	if recordSex == nil or recordSex == viewerSex then return "player" end
	return nil
end

-- How well a pooled body suits a record when several donors lent its shape:
-- the record's own race 2, its faction 1. A body of the other faction drops
-- pieces limited to the record's faction.
function LibraryBody.DonorRank(entry, record)
	if type(entry) ~= "table" or type(record) ~= "table" then return 0 end
	local rank = 0
	if record.raceID ~= nil and entry.donorRace == record.raceID then rank = rank + 2 end
	if record.faction ~= nil and entry.donorFaction == record.faction then rank = rank + 1 end
	return rank
end

-- Whether a card on the wall should be painted again for a body that just
-- arrived: its shape (ideal) is among arrived, and the card holds no body of
-- that shape (heldKey) or one the new body outranks.
function LibraryBody.WantsRepaint(heldKey, ideal, arrived, newRank, heldRank)
	if ideal == nil or type(arrived) ~= "table" or not arrived[ideal] then return false end
	if heldKey ~= ideal then return true end
	return (newRank or 0) > (heldRank or 0)
end

-- How far the pool falls short of the wall. ideals holds one key per card that
-- needs a borrowed body; supply is key -> bodies, from CountByKey.
--   shapes  cards whose key no body carries: forgiving, since one body proves
--           the shape can be built
--   cards   cards left without a body once each body serves one card: what
--           the status line reports as looks waiting
function LibraryBody.Shortfall(ideals, supply)
	supply = type(supply) == "table" and supply or {}
	local left, shapes, cards = {}, 0, 0
	for _, key in ipairs(type(ideals) == "table" and ideals or {}) do
		local stock = supply[key] or 0
		if stock == 0 then shapes = shapes + 1 end
		local used = left[key] or 0
		if used < stock then
			left[key] = used + 1
		else
			cards = cards + 1
		end
	end
	return shapes, cards
end

-- What a card shows in place of a body it has none of the right sex for.
function LibraryBody.NoBodyText(sex)
	local who = sex == 3 and "a woman" or sex == 2 and "a man" or "someone who can wear it"
	return ("Shows once you've seen %s\nHover over, target or group with one"):format(who)
end

-- Which body the snap pop-up draws:
--   "live"  the snapped player's own body
--   "own"   the record's race built on your body, when the sexes agree
--   "pool"  a borrowed body already built for the record's race and sex
--   nil     text only, since any other body is the wrong race or sex
-- input: hasLook, live, pooled, recordSex, viewerSex.
function LibraryBody.PopupBody(input)
	if type(input) ~= "table" or not input.hasLook then return nil end
	if input.live then return "live" end
	if input.recordSex ~= nil and input.recordSex == input.viewerSex then return "own" end
	if input.pooled then return "pool" end
	return nil
end

ns.LibraryBody = LibraryBody
return LibraryBody
