local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Puts a stored look on a model: the dress-up scene, the actor for a race and
-- sex, the order slots go on in, and the camera distance. Every scene uses
-- Blizzard's own dress-up scene so the camera and lighting match what the game
-- shows at a transmogrifier. Read-only: nothing here changes a setting, an
-- outfit or an item.
local LookRender = {}
local LookCodec = ns.LookCodec or require("LookCodec")

-- Blizzard keeps this as a file-local in its dress-up code, so it cannot be
-- read from the environment; the value is theirs, repeated here.
local DRESS_UP_SCENE_ID = 596

-- INVSLOT_MAINHAND, repeated rather than read: this module is required by the
-- specs, where the client's constants do not exist.
local MAINHAND_SLOT = 16
local OUTFIT_SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 19 }

-- Returns the scene's player actor with the dress-up camera already applied,
-- or nil when this build does not hand one back.
-- A scene holds one actor per race, and a transition re-creates them all rather
-- than emptying them, so an actor that drew an earlier record is still drawing
-- it. Showing a second record then stacks two bodies in one frame. Blizzard
-- empties an actor it does not want with ClearModel, so everything but the one
-- in use is cleared.
local function ClearOtherActors(scene, keep)
	if type(scene.EnumerateActiveActors) ~= "function" then return end
	local ok, iterator = pcall(scene.EnumerateActiveActors, scene)
	if not ok or type(iterator) ~= "function" then return end
	for other in iterator do
		if other ~= keep and type(other.ClearModel) == "function" then
			pcall(other.ClearModel, other)
		end
	end
end

-- The scene names its actors by race, form and sex, lowercased, the way
-- Blizzard's own GetPlayerActorLabelTag builds them: "orc-male",
-- "dracthyr-alt-male" for the second body of a race that has one.
--
-- Asking for that name directly is the only way to reach the alternate-form
-- actor for somebody else's race. GetPlayerActor will build the tag itself,
-- but only reads "does this race have a second body" from the viewer, and it
-- skips that read entirely once a race and sex are handed to it, so it can
-- never return a "-alt" actor for anyone but you.
function LookRender.ActorTag(raceFile, sex, altered)
	if type(raceFile) ~= "string" or raceFile == "" then return nil end
	if sex ~= 2 and sex ~= 3 then return nil end
	local name = raceFile:lower()
	if altered then name = name .. "-alt" end
	return name .. (sex == 2 and "-male" or "-female")
end

