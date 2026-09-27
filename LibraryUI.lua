local _, ns = ...

-- The library window: every stored look, four to a row, each on a body of its
-- own race. This file is the window, its header, filters and status line;
-- LibraryCards draws each card and LibraryBodies lends the bodies.
--
-- Snapshots and your own outfits and custom sets are two exclusive walls,
-- switched from the header sentence.
--
-- The grid is Blizzard's scroll box, the same one the mount picker uses, so
-- the wheel and the bar behave here the way they do there.
local LibraryUI = {}

local Bodies, Cards = ns.LibraryBodies, ns.LibraryCards
local Library = Cards.Library

local COLS = 4
local CARD_W, CARD_H = Bodies.CARD_W, Bodies.CARD_H
local GAP, MARGIN = 10, 14
local HEADER, FOOTER = 88, 12
local BAR_GUTTER, BAR_GAP = 14, 6
local ROWS_SHOWN = 2
local LIBRARY_STRATA = "DIALOG"

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Shared with the snap pop-up, which is drawn the same way.
LibraryUI.BACKDROP = BACKDROP

local window

-- The whole filter state: mode, owners, sources, races, classes, armour and
-- the archive switch.
local raceFilter
local nameQuery

local function Records()
	local Store = ns.Library
	local library = Library()
	if not library or type(Store) ~= "table" then return {} end
	return Store.Sorted(library)
end

-- What the wall draws from: the archive when the Archived switch is on,
-- otherwise the records.
local function WallRecords()
	local Store, Filter, library = ns.Library, ns.LibraryFilter, Library()
	if library and Store and Store.Archived and Filter
		and Filter.ShowsArchived(raceFilter) then
		return Store.Archived(library)
	end
	return Records()
end

