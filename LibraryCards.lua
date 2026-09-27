local _, ns = ...

-- One card on the library wall: building it, painting a record onto it, its
-- archive, restore and delete controls, and the framing every card shares.
--
-- A card is a portrait. Left-click opens the detail pane on it, right-click
-- offers Delete. Dragging a card moves every model at once, side to side to
-- turn and up and down to zoom: a wall of portraits is for comparing them, and
-- comparing them means seeing them the same way.
local LibraryCards = {}

local Bodies = ns.LibraryBodies
local CARD_W = Bodies.CARD_W
local TurnCard, Release = Bodies.TurnCard, Bodies.Release

-- The library window, once LibraryUI has built it.
local window

function LibraryCards.Attach(frame)
	window = frame
end

-- Degrees of yaw per pixel dragged, slow enough to stop on a detail.
local TURN_PER_PIXEL = 0.6

-- What the wall is zoomed to, as a share of each card's own framing, so one
-- at the default means every card shows what it was framed to show. Dragging a card up and
-- down moves it, the zoom buttons step it, and it is saved.
local DEFAULT_ZOOM = 1
LibraryCards.DEFAULT_ZOOM = DEFAULT_ZOOM

-- Saved under mountZoom. The bounds read back here are wider than the ones
-- the controls write: LibraryZoom clamps inside them.
local function Zoom()
	local saved = MogtrotDB and tonumber(MogtrotDB.mountZoom)
	if saved and saved > 0.05 and saved <= 6 then return saved end
	return DEFAULT_ZOOM
end

LibraryCards.Zoom = Zoom

-- The archived card whose Delete has been clicked once. Keyed by record, not
-- by card, because cards are pooled.
local armedDelete

function LibraryCards.Disarm()
	armedDelete = nil
end

local function Library()
	if type(MogtrotDB) ~= "table" then return nil end
	local library = MogtrotDB.library
	if type(library) ~= "table" or type(library.records) ~= "table" then return nil end
	return library
end

-- The saved library, or nil before there is one. The window reads it too.
LibraryCards.Library = Library

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
LibraryCards.ClassInfoFor = ClassInfoFor

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

LibraryCards.ClassAtlas = ClassAtlas

function LibraryCards.ClassRGB(classID)
	local _className, color = ClassInfoFor(classID)
	if not color then return nil end
	return { color.r, color.g, color.b }
end

-- Zooms one card to the shared factor. Always the camera: an actor has no
-- distance of its own to move, and the scene is what draws it.
local function ZoomCard(card, factor)
	local scene = card.body and card.body.scene
	local render = ns.LookRender
	if not (scene and render) then return end
	render.ZoomTo(scene, factor)
end

-- One card put the way the whole wall is: same angle, same distance.
local function FrameCard(card)
	TurnCard(card, Bodies.Yaw())
	ZoomCard(card, Zoom())
end

local function ApplyFraming()
	if not window or not window.Box then return end
	window.Box:ForEachFrame(FrameCard)
end

-- What the zoom controls say, in a number that grows as the models do.
function LibraryCards.ShowZoom()
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
	LibraryCards.ShowZoom()
	ApplyFraming()
end

LibraryCards.SetZoom = SetZoom

-- Says on the card's subtitle when the body left pieces off because they are
-- limited to the record's faction and the body is of the other one.
local function FactionSub(card, record, actor, transmogList)
	if card.record ~= record then return end
	local Text, render = ns.LibraryText, ns.LookRender
	if not (Text and render) then return end
	local dropped = render.DroppedSlots(actor, transmogList)
	local note = Text.FactionNote(record, actor.mogtrotDonorFaction, dropped)
	card.Sub:SetText(note or Text.Subtitle(record))
end

-- Shows the body a card already holds and dresses it.
local function ReuseBody(card, record, entry, look)
	local render = ns.LookRender
	local actor = entry.actor
	card.actor = actor
	-- A body taken back out of the pool is still facing wherever it was left,
	-- so it is put the way the wall is now.
	FrameCard(card)
	local list = render.TransmogList(look)
	render.DressWhenLoaded(actor, list, function()
		FactionSub(card, record, actor, list)
	end)
end

