local _, ns = ...

-- The outfit list's rows: outfit rows and category headers, built once per
-- pooled frame and painted per refresh, the pinned "Show equipped gear" row,
-- and dragging rows and headers to reorder them.
local MainWindowRows = {}

local function CaseInsensitive(a, b)
	return strlower(a) < strlower(b)
end

-- parts: frame, showOutfitMenu, showCategoryMenu, macroIcon.
function MainWindowRows.Attach(Addon, deps, parts)
	local Tree = deps.Tree
	local Macro = deps.Macro
	local Lint = deps.Lint
	local LINT_COLOURS = deps.lintColours
	local EQUIP_SPELL_ID = deps.equipSpellID
	local OutfitWear_PreClick = deps.outfitWearPreClick
	local OutfitWear_PostClick = deps.outfitWearPostClick
	local OpenTitlePicker = deps.openTitlePicker
	local CountOutfitTitles = deps.countOutfitTitles
	local UI, MainWindow = ns.UI, ns.UI.MainWindow
	local NEW_CATEGORY_NAME = Tree.NEW_CATEGORY_NAME
	local CategoryColor = ns.CategoryColor
	local frame = parts.frame
	local ShowOutfitMenu = parts.showOutfitMenu
	local ShowCategoryMenu = parts.showCategoryMenu
	local MacroIcon = parts.macroIcon

	local function CategoryPath(catID)
		return Tree.CategoryPath(MogtrotCharDB, catID)
	end

	-- Built by hand rather than with GameTooltip:SetOutfit, whose "right click to lock"
	-- line describes Blizzard's row, not this one.
	local function Row_OnEnter(self)
		self.Highlight:Show()
		Addon:ShowPreview(self.outfitID)
		GameTooltip:SetOwner(frame, "ANCHOR_NONE")
		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint("TOPLEFT", frame, "TOPRIGHT", 8, 0)

		if not self.outfitID then
			GameTooltip:SetText("Show equipped gear")
			GameTooltip:AddLine("Clears the displayed outfit.", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
			return
		end

		local info = Addon.outfitsByID and Addon.outfitsByID[self.outfitID]
		GameTooltip:SetText(info and info.name or self.outfitName or "Outfit", 1, 0.82, 0)

		if info and info.situationCategories and #info.situationCategories > 0 then
			GameTooltip:AddLine(table.concat(info.situationCategories, ", "), 1, 1, 1, true)
		end
		if C_TransmogOutfitInfo.IsLockedOutfit(self.outfitID) then
			GameTooltip:AddLine("Locked", 0.4, 1, 0.4)
		end

		local path = CategoryPath(MogtrotCharDB and MogtrotCharDB.assign
			and MogtrotCharDB.assign[self.outfitID])
		if path then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine("Mogtrot: " .. path, 0.5, 0.8, 1)
		end

		local mounts = MogtrotCharDB and MogtrotCharDB.mounts
			and MogtrotCharDB.mounts[self.outfitID]
		if mounts then
			local names = {}
			for mountID in pairs(mounts) do
				local mountName = C_MountJournal.GetMountInfoByID(mountID)
				if mountName then table.insert(names, mountName) end
			end
			table.sort(names, CaseInsensitive)
			for index, mountName in ipairs(names) do
				if index > 4 then
					GameTooltip:AddLine(("...and %d more"):format(#names - 4), 0.5, 0.8, 1)
					break
				end
				GameTooltip:AddLine((index == 1 and "Mounts: " or "        ") .. mountName, 0.5, 0.8, 1)
			end
		end

		-- The dot on the row only carries green, yellow or grey. What is actually missing
		-- goes here, since this is where there is room to name it.
		GameTooltip:AddLine(" ")
		Addon:AddLintTooltip(GameTooltip, self.outfitID)
		Addon:AddWearTooltip(GameTooltip, self.outfitID)

		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Click to wear", 0.6, 0.6, 0.6)
		if MogtrotDB.announceEnabled ~= false then
			GameTooltip:AddLine("Shift-click to wear and announce it in /say", 0.6, 0.6, 0.6)
		end
		GameTooltip:AddLine("|cffffd100\"...\"|r on the right opens this outfit's menu",
			0.6, 0.6, 0.6)
		GameTooltip:AddLine("Drag to reorder", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end

	local function Row_OnLeave(self)
		self.Highlight:Hide()
		GameTooltip:Hide()
	end

	-- Dragging only ever reorders. Putting an outfit on an action bar lives in the
	-- ellipsis menu, where it is discoverable and cannot be triggered by holding a
	-- modifier you happened to be using for something else.
	local function Row_OnDragStart(self)
		if InCombatLockdown() or not self.outfitID then return end

		Addon.drag = { kind = "outfit", outfitID = self.outfitID }
		self:SetAlpha(0.4)
	end

	local function Row_OnDragStop(self)
		self:SetAlpha(1)
		Addon:FinishDrag()
	end

	-- Duration object in, never numbers. GetSpellCooldown's start and duration are
	-- secret, and tainted code may not compare them (CooldownFrame_Set) or pass them
	-- to a setter (SetCooldown) - both are "AllowedWhenUntainted". The object-taking
	-- pair exists for exactly this: nothing secret is ever exposed to us, and
	-- clearIfZero defaults true, so an inactive cooldown clears the swipe by itself.
	local function UpdateRowCooldown(row)
		local cooldown = C_Spell.GetSpellCooldownDuration(EQUIP_SPELL_ID)
		if cooldown then
			row.Cooldown:SetCooldownFromDurationObject(cooldown)
		else
			row.Cooldown:Clear()
		end
	end

	local function BuildMountButton(row)
		-- The mount slot: a button so it can be clicked, always drawn so the column is
		-- straight and so an outfit with no mounts still has somewhere to click. A
		-- texture alone could not take the click, and the row underneath would wear the
		-- outfit instead.
		row.MountButton = CreateFrame("Button", nil, row)
		row.MountButton:Hide()
		row.MountButton:SetSize(22, MainWindow.RowHeight)
		row.MountButton:SetPoint("RIGHT", -40, 0)
		row.MountButton:RegisterForClicks("LeftButtonUp")

		row.MountButton.Empty = row.MountButton:CreateTexture(nil, "BACKGROUND")
		row.MountButton.Empty:SetSize(18, 18)
		row.MountButton.Empty:SetPoint("CENTER")
		row.MountButton.Empty:SetColorTexture(1, 1, 1, 0.07)

		row.MountIcon = row.MountButton:CreateTexture(nil, "ARTWORK")
		row.MountIcon:SetSize(18, 18)
		row.MountIcon:SetPoint("CENTER")
		row.MountIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.MountIcon:Hide()

		row.MountCount = row.MountButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.MountCount:SetPoint("BOTTOMRIGHT", row.MountIcon, "BOTTOMRIGHT", 2, -2)
		row.MountCount:Hide()


		row.MountButton:SetScript("OnClick", function(self)
			local outfitID = self:GetParent().outfitID
			if outfitID then Addon:OpenMountPicker(outfitID) end
		end)
		row.MountButton:SetScript("OnEnter", function(self)
			self.Empty:SetColorTexture(1, 1, 1, 0.18)
			local parent = self:GetParent()
			if not parent.outfitID then return end

			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			local count = Addon:CountOutfitMounts(parent.outfitID)
			GameTooltip:SetText(count > 0 and ("Mounts (%d)"):format(count) or "No mounts linked")
			GameTooltip:AddLine("Click to choose mounts for this outfit.", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		row.MountButton:SetScript("OnLeave", function(self)
			self.Empty:SetColorTexture(1, 1, 1, 0.07)
			GameTooltip:Hide()
		end)
	end

	local function BuildTitleButton(row)
		row.TitleButton = CreateFrame("Button", nil, row)
		row.TitleButton:SetSize(16, MainWindow.RowHeight)
		row.TitleButton:SetPoint("RIGHT", -18, 0)
		row.TitleButton:RegisterForClicks("LeftButtonUp")

		row.TitleButton.Empty = row.TitleButton:CreateTexture(nil, "BACKGROUND")
		row.TitleButton.Empty:SetSize(13, 13)
		row.TitleButton.Empty:SetPoint("CENTER")
		row.TitleButton.Empty:SetColorTexture(1, 1, 1, 0)

		row.TitleIcon = row.TitleButton:CreateTexture(nil, "ARTWORK")
		row.TitleIcon:SetSize(13, 13)
		row.TitleIcon:SetPoint("CENTER")
		row.TitleIcon:SetTexture(237446)
		row.TitleIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.TitleIcon:Show()

		row.TitleCount = row.TitleButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.TitleCount:SetPoint("BOTTOMRIGHT", row.TitleIcon, "BOTTOMRIGHT", 2, -2)
		row.TitleCount:Hide()
		row.TitleButton:SetScript("OnClick", function(self)
			local outfitID = self:GetParent().outfitID
			if outfitID then OpenTitlePicker(outfitID) end
		end)
		row.TitleButton:SetScript("OnEnter", function(self)
			self.Empty:SetColorTexture(1, 1, 1, 0.1)
			local outfitID = self:GetParent().outfitID
			if not outfitID then return end
			local count = CountOutfitTitles(outfitID)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(count > 0 and ("Titles (%d)"):format(count) or "No titles linked")
			GameTooltip:AddLine("Click to choose titles for this outfit.", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end)
		row.TitleButton:SetScript("OnLeave", function(self)
			self.Empty:SetColorTexture(1, 1, 1, 0)
			GameTooltip:Hide()
		end)
	end

	local function BuildMenuButton(row)
		-- The menu also lives on a button of its own, so reaching it never depends on
		-- what right-click happens to be bound to.
		row.MenuButton = CreateFrame("Button", nil, row)
		row.MenuButton:SetSize(18, MainWindow.RowHeight)
		row.MenuButton:SetPoint("RIGHT", 0, 0)
		row.MenuButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.MenuButton.Text = row.MenuButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.MenuButton.Text:SetAllPoints()
		row.MenuButton.Text:SetText("...")
		row.MenuButton.Text:SetTextColor(1, 0.82, 0)
		row.MenuButton:Hide()
		row.MenuButton:SetScript("OnClick", function(self)
			local parent = self:GetParent()
			if parent.outfitID then ShowOutfitMenu(parent) end
		end)
		row.MenuButton:SetScript("OnEnter", function(self)
			self.Text:SetTextColor(1, 0.92, 0.35)
		end)
		row.MenuButton:SetScript("OnLeave", function(self)
			self.Text:SetTextColor(1, 0.82, 0)
		end)
	end

	-- One-time construction, kept apart from the per-refresh paint because list rows come
	-- from a recycling pool that hands back a frame it may have used for something else.
	function Addon:BuildOutfitRow(row)
		if row.built then return row end
		row.built = true

		row:SetHeight(MainWindow.RowHeight)

		-- Addon buttons never receive SecureActionButton_OnClick's isSecureAction flag, so it
		-- falls back to the ActionButtonUseKeyDown CVar to decide which edge acts. Register
		-- both edges and pin useOnKeyDown so the wear action fires whatever that CVar is set to.
		row:RegisterForClicks("AnyDown", "AnyUp")
		row:SetAttribute("useOnKeyDown", false)
		row:RegisterForDrag("LeftButton")

		-- Right-click wears as well. Blizzard's own row locks the appearance on right-click,
		-- but that path is closed to addons: ChangeDisplayedOutfit is protected
		-- (ADDON_ACTION_FORBIDDEN), and the secure "outfit" action exposes only
		-- change/toggle/clear. The menu lives on the ellipsis button instead.
		row:SetAttribute("type2", "outfit")

		row.Highlight = row:CreateTexture(nil, "BACKGROUND")
		row.Highlight:SetAllPoints()
		row.Highlight:SetColorTexture(1, 1, 1, 0.12)
		row.Highlight:Hide()

		row.Active = row:CreateTexture(nil, "BACKGROUND")
		row.Active:SetAllPoints()
		row.Active:SetColorTexture(1, 0.82, 0, 0.18)
		row.Active:Hide()

		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetSize(MainWindow.IconSize, MainWindow.IconSize)
		row.Icon:SetPoint("LEFT", 2, 0)
		row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

		row.Cooldown = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
		row.Cooldown:SetAllPoints(row.Icon)
		row.Cooldown:SetHideCountdownNumbers(true)
		row.Cooldown:SetDrawBling(false)

		-- Same lock indicator Blizzard puts on their outfit icons and action buttons.
		row.LockOverlay = CreateFrame("Frame", nil, row, "AutoCastOverlayTemplate")
		row.LockOverlay:SetAllPoints(row.Icon)
		row.LockOverlay:Hide()

		row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 16, 0)
		row.Name:SetPoint("RIGHT", -72, 0)
		row.Name:SetJustifyH("LEFT")
		row.Name:SetWordWrap(false)

		BuildMountButton(row)
		BuildTitleButton(row)

		-- This row has no room for "11/16", so it carries the state as a dot and the
		-- detail in the tooltip. Immediately left of the name rather than out in the
		-- indicator column: it describes the outfit, so it reads as part of the name.
		-- A greyscale orb tinted per state, rather than a flat colour block: the same
		-- texture reads as a dot instead of a square, and takes any colour.
		row.LintDot = row:CreateTexture(nil, "OVERLAY")
		row.LintDot:SetTexture("Interface\\COMMON\\Indicator-Gray")
		row.LintDot:SetSize(11, 11)
		row.LintDot:SetPoint("RIGHT", row.Name, "LEFT", -2, 0)

		BuildMenuButton(row)

		row:SetScript("OnEnter", Row_OnEnter)
		row:SetScript("OnLeave", Row_OnLeave)
		row:SetScript("OnDragStart", Row_OnDragStart)
		row:SetScript("OnDragStop", Row_OnDragStop)

		-- Whether the wear will actually happen has to be read before the click, since
		-- the click is what starts the cooldown that would otherwise mask it.
		row:SetScript("PreClick", OutfitWear_PreClick)

		-- Clicking a row wears the outfit, which is the moment worth capturing. This does
		-- not depend on the event firing usefully.
		row:SetScript("PostClick", OutfitWear_PostClick)

		return row
	end

	-- A one-shot gold wash, so the thing you just created or moved announces itself
	-- when the list jumps to it. Built once per frame, replayed per event.
	local function AddFlash(frame)
		if frame.Flash then return end
		local tex = frame:CreateTexture(nil, "OVERLAY")
		tex:SetAllPoints()
		tex:SetColorTexture(1, 0.82, 0, 1)
		tex:SetAlpha(0)

		local group = tex:CreateAnimationGroup()
		local fade = group:CreateAnimation("Alpha")
		fade:SetFromAlpha(0.6)
		fade:SetToAlpha(0)
		fade:SetDuration(0.9)
		fade:SetSmoothing("OUT")

		frame.Flash, frame.FlashAnim = tex, group
	end

	-- Pooled frames arrive mid-flash if one was playing when they were recycled.
	local function ResetFlash(frame)
		if frame.FlashAnim then
			frame.FlashAnim:Stop()
			frame.Flash:SetAlpha(0)
		end
	end

	-- Everything that varies per refresh. Reads the active outfit itself rather than taking
	-- it from Refresh, because a row can be realised by a scroll long after the last refresh.
	function Addon:InitOutfitRow(row, entry)
		self:BuildOutfitRow(row)
		AddFlash(row)
		ResetFlash(row)

		local info = entry.info
		local activeOutfitID = C_TransmogOutfitInfo.GetActiveOutfitID()
		local outfitID = info.outfitID

		-- Clear every pooled value before assigning this outfit.
		row.outfitID = nil
		row.outfitName = nil
		for _, button in ipairs({
			row.MountButton, row.TitleButton, row.MenuButton,
		}) do
			button.outfitID = nil
			button:Hide()
			button:Enable()
		end
		for _, icon in ipairs({
			row.MountIcon, row.TitleIcon,
		}) do
			icon:SetTexture(nil)
			icon:Hide()
		end
		for _, count in ipairs({
			row.MountCount, row.TitleCount,
		}) do
			count:SetText("")
			count:Hide()
		end
		row.TitleButton.Empty:SetColorTexture(1, 1, 1, 0)
		row.MenuButton.Text:SetText("...")
		row.MenuButton.Text:SetTextColor(1, 0.82, 0)

		row.outfitID = outfitID
		row.outfitName = info.name
		row.Icon:SetTexture(info.icon)
		row.Name:SetText(info.name)
		row.Name:ClearAllPoints()
		row.Name:SetPoint("LEFT", row.Icon, "RIGHT", Lint.NameInset(MogtrotDB), 0)
		row.Name:SetPoint("RIGHT", -72, 0)
		row.Active:SetShown(outfitID == activeOutfitID)
		row.MenuButton.outfitID = outfitID
		row.MenuButton:Show()

		-- A pooled frame arrives carrying whatever the drag and hover handlers last left on it.
		row:SetAlpha(1)
		row.Highlight:Hide()

		local firstMountID, mountCount =
			ns.OutfitLinks.Representative(MogtrotCharDB.mounts, outfitID)

		row.MountButton.outfitID = outfitID
		row.MountButton:Show()
		if firstMountID then
			local _name, _spellID, mountIcon = C_MountJournal.GetMountInfoByID(firstMountID)
			row.MountIcon:SetTexture(mountIcon)
			row.MountIcon:Show()
			row.MountCount:SetText(mountCount > 1 and mountCount or "")
			row.MountCount:SetShown(mountCount > 1)
		else
			row.MountIcon:SetTexture(MacroIcon(Macro.SUMMON))
			row.MountIcon:Show()
			row.MountCount:SetText(0)
			row.MountCount:Show()
		end

		local titleCount = CountOutfitTitles(outfitID)
		row.TitleButton.outfitID = outfitID
		row.TitleButton:Show()
		row.TitleIcon:SetTexture(237446)
		row.TitleIcon:Show()
		row.TitleCount:SetText(titleCount)
		row.TitleCount:Show()


		-- Set unconditionally, like everything else on a pooled row: a recycled frame that
		-- kept the previous outfit's dot would be wrong while looking entirely right.
		if Lint.ShowInList(MogtrotDB) then
			local lintState = self:LintState(info.outfitID)
			local lintColour = LINT_COLOURS[lintState]
			row.LintDot:SetVertexColor(lintColour[1], lintColour[2], lintColour[3],
				lintState == "unknown" and 0.4 or 1)
			row.LintDot:Show()
		else
			row.LintDot:Hide()
		end

		local locked = C_TransmogOutfitInfo.IsLockedOutfit(info.outfitID)
		row.LockOverlay:SetShown(locked)
		if locked and row.LockOverlay.ShowAutoCastEnabled then
			row.LockOverlay:ShowAutoCastEnabled(true)
		end

		if info.outfitID == activeOutfitID then
			row.Name:SetTextColor(1, 1, 1)
		elseif info.isDisabled then
			row.Name:SetTextColor(0.5, 0.5, 0.5)
		else
			row.Name:SetTextColor(1, 0.82, 0)
		end

		row:SetAttribute("type", "outfit")
		row:SetAttribute("action", "change")
		row:SetAttribute("outfit-index", info.index)

		UpdateRowCooldown(row)
	end

	-- "Show equipped gear" is not an entry: it sits below the scrolling area at a fixed
	-- offset, so it stays a plain child of the window and never enters the data provider.
	function Addon:EnsureClearRow()
		if not self.clearRow then
			self.clearRow = self:BuildOutfitRow(CreateFrame("Button", nil, frame, UI.ActionButtonTemplate))
			self.clearRow:SetWidth(MainWindow.Width - 2 * UI.Pad - 10)
			self.clearRow.Icon:SetTexture("Interface\\Icons\\INV_Shirt_White_01")
			self.clearRow.Name:SetText("Show equipped gear")
			self.clearRow.Name:SetTextColor(0.7, 0.7, 0.7)
			self.clearRow.Name:ClearAllPoints()
			self.clearRow.Name:SetPoint("LEFT", self.clearRow.Icon, "RIGHT", 16, 0)
			self.clearRow.Name:SetPoint("RIGHT", frame.NewCategoryButton, "LEFT", -4, 0)
			self.clearRow.MenuButton:Hide()
			self.clearRow.LockOverlay:Hide()
			-- "Show equipped gear" is not an outfit, so it has no companion entries.
			self.clearRow.TitleButton:Hide()
			self.clearRow.LintDot:Hide()
			self.clearRow:SetAttribute("type", "outfit")
			self.clearRow:SetAttribute("action", "clear")
			self.clearRow.Cooldown:Clear()
			self.clearRow:Show()
			frame.NewCategoryButton:SetPoint("RIGHT", self.clearRow, "RIGHT", -4, 0)
			frame.NewCategoryButton:SetFrameLevel(self.clearRow:GetFrameLevel() + 2)
		end
		return self.clearRow
	end

	function Addon:PaintClearRow()
		local clearRow = self:EnsureClearRow()
		clearRow.Active:SetShown(C_TransmogOutfitInfo.IsEquippedGearOutfitDisplayed())
	end

	local function Header_OnClick(self, button)
		if button == "RightButton" then
			ShowCategoryMenu(self)
			return
		end
		if InCombatLockdown() then return end
		local cat = MogtrotCharDB.cats[self.catID]
		if cat then
			cat.collapsed = not cat.collapsed
			Addon:Refresh()
		end
	end

	local function Header_OnDragStart(self)
		if InCombatLockdown() then return end
		local cat = MogtrotCharDB.cats[self.catID]
		if not cat or cat.protected then return end
		Addon.drag = { kind = "cat", catID = self.catID }
		self:SetAlpha(0.4)
	end

	local function Header_OnDragStop(self)
		self:SetAlpha(1)
		Addon:FinishDrag()
	end

	function Addon:BuildHeaderRow(header)
		if header.built then return header end
		header.built = true

		header:SetHeight(MainWindow.HeaderHeight)
		header:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		header:RegisterForDrag("LeftButton")

		header.Background = header:CreateTexture(nil, "BACKGROUND")
		header.Background:SetAllPoints()

		header.Arrow = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		header.Arrow:SetPoint("LEFT", 4, 0)

		header.Count = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		header.Count:SetPoint("RIGHT", -24, 0)

		-- Truncates at the count rather than running underneath it and the + button.
		header.Name = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		header.Name:SetPoint("LEFT", header.Arrow, "RIGHT", 4, 0)
		header.Name:SetPoint("RIGHT", header.Count, "LEFT", -6, 0)
		header.Name:SetJustifyH("LEFT")
		header.Name:SetWordWrap(false)

		header.AddButton = CreateFrame("Button", nil, header)
		header.AddButton:SetSize(16, 16)
		header.AddButton:SetPoint("RIGHT", -4, 0)
		header.AddButton.Text = header.AddButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		header.AddButton.Text:SetAllPoints()
		header.AddButton.Text:SetText("+")
		header.AddButton:SetScript("OnClick", function(self)
			Addon:CreateCategory(NEW_CATEGORY_NAME, self:GetParent().catID, true)
		end)
		header.AddButton:SetScript("OnEnter", function(self)
			self.Text:SetTextColor(1, 1, 1)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Add sub-category")
			GameTooltip:Show()
		end)
		header.AddButton:SetScript("OnLeave", function(self)
			self.Text:SetTextColor(1, 0.82, 0)
			GameTooltip:Hide()
		end)
		header.AddButton.Text:SetTextColor(1, 0.82, 0)

		header:SetScript("OnClick", Header_OnClick)
		header:SetScript("OnDragStart", Header_OnDragStart)
		header:SetScript("OnDragStop", Header_OnDragStop)
		header:SetScript("OnEnter", function(self)
			local cat = MogtrotCharDB.cats[self.catID]
			local color = CategoryColor.Normalize(cat and cat.color)
			self.Background:SetColorTexture(color.r, color.g, color.b, 0.8)
		end)
		header:SetScript("OnLeave", function(self)
			local cat = MogtrotCharDB.cats[self.catID]
			local color = CategoryColor.Normalize(cat and cat.color)
			self.Background:SetColorTexture(color.r, color.g, color.b, 0.55)
		end)

		return header
	end

	function Addon:InitHeaderRow(header, entry)
		self:BuildHeaderRow(header)
		AddFlash(header)
		ResetFlash(header)

		-- Set before the guard: a pooled frame keeps whatever category it last carried, and
		-- a stale one here would send clicks and drops to the wrong place.
		header.catID = entry.catID

		local cat = MogtrotCharDB.cats[entry.catID]
		if not cat then return end

		header.Arrow:SetText(cat.collapsed and "+" or "-")
		-- The category being renamed shows the editor in place of its name. Recycling can
		-- move that category to a different frame, so the choice is made per row, not once.
		header.Name:SetText(self.editing == entry.catID and "" or cat.name)
		header.Count:SetText(Tree.CountOutfits(MogtrotCharDB, entry.catID))
		local color = CategoryColor.Normalize(cat.color)
		header.Background:SetColorTexture(color.r, color.g, color.b, 0.55)
		header:SetAlpha(1)
	end

	function Addon:UpdateCooldowns()
		self.listBox:ForEachFrame(function(row)
			if row.outfitID then UpdateRowCooldown(row) end
		end)
	end
end

ns.MainWindowRows = MainWindowRows
return MainWindowRows