-- The records the wall shows under the current search and filters.
local function WallList(allRecords)
	local Filter = ns.LibraryFilter
	local searched = {}
	for _, record in ipairs(allRecords) do
		if not Filter or Filter.NameMatches(record, nameQuery) then
			searched[#searched + 1] = record
		end
	end
	return Filter and Filter.Apply(searched, raceFilter) or searched
end

-- The character list is the longest filter here and the only one worth typing
-- at, so it gets the shared search-select window instead of a submenu.
local function OpenCharacterPicker()
	local Filter = ns.LibraryFilter
	if not (Filter and raceFilter and ns.OpenSearchPicker) then return end

	local items = {}
	for _, entry in ipairs(Filter.OwnerEntries(Records())) do
		local label = entry.name
		if entry.realm and entry.realm ~= "" then
			label = label .. "-" .. entry.realm
		end
		items[#items + 1] = {
			name = label,
			guid = entry.guid,
			iconAtlas = Cards.ClassAtlas(entry.classID),
			nameColor = Cards.ClassRGB(entry.classID),
			preselected = Filter.IsOwnerSelected(raceFilter, entry.guid),
		}
	end

	ns.OpenSearchPicker({
		strata = LIBRARY_STRATA,
		title = "Characters",
		searchHint = "Search character name",
		emptyText = "No character here owns an outfit or a custom set yet.",
		items = items,
		multi = true,
		bulkSelect = true,
		buttons = { {
			text = "Show",
			width = 90,
			allowEmpty = true,
			tipTitle = "Show these characters",
			tipBody = "Only the ticked characters' outfits and custom sets appear.",
			onClick = function(chosen)
				-- Everyone ticked means "all", not "these five": a character who
				-- logs in later should arrive shown rather than hidden.
				if #chosen == #items then
					Filter.SelectAllOwners(raceFilter)
				else
					Filter.SelectNoOwners(raceFilter)
					for _, item in ipairs(chosen) do
						Filter.SetOwner(raceFilter, item.guid, true)
					end
				end
				LibraryUI.Refresh()
			end,
		} },
	})
end

-- What the switch in the header sentence does. How it looks is
-- PairingHeaderUI's, and what it says is PairingHeader's. It names the wall it
-- takes you to, so a click goes straight there.
local function HeaderAction(action)
	if action ~= "libraryMode" then return end
	local Filter = ns.LibraryFilter
	if not (Filter and raceFilter) then return end
	local current = Filter.IsSnapshotMode(raceFilter) and "snapshots" or "mine"
	Filter.SetMode(raceFilter, ns.PairingHeader.OtherLibraryMode(current))
	LibraryUI.Refresh()
end

local SWITCH_H = 22

-- The two control rows, stacked against the close button and sharing a
-- left edge, so "Show:" and "Zoom:" line up and what follows each of them
-- starts in the same place. The rows are laid out left to right from that
-- edge and their right edges are ragged; the width is what the Show row
-- needs at its longest, so neither row can reach the close button.
local CONTROLS_W = 322
local LABEL_W = 46
local ZOOM_H = 16

-- A boxed button in the header, the same shape as the mount picker's mode
-- switch. The height and the font are arguments because the zoom row is
-- deliberately smaller than the row above it.
local function BuildSwitch(parent, label, width, height, font)
	local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
	button:SetSize(width, height or SWITCH_H)
	button:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	button.Text = button:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
	button.Text:SetPoint("CENTER")
	button.Text:SetText(label)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

-- The frame itself, its close button, the snap handle, the header sentence,
-- the status line and the flash that briefly replaces it.
local function BuildFrame()
	window = CreateFrame("Frame", "MogtrotLibrary", UIParent, "BackdropTemplate")
	Cards.Attach(window)
	window:SetSize(MARGIN * 2 + CARD_W * COLS + GAP * (COLS - 1) + BAR_GUTTER,
		HEADER + CARD_H * ROWS_SHOWN + GAP * (ROWS_SHOWN - 1) + MARGIN + FOOTER)
	window:SetPoint("CENTER")
	window:SetFrameStrata(LIBRARY_STRATA)
	window:SetToplevel(true)
	window:SetFlattensRenderLayers(true)
	window:SetIsFrameBuffer(true)
	window:SetClampedToScreen(true)
	window:SetMovable(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
	end)
	window:SetBackdrop(BACKDROP)
	window:SetBackdropColor(0, 0, 0, 0.94)

	window.Close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	window.Close:SetPoint("TOPRIGHT", -4, -4)

	local Addon, Macro = ns.Addon, ns.Macro
	if Addon and Addon.CreateMacroDrag and Macro then
		window.SnapDrag = Addon:CreateMacroDrag(window, Macro.SNAP,
			"Capture macro for the action bar",
			"Drag to a bar. Makes one general macro that captures your target's look,"
				.. " and reuses that same macro every time after.")
	end

	-- The header is one sentence and the word that can change is its control,
	-- so there is no window title and no tabs: "Showing my characters - 50 of
	-- 247 looks" is both. Laid out from PairingHeader's segments, the same as
	-- the pairing windows'.
	window.HeaderRow = CreateFrame("Frame", nil, window)
	window.HeaderRow:SetPoint("TOPLEFT", MARGIN + 2, -12)
	window.HeaderRow:SetHeight(SWITCH_H)
	window.PaintHeader = ns.PairingHeaderUI.New(window.HeaderRow, SWITCH_H,
		HeaderAction, ns.PairingHeader.LibrarySegments)

	window.Status = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	window.Status:SetPoint("TOPLEFT", MARGIN + 2, -68)
	window.Status:SetJustifyH("LEFT")

	-- A brief note in the status line's place, then the status line again.
	window.Flash = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	window.Flash:SetPoint("LEFT", window.Status, "LEFT")
	window.Flash:SetJustifyH("LEFT")
	window.Flash:Hide()
	window.FlashFade = window.Flash:CreateAnimationGroup()
	local fade = window.FlashFade:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0)
	fade:SetStartDelay(4)
	fade:SetDuration(1)
	local function EndFlash()
		window.Flash:Hide()
		window.Status:Show()
	end
	window.FlashFade:SetScript("OnFinished", EndFlash)
	window.FlashFade:SetScript("OnStop", EndFlash)
	window:HookScript("OnHide", function()
		Cards.Disarm()
		window.FlashFade:Stop()
	end)
end

