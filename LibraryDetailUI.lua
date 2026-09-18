local _, ns = ...

-- The pane that hangs off the library window and says what a look is made of.
--
-- One icon per slot, plus the mount and the title, with the detail in the
-- tooltip rather than on the face of it: a wall of names is unreadable and a
-- wall of icons is not.
--
-- It docks to a side of the library the way the outfit preview docks to the
-- mount picker: drag it and it snaps to whichever side and position you let go
-- nearest, and it stays attached from then on.
local LibraryDetailUI = {}

-- Laid out like the character sheet: a column of icons down each side of the
-- model, weapons underneath. Nobody has to learn where anything is.
local ICON = 36
local GAP = 4
local MARGIN = 10
local HEADER = 46
local MODEL_W = 156
local FOOTER = 12
local PANE_W = MARGIN * 2 + ICON * 2 + GAP * 2 + MODEL_W

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local EMPTY_ICON = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"

local pane
local dock = { side = "right", position = 0 }
local owner
local shown

-- Where the pane sits, given a side and how far along that side. Position runs
-- from 0 at the top or left to 1 at the bottom or right, so a pane dragged up
-- the side of the window stays where it was put.
local function ApplyDock()
	if not (pane and owner) then return end
	local side = dock.side
	local position = math.max(0, math.min(dock.position or 0, 1))
	local ownerW, ownerH = owner:GetSize()
	local paneW, paneH = pane:GetSize()

	pane:ClearAllPoints()
	if side == "left" or side == "right" then
		local span = math.max(0, ownerH - paneH)
		local offset = -position * span
		if side == "left" then
			pane:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, offset)
		else
			pane:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, offset)
		end
	else
		local span = math.max(0, ownerW - paneW)
		local offset = position * span
		if side == "top" then
			pane:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", offset, 4)
		else
			pane:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", offset, -4)
		end
	end
end

-- Snaps to whichever side of the library the pane was let go nearest, and
-- remembers how far along that side it was.
local function DockFromCursor()
	if not (pane and owner) then return end
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale

	local left, right = owner:GetLeft(), owner:GetRight()
	local bottom, top = owner:GetBottom(), owner:GetTop()
	if not (left and right and bottom and top) then return end

	local toLeft, toRight = math.abs(x - left), math.abs(x - right)
	local toBottom, toTop = math.abs(y - bottom), math.abs(y - top)
	local nearest = math.min(toLeft, toRight, toBottom, toTop)

	if nearest == toLeft then
		dock.side = "left"
	elseif nearest == toRight then
		dock.side = "right"
	elseif nearest == toTop then
		dock.side = "top"
	else
		dock.side = "bottom"
	end

	if dock.side == "left" or dock.side == "right" then
		local span = math.max(1, top - bottom)
		dock.position = math.max(0, math.min((top - y) / span, 1))
	else
		local span = math.max(1, right - left)
		dock.position = math.max(0, math.min((x - left) / span, 1))
	end
	ApplyDock()
end

-- What the client will say about one stored appearance. Returns icon, name and
-- the visual that many items share, because a source is one item and a visual
-- is the look that item and its twins all wear.
local function SourceDetail(sourceID)
	local collection = C_TransmogCollection
	if type(sourceID) ~= "number" or sourceID <= 0 or not collection then return nil end

	local link, name, icon, visualID, itemID
	if collection.GetSourceInfo then
		local ok, info = pcall(collection.GetSourceInfo, sourceID)
		if ok and type(info) == "table" then
			name, visualID, itemID = info.name, info.visualID, info.itemID
		end
	end
	if collection.GetAppearanceSourceInfo then
		local ok, info = pcall(collection.GetAppearanceSourceInfo, sourceID)
		if ok and type(info) == "table" then
			link = info.itemLink
			icon = info.icon
		end
	end
	if not icon and itemID and C_Item and C_Item.GetItemIconByID then
		local ok, fromItem = pcall(C_Item.GetItemIconByID, itemID)
		if ok then icon = fromItem end
	end
	return { icon = icon, name = name, link = link, visualID = visualID, itemID = itemID }
end

local function IllusionName(illusionID)
	local collection = C_TransmogCollection
	if type(illusionID) ~= "number" or illusionID <= 0 or not collection then return nil end
	if collection.GetIllusionInfo then
		local ok, info = pcall(collection.GetIllusionInfo, illusionID)
		if ok and type(info) == "table" then
			return info.name or info.sourceText
		end
	end
	return nil
end

