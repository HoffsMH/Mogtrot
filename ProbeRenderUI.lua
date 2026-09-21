local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Two things wearing one name, for now: the model-scene helpers the library
-- renders through, and a probe window of up to four panels used to answer a
-- question by looking rather than by reasoning.
--
-- Every panel uses Blizzard's own dress-up scene so the camera and lighting
-- match what the game shows at a transmogrifier. Read-only: nothing here
-- changes a setting, an outfit or an item.
local ProbeRenderUI = {}

-- Blizzard keeps this as a file-local in its dress-up code, so it cannot be
-- read from the environment; the value is theirs, repeated here.
local DRESS_UP_SCENE_ID = 596

-- INVSLOT_MAINHAND, repeated rather than read: this module is required by the
-- specs, where the client's constants do not exist.
local MAINHAND_SLOT = 16
local OUTFIT_SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 19 }

local PANEL_W, PANEL_H = 260, 380
local GAP = 12

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local window

local function BuildPanel(parent, index)
	local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	panel:SetSize(PANEL_W, PANEL_H)
	panel:SetPoint("TOPLEFT", 14 + (index - 1) * (PANEL_W + GAP), -56)
	panel:SetBackdrop(BACKDROP)
	panel:SetBackdropColor(0, 0, 0, 0.8)

	panel.Scene = CreateFrame("ModelScene", nil, panel, "ModelSceneMixinTemplate")
	panel.Scene:SetPoint("TOPLEFT", 8, -8)
	panel.Scene:SetPoint("BOTTOMRIGHT", -8, 46)

	panel.Title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	panel.Title:SetPoint("BOTTOMLEFT", 10, 28)
	panel.Title:SetPoint("BOTTOMRIGHT", -10, 28)
	panel.Title:SetJustifyH("LEFT")

	panel.Status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.Status:SetPoint("BOTTOMLEFT", 10, 8)
	panel.Status:SetPoint("BOTTOMRIGHT", -10, 10)
	panel.Status:SetJustifyH("LEFT")
	panel.Status:SetWordWrap(true)
	panel.Status:SetHeight(26)
	return panel
end

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
function ProbeRenderUI.ActorTag(raceFile, sex, altered)
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
	-- The transition resets the camera, so the remembered starting yaw is no
	-- longer what the camera is actually at.
	scene.mogtrotBaseYaw = nil
	if type(scene.GetPlayerActor) ~= "function" then return nil, "no player actor" end

	-- Which actor answered is the difference between a body at the right scale
	-- and armour floating in mid air, so the route taken is reported back.
	local actor, route
	local tag = ProbeRenderUI.ActorTag(raceFile, sex, altered)
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
function ProbeRenderUI.TransmogList(look)
	local list = {}
	if type(look) ~= "table" or not (ItemUtil and ItemUtil.CreateItemTransmogInfo) then
		return list
	end
	for slotID, entry in pairs(look) do
		if type(slotID) == "number" and type(entry) == "table" then
			local a, b, c = entry[1] or 0, entry[2] or 0, entry[3] or 0
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

function ProbeRenderUI.ApplyPlan(transmogList)
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

function ProbeRenderUI.ClearUnspecifiedSlots(actor, transmogList, slots)
	if type(actor) ~= "table" and type(actor) ~= "userdata" then return end
	if type(actor.UndressSlot) ~= "function" then return end
	local dressed = type(transmogList) == "table" and transmogList or {}
	for _, slot in ipairs(slots or OUTFIT_SLOTS) do
		if dressed[slot] == nil then pcall(actor.UndressSlot, actor, slot) end
	end
end

-- The scene's own camera, which is what a mounted scene has to be turned by:
-- turning the rider actor spins the passenger and leaves the mount facing the
-- other way, and a long mount spun about its own axis leaves the frame.
function ProbeRenderUI.Camera(scene)
	if type(scene.GetActiveCamera) ~= "function" then return nil end
	local ok, camera = pcall(scene.GetActiveCamera, scene)
	if not ok then return nil end
	return camera
end

