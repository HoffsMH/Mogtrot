local _, ns = ...

-- A plain window holding selectable text, for output meant to leave the game.
-- WoW cannot write to the system clipboard, so the only route out is an
-- EditBox the player copies by hand; the text arrives selected so that is one
-- keystroke. Read-only in spirit, not in fact: edits are discarded on close
-- because nothing reads the box back.
local CopyBox = {}

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local box

local function Ensure()
	if box then return box end

	box = CreateFrame("Frame", "MogtrotCopyBox", UIParent, "BackdropTemplate")
	box:SetSize(620, 460)
	box:SetPoint("CENTER")
	box:SetFrameStrata("DIALOG")
	box:SetClampedToScreen(true)
	box:SetMovable(true)
	box:EnableMouse(true)
	box:RegisterForDrag("LeftButton")
	box:SetScript("OnDragStart", box.StartMoving)
	box:SetScript("OnDragStop", box.StopMovingOrSizing)
	box:SetBackdrop(BACKDROP)
	box:SetBackdropColor(0, 0, 0, 0.94)

	box.Close = CreateFrame("Button", nil, box, "UIPanelCloseButton")
	box.Close:SetPoint("TOPRIGHT", -4, -4)

	box.Title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	box.Title:SetPoint("TOPLEFT", 16, -14)
	box.Title:SetPoint("RIGHT", box.Close, "LEFT", -6, 0)
	box.Title:SetJustifyH("LEFT")
	box.Title:SetWordWrap(false)

	box.Hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	box.Hint:SetPoint("BOTTOMLEFT", 16, 10)
	box.Hint:SetText("Ctrl-C copies the selection. Escape closes.")

	box.Scroll = CreateFrame("ScrollFrame", "MogtrotCopyBoxScroll", box,
		"UIPanelScrollFrameTemplate")
	box.Scroll:SetPoint("TOPLEFT", 14, -38)
	box.Scroll:SetPoint("BOTTOMRIGHT", -32, 30)

	box.Edit = CreateFrame("EditBox", nil, box.Scroll)
	box.Edit:SetMultiLine(true)
	box.Edit:SetAutoFocus(false)
	box.Edit:SetFontObject("GameFontHighlightSmall")
	box.Edit:SetWidth(560)
	box.Edit:SetScript("OnEscapePressed", function() box:Hide() end)
	box.Scroll:SetScrollChild(box.Edit)

	tinsert(UISpecialFrames, "MogtrotCopyBox")
	box:Hide()
	return box
end

-- lines is an array; they are joined with newlines so callers never build the
-- blob themselves.
function CopyBox.Show(title, lines)
	local frame = Ensure()
	frame.Title:SetText(title or "Mogtrot")
	frame.Edit:SetText(table.concat(lines or {}, "\n"))
	frame:Show()
	frame.Edit:SetFocus()
	frame.Edit:HighlightText()
	return frame
end

ns.CopyBox = CopyBox
return CopyBox
