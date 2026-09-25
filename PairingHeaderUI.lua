local _, ns = ...

-- Lays PairingHeader's sentence out as widgets: plain prose as font strings,
-- and every changeable word as a boxed, iconed button.
--
-- Shared, because the mount window and the hearthstone window are two views
-- of one question and their headers must read identically, and because the
-- library's header is the same sentence about a different collection. Written
-- twice they would drift, and the first sign of that is a window you can
-- switch out of but not back into.
--
-- A window that wants one of those words on its own, outside a sentence, takes
-- it from here too, so the two are one control rather than two that resemble
-- each other.
--
-- The window supplies what each word does; this knows only how one looks.
local PairingHeaderUI = {}

local PAD = 7
local ICON = 16
local BACKDROP = { edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

-- The same two the macro handles wear, so one thing has one icon everywhere.
local RANDOM_FAVOURITE_SPELL_ID = 150544
local HEARTHSTONE_ITEM_ID = 6948

local TIP = {
	domain = { "Switch what you are pairing",
		"Mounts and hearthstones each pair with the same outfit." },
	outfit = { "Choose another outfit", "Click to select an outfit." },
	mode = { "Switch between an outfit and your pins",
		"Pins belong to the account; an outfit's links belong to that outfit." },
	libraryMode = { "Switch what the library shows",
		"Your own characters' outfits and custom sets, or the snapshots you took"
			.. " of other players. Snapshots are account-wide and are narrowed by"
			.. " race, class and armour." },
	body = { "Switch whose body a look is on",
		"Every look on the body of whoever wore it, or all of them on your own." },
}

-- Returns the texture and whether it is an atlas, because the two need
-- different setters. An icon the client will not name is simply absent, and
-- the word stands on its own.
local function IconFor(name, outfitIcon)
	if name == "mounts" then
		return C_Spell and C_Spell.GetSpellTexture
			and C_Spell.GetSpellTexture(RANDOM_FAVOURITE_SPELL_ID) or nil, false
	end
	if name == "hearthstones" then
		return C_Item and C_Item.GetItemIconByID
			and C_Item.GetItemIconByID(HEARTHSTONE_ITEM_ID) or nil, false
	end
	if name == "outfit" then return outfitIcon, false end
	if name == "pins" then return "auctionhouse-icon-favorite", true end
	if name == "characters" then return "socialqueuing-icon-group", true end
	-- Whatever the snap macro wears, since the snap macro is what makes these.
	if name == "snapshots" then
		local Macro = ns.Macro
		return Macro and Macro.FixedIcon(Macro.SNAP) or nil, false
	end
	return nil, false
end

PairingHeaderUI.Icon = IconFor

-- The menu behind a word that stands for one of a fixed set: the domain in
-- the pairing windows, the mode in the library. Which words those are and how
-- their rows read is PairingHeader.Choices'.
--
-- Plain buttons rather than radios: the sentence behind the menu already says
-- which one you are on, so a dot repeats it and costs the row its left edge.
-- The icon goes there instead, and a minimum width keeps the rows the same
-- size rather than one per word length.
local MENU_ICON = 16
local MENU_WIDTH = 170

function PairingHeaderUI.ShowMenu(anchor, action, onChoose)
	if not (MenuUtil and anchor) then return end
	local choices = ns.PairingHeader.Choices(action)
	if #choices == 0 then return end
	MenuUtil.CreateContextMenu(anchor, function(_owner, root)
		root:SetMinimumWidth(MENU_WIDTH)
		for _, choice in ipairs(choices) do
			local value = choice.value
			local entry = root:CreateButton(choice.text, function() onChoose(value) end)
			entry:AddInitializer(function(button)
				local icon, isAtlas = IconFor(choice.icon)
				local texture = button:AttachTexture()
				texture:SetSize(MENU_ICON, MENU_ICON)
				texture:SetPoint("LEFT", button, "LEFT", 4, 0)
				texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				if icon and isAtlas then
					texture:SetAtlas(icon, false)
				elseif icon then
					texture:SetTexture(icon)
				end
				button.fontString:ClearAllPoints()
				button.fontString:SetPoint("LEFT", texture, "RIGHT", 8, 0)
			end)
		end
	end)
end

local function Segment_OnEnter(self)
	local tip = TIP[self.action]
	if not tip then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(tip[1])
	GameTooltip:AddLine(tip[2], 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

-- A word, and how one is painted. A word standing alone and a word inside a
-- sentence are the same control, so both are made here rather than once per
-- window that wants one.
local function NewSegment(parent, height, onClick)
	local segment = CreateFrame("Button", nil, parent, "BackdropTemplate")
	segment:SetHeight(height)
	segment.Icon = segment:CreateTexture(nil, "ARTWORK")
	segment.Icon:SetSize(ICON, ICON)
	segment.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	segment.Icon:Hide()
	segment.Text = segment:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	segment.Text:SetPoint("LEFT")
	segment:SetScript("OnEnter", Segment_OnEnter)
	segment:SetScript("OnLeave", GameTooltip_Hide)
	segment:SetScript("OnClick", onClick)
	return segment
end

local function Paint(segment, part, outfitIcon)
	segment.action = part.action
	segment.Text:SetText(part.text)
	segment.Text:ClearAllPoints()
	-- A clickable word is boxed in gold and takes the mouse; the prose
	-- between is plain and lets clicks through to the window behind. A boxed
	-- word with no action looks the same and takes no clicks.
	if part.action or part.boxed then
		local icon, isAtlas = IconFor(part.icon, outfitIcon)
		segment.Icon:ClearAllPoints()
		segment.Icon:SetPoint("LEFT", segment, "LEFT", PAD, 0)
		if icon and isAtlas then
			segment.Icon:SetAtlas(icon, false)
		elseif icon then
			segment.Icon:SetTexture(icon)
		end
		segment.Icon:SetShown(icon ~= nil)
		local room = icon and (ICON + 4) or 0
		segment.Text:SetTextColor(1, 0.82, 0)
		segment.Text:SetPoint("LEFT", segment, "LEFT", PAD + room, 0)
		segment:SetBackdrop(BACKDROP)
		segment:SetBackdropBorderColor(1, 0.82, 0, 1)
		segment:SetWidth(segment.Text:GetStringWidth() + room + PAD * 2)
	else
		segment.Icon:Hide()
		segment.Text:SetTextColor(0.85, 0.85, 0.85)
		segment.Text:SetPoint("LEFT")
		if segment.ClearBackdrop then segment:ClearBackdrop()
		else segment:SetBackdrop(nil) end
		segment:SetWidth(math.max(segment.Text:GetStringWidth(), 1))
	end
	segment:EnableMouse(part.action ~= nil)
end

-- One changeable word standing on its own, outside any sentence: the same box,
-- the same menu and the same tooltip as a word inside one. Two dropdowns that
-- look different are two controls as far as anyone reading the window is
-- concerned, and this window already says one of these sentences above it.
--
-- The action never changes, so the word always opens the same menu. Say(value)
-- puts it on one of that menu's choices.
function PairingHeaderUI.Word(parent, height, action, onChoose)
	local word
	word = NewSegment(parent, height, function()
		PairingHeaderUI.ShowMenu(word, action, onChoose)
	end)
	function word:Say(value)
		local choice = ns.PairingHeader.Choice(action, value)
		Paint(self, { text = choice and choice.text or tostring(value),
			action = action, icon = choice and choice.icon })
	end
	return word
end

-- row is the frame the sentence is laid out in, left to right. height is the
-- row's own height so a boxed word fills it. onClick(action, segment) is
-- called with the action the word carries and the widget clicked.
--
-- sentence is which of PairingHeader's sentences this row says. A window
-- names it once, here, rather than at every paint, and there is no default:
-- a window that forgot would otherwise lay out somebody else's sentence and
-- look like it meant to.
function PairingHeaderUI.New(row, height, onClick, sentence)
	local segments = {}

	-- The segment goes back with the action so a caller can hang a menu off
	-- the word that was clicked.
	local function Segment_OnClick(self)
		if self.action and onClick then onClick(self.action, self) end
	end

	local function Acquire(index)
		local segment = segments[index]
		if segment then return segment end
		segment = NewSegment(row, height, Segment_OnClick)
		segments[index] = segment
		return segment
	end

	-- state is whatever this row's sentence reads, plus outfitIcon for a word
	-- that names an outfit.
	return function(state)
		local parts = sentence(state)
		local anchor
		for index, part in ipairs(parts) do
			local segment = Acquire(index)
			Paint(segment, part, state and state.outfitIcon)
			segment:ClearAllPoints()
			if anchor then
				segment:SetPoint("LEFT", anchor, "RIGHT", 0, 0)
			else
				segment:SetPoint("LEFT", row, "LEFT", 0, 0)
			end
			segment:Show()
			anchor = segment
		end
		for index = #parts + 1, #segments do segments[index]:Hide() end
	end
end

ns.PairingHeaderUI = PairingHeaderUI
return PairingHeaderUI