local function SlotTooltip(button)
	local entry = button.entry
	if not entry then return end
	local Text = ns.LibraryText

	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(Text and Text.SlotName(entry.slot) or "Slot")
	if entry.empty then
		GameTooltip:AddLine("Nothing stored for this slot.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
		return
	end

	local detail = entry.detail
	if detail then
		GameTooltip:AddLine(detail.link or detail.name or "the client would not name it",
			1, 1, 1, true)
		if detail.itemID then
			GameTooltip:AddLine(("item %d"):format(detail.itemID), 0.6, 0.6, 0.6)
		end
		if detail.visualID then
			-- Worth saying out loud: many different items share one visual, so
			-- this number is the look and the one above is the thing that wears it.
			GameTooltip:AddLine(("appearance %d, shared by every item that looks like this")
				:format(detail.visualID), 0.6, 0.6, 0.6, true)
		end
	end
	if entry.illusion and entry.illusion > 0 then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine(("Enchant: %s"):format(
			IllusionName(entry.illusion) or ("illusion " .. entry.illusion)), 0.6, 0.9, 1)
	end
	if entry.secondary and entry.secondary > 0 and entry.secondary ~= entry.source then
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Shoulders are set apart; the other one differs.",
			0.6, 0.6, 0.6, true)
	end
	GameTooltip:Show()
end

local function ExtraTooltip(button)
	if not button.lines then return end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetText(button.heading or "")
	for _, line in ipairs(button.lines) do
		GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true)
	end
	GameTooltip:Show()
end