-- Turns a scene to a yaw measured from wherever its camera started, so every
-- card agrees on what "front" means whatever camera its scene shipped with.
--
-- The sign is negated on purpose. Orbiting the camera one way looks like
-- turning the model the other, so without this a drag to the right spins the
-- model the opposite way from every other model in the game.
function ProbeRenderUI.TurnCamera(scene, degrees)
	local camera = ProbeRenderUI.Camera(scene)
	if not camera or type(camera.SetYaw) ~= "function" then return false end
	if scene.mogtrotBaseYaw == nil then
		local ok, base = pcall(camera.GetYaw, camera)
		scene.mogtrotBaseYaw = ok and base or 0
	end
	return (pcall(camera.SetYaw, camera, scene.mogtrotBaseYaw - math.rad(degrees)))
end

-- Pulls the camera in by a fraction of its own distance. A mount scene is
-- framed for the mount journal's big panel, so in a card it reads as a distant
-- speck unless it is brought closer.
function ProbeRenderUI.ZoomBy(scene, factor)
	local camera = ProbeRenderUI.Camera(scene)
	if not camera or type(camera.GetZoomDistance) ~= "function" then return false end
	local ok, distance = pcall(camera.GetZoomDistance, camera)
	if not ok or type(distance) ~= "number" then return false end
	if type(camera.SetMinZoomDistance) == "function" then
		pcall(camera.SetMinZoomDistance, camera, 0.01)
	end
	return (pcall(camera.SetZoomDistance, camera, distance * factor))
end

-- A mount and a place to sit on it.
--
-- A mount brings its own model scene, its own camera and its own seating
-- animation, so this transitions to the scene the journal names rather than
-- the dress-up one, and hands back both actors. The rider is left empty: the
-- caller builds and dresses that body itself, which is the whole point, and
-- Blizzard's own AttachPlayerToMount would overwrite it with your character.
--
-- A self mount is one the player turns into rather than climbs onto, so it has
-- no rider at all and says so.
function ProbeRenderUI.PreparedMount(scene, mountID)
	local journal = C_MountJournal
	if not (journal and journal.GetMountInfoExtraByID) then
		return nil, "this client exposes no mount display info"
	end
	if type(scene.TransitionToModelSceneID) ~= "function" then return nil, "no mixin" end

	local ok, displayID, _b, _c, isSelfMount, _d, sceneID, animID, kitID =
		pcall(journal.GetMountInfoExtraByID, mountID)
	if not ok then
		return nil, ("mount %s could not be read"):format(tostring(mountID))
	end

	-- A mount with several appearances answers with no display of its own, so
	-- the first of its appearances stands in. The mount picker already does
	-- this; without it those mounts look broken rather than absent.
	if not displayID or displayID == 0 then
		local gotAll, all = pcall(journal.GetMountAllCreatureDisplayInfoByID, mountID)
		if gotAll and type(all) == "table" and all[1] then
			displayID = all[1].creatureDisplayID
		end
	end
	-- Two different failures, said apart: a mount with no display cannot be
	-- drawn at all, while one with no scene of its own could be drawn if we
	-- knew where to put the camera.
	if not displayID or displayID == 0 then
		return nil, ("mount %s has no display, even among its appearances")
			:format(tostring(mountID))
	end
	if not sceneID then
		return nil, ("mount %s display %d has no scene"):format(tostring(mountID),
			displayID)
	end

	pcall(scene.ClearScene, scene)
	if not pcall(scene.TransitionToModelSceneID, scene, sceneID,
		CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true) then
		return nil, "mount scene refused"
	end

	local gotMount, mount = pcall(scene.GetActorByTag, scene, "unwrapped")
	if not gotMount or not mount then return nil, "mount scene has no mount actor" end
	if not pcall(mount.SetModelByCreatureDisplayID, mount, displayID, true) then
		return nil, ("mount display %d refused"):format(displayID)
	end
	if isSelfMount then
		pcall(mount.SetAnimationBlendOperation, mount, Enum.ModelBlendOperation.None)
		pcall(mount.SetAnimation, mount, 618)
	else
		pcall(mount.SetAnimationBlendOperation, mount, Enum.ModelBlendOperation.Anim)
		pcall(mount.SetAnimation, mount, 0)
	end

	scene.mogtrotBaseYaw = nil

	local rider
	if not isSelfMount then
		local gotRider, seated = pcall(scene.GetPlayerActor, scene, "player-rider")
		if gotRider then rider = seated end
	end
	return mount, nil, rider, animID, kitID, isSelfMount
