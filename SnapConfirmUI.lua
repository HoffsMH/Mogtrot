local _, ns = ...

-- The snap confirmation: who was captured, their look, and Cancel and Confirm.
-- A fill runs across Confirm for SnapCapture.CONFIRM_SECONDS; SnapCapture
-- holds the capture and its timer, and this frame only draws and forwards
-- clicks. One frame; a second capture replaces the first. Which body it
-- draws is LibraryBody.PopupBody's choice: the snapped player's own, else the
-- record's race on your body when the sexes agree, else a borrowed body lent
-- from the pool for as long as the pop-up is up, else text only.
local SnapConfirmUI = {}

local Bodies = ns.LibraryBodies
local Pool, IdealBodyKey, RankFor = Bodies.Pool, Bodies.IdealBodyKey, Bodies.RankFor
local Release, TurnCard = Bodies.Release, Bodies.TurnCard
local BACKDROP = ns.LibraryUI.BACKDROP

local CONFIRM_W, CONFIRM_H = 300, 420
local confirm

local function SaveConfirmPosition(frame)
	local point, _, relPoint, x, y = frame:GetPoint()
	if not (MogtrotDB and point) then return end
	MogtrotDB.snapConfirmPosition = { point = point, relPoint = relPoint, x = x, y = y }
end

local function Choose(keep)
	local capture = ns.SnapCapture
	if confirm and confirm.token and capture then capture.Resolve(confirm.token, keep) end
end

-- The snapped player's own body, built from the live unit and dressed in the
-- captured look, so race, sex and build are theirs. nil if it cannot be built.
local function LiveBody(scene, record, unit)
	local render, codec, body = ns.LookRender, ns.LookCodec, ns.RaceBody
	if not (render and codec and body and unit) then return nil end
	local look = codec.Decode(record.look)
	if type(look) ~= "table" then return nil end
	local altered = record.nativeForm == false and body.HasAlternateForm(record.raceID)
	local actor = render.PreparedActor(scene, record.raceFile, record.sex, altered)
	if not (actor and type(actor.SetModelByUnit) == "function") then return nil end
	local native = body.UseNativeForm(unit)
	-- Setting a unit on a model that is already loaded can keep the old one.
	if type(actor.ClearModel) == "function" then pcall(actor.ClearModel, actor) end
	local sheathe, autoDress, hideWeapons, holdBowString = false, false, false, false
	local ok, applied = pcall(actor.SetModelByUnit, actor, unit, sheathe, autoDress,
		hideWeapons, native, holdBowString)
	if not ok or applied == false then return nil end
	TurnCard({ actor = actor }, Bodies.Yaw())
	render.DressWhenLoaded(actor, render.TransmogList(look), function() end)
	return actor
end

-- Hands a body lent to the pop-up back to the pool.
local function ReturnConfirmBody(frame)
	if frame.body then Release(frame) end
end

-- A borrowed body already built for the record's race and sex, lent to the
-- pop-up and dressed in the look. nil when the pool has none free.
local function PooledBody(frame, record)
	local render, codec, body = ns.LookRender, ns.LookCodec, ns.RaceBody
	if not (render and codec and body) then return nil end
	local look = codec.Decode(record.look)
	local ideal = IdealBodyKey(record, body)
	if type(look) ~= "table" or not ideal then return nil end
	local entry = Pool():Take(frame, ideal, RankFor(record))
	if not entry then return nil end
	frame.body = entry
	local scene = entry.scene
	scene:SetFixedFrameStrata(false)
	scene:SetFixedFrameLevel(false)
	scene:SetParent(frame)
	scene:SetFixedFrameStrata(true)
	scene:SetFixedFrameLevel(true)
	scene:ClearAllPoints()
	scene:SetPoint("TOPLEFT", frame.Scene, "TOPLEFT")
	scene:SetPoint("BOTTOMRIGHT", frame.Scene, "BOTTOMRIGHT")
	scene:Show()
	TurnCard({ actor = entry.actor }, Bodies.Yaw())
	render.DressWhenLoaded(entry.actor, render.TransmogList(look), function() end)
	return entry.actor
end

-- Draws the pop-up's body and says which: "live", "own", "pool", or nil for
-- text only.
local function DrawConfirmBody(frame, record, liveUnit)
	ReturnConfirmBody(frame)
	local decide = ns.LibraryBody.PopupBody
	local input = { hasLook = record.look ~= "", live = liveUnit ~= nil,
		recordSex = record.sex, viewerSex = UnitSex and UnitSex("player") or nil }
	if decide(input) == "live" then
		if LiveBody(frame.Scene, record, liveUnit) then return "live" end
		input.live = false
	end
	if decide(input) == "own" then
		if select(2, Bodies.RenderInto(frame.Scene, record, "player")) ~= nil then
			return "own"
		end
		return nil
	end
	input.pooled = input.hasLook and PooledBody(frame, record) ~= nil
	if decide(input) == "pool" then return "pool" end
	ReturnConfirmBody(frame)
	return nil
end

local function PaintConfirmBody(frame)
	local from = frame.drawnFrom
	frame.Scene:SetShown(from == "live" or from == "own")
	frame.NoModel:SetText(from and "" or "Open the library to see this look.")
end

-- The live body became ready while the pop-up was up; it replaces whatever
-- was drawn.
local function SwapInLive(frame, unit)
	if not (frame.record and LiveBody(frame.Scene, frame.record, unit)) then return end
	ReturnConfirmBody(frame)
	frame.drawnFrom = "live"
	PaintConfirmBody(frame)
end