local function BuildIcon(parent, onEnter)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(ICON, ICON)
	button.Texture = button:CreateTexture(nil, "ARTWORK")
	button.Texture:SetAllPoints()
	button.Texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.Border = button:CreateTexture(nil, "OVERLAY")
	button.Border:SetColorTexture(0.3, 0.3, 0.3, 1)
	button.Border:SetAllPoints()
	button.Border:SetDrawLayer("BACKGROUND")
	button:SetScript("OnEnter", onEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

local function Ensure(library)
	if pane then return pane end
	owner = library

	pane = CreateFrame("Frame", "MogtrotLibraryDetail", library, "BackdropTemplate")
	pane:SetFrameStrata("DIALOG")
	pane:SetFrameLevel(library:GetFrameLevel() + 10)
	pane:SetBackdrop(BACKDROP)
	pane:SetBackdropColor(0, 0, 0, 0.94)
	pane:EnableMouse(true)
	pane:RegisterForDrag("LeftButton")
	pane:SetScript("OnDragStart", function(self)
		self.dragging = true
		self:SetScript("OnUpdate", function() DockFromCursor() end)
	end)
	pane:SetScript("OnDragStop", function(self)
		self.dragging = false
		self:SetScript("OnUpdate", nil)
		DockFromCursor()
	end)

	pane.Title = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	pane.Title:SetPoint("TOPLEFT", MARGIN, -12)
	pane.Title:SetPoint("TOPRIGHT", -MARGIN, -12)
	pane.Title:SetJustifyH("LEFT")
	pane.Title:SetWordWrap(false)

	pane.Sub = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pane.Sub:SetPoint("TOPLEFT", MARGIN, -28)
	pane.Sub:SetPoint("TOPRIGHT", -MARGIN, -28)
	pane.Sub:SetJustifyH("LEFT")
	pane.Sub:SetWordWrap(false)

	local Text = ns.LibraryText
	local columns = Text and Text.SLOT_COLUMNS or { left = {}, right = {}, bottom = {} }

	pane.Slots = {}
	local function Column(slots, anchorX)
		for index, slotID in ipairs(slots) do
			local button = BuildIcon(pane, SlotTooltip)
			button:SetPoint("TOPLEFT", anchorX, -(HEADER + (index - 1) * (ICON + GAP)))
			button.slotID = slotID
			pane.Slots[slotID] = button
		end
	end
	Column(columns.left, MARGIN)
	Column(columns.right, MARGIN + ICON + GAP + MODEL_W + GAP)

	local tallest = math.max(#columns.left, #columns.right)
	local columnBottom = HEADER + tallest * (ICON + GAP)

	-- The model stands between the columns, as it does on the character sheet.
	-- It is not built here: the wall lends the pane the body it is already
	-- showing, so the two can never be two different people.
	pane.ModelSlot = CreateFrame("Frame", nil, pane)
	pane.ModelSlot:SetPoint("TOPLEFT", MARGIN + ICON + GAP, -HEADER)
	pane.ModelSlot:SetSize(MODEL_W, columnBottom - HEADER - GAP)

	-- Used when the body needs nothing borrowed, so building one here cannot
	-- disagree with the card: both come from your own unit.
	pane.OwnScene = CreateFrame("ModelScene", nil, pane.ModelSlot,
		"ModelSceneMixinTemplate")
	pane.OwnScene:SetAllPoints()
	pane.OwnScene:EnableMouse(false)
	pane.OwnScene:EnableMouseWheel(false)
	pane.OwnScene:Hide()

	pane.NoModel = pane.ModelSlot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	pane.NoModel:SetPoint("CENTER")
	pane.NoModel:SetWidth(MODEL_W - 8)
	pane.NoModel:SetJustifyH("CENTER")
	pane.NoModel:SetWordWrap(true)

	-- Weapons underneath the model, centred, the way they hang below a
	-- character sheet.
	local weapons = columns.bottom
	local weaponsWidth = #weapons * ICON + math.max(0, #weapons - 1) * GAP
	local weaponsLeft = (PANE_W - weaponsWidth) / 2
	for index, slotID in ipairs(weapons) do
		local button = BuildIcon(pane, SlotTooltip)
		button:SetPoint("TOPLEFT", weaponsLeft + (index - 1) * (ICON + GAP),
			-columnBottom)
		button.slotID = slotID
		pane.Slots[slotID] = button
	end

	local extrasTop = columnBottom + ICON + GAP

	pane.Mount = BuildIcon(pane, ExtraTooltip)
	pane.Mount:SetPoint("TOPLEFT", MARGIN, -extrasTop)
	pane.Title2 = BuildIcon(pane, ExtraTooltip)
	pane.Title2:SetPoint("TOPLEFT", MARGIN + ICON + GAP, -extrasTop)

	pane:SetSize(PANE_W, extrasTop + ICON + FOOTER)
	pane:Hide()
	ApplyDock()
	return pane
end

-- Fills the pane from a record. Everything it shows is read here rather than
-- in the tooltip, so hovering never has to hit the client.
function LibraryDetailUI.Show(library, record)
	local frame = Ensure(library)
	local Text = ns.LibraryText
	local codec = ns.LookCodec
	if not (Text and codec and record) then return end

	shown = record
	frame.Title:SetText(Text.Title(record))
	frame.Sub:SetText(Text.Subtitle(record))

	local look = codec.Decode(record.look) or {}
	for slotID, button in pairs(frame.Slots) do
		local entry = look[slotID]
		local source = entry and entry[1] or 0
		if source and source > 0 then
			local detail = SourceDetail(source)
			button.entry = {
				slot = slotID, source = source,
				secondary = entry[2], illusion = entry[3], detail = detail,
			}
			button.Texture:SetTexture(detail and detail.icon or EMPTY_ICON)
			button.Texture:SetDesaturated(false)
			button:Show()
		else
			button.entry = { slot = slotID, empty = true }
			button.Texture:SetTexture(EMPTY_ICON)
			button.Texture:SetDesaturated(true)
			button:Show()
		end
	end

	local journal = C_MountJournal
	if record.mount and journal and journal.GetMountInfoByID then
		local ok, name, _spell, icon = pcall(journal.GetMountInfoByID, record.mount)
		frame.Mount.Texture:SetTexture(ok and icon or EMPTY_ICON)
		frame.Mount.Texture:SetDesaturated(false)
		frame.Mount.heading = "Mount"
		frame.Mount.lines = { ok and tostring(name) or ("mount " .. record.mount) }
	else
		frame.Mount.Texture:SetTexture(EMPTY_ICON)
		frame.Mount.Texture:SetDesaturated(true)
		frame.Mount.heading = "Mount"
		frame.Mount.lines = { "They were on foot." }
	end

	frame.Title2.heading = "Title"
	if record.title then
		frame.Title2.Texture:SetTexture("Interface\\Icons\\INV_Scroll_11")
		frame.Title2.Texture:SetDesaturated(false)
		frame.Title2.lines = { record.title }
	else
		frame.Title2.Texture:SetTexture(EMPTY_ICON)
		frame.Title2.Texture:SetDesaturated(true)
		frame.Title2.lines = { "No title was showing." }
	end

	-- Borrow the body the wall built. Rebuilding one here would borrow from
	-- whoever happens to be standing about now, and once the original donor has
	-- gone that is a different face wearing the same clothes.
	local ui = ns.LibraryUI
	local inset = { left = 0, right = 0, top = 0, bottom = 0 }

	-- A twin first: that is the only way to match a body borrowed from a
	-- stranger. Failing that, build one here, but only when doing so cannot
	-- disagree with the card.
	local shownBody = ui and ui.PaneBody and ui.PaneBody(record, frame.ModelSlot, inset)
	if shownBody then
		frame.OwnScene:Hide()
	else
		if ui and ui.ReturnPaneBody then ui.ReturnPaneBody() end
		if ui and ui.BodyIsDeterministic and ui.BodyIsDeterministic(record)
			and ui.RenderInto then
			local how = select(2, ui.RenderInto(frame.OwnScene, record))
			shownBody = how ~= nil
			frame.OwnScene:SetShown(shownBody and true or false)
		else
			frame.OwnScene:Hide()
		end
	end

	frame.NoModel:SetText(shownBody and ""
		or "No body has been built for this look yet. Point at somebody of the"
			.. " other sex and it will appear here.")

	ApplyDock()
	frame:Show()
	return frame
end

function LibraryDetailUI.Hide()
	if ns.LibraryUI and ns.LibraryUI.ReturnPaneBody then
		ns.LibraryUI.ReturnPaneBody()
	end
	if pane then pane:Hide() end
	shown = nil
end

function LibraryDetailUI.Shown()
	return shown
end

-- Called when the library moves or resizes, so the pane follows it.
function LibraryDetailUI.Reanchor()
	ApplyDock()
end

ns.LibraryDetailUI = LibraryDetailUI
return LibraryDetailUI