end

-- Seats a rider the caller has already built and dressed. The scale is the
-- mount's business: Blizzard asks the mount what it wants and inverts it.
function ProbeRenderUI.Seat(mount, rider, animID, kitID)
	if not (mount and rider) then return false end
	if type(mount.CalculateMountScale) == "function"
		and type(rider.SetRequestedScale) == "function" then
		local ok, scale = pcall(mount.CalculateMountScale, mount, rider)
		if ok and type(scale) == "number" and scale ~= 0 then
			pcall(rider.SetRequestedScale, rider, 1 / scale)
		end
	end
	return (pcall(mount.AttachToMount, mount, rider, animID, kitID))
end

-- Whether each slot the look asked for is actually on the body.
--
-- ItemTryOnReason answers "accepted", not "drawn", so a wall of ok tells you
-- nothing about what the viewer can see. IsSlotVisible is the observable for
-- armour, and it has settled that once before: eleven slots reported success
-- on a body that drew none of them.
--
-- (caution) It answers nothing useful for a weapon. Measured: a body plainly
-- holding a dagger reported both weapon slots invisible while every armour
-- slot reported visible. Armour is composited into the body texture and a
-- weapon is an attachment, so there is nothing of a weapon in the composite
-- for the call to find. Weapon slots are left unanswered rather than
-- answered wrongly, because a confident wrong answer is what sent the last
-- two diagnoses down the wrong path.
local WEAPON_SLOTS = { [16] = true, [17] = true, [18] = true }

function ProbeRenderUI.SlotVisibility(actor, transmogList)
	local visible = {}
	if type(transmogList) ~= "table" then return visible end
	if not (actor and type(actor.IsSlotVisible) == "function") then return visible end
	for slot in pairs(transmogList) do
		if type(slot) == "number" and not WEAPON_SLOTS[slot] then
			local ok, drawn = pcall(actor.IsSlotVisible, actor, slot)
			visible[slot] = ok and drawn or false
		end
	end
	return visible
end

-- Collects the ItemTryOnReason per slot. A call that does not error still
-- reports why the slot was refused, and a refusal is the difference between
-- a slot applied and a slot the viewer can see.
local function ApplySlots(actor, transmogList)
	local reasons = {}
	for _, step in ipairs(ProbeRenderUI.ApplyPlan(transmogList)) do
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

-- A model loads asynchronously, and its unit's gear arrives later still, so
-- dressing in the same frame paints onto a body that is not there yet.
-- Blizzard's actor mixin offers the load callback; the timed repaints cover
-- the gap between the model arriving and its gear following.
local function DressWhenLoaded(actor, transmogList, onStatus)
	if type(transmogList) ~= "table" or type(actor.SetItemTransmogInfo) ~= "function" then
		return "no transmog list"
	end

	actor.mogtrotPaint = (actor.mogtrotPaint or 0) + 1
	local token = actor.mogtrotPaint

	-- Each repaint undresses and redresses, which the viewer sees as the model
	-- flinching. Once a pass comes back with every slot applied and nothing
	-- still loading, there is nothing left to wait for, so the remaining
	-- retries stand down rather than flickering the model for five seconds.
	actor.mogtrotSettled = nil

	local function Paint(reason)
		-- A newer request owns the actor now; this one is stale.
		if actor.mogtrotPaint ~= token then return end
		if actor.mogtrotSettled == token then return end
		pcall(actor.SetAutoDress, actor, false)
		pcall(actor.Undress, actor)
		ProbeRenderUI.ClearUnspecifiedSlots(actor, transmogList)
		local reasons = ApplySlots(actor, transmogList)
		local Probe = ns.ClientProbe
		local text, retryable = "applied", 0
		local settled = false
		if Probe and Probe.TryOnTally then
			local tally, pending = Probe.TryOnTally(reasons)
			text, retryable = Probe.TallyText(tally), pending
			local applied = 0
			for _ in pairs(transmogList) do applied = applied + 1 end
			settled = pending == 0 and (tally["ok"] or 0) >= applied
		end
		local lateEnough = reason ~= "immediate" and reason ~= "on load"
			and reason ~= "retry 0.1s" and reason ~= "retry 0.5s"
		if settled and lateEnough then actor.mogtrotSettled = token end
		if onStatus then
			-- The reasons themselves ride along: a caller that wants to say
			-- which slot was refused cannot get that back out of the text.
			onStatus(("%s [%s%s]"):format(text, reason,
				retryable > 0 and (", %d still loading"):format(retryable) or ""),
				reasons)
		end
	end

	if type(actor.SetOnModelLoadedCallback) == "function" then
		pcall(actor.SetOnModelLoadedCallback, actor, function() Paint("on load") end)
	end
	Paint("immediate")
	if C_Timer and C_Timer.After then
		-- A dozen appearances stream in over seconds, not frames, so the tail
		-- of the window is what tells apart "refused" from "not here yet".
		for _, delay in ipairs({ 0.1, 0.5, 1.5, 3, 5 }) do
			C_Timer.After(delay, function() Paint(("retry %ss"):format(delay)) end)
		end
	end
	return "dressing"