-- raceFile and sex are optional. The scene keeps one actor per race and sex,
-- each with the scale and placement that race needs, and picks the viewer's
-- own by default. Asking for the race being shown instead is what stops a
-- small race rendering in a large race's slot, adrift in the frame.
local function PreparedActor(scene, raceFile, sex, altered)
	if type(scene.TransitionToModelSceneID) ~= "function" then return nil, "no mixin" end
	local ok = pcall(scene.TransitionToModelSceneID, scene, DRESS_UP_SCENE_ID,
		CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
	if not ok then return nil, "transition failed" end
	-- The transition resets the camera, so the remembered starting distance is
	-- no longer what the camera is actually at.
	scene.mogtrotBaseDistance = nil
	if type(scene.GetPlayerActor) ~= "function" then return nil, "no player actor" end

	-- Which actor answered is the difference between a body at the right scale
	-- and armour floating in mid air, so the route taken is reported back.
	local actor, route
	local tag = LookRender.ActorTag(raceFile, sex, altered)
	if tag then
		local got, byTag = pcall(scene.GetPlayerActor, scene, tag)
		if got and byTag then actor, route = byTag, tag end
	end
	if not actor and type(raceFile) == "string" and type(sex) == "number" then
		local overrideActorName, forceAlternateForm = nil, false
		local got, byRace = pcall(scene.GetPlayerActor, scene, overrideActorName,
			forceAlternateForm, raceFile, sex)
		if got and byRace then
			actor = byRace
			route = ("%s/%s by race"):format(raceFile, sex)
		end
	end
	if not actor then
		local gotActor, byDefault = pcall(scene.GetPlayerActor, scene)
		if not gotActor then return nil, "no player actor" end
		actor, route = byDefault, "your own actor"
	end
	if not actor then return nil, "no player actor" end
	ClearOtherActors(scene, actor)
	return actor, nil, route
end

-- A captured look becomes the list SetItemTransmogInfo wants, one entry per
-- slot. A slot holding nothing positive is dropped: applying it reports a
-- refusal for a slot nobody ever wore. Negative values are the client's own
-- "none" for a weapon's secondary appearance and travel through untouched.
function LookRender.TransmogList(look)
	local list = {}
	if type(look) ~= "table" or not (ItemUtil and ItemUtil.CreateItemTransmogInfo) then
		return list
	end
	for slotID, entry in pairs(look) do
		if type(slotID) == "number" and type(entry) == "table" then
			local a, b, c = LookCodec.DrawParts(slotID,
				entry[1] or 0, entry[2] or 0, entry[3] or 0)
			if a > 0 or b > 0 or c > 0 then
				local ok, info = pcall(ItemUtil.CreateItemTransmogInfo, a, b, c)
				if ok and info then list[slotID] = info end
			end
		end
	end
	return list
end

-- The order slots are applied in, whether each drags its child items along,
-- and where the actor's hand memory is reset.
--
-- Armour ascending, then the off hand, then the main hand. Blizzard:
-- "offhand is processed first and mainhand might override offhand". Their
-- shop and Perks previews use that order, and so does Plumber.
--
-- An actor keeps a running idea of which hand to fill next, which is why
-- `ResetNextHandSlot` exists: "Since we are manually setting the 2 items in
-- each hand, reset the actors sense of what hand to put stuff into". Without
-- it the second weapon lands in the hand the first one already took, and one
-- of the two is silently dropped. Every Blizzard path that fills both hands
-- calls it; the one that does not is `DressUpItemTransmogInfoList`, which is
-- where this loop was copied from, and it has the same fault.
--
-- Child items are ignored everywhere except the main hand, whose child is the
-- off-hand a two-hander occupies. Leaving them live on every slot lets each
-- call re-evaluate the whole set, so a later slot silently undoes an earlier
-- one and most of the outfit never appears.
local OFFHAND_SLOT = 17

function LookRender.ApplyPlan(transmogList)
	local plan = {}
	if type(transmogList) ~= "table" then return plan end
	local armour, weapons = {}, {}
	for slot in pairs(transmogList) do
		if slot == MAINHAND_SLOT or slot == OFFHAND_SLOT then
			weapons[#weapons + 1] = slot
		elseif type(slot) == "number" then
			armour[#armour + 1] = slot
		end
	end
	table.sort(armour)
	-- Descending, so the off hand goes on before the main hand.
	table.sort(weapons, function(a, b) return a > b end)

	for _, slot in ipairs(armour) do
		plan[#plan + 1] = { slot = slot, ignoreChildItems = true }
	end
	-- With both hands filled the main hand goes on last, and letting it
	-- re-evaluate its children there undoes the off-hand just applied.
	-- Blizzard's own two-weapon preview passes true for both for this reason.
	-- A lone main hand still keeps its children, whose child is the off-hand a
	-- two-hander occupies.
	local bothHands = #weapons > 1
	for index, slot in ipairs(weapons) do
		plan[#plan + 1] = {
			slot = slot,
			ignoreChildItems = bothHands or slot ~= MAINHAND_SLOT,
			resetHands = index == 1 or nil,
			hand = slot == MAINHAND_SLOT and "MAINHANDSLOT" or "SECONDARYHANDSLOT",
		}
	end
	return plan
end

function LookRender.ClearUnspecifiedSlots(actor, transmogList, slots)
	if type(actor) ~= "table" and type(actor) ~= "userdata" then return end
	if type(actor.UndressSlot) ~= "function" then return end
	local dressed = type(transmogList) == "table" and transmogList or {}
	for _, slot in ipairs(slots or OUTFIT_SLOTS) do
		if dressed[slot] == nil then pcall(actor.UndressSlot, actor, slot) end
	end
end

-- The scene's own camera.
function LookRender.Camera(scene)
	if type(scene.GetActiveCamera) ~= "function" then return nil end
	local ok, camera = pcall(scene.GetActiveCamera, scene)
	if not ok then return nil end
	return camera
end

-- A zoom is kept as a fraction of the span between the camera's own two
-- limits and saturated, so a distance outside that span is silently the limit
-- instead. Both ends move out of the way first, and they move the same way
-- every call so one distance always means one distance.
local function SetDistance(scene, camera, distance)
	if type(camera.SetMinZoomDistance) == "function" then
		pcall(camera.SetMinZoomDistance, camera, 0.01)
	end
	if type(camera.SetMaxZoomDistance) == "function" then
		pcall(camera.SetMaxZoomDistance, camera,
			math.max(distance, scene.mogtrotBaseDistance or distance))
	end
	return (pcall(camera.SetZoomDistance, camera, distance))
end

-- Puts the camera at a fraction of the distance its scene shipped with, so
-- one number frames scenes that were each built for a different panel.
--
-- The distance to measure from is recorded once per scene, because the camera
-- reports wherever it was last put: scaling what it reads back compounds every
-- call and, driven from a drag, buries the camera in the model within a second.
function LookRender.ZoomTo(scene, factor)
	local camera = LookRender.Camera(scene)
	if not camera or type(camera.GetZoomDistance) ~= "function" then return false end
	if scene.mogtrotBaseDistance == nil then
		local ok, distance = pcall(camera.GetZoomDistance, camera)
		if not ok or type(distance) ~= "number" then return false end
		-- A camera with no limits of its own answers zero, or nan, which
		-- compares false to everything including itself.
		if distance ~= distance or distance <= 0 then return false end
		scene.mogtrotBaseDistance = distance
	end

	return SetDistance(scene, camera, scene.mogtrotBaseDistance * factor)
end

-- A weapon is an attachment, not part of the composited body, so the armour
-- reads below leave weapon slots unanswered rather than answer them wrongly.
local WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true }

-- The armour slots the look asked for that the actor does not hold, in slot
-- order. A slot the client refuses without saying so, such as a faction's
-- racial piece on a body of the other faction, reports reason 0 and is left
-- empty.
function LookRender.DroppedSlotList(actor, transmogList)
	local dropped = {}
	if type(transmogList) ~= "table" then return dropped end
	if not (actor and type(actor.GetItemTransmogInfo) == "function") then return dropped end
	for slot in pairs(transmogList) do
		if type(slot) == "number" and not WEAPON_SLOTS[slot] then
			local ok, held = pcall(actor.GetItemTransmogInfo, actor, slot)
			if ok and held == nil then dropped[#dropped + 1] = slot end
		end
	end
	table.sort(dropped)
	return dropped
end

function LookRender.DroppedSlots(actor, transmogList)
	return #LookRender.DroppedSlotList(actor, transmogList)
end

-- Collects the ItemTryOnReason per slot. A call that does not error still
-- reports why the slot was refused, and a refusal is the difference between
-- a slot applied and a slot the viewer can see.
local function ApplySlots(actor, transmogList)
	local reasons = {}
	for _, step in ipairs(LookRender.ApplyPlan(transmogList)) do
		if step.resetHands and type(actor.ResetNextHandSlot) == "function" then
			pcall(actor.ResetNextHandSlot, actor)
		end
		local info = transmogList[step.slot]
		local ok, reason
		-- A weapon is named into its hand rather than handed to
		-- SetItemTransmogInfo, which Blizzard say "will automatically handle
		-- whether the player can dual wield" and therefore drops one of two
		-- on a class that cannot. TryOn takes the hand outright, and carries
		-- the illusion in the same call. This is the Dressing Room set
		-- panel's route.
		if step.hand and type(actor.TryOn) == "function" and info
			and (info.appearanceID or 0) > 0 then
			ok, reason = pcall(actor.TryOn, actor, info.appearanceID, step.hand,
				(info.illusionID or 0) > 0 and info.illusionID or nil)
		else
			ok, reason = pcall(actor.SetItemTransmogInfo, actor, info, step.slot,
				step.ignoreChildItems)
		end
		reasons[step.slot] = ok and reason or nil
	end
	return reasons
end

-- SetItemTransmogInfo answers with an ItemTryOnReason, not a boolean. Every
-- slot that reports anything other than Success is a slot the viewer is not
-- seeing, which is the difference between "applied" and "worked".
LookRender.TRY_ON_REASON = {
	[0] = "ok",
	[1] = "wrongRace",
	[2] = "notEquippable",
	[3] = "pending",
}

-- Returns a tally keyed by reason name, plus how many slots are still worth
-- retrying. Only pending is worth retrying: the other refusals are permanent
-- for this body.
function LookRender.TryOnTally(reasons)
	local tally, retryable, total = {}, 0, 0
	for _, reason in pairs(reasons or {}) do
		local name = LookRender.TRY_ON_REASON[reason] or ("reason " .. tostring(reason))
		tally[name] = (tally[name] or 0) + 1
		total = total + 1
		if reason == 3 then retryable = retryable + 1 end
	end
	return tally, retryable, total
end

-- A model loads asynchronously, and its unit's gear arrives later still, so
-- dressing in the same frame paints onto a body that is not there yet.
-- Blizzard's actor mixin offers the load callback; the timed repaints cover
-- the gap between the model arriving and its gear following.
-- A dozen appearances stream in over seconds, not frames, so the tail of the
-- window is what tells apart "refused" from "not here yet". A pass before the
-- third retry (1.5 s) can look settled while gear is still on its way.
local RETRY_DELAYS = { 0.1, 0.5, 1.5, 3, 5 }
local SETTLE_FROM_RETRY = 3

local function DressWhenLoaded(actor, transmogList, onStatus)
	if type(transmogList) ~= "table" or type(actor.SetItemTransmogInfo) ~= "function" then
		return
	end

	actor.mogtrotPaint = (actor.mogtrotPaint or 0) + 1
	local token = actor.mogtrotPaint

	-- Each repaint undresses and redresses, which the viewer sees as the model
	-- flinching. Once a pass comes back with every slot applied and nothing
	-- still loading, there is nothing left to wait for, so the remaining
	-- retries stand down rather than flickering the model for five seconds.
	actor.mogtrotSettled = nil

	-- retry is the index into RETRY_DELAYS, nil for the first pass and the
	-- load callback.
	local function Paint(retry)
		-- A newer request owns the actor now; this one is stale.
		if actor.mogtrotPaint ~= token then return end
		if actor.mogtrotSettled == token then return end
		pcall(actor.SetAutoDress, actor, false)
		pcall(actor.Undress, actor)
		LookRender.ClearUnspecifiedSlots(actor, transmogList)
		local reasons = ApplySlots(actor, transmogList)
		local tally, pending = LookRender.TryOnTally(reasons)
		local applied = 0
		for _ in pairs(transmogList) do applied = applied + 1 end
		local settled = pending == 0 and (tally["ok"] or 0) >= applied
		local lateEnough = retry ~= nil and retry >= SETTLE_FROM_RETRY
		if settled and lateEnough then actor.mogtrotSettled = token end
		if onStatus then onStatus() end
	end

	if type(actor.SetOnModelLoadedCallback) == "function" then
		pcall(actor.SetOnModelLoadedCallback, actor, function() Paint() end)
	end
	Paint()
	if C_Timer and C_Timer.After then
		for index, delay in ipairs(RETRY_DELAYS) do
			C_Timer.After(delay, function() Paint(index) end)
		end
	end
	return "dressing"
end

LookRender.DressWhenLoaded = DressWhenLoaded
-- Any window that wants Blizzard's dress-up camera wants this exact sequence.
LookRender.PreparedActor = PreparedActor

ns.LookRender = LookRender
return LookRender
