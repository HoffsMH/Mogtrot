local _, ns = ...

-- Lays PairingHeader's sentence out as widgets: plain prose as font strings,
-- and every changeable word as a boxed, iconed button.
--
-- Shared, because the mount window and the hearthstone window are two views
-- of one question and their headers must read identically. Written twice they
-- would drift, and the first sign of that is a window you can switch out of
-- but not back into.
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
	return nil, false
end

PairingHeaderUI.Icon = IconFor

-- The domain menu, shared so both windows offer the same one.
--
-- Plain buttons rather than radios: the sentence behind the menu already says
-- which domain you are on, so a dot repeats it and costs the row its left
-- edge. The icon goes there instead, and a minimum width keeps the rows the
-- same size rather than one per word length.
local MENU_ICON = 16
local MENU_WIDTH = 170

function PairingHeaderUI.ShowDomainMenu(anchor, onChoose)
	if not (MenuUtil and anchor) then return end
	MenuUtil.CreateContextMenu(anchor, function(_owner, root)
		root:SetMinimumWidth(MENU_WIDTH)
		for _, domain in ipairs(ns.PairingHeader.DOMAINS) do
			local choice = domain
			local entry = root:CreateButton(choice, function() onChoose(choice) end)
			entry:AddInitializer(function(button)
				local icon, isAtlas = IconFor(choice)
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

-- row is the frame the sentence is laid out in, left to right. height is the
-- row's own height so a boxed word fills it. onClick(action, segment) is
-- called with "domain", "outfit" or "mode", and the widget clicked.
function PairingHeaderUI.New(row, height, onClick)
	local segments = {}

	-- The segment goes back with the action so a caller can hang a menu off
	-- the word that was clicked.
	local function Segment_OnClick(self)
		if self.action and onClick then onClick(self.action, self) end
	end

	local function Acquire(index)
		local segment = segments[index]
		if segment then return segment end
		segment = CreateFrame("Button", nil, row, "BackdropTemplate")
		segment:SetHeight(height)
		segment.Icon = segment:CreateTexture(nil, "ARTWORK")
		segment.Icon:SetSize(ICON, ICON)
		segment.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		segment.Icon:Hide()
		segment.Text = segment:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		segment.Text:SetPoint("LEFT")
		segment:SetScript("OnEnter", Segment_OnEnter)
		segment:SetScript("OnLeave", GameTooltip_Hide)
		segment:SetScript("OnClick", Segment_OnClick)
		segments[index] = segment
		return segment
	end

	-- state is PairingHeader's, plus outfitIcon for the outfit word.
	return function(state)
		local parts = ns.PairingHeader.Segments(state)
		local anchor
		for index, part in ipairs(parts) do
			local segment = Acquire(index)
			segment.action = part.action
			segment.Text:SetText(part.text)
			segment.Text:ClearAllPoints()
			-- A clickable word is boxed in gold and takes the mouse; the prose
			-- between is plain and lets clicks through to the window behind.
			if part.action then
				local icon, isAtlas = IconFor(part.icon, state and state.outfitIcon)
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