end

local function Ensure()
	if window then return window end

	window = CreateFrame("Frame", "MogtrotProbeRender", UIParent, "BackdropTemplate")
	window:SetSize(14 * 2 + PANEL_W * 4 + GAP * 3, PANEL_H + 76)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	window:SetBackdrop(BACKDROP)
	window:SetBackdropColor(0, 0, 0, 0.94)

	window.Close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	window.Close:SetPoint("TOPRIGHT", -4, -4)

	window.Title = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.Title:SetPoint("TOPLEFT", 16, -16)
	window.Title:SetText("Mogtrot render probe: same outfit, four ways of setting the body")

	window.Form = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.Form:SetPoint("TOPLEFT", 16, -32)
	window.Form:SetJustifyH("LEFT")

	window.Refresh = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
	window.Refresh:SetSize(90, 22)
	window.Refresh:SetPoint("TOPRIGHT", -34, -10)
	window.Refresh:SetText("Refresh")
	window.Refresh:SetScript("OnClick", function()
		if window.lastDeps then ProbeRenderUI.Show(window.lastDeps) end
	end)

	window.Panels = {}
	for i = 1, 4 do
		window.Panels[i] = BuildPanel(window, i)
		window.Panels[i]:Hide()
	end

	tinsert(UISpecialFrames, "MogtrotProbeRender")
	window:Hide()
	return window
end

-- deps = { plans = { {title, note, apply(actor, setStatus), raceFile, sex} },
-- formNote }. A plan naming a race gets the scene actor built for that race
-- and sex rather than the viewer's own.
-- Each plan owns its own body call and dressing; the window only supplies a
-- prepared actor and a place to report.
function ProbeRenderUI.Show(deps)
	deps = deps or {}
	local frame = Ensure()
	frame.lastDeps = deps
	frame:Show()


	local plans = deps.plans or {}

	if deps.formNote then frame.Form:SetText(deps.formNote()) end

	frame:SetWidth(14 * 2 + PANEL_W * math.max(#plans, 1)
		+ GAP * math.max(#plans - 1, 0))

	for index, panel in ipairs(frame.Panels) do
		local plan = plans[index]
		if not plan then
			panel:Hide()
		else
		panel:Show()
		panel.Title:SetText(plan.title)
		local actor, why = PreparedActor(panel.Scene, plan.raceFile, plan.sex,
			plan.altered)
		if not actor then
			panel.Status:SetText(why or "no actor")
		else
			local function Status(text)
				panel.Status:SetText(("%s - %s"):format(plan.note, text))
			end
			Status(plan.apply(actor, Status))
		end
		end
	end

	return frame
end

ProbeRenderUI.DressWhenLoaded = DressWhenLoaded
-- Any window that wants Blizzard's dress-up camera wants this exact sequence.
ProbeRenderUI.PreparedActor = PreparedActor

ns.ProbeRenderUI = ProbeRenderUI
return ProbeRenderUI