-- Draws one card, or a placeholder saying why it cannot.
local function RenderCard(card, record)
	local render = ns.LookRender
	local codec = ns.LookCodec
	local body = ns.RaceBody
	if record.look == "" then
		Release(card)
		card.Placeholder:SetText("Appearance not captured\nWear this outfit once")
		card.Placeholder:Show()
		return
	end
	if not (render and codec and body) then
		card.actor = nil
		return
	end

	-- Whose body this card is meant to show, which form it is in, which actor
	-- will hold it and what a reusable body must be keyed with: one answer,
	-- computed before anything is touched.
	--
	-- Asking for a keyed body only when a keyed body is what this card will
	-- produce matters more than it looks. A creature row keys nothing, so
	-- handing it a borrowed body destroys it: the key is wiped, the record
	-- counts as missing again, and the whole wall drops back to showing
	-- everything on you.
	local plan = Bodies.BodyPlan(record, body)
	local entry = Bodies.Acquire(card, plan.keyed and plan.idealKey or nil, record)
	if not entry then
		card.actor = nil
		return
	end

	-- A body that is already exactly right is never rebuilt: rebuilding it
	-- anywhere the right donor is absent would hand back a worse one. A card
	-- asked to show your body reuses nothing, because a borrowed body is not
	-- what was asked for.
	if ns.LibraryBody.CanReuse(plan, entry.key, entry.actor ~= nil) then
		local look = codec.Decode(record.look)
		if type(look) == "table" then
			ReuseBody(card, record, entry, look)
			return
		end
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
	local actor = render.PreparedActor(entry.scene, plan.tagRace,
		plan.tagSex, plan.altered)
	if not actor then return end
	card.actor = actor
	entry.actor = actor

	if not Bodies.SetBody(actor, record, body) then
		-- Text rather than a wrong body. The actor may still hold another
		-- record's model, so it is emptied and the scene handed back.
		if type(actor.ClearModel) == "function" then pcall(actor.ClearModel, actor) end
		Bodies.EmptyEntry(entry)
		Release(card)
		card.actor = nil
		card.Placeholder:SetText(ns.LibraryBody.NoBodyText(record.sex))
		card.Placeholder:Show()
		return
	end
	FrameCard(card)

	local look = codec.Decode(record.look)
	if type(look) ~= "table" then return end
	entry.key = actor.mogtrotBodyKey
	entry.borrowed = actor.mogtrotBorrowed
	entry.donorRace = actor.mogtrotDonorRace
	entry.donorGUID = actor.mogtrotDonorGUID
	entry.donorFaction = actor.mogtrotDonorFaction
	local list = render.TransmogList(look)
	render.DressWhenLoaded(actor, list, function()
		FactionSub(card, record, actor, list)
	end)
end

-- Cards are pooled, so one arrives still holding whoever it last drew. Every
-- field that varies per record is cleared here, in one place, and RenderCard
-- cannot skip it by leaving early. That is the whole point: correctness used
-- to mean checking that all nine exits set all of it.
local function ResetCard(card)
	card.actor = nil
	card.Placeholder:Hide()
end

local function ApplyCardLayout(card)
	local layout = ns.LibraryText.CardLayout()
	card.Title:SetPoint("BOTTOMLEFT", 9, layout.title)
	card.Title:SetPoint("BOTTOMRIGHT", -9, layout.title)
	card.Sub:SetPoint("BOTTOMLEFT", 9, layout.sub)
	card.Sub:SetPoint("BOTTOMRIGHT", -9, layout.sub)
	local scene = card.body and card.body.scene
	if scene and scene:GetParent() == card then
		scene:SetPoint("BOTTOMRIGHT", -7, layout.scene)
	end
end

local function Paint(card, record)
	ResetCard(card)
	RenderCard(card, record)
	ApplyCardLayout(card)
end