local function EnsureConfirm()
	if confirm then return confirm end
	local frame = CreateFrame("Frame", "MogtrotSnapConfirm", UIParent, "BackdropTemplate")
	frame:SetSize(CONFIRM_W, CONFIRM_H)
	local where = MogtrotDB and MogtrotDB.snapConfirmPosition
	if type(where) == "table" and where.point then
		frame:SetPoint(where.point, UIParent, where.relPoint, where.x, where.y)
	else
		frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
	end
	frame:SetFrameStrata("FULLSCREEN_DIALOG")
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 0.9)
	-- Dragged from anywhere but the buttons, which take their own clicks.
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self.dragging = nil
		self:StopMovingOrSizing()
		SaveConfirmPosition(self)
	end)

	frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.Title:SetPoint("TOPLEFT", 10, -10)
	frame.Title:SetPoint("TOPRIGHT", -10, -10)
	frame.Title:SetJustifyH("CENTER")
	frame.Title:SetWordWrap(true)

	frame.Scene = CreateFrame("ModelScene", nil, frame, "ModelSceneMixinTemplate")
	frame.Scene:SetPoint("TOPLEFT", 8, -40)
	frame.Scene:SetPoint("BOTTOMRIGHT", -8, 46)
	frame.Scene:EnableMouse(false)
	frame.Scene:EnableMouseWheel(false)

	frame.NoModel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.NoModel:SetPoint("CENTER", 0, 4)
	frame.NoModel:SetWidth(CONFIRM_W - 32)
	frame.NoModel:SetJustifyH("CENTER")

	-- Boxed in gold like the header's words, rather than Blizzard's red buttons.
	local GOLD_EDGE = { edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }
	local function GoldButton(label, onClick)
		local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
		button:SetBackdrop(GOLD_EDGE)
		button:SetBackdropBorderColor(1, 0.82, 0, 1)
		button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "ADD")
		button:GetHighlightTexture():SetVertexColor(1, 0.82, 0, 0.15)
		button.Label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		button.Label:SetPoint("CENTER")
		button.Label:SetText(label)
		button:SetScript("OnClick", onClick)
		return button
	end

	local width = (CONFIRM_W - 30) / 2
	frame.Cancel = GoldButton("Cancel", function() Choose(false) end)
	frame.Cancel:SetSize(width, 26)
	frame.Cancel:SetPoint("BOTTOMLEFT", 10, 10)

	frame.Confirm = GoldButton("", function() Choose(true) end)
	frame.Confirm:SetSize(width, 26)
	frame.Confirm:SetPoint("BOTTOMRIGHT", -10, 10)

	-- A child frame draws over the button's own text, so the label sits on
	-- the fill instead.
	frame.Fill = CreateFrame("StatusBar", nil, frame.Confirm)
	frame.Fill:SetPoint("TOPLEFT", 1, -1)
	frame.Fill:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.Fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	frame.Fill:SetStatusBarColor(1, 0.82, 0, 0.35)
	frame.Fill:SetMinMaxValues(0, 1)
	frame.Fill.Label = frame.Fill:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.Fill.Label:SetPoint("CENTER")
	frame.Fill.Label:SetText("Confirm")

	frame:SetScript("OnUpdate", function(self)
		local capture = ns.SnapCapture
		if not capture then return end
		local now = GetTime()
		self.Fill:SetValue(capture.ConfirmFraction(now - self.startedAt, self.duration))
		if not self.recheck then return end
		local step = capture.LiveRetry(now - self.startedAt, now - self.lastCheck)
		if step == "stop" then
			self.recheck = nil
		elseif step == "check" then
			self.lastCheck = now
			local unit = self.recheck()
			if unit then
				self.recheck = nil
				SwapInLive(self, unit)
			end
		end
	end)
	-- Escape closes special frames by hiding them, which is a Cancel. Hiding
	-- UIParent also fires OnHide but leaves this frame shown, so it is not.
	frame:SetScript("OnHide", function(self)
		if self:IsShown() then return end
		ReturnConfirmBody(self)
		Choose(false)
	end)
	tinsert(UISpecialFrames, "MogtrotSnapConfirm")
	frame:Hide()
	confirm = frame
	return frame
end

-- token is SnapCapture's handle for the pending capture; clicks carry it back.
-- liveUnit, when given, is still the player captured and its model is ready.
-- recheck, when given, asks again for that unit while the pop-up is up.
function SnapConfirmUI.ConfirmSnap(record, isNew, token, liveUnit, recheck)
	local text, capture = ns.LibraryText, ns.SnapCapture
	if type(record) ~= "table" or not (text and capture) then
		error("snap confirmation unavailable")
	end
	local frame = EnsureConfirm()
	frame.token = token
	frame.record = record

	frame.Title:SetText(text.Confirmation(record, isNew))
	-- Which body was drawn: "live", "own", "pool", or nil for text only.
	frame.drawnFrom = DrawConfirmBody(frame, record, liveUnit)
	PaintConfirmBody(frame)

	frame.startedAt = GetTime()
	frame.lastCheck = frame.startedAt
	frame.recheck = frame.drawnFrom ~= "live" and record.look ~= "" and recheck or nil
	frame.duration = capture.CONFIRM_SECONDS
	frame.Fill:SetValue(0)
	frame:Show()
	frame:Raise()
end

-- Hides the pop-up if it still shows this capture.
function SnapConfirmUI.HideConfirm(token)
	if not confirm or confirm.token ~= token then return end
	confirm.token = nil
	confirm.recheck = nil
	ReturnConfirmBody(confirm)
	-- A drag still under way when the capture resolves ends where it is.
	if confirm.dragging then
		confirm.dragging = nil
		confirm:StopMovingOrSizing()
		SaveConfirmPosition(confirm)
	end
	confirm:Hide()
end

ns.SnapConfirmUI = SnapConfirmUI
return SnapConfirmUI
