local _, ns = ...

-- Three model panels side by side, each built a different way, so the
-- question the API probe cannot answer gets answered by looking: does a body
-- set from a stored display ID actually render as that body, wearing the
-- transmog we put on it?
--
-- Every panel uses Blizzard's own dress-up scene so the camera and lighting
-- match what the game shows at a transmogrifier. Read-only: nothing here
-- changes a setting, an outfit or an item.
local ProbeRenderUI = {}

-- Blizzard keeps this as a file-local in its dress-up code, so it cannot be
-- read from the environment; the value is theirs, repeated here.
local DRESS_UP_SCENE_ID = 596

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
local function PreparedActor(scene)
	if type(scene.TransitionToModelSceneID) ~= "function" then return nil, "no mixin" end
	local ok = pcall(scene.TransitionToModelSceneID, scene, DRESS_UP_SCENE_ID,
		CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
	if not ok then return nil, "transition failed" end
	if type(scene.GetPlayerActor) ~= "function" then return nil, "no player actor" end
	local gotActor, actor = pcall(scene.GetPlayerActor, scene)
	if not gotActor or not actor then return nil, "no player actor" end
	return actor
end

-- Collects the ItemTryOnReason per slot. A call that does not error still
-- reports why the slot was refused, and a refusal is the difference between
-- a slot applied and a slot the viewer can see.
local function ApplySlots(actor, transmogList)
	local reasons = {}
	for slotID, info in pairs(transmogList) do
		local ok, reason = pcall(actor.SetItemTransmogInfo, actor, info, slotID)
		reasons[slotID] = ok and reason or nil
	end
	return reasons
end

-- A model loads asynchronously, and its unit's gear arrives later still, so
-- dressing in the same frame paints onto a body that is not there yet. That
-- is why a fresh target rendered naked while a second run came out dressed.
-- Blizzard's actor mixin offers the load callback; the timed repaints cover
-- the gap between the model arriving and its gear following.
local function DressWhenLoaded(actor, transmogList, onStatus)
	if type(transmogList) ~= "table" or type(actor.SetItemTransmogInfo) ~= "function" then
		return "no transmog list"
	end

	actor.mogtrotPaint = (actor.mogtrotPaint or 0) + 1
	local token = actor.mogtrotPaint

	local function Paint(reason)
		-- A newer request owns the actor now; this one is stale.
		if actor.mogtrotPaint ~= token then return end
		pcall(actor.SetAutoDress, actor, false)
		pcall(actor.Undress, actor)
		local reasons = ApplySlots(actor, transmogList)
		local Probe = ns.ClientProbe
		local text, retryable = "applied", 0
		if Probe and Probe.TryOnTally then
			local tally, pending = Probe.TryOnTally(reasons)
			text, retryable = Probe.TallyText(tally), pending
		end
		if onStatus then
			onStatus(("%s [%s%s]"):format(text, reason,
				retryable > 0 and (", %d still loading"):format(retryable) or ""))
		end
	end

	if type(actor.SetOnModelLoadedCallback) == "function" then
		pcall(actor.SetOnModelLoadedCallback, actor, function() Paint("on load") end)
	end
	Paint("immediate")
	if C_Timer and C_Timer.After then
		C_Timer.After(0.1, function() Paint("retry 0.1s") end)
		C_Timer.After(0.5, function() Paint("retry 0.5s") end)
		C_Timer.After(1.5, function() Paint("retry 1.5s") end)
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

-- deps = { plans = { {title, note, apply(actor, setStatus)} }, formNote }
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
		local actor, why = PreparedActor(panel.Scene)
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

ns.ProbeRenderUI = ProbeRenderUI
return ProbeRenderUI