local function Delete(record)
	local Store = ns.Library
	local library = Library()
	if not (Store and library) then return end
	Store.Delete(library, record.id)
	if ns.LibraryDetailUI and ns.LibraryDetailUI.Shown() == record then
		ns.LibraryDetailUI.Hide()
	end
	ns.LibraryUI.Refresh()
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
	local startYaw, startZoom = Bodies.Yaw(), Zoom()
	card.dragging = true
	card:SetScript("OnUpdate", function(self)
		if not self.dragging then return end
		local x, y = GetCursorPosition()
		-- Deliberately not wrapped into 0-360. An angle that jumps from 359 to
		-- 1 is the same direction to a mathematician and a lurch to anybody
		-- watching, because the model takes the long way round to get there.
		-- Radians do not care how large the number is.
		Bodies.SetYaw(startYaw + (x - startX) * TURN_PER_PIXEL)
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
	-- Tooltips below the button: the card that slides under the pointer after
	-- an archive shows one at once, and to the left it would cover the flash.
	card.Archive:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
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
			GameTooltip:Hide()
			ns.LibraryUI.Refresh()
			ns.LibraryUI.Flash("Archived. To restore or delete it, turn on"
				.. " Show: Archived, top right.")
		end
	end)

	-- On an archived card the X gives way to these two. Text rather than
	-- atlases, so neither can be an invisible hotspot.
	local function CardButton(label, width)
		local button = CreateFrame("Button", nil, card, "BackdropTemplate")
		button:SetSize(width, 18)
		button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
		button:SetBackdropColor(0, 0, 0, 0.75)
		button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		button.Text:SetPoint("CENTER")
		button.Text:SetText(label)
		button:SetScript("OnLeave", GameTooltip_Hide)
		button:Hide()
		return button
	end

	card.Delete = CardButton("Delete", 54)
	card.Delete:SetPoint("TOPRIGHT", -4, -4)
	card.Delete:SetScript("OnEnter", function(self)
		local record = self:GetParent().record
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Delete this snapshot for good")
		if record and armedDelete == record.id then
			GameTooltip:AddLine("Click again to delete it. This cannot be undone.",
				1, 0.3, 0.3, true)
		else
			GameTooltip:AddLine("Click twice. It cannot be undone.",
				0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
	end)
	card.Delete:SetScript("OnClick", function(self)
		local record = self:GetParent().record
		if not record then return end
		if armedDelete ~= record.id then
			armedDelete = record.id
			LibraryCards.PaintAllControls()
			if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
			return
		end
		armedDelete = nil
		GameTooltip:Hide()
		Delete(record)
	end)

	card.Restore = CardButton("Restore", 58)
	card.Restore:SetPoint("RIGHT", card.Delete, "LEFT", -4, 0)
	card.Restore:SetBackdropBorderColor(1, 0.82, 0, 1)
	card.Restore:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Restore this snapshot")
		GameTooltip:AddLine("Puts it back on the wall and out of the archive.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	card.Restore:SetScript("OnClick", function(self)
		local record = self:GetParent().record
		local Store, library = ns.Library, Library()
		if not (record and Store and library) then return end
		armedDelete = nil
		GameTooltip:Hide()
		if Store.Restore(library, record.id) then
			ns.LibraryUI.Refresh()
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
			root:CreateButton("Delete", function() Delete(record) end)
		end)
	end)
end

-- Every control on every paint: a pooled card keeps whatever the last record
-- left on it otherwise.
local function PaintControls(card)
	local record = card.record
	local Store = ns.Library
	local controls = record and Store and Store.CardControls(record)
		or { archive = record ~= nil and record.source ~= "mine" }
	card.Archive:SetShown(controls.archive == true)
	card.Restore:SetShown(controls.restore == true)
	card.Delete:SetShown(controls.delete == true)
	local armed = controls.delete and armedDelete == record.id
	card.Delete.Text:SetText(armed and "Delete?" or "Delete")
	if armed then
		card.Delete:SetBackdropColor(0.6, 0, 0, 0.9)
		card.Delete:SetBackdropBorderColor(1, 0.3, 0.3, 1)
		card.Delete.Text:SetTextColor(1, 1, 1)
	else
		card.Delete:SetBackdropColor(0, 0, 0, 0.75)
		card.Delete:SetBackdropBorderColor(0.9, 0.2, 0.2, 1)
		card.Delete.Text:SetTextColor(1, 0.4, 0.4)
	end
end

function LibraryCards.PaintAllControls()
	if not (window and window.Box) then return end
	window.Box:ForEachFrame(function(card)
		if card.built then PaintControls(card) end
	end)
end

-- The grid view's element initializer.
function LibraryCards.Init(card, record)
	BuildCard(card)
	card.record = record
	PaintControls(card)
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
	Paint(card, record)
end

ns.LibraryCards = LibraryCards
return LibraryCards