-- The search box, the filter dropdown and its menu.
local function BuildFilters(Filter)
	window.Search = CreateFrame("EditBox", nil, window, "SearchBoxTemplate")
	window.Search:SetSize(250, 20)
	window.Search:SetAutoFocus(false)
	window.Search:SetPoint("TOPLEFT", MARGIN + 2, -40)
	if window.Search.Instructions then
		window.Search.Instructions:SetText("Search character name")
	end
	window.Search:HookScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or "")
		nameQuery = text ~= "" and text or nil
		LibraryUI.Refresh()
	end)

	raceFilter = Filter and Filter.New() or nil
	window.FilterDropdown = CreateFrame("DropdownButton", nil, window,
		"WowStyle1FilterDropdownTemplate")
	window.FilterDropdown:SetPoint("LEFT", window.Search, "RIGHT", 14, 0)
	window.FilterDropdown:SetScript("OnEnter", function(self)
		if self:IsMenuOpen() then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Filters")
		GameTooltip:AddLine(self.mogtrotStatus
			or "Race: All | Class: All | Armor: All",
			0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	window.FilterDropdown:SetScript("OnLeave", GameTooltip_Hide)
	window.FilterDropdown:HookScript("OnMouseDown", function()
		GameTooltip:Hide()
	end)
	window.FilterDropdown:SetupMenu(function(_dropdown, root)
		if not (Filter and raceFilter) then return end
		local records = WallRecords()
		local races = Filter.Races(records)
		local classes = Filter.Classes(records)
		local function Changed()
			LibraryUI.Refresh()
			return MenuResponse.Refresh
		end
		root:CreateButton(CHECK_ALL or "Check All", function()
			Filter.SelectAllFilters(raceFilter)
			return Changed()
		end)
		root:CreateButton(UNCHECK_ALL or "Uncheck All", function()
			Filter.SelectNoFilters(raceFilter)
			return Changed()
		end)
		root:CreateDivider()

		-- The menu answers whichever question the mode is asking. Race, class
		-- and armour narrow a crowd of strangers; on your own characters the
		-- character list has already narrowed all three.
		if not Filter.IsSnapshotMode(raceFilter) then
			root:CreateTitle("Show:")
			for _, entry in ipairs({ { "outfits", "Outfits" },
				{ "customSets", "Custom sets" } }) do
				local source, label = entry[1], entry[2]
				root:CreateCheckbox(label, function()
					return Filter.IsSourceSelected(raceFilter, source)
				end, function()
					Filter.SetSource(raceFilter, source,
						not Filter.IsSourceSelected(raceFilter, source))
					return Changed()
				end)
			end
			root:CreateDivider()
			root:CreateCheckbox("Hide outfits with nothing set", function()
				return Filter.HidesEmptyOutfits(raceFilter)
			end, function()
				Filter.SetHideEmptyOutfits(raceFilter,
					not Filter.HidesEmptyOutfits(raceFilter))
				return Changed()
			end)
			return
		end

		local raceMenu = root:CreateButton("Race")
		raceMenu:CreateButton(CHECK_ALL or "All", function()
			Filter.SelectAll(raceFilter)
			return Changed()
		end)
		raceMenu:CreateButton(UNCHECK_ALL or "None", function()
			Filter.SelectNone(raceFilter)
			return Changed()
		end)
		raceMenu:CreateDivider()
		for _, raceID in ipairs(races) do
			local id = raceID
			local info = C_CreatureInfo and C_CreatureInfo.GetRaceInfo
				and C_CreatureInfo.GetRaceInfo(id)
			local label = info and info.raceName or ("Race " .. id)
			raceMenu:CreateCheckbox(label, function()
				return Filter.IsRaceSelected(raceFilter, id)
			end, function()
				Filter.SetRace(raceFilter, id,
					not Filter.IsRaceSelected(raceFilter, id))
				return Changed()
			end)
		end
		local classMenu = root:CreateButton("Class")
		classMenu:CreateButton(CHECK_ALL or "All", function()
			Filter.SelectAllClasses(raceFilter)
			return Changed()
		end)
		classMenu:CreateButton(UNCHECK_ALL or "None", function()
			Filter.SelectNoClasses(raceFilter)
			return Changed()
		end)
		classMenu:CreateDivider()
		for _, classID in ipairs(classes) do
			local id = classID
			local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo
				and C_CreatureInfo.GetClassInfo(id)
			local label = info and info.className or ("Class " .. id)
			classMenu:CreateCheckbox(label, function()
				return Filter.IsClassSelected(raceFilter, id)
			end, function()
				Filter.SetClass(raceFilter, id,
					not Filter.IsClassSelected(raceFilter, id))
				return Changed()
			end)
		end
		local armorMenu = root:CreateButton("Armor type")
		armorMenu:CreateButton(CHECK_ALL or "All", function()
			Filter.SelectAllArmorTypes(raceFilter)
			return Changed()
		end)
		armorMenu:CreateButton(UNCHECK_ALL or "None", function()
			Filter.SelectNoArmorTypes(raceFilter)
			return Changed()
		end)
		armorMenu:CreateDivider()
		for _, armorType in ipairs(Filter.ARMOR_TYPES) do
			local label = armorType
			armorMenu:CreateCheckbox(label, function()
				return Filter.IsArmorTypeSelected(raceFilter, label)
			end, function()
				Filter.SetArmorType(raceFilter, label,
					not Filter.IsArmorTypeSelected(raceFilter, label))
				return Changed()
			end)
		end
	end)
	if window.SnapDrag then
		window.SnapDrag:ClearAllPoints()
		window.SnapDrag:SetPoint("LEFT", window.CharacterButton, "RIGHT", 12, 0)
	end
end

local function BuildCharacterButton()
	window.CharacterButton = BuildSwitch(window, "Characters: All", 150)
	window.CharacterButton:SetPoint("LEFT", window.FilterDropdown, "RIGHT", 8, 0)
	window.CharacterButton:SetBackdropBorderColor(1, 0.82, 0, 1)
	window.CharacterButton.Text:SetTextColor(1, 0.82, 0)
	window.CharacterButton:SetScript("OnClick", OpenCharacterPicker)
	window.CharacterButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Characters")
		GameTooltip:AddLine("Whose outfits and custom sets the library shows.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
end

-- The frames of the Show and Zoom rows, then the Show row's controls: the
-- body word and the Archived switch.
local function BuildShowRow(Filter)
	window.ShowRow = CreateFrame("Frame", nil, window)
	window.ShowRow:SetSize(CONTROLS_W, SWITCH_H)
	window.ShowRow:SetPoint("TOPRIGHT", window.Close, "TOPLEFT", -6, -8)

	window.ZoomRow = CreateFrame("Frame", nil, window)
	window.ZoomRow:SetSize(CONTROLS_W, ZOOM_H)
	window.ZoomRow:SetPoint("TOPLEFT", window.ShowRow, "BOTTOMLEFT", 0, -6)

	window.ShowLabel = window.ShowRow:CreateFontString(nil, "OVERLAY",
		"GameFontNormal")
	window.ShowLabel:SetPoint("LEFT")
	window.ShowLabel:SetText("Show:")

	-- Whose body a look stands on, as the same dropdown word the sentence
	-- above uses for the wall. What it sets is what you asked for, not what is
	-- on screen: original race is granted the moment the last body has been
	-- borrowed, and until then the line under the wall says so.
	window.Body = ns.PairingHeaderUI.Word(window.ShowRow, SWITCH_H, "body",
		function(value)
			Bodies.SetViewMode(ns.PairingHeader.Body(value))
			LibraryUI.Refresh()
		end)
	window.Body:SetPoint("LEFT", window.ShowLabel, "LEFT", LABEL_W, 0)

	-- Only on the snapshot wall: the archive holds nothing else. On, the wall
	-- is the archive instead of the records.
	window.Archived = BuildSwitch(window.ShowRow, "Archived", 76)
	window.Archived:SetPoint("LEFT", window.Body, "RIGHT", 6, 0)
	window.Archived:SetScript("OnClick", function(self)
		if not (Filter and raceFilter) then return end
		local on = Filter.ShowsArchived(raceFilter)
		if not on and not window.anyArchived then return end
		Filter.SetArchived(raceFilter, not on)
		Cards.Disarm()
		window.FlashFade:Stop()
		LibraryUI.Refresh()
		window.Box:ScrollToBegin()
		if GameTooltip:IsOwned(self) then self:GetScript("OnEnter")(self) end
	end)
	window.Archived:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Archived snapshots")
		if Filter and Filter.ShowsArchived(raceFilter) then
			GameTooltip:AddLine("Showing only the snapshots you archived. Restore"
				.. " puts one back on the wall; Delete removes it for good.",
				0.6, 0.6, 0.6, true)
			GameTooltip:AddLine("Click to go back to the wall.", 0.9, 0.9, 0.9, true)
		elseif window.anyArchived then
			GameTooltip:AddLine("Show only the snapshots you archived, to restore"
				.. " or delete them.", 0.6, 0.6, 0.6, true)
		else
			GameTooltip:AddLine("Nothing archived.", 1, 0.3, 0.3)
			GameTooltip:AddLine("The X on a snapshot archives it.",
				0.9, 0.9, 0.9, true)
		end
		local days = type(MogtrotDB) == "table" and tonumber(MogtrotDB.archiveDays)
		if days and days > 0 then
			GameTooltip:AddLine(("Archived snapshots are dropped after %d days.")
				:format(days), 0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
	end)
end

-- Zoom, on its own row under the Show row and smaller than it: this is a
-- nudge, not a mode, and at the same weight it read as a third thing you
-- choose between. Dragging a card up and down does the same, but a drag is
-- invisible until somebody tries it, and it cannot offer the way back: the
-- readout is that, and says how far from its normal framing the wall has
-- been taken.
local function BuildZoomButton(label, width, steps)
	local button = BuildSwitch(window.ZoomRow, label, width, ZOOM_H,
		"GameFontNormalSmall")
	button:SetBackdropBorderColor(1, 0.82, 0, 1)
	button.Text:SetTextColor(1, 0.82, 0)
	button:SetScript("OnClick", function()
		local Zooms = ns.LibraryZoom
		if not Zooms then return end
		Cards.SetZoom(Zooms.Step(Cards.Zoom(), steps))
	end)
	return button
end

local function BuildZoomRow()
	window.ZoomLabel = window.ZoomRow:CreateFontString(nil, "OVERLAY",
		"GameFontNormal")
	window.ZoomLabel:SetPoint("LEFT")
	window.ZoomLabel:SetText("Zoom:")

	window.ZoomOut = BuildZoomButton("-", 18, -1)
	window.ZoomOut:SetPoint("LEFT", window.ZoomLabel, "LEFT", LABEL_W, 0)
	window.ZoomOut:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Zoom out")
		GameTooltip:AddLine("Every model a step further away. Dragging a card"
			.. " down does the same.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)

	window.ZoomLevel = BuildSwitch(window.ZoomRow, "", 44, ZOOM_H,
		"GameFontNormalSmall")
	window.ZoomLevel:SetPoint("LEFT", window.ZoomOut, "RIGHT", 4, 0)
	window.ZoomLevel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
	window.ZoomLevel.Text:SetTextColor(0.7, 0.7, 0.7)
	window.ZoomLevel:SetScript("OnClick", function()
		Cards.SetZoom(Cards.DEFAULT_ZOOM)
	end)
	window.ZoomLevel:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Zoom")
		GameTooltip:AddLine("How close the wall is against the way a card is"
			.. " normally framed. Kept until you change it.", 0.6, 0.6, 0.6, true)
		GameTooltip:AddLine("Click to put it back.", 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)

	window.ZoomIn = BuildZoomButton("+", 18, 1)
	window.ZoomIn:SetPoint("LEFT", window.ZoomLevel, "RIGHT", 4, 0)
	window.ZoomIn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Zoom in")
		GameTooltip:AddLine("Every model a step closer. Dragging a card up"
			.. " does the same.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
end

-- The grid of cards and its scrollbar.
local function BuildBox()
	window.Box = CreateFrame("Frame", nil, window, "WowScrollBoxList")
	window.Box:SetPoint("TOPLEFT", MARGIN, -HEADER)
	window.Box:SetPoint("BOTTOMRIGHT", -(MARGIN + BAR_GUTTER), FOOTER)

	window.Bar = CreateFrame("EventFrame", nil, window, "MinimalScrollBar")
	window.Bar:SetPoint("TOPLEFT", window.Box, "TOPRIGHT", BAR_GAP, 0)
	window.Bar:SetPoint("BOTTOMLEFT", window.Box, "BOTTOMRIGHT", BAR_GAP, 0)

	window.View = CreateScrollBoxListGridView(COLS, 0, 0, 0, 0, GAP, GAP)
	window.View:SetElementSize(CARD_W, CARD_H)
	-- A wheel notch moves a whole row.
	window.View:SetPanExtent(CARD_H + GAP)
	window.View:SetElementInitializer("Button", Cards.Init)
	-- A recycled card hands its body back rather than taking it out of
	-- circulation, so the next card that wants that body finds it waiting.
	window.View:SetElementResetter(function(card)
		Bodies.Release(card)
	end)

	ScrollUtil.InitScrollBoxListWithScrollBar(window.Box, window.Bar, window.View)
	window.BarVisibility = ScrollUtil.AddManagedScrollBarVisibilityBehavior(
		window.Box, window.Bar)

	window:EnableMouseWheel(true)
	window:SetScript("OnMouseWheel", function(_self, delta)
		window.Box:OnMouseWheel(delta)
	end)
end

local function Ensure()
	if window then return window end

	local Filter = ns.LibraryFilter
	BuildFrame()
	BuildFilters(Filter)
	BuildCharacterButton()
	BuildShowRow(Filter)
	BuildZoomRow()
	BuildBox()

	-- The sentence shares its row with the Show controls, so it ends where
	-- they begin. Against the rows rather than the first word in them, so the
	-- sentence keeps its room whatever the Show row happens to read.
	window.HeaderRow:SetPoint("RIGHT", window.ShowRow, "LEFT", -10, 0)

	tinsert(UISpecialFrames, "MogtrotLibrary")
	window:Hide()
	return window
end

-- The WarmBody calls one donor's ingest makes, in order, as { record, want }:
-- one body per card on the wall, since a card will not stand in a body
-- another card holds and the donor may be gone by the time it is drawn, then
-- one of every other shape, for the walls not showing. Records of your own
-- sex are left out; WarmBody would skip them.
function LibraryUI.WarmPlan()
	local body = ns.RaceBody
	if not (ns.Library and body) then return {} end
	local mine = UnitSex and UnitSex("player") or nil
	local plan, nth = {}, {}
	local function Other(record)
		return type(record) == "table" and record.look ~= "" and record.sex ~= nil
			and record.sex ~= mine
	end
	for _, record in ipairs(WallList(WallRecords())) do
		local ideal = Bodies.IdealBodyKey(record, body)
		if ideal then
			nth[ideal] = (nth[ideal] or 0) + 1
			if Other(record) then plan[#plan + 1] = { record = record, want = nth[ideal] } end
		end
	end
	for _, record in ipairs(WallRecords()) do
		if Other(record) then plan[#plan + 1] = { record = record, want = 1 } end
	end
	return plan
end

-- A burst of unit events would otherwise repaint the wall several times in a
-- frame, and every repaint undresses and redresses every model, which reads as
-- the cards flickering.
local refreshPending = false

function LibraryUI.Soon()
	if refreshPending then return end
	refreshPending = true
	C_Timer.After(0.1, function()
		refreshPending = false
		LibraryUI.Refresh()
	end)
end

-- Bodies are borrowed only from donors DonorWatchUI takes in passing.
local watcher = CreateFrame("Frame", "MogtrotBodyWatcher")

-- Changing form changes the body every card is standing on while the wall
-- is showing you, so the wall follows you into and out of it.
watcher:RegisterUnitEvent("UNIT_MODEL_CHANGED", "player")
watcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
watcher:SetScript("OnEvent", function()
	-- Borrowed bodies are somebody else's and are kept; only the ones built
	-- from you are rebuilt.
	if window ~= nil and window:IsShown() then LibraryUI.Soon() end
end)

function LibraryUI.Refresh()
	if not window or not window:IsShown() then return end

	local allRecords = WallRecords()
	local Filter = ns.LibraryFilter
	local list = WallList(allRecords)
	-- On your own characters the wall opens where you are, in the order your
	-- own outfit list already uses. Snapshot mode is other people, so there
	-- is no "current character" to lead with and the recency order stands.
	if Filter and not Filter.IsSnapshotMode(raceFilter) then
		local rank
		local tree = ns.Tree
		if tree and type(MogtrotCharDB) == "table" then
			rank = {}
			for position, choice in ipairs(
				tree.OutfitChoices(MogtrotCharDB, ns.Addon and ns.Addon.outfitsByID)) do
				rank[choice.outfitID] = position
			end
		end
		list = Filter.Order(list, UnitGUID and UnitGUID("player") or nil, rank)
	end
	if Filter and window.FilterDropdown then
		local races = Filter.Races(allRecords)
		local classes = Filter.Classes(allRecords)
		local owners = Filter.Owners(allRecords)
		local raceLabel = Filter.Label(Filter.SelectionCount(raceFilter, races), #races)
		local classLabel = Filter.Label(Filter.ClassSelectionCount(raceFilter, classes),
			#classes)
		local armorLabel = Filter.Label(Filter.ArmorSelectionCount(raceFilter),
			#Filter.ARMOR_TYPES)
		local ownerLabel = Filter.Label(Filter.OwnerSelectionCount(raceFilter, owners),
			#owners)
		local sourceLabel = Filter.Label(Filter.SourceSelectionCount(raceFilter),
			#Filter.SOURCES())
		local addon = ns.Addon
		local sync = addon and addon.OutfitLibrarySyncState
			and addon.OutfitLibrarySyncState()
		local customSync = addon and addon.CustomSetLibrarySyncState
			and addon.CustomSetLibrarySyncState()
		local missing = sync and sync.missing or 0
		local customMissing = customSync and customSync.missing or 0
		-- Each mode reports only the filters it actually applies, so a line
		-- saying "Race: All" can never be read as a filter that did nothing.
		if Filter.IsSnapshotMode(raceFilter) then
			window.FilterDropdown.mogtrotStatus =
				("Race: %s | Class: %s | Armor: %s"):format(raceLabel, classLabel,
					armorLabel)
		else
			local notCaptured = missing + customMissing
			window.FilterDropdown.mogtrotStatus =
				("Show: %s | Character: %s"):format(sourceLabel, ownerLabel)
				.. (notCaptured > 0 and (" | %d not captured yet"):format(notCaptured) or "")
		end
		if window.CharacterButton then
			window.CharacterButton.Text:SetText(("Characters: %s"):format(ownerLabel))
		end
	end
	-- The wall stays apples to apples on the forgiving count; the honest one
	-- says how many cards still show text.
	local waiting, unbuilt = Bodies.Missing(list)
	local watch = ns.DonorWatchUI
	local offered = watch ~= nil and watch.Offered()
	local fullFidelity = waiting == 0 and offered
	Bodies.SetFullFidelity(fullFidelity)
	local viewMode = Bodies.ViewMode()

	Cards.ShowZoom()

	local snapshotMode = not Filter or Filter.IsSnapshotMode(raceFilter)
	local showsArchived = Filter and Filter.ShowsArchived(raceFilter) or false

	-- Three looks: on, off, and nothing to show.
	local library = Library()
	window.anyArchived = library ~= nil and type(library.archive) == "table"
		and #library.archive > 0
	window.Archived:SetShown(snapshotMode)
	window.Archived:SetEnabled(showsArchived or window.anyArchived)
	if showsArchived then
		window.Archived:SetBackdropBorderColor(1, 0.82, 0, 1)
		window.Archived.Text:SetTextColor(1, 0.82, 0)
	elseif not window.anyArchived then
		window.Archived:SetBackdropBorderColor(0.4, 0.3, 0.3, 1)
		window.Archived.Text:SetTextColor(0.5, 0.45, 0.45)
	else
		window.Archived:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
		window.Archived.Text:SetTextColor(0.7, 0.7, 0.7)
	end
	-- The sentence says which wall you are on and how much of it is showing;
	-- the line under it says why that is not all of it.
	window.PaintHeader({
		mode = snapshotMode and "snapshots" or "mine",
		shown = #list,
		total = Filter and Filter.ModeCount(allRecords, raceFilter) or #allRecords,
		archived = showsArchived,
	})

	-- Only one mode has characters to choose between, and the box searches a
	-- different thing in each.
	if window.CharacterButton then
		window.CharacterButton:SetShown(not snapshotMode)
		-- A hidden frame keeps its place, so whatever sits after it has to be
		-- re-anchored or it leaves a hole.
		if window.SnapDrag then
			window.SnapDrag:ClearAllPoints()
			window.SnapDrag:SetPoint("LEFT", snapshotMode and window.FilterDropdown
				or window.CharacterButton, "RIGHT", 12, 0)
		end
	end
	if window.Search.Instructions then
		window.Search.Instructions:SetText(snapshotMode
			and "Search character name" or "Search set name")
	end

	-- What is on the wall, as opposed to what was asked for.
	local showing = fullFidelity and viewMode == "original"

	-- The word says what you asked for, and is shown only once original race
	-- is known to draw every look; until then the line under the wall says
	-- what is missing, and the wall turns over by itself when it arrives.
	window.Body:Say(viewMode)
	window.Body:SetShown(fullFidelity)
	window.Archived:ClearAllPoints()
	window.Archived:SetPoint("LEFT", window.Body, fullFidelity and "RIGHT" or "LEFT",
		fullFidelity and 6 or 0, 0)
	window.ShowRow:SetShown(fullFidelity or window.Archived:IsShown())

	window.Box:SetDataProvider(CreateDataProvider(list),
		ScrollBoxConstants.RetainScrollPosition)

	window.statusParts = { list = #list, all = #allRecords, showsArchived = showsArchived,
		showing = showing, unbuilt = unbuilt }
	LibraryUI.PaintStatus()
end

-- The line under the header. The count is in the sentence above, so this
-- line is only the filters and which body the looks are on. Repainted alone
-- when only the background checks moved on, since a Refresh redresses every
-- card.
function LibraryUI.PaintStatus()
	if not (window and window:IsShown() and window.statusParts) then return end
	local parts = window.statusParts
	local filterStatus = window.FilterDropdown
		and window.FilterDropdown.mogtrotStatus
		or "Race: All | Class: All | Armor: All"
	local hint = "Right-click a card for options; drag to turn them all."
	if parts.list == 0 then
		if parts.all == 0 and parts.showsArchived then
			window.Status:SetText("Nothing archived")
		elseif parts.all == 0 then
			window.Status:SetText("Nothing captured yet: target someone and type /mogtrot snap")
		else
			window.Status:SetText(filterStatus)
		end
	elseif parts.showing and parts.unbuilt > 0 then
		window.Status:SetText(("%s | %d %s for someone of the other sex to pass by.")
			:format(filterStatus, parts.unbuilt, parts.unbuilt == 1 and "look waits" or "looks wait"))
	elseif parts.showing then
		window.Status:SetText(("%s | %s"):format(filterStatus, hint))
	elseif Bodies.FullFidelity() then
		window.Status:SetText(("%s | Shown on your race. %s"):format(filterStatus, hint))
	else
		window.Status:SetText(("%s | Some looks are shown on your own body until you've"
			.. " seen someone who can wear them."):format(filterStatus))
	end
end

-- A short note where the status line is, for a few seconds. Not a dialog: the
-- window stays live under it.
function LibraryUI.Flash(text)
	if not (window and window:IsShown()) then return end
	window.FlashFade:Stop()
	window.Flash:SetText(text)
	window.Flash:SetAlpha(1)
	window.Status:Hide()
	window.Flash:Show()
	window.FlashFade:Play()
end

-- On screen right now, which is what a shortcut to it needs to know.
-- IsVisible rather than IsShown: IsShown answers only for the frame's own
-- flag and stays true under a hidden parent.
function LibraryUI.IsOpen()
	return window ~= nil and window:IsVisible()
end

-- The library and the pairing window are both full-size and both about the
-- same outfits, so two of them open is two places to look and one of them
-- covering the other.
local function CloseOthers()
	local addon = ns.Addon
	if not addon then return end
	if addon.ClosePicker then addon:ClosePicker() end
end

function LibraryUI.Show()
	CloseOthers()
	local frame = Ensure()
	frame:Show()
	LibraryUI.Refresh()
	return frame
end

function LibraryUI.Hide()
	if window then window:Hide() end
end

function LibraryUI.Toggle()
	local frame = Ensure()
	if frame:IsShown() then
		frame:Hide()
	else
		LibraryUI.Show()
	end
	return frame
end

ns.LibraryUI = LibraryUI
return LibraryUI
