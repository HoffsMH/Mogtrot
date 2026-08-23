local ADDON_NAME, ns = ...

-- Builds and paints the outfit list window where users organise and wear outfits.
local MainWindowUI = {}

local function CaseInsensitive(a, b)
	return strlower(a) < strlower(b)
end

function MainWindowUI.Attach(Addon, deps)
	local Tree = deps.Tree
	local Macro = deps.Macro
	local Wear = deps.Wear
	local Lint = deps.Lint
	local LINT_COLOURS = deps.lintColours
	local EQUIP_SPELL_ID = deps.equipSpellID
	local OutfitWear_PreClick = deps.outfitWearPreClick
	local OutfitWear_PostClick = deps.outfitWearPostClick
	local OpenTitlePicker = deps.openTitlePicker
	local CountOutfitTitles = deps.countOutfitTitles
	local CopyOutfitTitles = deps.copyOutfitTitles
	local ClearOutfitTitles = deps.clearOutfitTitles
	assert(type(OpenTitlePicker) == "function", "MainWindowUI requires openTitlePicker")
	assert(type(CountOutfitTitles) == "function", "MainWindowUI requires countOutfitTitles")
	assert(type(CopyOutfitTitles) == "function", "MainWindowUI requires copyOutfitTitles")
	assert(type(ClearOutfitTitles) == "function", "MainWindowUI requires clearOutfitTitles")
	local UI, MainWindow = ns.UI, ns.UI.MainWindow
	local NEW_CATEGORY_NAME = Tree.NEW_CATEGORY_NAME

	local function CategoryPath(catID)
		return Tree.CategoryPath(MogtrotCharDB, catID)
	end

	local function MountText(count)
		if count == 0 then return "no mounts" end
		if count == 1 then return "1 mount" end
		return ("%d mounts"):format(count)
	end

	local function OutfitText(count)
		if count == 0 then return "no outfits" end
		if count == 1 then return "1 outfit" end
		return ("%d outfits"):format(count)
	end

	local function TitleText(count)
		if count == 0 then return "no titles" end
		if count == 1 then return "1 title" end
		return ("%d titles"):format(count)
	end

	-- Categories as picker choices, counted so an empty one is not indistinguishable
	-- from a full one. The count includes sub-categories, which is what the list shows.
	local function CategoryChoices(excludeID, skipID)
		local choices = Tree.CategoryChoices(MogtrotCharDB, excludeID, skipID)
		for _, choice in ipairs(choices) do
			local count = Tree.CountOutfits(MogtrotCharDB, choice.catID)
			choice.note = OutfitText(count)
			choice.noteDim = count == 0
		end
		return choices
	end

	local function OpenMoveOutfit(outfitID, outfitName)
		ns.OpenSearchPicker({
			title = ("Move %s"):format(outfitName or "outfit"),
			searchHint = "Search categories",
			emptyText = "No categories match.",
			-- Not the category it already sits in; moving it there does nothing. Its
			-- sub-categories stay, since those are real destinations.
			items = CategoryChoices(nil, MogtrotCharDB.assign[outfitID]),
			buttons = {
				{
					text = "Move", width = 90,
					onClick = function(chosen)
						Addon.reveal = { kind = "outfit", id = outfitID }
						Addon:MoveOutfit(outfitID, chosen[1].catID)
					end,
				},
			},
		})
	end

	local function OpenMoveCategory(catID, catName)
		local choices = CategoryChoices(catID)
		-- Top level is a different kind of answer from a category, so it is pinned
		-- above them rather than sorted among them. No catID is what says so.
		table.insert(choices, 1, { name = "Top level", divider = true })

		ns.OpenSearchPicker({
			title = ("Move %s"):format(catName or "category"),
			searchHint = "Search categories",
			emptyText = "No categories match.",
			items = choices,
			buttons = {
				{
					text = "Move", width = 90,
					onClick = function(chosen)
						-- Set before the move, which refreshes synchronously. A refused
						-- move just scrolls to where the category still is, which is
						-- the right place to be looking either way.
						Addon.reveal = { kind = "cat", id = catID }
						Addon:MoveCategory(catID, chosen[1].catID)
					end,
				},
			},
		})
	end

	-- One call per target rather than a bulk copy, so each outfit gets the same chat
	-- line and refresh it would get from a single copy. The target is
	-- re-checked at commit time because the window outlives the list it was built from.
	local function CopyMountsToChosen(sourceOutfitID, chosen, merge)
		for _, choice in ipairs(chosen) do
			if Addon.outfitsByID and Addon.outfitsByID[choice.outfitID] then
				Addon:CopyMountsTo(sourceOutfitID, choice.outfitID, merge)
			end
		end
	end

	local function OpenCopyMounts(sourceOutfitID)
		local count = Addon:CountOutfitMounts(sourceOutfitID)
		if count == 0 then return end

		local info = Addon.outfitsByID and Addon.outfitsByID[sourceOutfitID]
		local choices = Tree.OutfitChoices(MogtrotCharDB, Addon.outfitsByID, sourceOutfitID)
		for _, choice in ipairs(choices) do
			local mounts = Addon:CountOutfitMounts(choice.outfitID)
			choice.note = MountText(mounts)
			choice.noteDim = mounts == 0
		end

		ns.OpenSearchPicker({
			title = ("Copy %s from %s"):format(MountText(count), info and info.name or "outfit"),
			searchHint = "Search outfits and categories",
			emptyText = "No outfits match.",
			multi = true,
			items = choices,
			buttons = {
				{
					text = "Add", width = 90,
					tipTitle = "Add",
					tipBody = "Each selected outfit keeps the mounts it already has and gains these on top.",
					onClick = function(chosen) CopyMountsToChosen(sourceOutfitID, chosen, true) end,
				},
				{
					text = "Replace", width = 110, danger = true,
					tipTitle = "Replace",
					tipBody = "Each selected outfit ends up with exactly these mounts. Whatever it had is discarded.",
					onClick = function(chosen) CopyMountsToChosen(sourceOutfitID, chosen, false) end,
				},
			},
		})
	end

	local function CopyTitlesToChosen(sourceOutfitID, chosen, merge)
		for _, choice in ipairs(chosen) do
			if Addon.outfitsByID and Addon.outfitsByID[choice.outfitID] then
				CopyOutfitTitles(sourceOutfitID, choice.outfitID, merge)
			end
		end
	end

	local function OpenCopyTitles(sourceOutfitID)
		local count = CountOutfitTitles(sourceOutfitID)
		if count == 0 then return end

		local info = Addon.outfitsByID and Addon.outfitsByID[sourceOutfitID]
		local choices = Tree.OutfitChoices(MogtrotCharDB, Addon.outfitsByID, sourceOutfitID)
		for _, choice in ipairs(choices) do
			local titles = CountOutfitTitles(choice.outfitID)
			choice.note = TitleText(titles)
			choice.noteDim = titles == 0
		end

		ns.OpenSearchPicker({
			title = ("Copy %s from %s"):format(TitleText(count), info and info.name or "outfit"),
			searchHint = "Search outfits and categories",
			emptyText = "No outfits match.",
			multi = true,
			items = choices,
			buttons = {
				{
					text = "Add", width = 90,
					tipTitle = "Add",
					tipBody = "Each selected outfit keeps its titles and gains these on top.",
					onClick = function(chosen) CopyTitlesToChosen(sourceOutfitID, chosen, true) end,
				},
				{
					text = "Replace", width = 110, danger = true,
					tipTitle = "Replace",
					tipBody = "Each selected outfit ends up with exactly these titles.",
					onClick = function(chosen) CopyTitlesToChosen(sourceOutfitID, chosen, false) end,
				},
			},
		})
	end

	-- Opens the outfit checklist where users choose every outfit linked to one mount.
	function Addon:OpenAddMountToOutfits(mountID, mountName)
		local linked = ns.MountIndex.Build(MogtrotCharDB)[mountID] or {}
		local has = {}
		for _, outfitID in ipairs(linked) do has[outfitID] = true end

		local choices = Tree.OutfitChoices(MogtrotCharDB, self.outfitsByID)
		for _, choice in ipairs(choices) do
			choice.preselected = has[choice.outfitID] or nil
		end

		ns.OpenSearchPicker({
			title = ("Outfits using %s"):format(mountName or "mount"),
			searchHint = "Search outfits and categories",
			emptyText = "No outfits match.",
			multi = true,
			items = choices,
			buttons = {
				{
					text = "Apply", width = 90,
					tipTitle = "Set which outfits use this mount",
					tipBody = "Ticked outfits get the mount, unticked ones lose it.",
					onClick = function(chosen)
						Addon:ApplyMountToOutfits(mountID, mountName, choices, chosen)
					end,
				},
			},
		})
	end

	local CLEAR_OUTFIT_MOUNTS_DIALOG = "MOGTROT_CLEAR_OUTFIT_MOUNTS"

	StaticPopupDialogs[CLEAR_OUTFIT_MOUNTS_DIALOG] = {
		text = "Clear every linked mount from outfit '%s'?\n\n"
			.. "This affects only this outfit and cannot be undone.",
		button1 = "Clear mounts",
		button2 = CANCEL or "Cancel",
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		OnAccept = function(_popup, data)
			if type(data) ~= "table" or not data.outfitID then return end
			if not C_TransmogOutfitInfo.GetOutfitInfo(data.outfitID) then
				Addon:Warn("could not clear mounts because that outfit no longer exists.")
				return
			end
			if not next(MogtrotCharDB.mounts[data.outfitID] or {}) then return end
			Addon:ClearOutfitMounts(data.outfitID)
		end,
	}

	local function ConfirmClearOutfitMounts(outfitID, outfitName)
		if not outfitID or not next(MogtrotCharDB.mounts[outfitID] or {}) then return end
		StaticPopup_Show(CLEAR_OUTFIT_MOUNTS_DIALOG, outfitName or "Outfit", nil, {
			outfitID = outfitID,
		})
	end

	local CLEAR_OUTFIT_TITLES_DIALOG = "MOGTROT_CLEAR_OUTFIT_TITLES"

	StaticPopupDialogs[CLEAR_OUTFIT_TITLES_DIALOG] = {
		text = "Clear every linked title from outfit '%s'?\n\n"
			.. "This affects only this outfit and cannot be undone.",
		button1 = "Clear titles",
		button2 = CANCEL or "Cancel",
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
		OnAccept = function(_popup, data)
			if type(data) ~= "table" or not data.outfitID then return end
			if not C_TransmogOutfitInfo.GetOutfitInfo(data.outfitID) then
				Addon:Warn("could not clear titles because that outfit no longer exists.")
				return
			end
			ClearOutfitTitles(data.outfitID)
		end,
	}

	local function ConfirmClearOutfitTitles(outfitID, outfitName)
		if not outfitID or CountOutfitTitles(outfitID) == 0 then return end
		StaticPopup_Show(CLEAR_OUTFIT_TITLES_DIALOG, outfitName or "Outfit", nil, {
			outfitID = outfitID,
		})
	end

	local function ShowOutfitMenu(row)
		local outfitID = row.outfitID
		local outfitName = row.outfitName

		MenuUtil.CreateContextMenu(row, function(_owner, root)
			root:CreateTitle(row.outfitName or "Outfit")

			local mountCount = Addon:CountOutfitMounts(outfitID)
			root:CreateButton(
				mountCount > 0 and ("Mounts (%d)"):format(mountCount) or "Link mounts",
				function() Addon:OpenMountPicker(outfitID) end)

			if mountCount > 0 then
				root:CreateButton("Copy mounts to...", function()
					OpenCopyMounts(outfitID)
				end)

				root:CreateButton("Clear mounts", function()
					ConfirmClearOutfitMounts(outfitID, outfitName)
				end)
			end

			root:CreateCheckbox("Shuffle in pinned mounts", function()
				return not MogtrotCharDB.noPinnedShuffle[outfitID]
			end, function()
				MogtrotCharDB.noPinnedShuffle[outfitID] =
					not MogtrotCharDB.noPinnedShuffle[outfitID] and true or nil
				return MenuResponse.Refresh
			end)

			root:CreateDivider()

			local titleCount = CountOutfitTitles(outfitID)
			root:CreateButton(
				titleCount > 0 and ("Titles (%d)"):format(titleCount) or "Link titles",
				function() OpenTitlePicker(outfitID) end)

			if titleCount > 0 then
				root:CreateButton("Copy titles to...", function()
					OpenCopyTitles(outfitID)
				end)

				root:CreateButton("Clear titles", function()
					ConfirmClearOutfitTitles(outfitID, outfitName)
				end)
			end

			root:CreateDivider()

			root:CreateButton("Move to...", function()
				OpenMoveOutfit(outfitID, row.outfitName)
			end)

			root:CreateButton("Move up", function() Addon:MoveOutfitBySteps(outfitID, -1) end)
			root:CreateButton("Move down", function() Addon:MoveOutfitBySteps(outfitID, 1) end)

			root:CreateDivider()

			local canEdit = Addon:CanEditOutfitInfo()
			local editButton = root:CreateButton(
				canEdit and "Edit name and icon" or "Edit name and icon (needs Blizzard's list open)",
				function() Addon:OpenOutfitEditPopup(outfitID) end)
			editButton:SetEnabled(canEdit)

			root:CreateButton("Pick up for the action bar", function()
				if not InCombatLockdown() then
					C_TransmogOutfitInfo.PickupOutfit(outfitID)
				end
			end)
		end)
	end

	local function ShowCategoryMenu(header)
		local catID = header.catID
		local cat = MogtrotCharDB.cats[catID]
		if not cat then return end

		MenuUtil.CreateContextMenu(header, function(_owner, root)
			root:CreateTitle(cat.name)

			root:CreateButton("Add sub-category", function()
				Addon:CreateCategory(NEW_CATEGORY_NAME, catID, true)
			end)

			if not cat.protected then
				root:CreateButton("Rename", function() Addon:BeginRename(catID) end)
			end

			root:CreateDivider()
			root:CreateButton("Move up", function() Addon:MoveCategoryBySteps(catID, -1) end)
			root:CreateButton("Move down", function() Addon:MoveCategoryBySteps(catID, 1) end)

			if not cat.protected then
				root:CreateButton("Move into...", function()
					OpenMoveCategory(catID, cat.name)
				end)
			end

			root:CreateDivider()
			root:CreateButton("Add category", function()
				Addon:CreateCategory(NEW_CATEGORY_NAME, nil, true)
			end)

			if not cat.protected then
				root:CreateButton(RED_FONT_COLOR:WrapTextInColorCode("Delete category"), function()
					Addon:DeleteCategory(catID)
				end)
			end
		end)
	end

	local frame = CreateFrame("Frame", "MogtrotFrame", UIParent, "BackdropTemplate")
	Addon.window = frame
	Addon.frame = frame
		frame:SetSize(MainWindow.Width, 200)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if InCombatLockdown() then return end
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, relPoint, x, y = self:GetPoint()
		MogtrotDB.position = { point = point, relPoint = relPoint, x = x, y = y }
	end)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0, 0, 0, 0.92)
	frame:Hide()

	frame.Title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		frame.Title:SetPoint("TOPLEFT", UI.Pad, -UI.Pad)
	frame.Title:SetJustifyH("LEFT")
	frame.Title:SetWordWrap(false)

	frame.CloseButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.CloseButton:SetPoint("TOPRIGHT", 0, 0)

	frame.NewCategoryButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	frame.NewCategoryButton:SetText("Add category")
	-- Width from the label rather than a guess, so the button never crops its text
	-- and never leaves a gap when the wording changes.
		frame.NewCategoryButton:SetSize(frame.NewCategoryButton:GetTextWidth() + 20, MainWindow.HeaderButtonHeight)
	local newCategoryLabel = frame.NewCategoryButton:GetFontString()
	newCategoryLabel:ClearAllPoints()
	newCategoryLabel:SetAllPoints()
	newCategoryLabel:SetJustifyH("CENTER")
	frame.NewCategoryButton:SetPoint("LEFT", frame.Title, "RIGHT", 4, 0)
	frame.NewCategoryButton:SetScript("OnClick", function()
		Addon:CreateCategory(NEW_CATEGORY_NAME, nil, true)
	end)
	frame.NewCategoryButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Add category")
		GameTooltip:AddLine("Added at the top. Use a category's own + for a sub-category.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	frame.NewCategoryButton:SetScript("OnLeave", GameTooltip_Hide)

	-- Account macros occupy the first block of indices, so the nth is index n. Neither
	-- macro does anything character-specific - one opens the window, the other runs the
	-- same summon the keybinding runs - so both belong to the account rather than being
	-- remade on each alt. From the client's own constant, with today's value as a
	-- fallback if a build stops defining it.
	local ACCOUNT_MACRO_CAP = MAX_ACCOUNT_MACROS or 120

	-- Blizzard's own "summon a random favourite mount" button is this spell
	-- (Blizzard_MountCollection.xml:222), so its texture is the icon a user already
	-- reads as "put me on a mount".
	local RANDOM_FAVOURITE_SPELL_ID = 150544
	local OPEN_MACRO_DRAG_ICON = 2869702

	-- CreateMacro wants a fileID, not a path: handed the TOC's icon path it stores
	-- the default cog instead. Spell textures are fileIDs already, and these two are
	-- the icons the created macros use on the action bar.
	local function MacroIcon(command)
		if command == Macro.SUMMON then
			return C_Spell.GetSpellTexture(RANDOM_FAVOURITE_SPELL_ID)
		end
		return OPEN_MACRO_DRAG_ICON
	end

	local function AccountMacroBody(slot)
		return GetMacroBody(slot)
	end

	local function AccountMacroCount()
		local account = GetNumMacros()
		return account or 0
	end

	-- Asked before the drag rather than reported after it, so a full macro list is a
	-- tooltip line instead of a gesture that silently does nothing. Per command: one
	-- free slot and neither macro made means the first drag works and the second does
	-- not, and each handle has to say so for itself.
	function Addon:CanOfferMacro(command)
		return Macro.CanOffer(AccountMacroCount(), AccountMacroBody, command,
			ACCOUNT_MACRO_CAP)
	end

	function Addon.UpdateMacroIcon(_self, slot, command)
		if InCombatLockdown() then return false end
		local currentIcon = select(2, GetMacroInfo(slot))
		local icon = Macro.IconToApply(command, currentIcon, MacroIcon(command))
		if not icon then return false end
		EditMacro(slot, nil, icon, nil)
		return true
	end

	function Addon:UpdateOwnedOpenMacroIcon()
		local slot = Macro.Find(AccountMacroCount(), AccountMacroBody, Macro.OPEN)
		if slot then self:UpdateMacroIcon(slot, Macro.OPEN) end
	end

	-- A macro index for the cursor, or nil and a reason. Reuse before create: the
	-- marker line in the body is what finds ours again, so renaming it, editing it,
	-- or dragging a second time cannot produce a duplicate. Macro slots are the
	-- user's and scarce, so one is never taken without saying so.
	function Addon:AcquireMacro(command)
		local action, slot = Macro.Plan(AccountMacroCount(), AccountMacroBody,
			command, ACCOUNT_MACRO_CAP)

		if action == "reuse" then
			self:UpdateMacroIcon(slot, command)
			return slot
		end
		if action == "full" then return nil, "full" end

		-- Tested in the drag handler too. That one is the cheap refusal with a
		-- specific message; this one guards the write, which is what combat blocks,
		-- and combat can start between the two.
		if InCombatLockdown() then return nil, "combat" end

		local perCharacter = false
		local name = Macro.NameOf(command)
		local body = Macro.Body(command)
		-- Argument order is Blizzard's own: name, icon, body, perCharacter
		-- (Blizzard_MacroIconSelector.lua:109).
		local index = CreateMacro(name, MacroIcon(command), body, perCharacter)
		if not index then return nil, "failed" end

		-- Trust nothing about what the client stored. CreateMacro's argument order has
		-- been got wrong before, and a macro whose body is not what we wrote runs as
		-- chat text on a bar the user has already committed to.
		local stored = GetMacroBody(index)
		if stored and strtrim(stored) ~= body then
			self:Warn("the macro was created with the wrong body - please report this "
				.. "with /mogtrot macro")
		end

		self:Say('created a general macro called "%s". Drop it on an action bar.', name)
		return index
	end

	function Addon:RepairSummonMacro()
		if InCombatLockdown() then return end
		local slot = Macro.RepairPlan(AccountMacroCount(), AccountMacroBody, Macro.SUMMON)
		if not slot then return end
		local body = Macro.Body(Macro.SUMMON)
		EditMacro(slot, nil, nil, body)
		if GetMacroBody(slot) ~= body then
			self:Warn("the summon macro did not update; delete and drag it again.")
		end
	end

	-- Two handles rather than one handle plus a modifier: both macros are then
	-- discoverable by hovering, with no gesture to learn. Same button, different
	-- command behind it, so the shape lives in one place.
	local MACRO_DRAG_SIZE = 20

	local function CreateMacroDrag(command, title, description)
		local button = CreateFrame("Button", nil, frame)
		button:SetSize(MACRO_DRAG_SIZE, MACRO_DRAG_SIZE)
		button:RegisterForDrag("LeftButton")

		button.Icon = button:CreateTexture(nil, "ARTWORK")
		button.Icon:SetAllPoints()
		button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		button.Icon:SetTexture(MacroIcon(command))
		button.Icon:SetVertexColor(0.75, 0.75, 0.75)

		button:SetScript("OnEnter", function(self)
			self.Icon:SetVertexColor(1, 1, 1)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(title)
			GameTooltip:AddLine(description, 0.6, 0.6, 0.6, true)
			-- Asked per command and per hover: with one slot left and neither macro
			-- made, both handles work, and whichever is dragged first takes it.
			if not Addon:CanOfferMacro(command) then
				GameTooltip:AddLine(" ")
				GameTooltip:AddLine(("No free general macro slots (%d of %d used)."):format(
					AccountMacroCount(), ACCOUNT_MACRO_CAP), 1, 0.3, 0.3, true)
			end
			GameTooltip:Show()
		end)

		button:SetScript("OnLeave", function(self)
			self.Icon:SetVertexColor(0.75, 0.75, 0.75)
			GameTooltip:Hide()
		end)

		button:SetScript("OnDragStart", function()
			if InCombatLockdown() then
				UIErrorsFrame:AddMessage("Mogtrot: can't make a macro in combat.", 1, 0.3, 0.3)
				return
			end

			local index, reason = Addon:AcquireMacro(command)
			if not index then
				if reason == "full" then
					Addon:Warn("no free general macro slots. Delete one and drag again.")
				end
				return
			end

			PickupMacro(index)
		end)

		return button
	end

	-- Drag to a bar for a macro that opens the window. Worth having over a plain
	-- keybinding because /click on the secure toggle is legal in combat.
	frame.MacroDrag = CreateMacroDrag(Macro.OPEN, "Macro for the action bar",
		"Drag to a bar. Makes one general macro that opens this window, and reuses "
		.. "that same one every time after.")
	-- The right-hand button hangs off the frame's right edge, the left-hand one off
	-- the right-hand one, and the search box off the left-hand one - never the
	-- reverse. That way the box absorbs the whole of any width change and neither
	-- button can drift onto the other or onto the box.
		frame.MacroDrag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -UI.Pad, -(UI.Pad + 18))

	-- The same summon the keybinding does, on a bar. Its own handle rather than a
	-- modifier on the one above, so hovering finds it.
	frame.SummonDrag = CreateMacroDrag(Macro.SUMMON, "Mount macro for the action bar",
		"Drag to a bar. Makes one general macro that summons a mount for the outfit "
		.. "you are wearing - the same thing the summon keybinding does.")
	frame.SummonDrag:SetPoint("TOPRIGHT", frame.MacroDrag, "TOPLEFT", -4, 0)

	frame.SettingsButton = CreateFrame("Button", nil, frame)
		frame.SettingsButton:SetSize(MainWindow.HeaderButtonHeight, MainWindow.HeaderButtonHeight)
		frame.SettingsButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -26, -UI.Pad + 1)

	frame.SettingsButton.Icon = frame.SettingsButton:CreateTexture(nil, "ARTWORK")
	frame.SettingsButton.Icon:SetAllPoints()
	frame.SettingsButton.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	frame.SettingsButton.Icon:SetTexture(136243)
	frame.SettingsButton.Icon:SetVertexColor(0.4, 0.4, 0.4)
	frame.SettingsButton:Disable()
	frame.SettingsButton:SetScript("OnClick", function()
		if Addon.settingsCategory and Settings and Settings.OpenToCategory then
			Settings.OpenToCategory(Addon.settingsCategory:GetID())
		end
	end)
	frame.SettingsButton:SetScript("OnEnter", function(self)
		self.Icon:SetVertexColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Mogtrot settings")
		GameTooltip:Show()
	end)
	frame.SettingsButton:SetScript("OnLeave", function(self)
		self.Icon:SetVertexColor(0.75, 0.75, 0.75)
		GameTooltip:Hide()
	end)


	frame.SearchBox = CreateFrame("EditBox", nil, frame, "SearchBoxTemplate")
	frame.SearchBox:SetHeight(20)
	frame.SearchBox:SetAutoFocus(false)
		frame.SearchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.Pad + 6, -(UI.Pad + 18))
	frame.SearchBox:SetPoint("TOPRIGHT", frame.SummonDrag, "TOPLEFT", -6, 0)
	if frame.SearchBox.Instructions then
		frame.SearchBox.Instructions:SetText("Search outfits and categories")
	end
	frame.SearchBox:HookScript("OnTextChanged", function(self)
		local text = strtrim(self:GetText() or "")
		local query = (text ~= "") and strlower(text) or nil
		if query == Addon.searchText then return end
		Addon.searchText = query
		Addon.scrollToTop = true
		Addon:Refresh()
	end)

	frame.Notice = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		frame.Notice:SetPoint("BOTTOMLEFT", UI.Pad, 8)
		frame.Notice:SetPoint("BOTTOMRIGHT", -UI.Pad, 8)
	frame.Notice:SetJustifyH("LEFT")

	Addon.listBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
		Addon.listBox:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.Pad, -(UI.Pad + 18 + MainWindow.SearchRowHeight))
	-- Width is fixed because the window only resizes vertically; the 10px gutter is the bar.
		Addon.listBox:SetSize(MainWindow.Width - 2 * UI.Pad - 10, MainWindow.MinListHeight)

	Addon.listBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	Addon.listBar:SetPoint("TOPLEFT", Addon.listBox, "TOPRIGHT", 2, 0)
	Addon.listBar:SetPoint("BOTTOMLEFT", Addon.listBox, "BOTTOMRIGHT", 2, 0)

	Addon.listView = CreateScrollBoxListLinearView()

	-- Headers and outfit rows are different heights, which is the whole reason this needs
	-- an extent calculator rather than a single element extent.
	Addon.listView:SetElementExtentCalculator(function(_dataIndex, entry)
		return entry.kind == "cat" and MainWindow.HeaderHeight or MainWindow.RowHeight
	end)

	-- Indent moves the left edge only; the view stretches every row to the right edge, so
	-- nested rows line up on the right exactly as the hand-rolled layout did.
	-- Indent stops growing well before it can eat the row. Nesting past this still
	-- nests, it just stops stepping right: unbounded indent took the row width to
	-- nothing around depth 20, and a name is worth more than the depth cue.
	local MAX_INDENT_DEPTH = 6

	Addon.listView:SetElementIndentCalculator(function(entry)
		return math.min(entry.depth, MAX_INDENT_DEPTH) * MainWindow.Indent
	end)

	Addon.listView:SetElementFactory(function(factory, entry)
		if entry.kind == "cat" then
			factory("Button", function(header, data) Addon:InitHeaderRow(header, data) end)
		else
			factory(UI.ActionButtonTemplate, function(row, data) Addon:InitOutfitRow(row, data) end)
		end
	end)

	-- Otherwise a wheel tick is however tall the first entry happens to be, so the distance
	-- changed depending on whether the list started on a header.
	Addon.listView:SetPanExtent(MainWindow.RowHeight)

	ScrollUtil.InitScrollBoxListWithScrollBar(Addon.listBox, Addon.listBar, Addon.listView)
	-- Hides the bar when there is nothing to scroll. Held rather than discarded so its
	-- lifetime does not depend on Blizzard's callback table keeping it reachable.
	Addon.listBarVisibility = ScrollUtil.AddManagedScrollBarVisibilityBehavior(Addon.listBox, Addon.listBar)

	Addon.listBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate, function()
		Addon:OnListUpdated()
	end, Addon)

	-- Drag feedback lives on its own frames: rows are child frames and would otherwise
	-- draw on top of textures belonging to the window itself. Parented to the ScrollBox so
	-- its clipping applies to the feedback as well as to the rows it points at.
	local function CreateOverlay(alpha, height)
		local overlay = CreateFrame("Frame", nil, Addon.listBox)
		overlay:SetFrameLevel(Addon.listBox:GetFrameLevel() + 50)
		if height then overlay:SetHeight(height) end
		overlay.Texture = overlay:CreateTexture(nil, "OVERLAY")
		overlay.Texture:SetAllPoints()
		overlay.Texture:SetColorTexture(1, 0.82, 0, alpha)
		overlay:Hide()
		return overlay
	end

	frame.InsertMarker = CreateOverlay(0.9, 2)

	-- Shown when a drop would go *into* a category rather than between rows.
	frame.DropInto = CreateOverlay(0.25)

	-- The ScrollBox owns the wheel over the list itself. This covers the rest of the window
	-- - search row, pinned row, footer - so the wheel is never dead over a Mogtrot frame.
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_self, delta)
		Addon.listBox:OnMouseWheel(delta)
	end)

	-- The button is bigger than the art it draws, so the corner is easy to grab
	-- rather than being a 16px target you have to aim at.
	frame.ResizeGrip = CreateFrame("Button", nil, frame)
	frame.ResizeGrip:SetSize(24, 24)
	frame.ResizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
	frame.ResizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	frame.ResizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	for _, texture in ipairs({ frame.ResizeGrip:GetNormalTexture(),
		frame.ResizeGrip:GetHighlightTexture() }) do
		texture:ClearAllPoints()
		texture:SetSize(16, 16)
		texture:SetPoint("BOTTOMRIGHT", -2, 2)
	end
	frame.ResizeGrip:SetScript("OnMouseDown", function(self)
		-- Resizing a frame holding secure children is not allowed in combat.
		if InCombatLockdown() then return end
		self.resizing = true
		self.startY = select(2, GetCursorPosition())
		self.startHeight = Addon:GetListHeight()
		self:SetScript("OnUpdate", function(grip)
			local _, cursorY = GetCursorPosition()
			local delta = (grip.startY - cursorY) / UIParent:GetEffectiveScale()
			Addon:SetListHeight(grip.startHeight + delta)
		end)
	end)
	frame.ResizeGrip:SetScript("OnMouseUp", function(self)
		self.resizing = nil
		self:SetScript("OnUpdate", nil)
	end)
	frame.ResizeGrip:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Drag to resize the list")
		GameTooltip:Show()
	end)
	frame.ResizeGrip:SetScript("OnLeave", GameTooltip_Hide)

	-- Inline editor for creating and renaming categories.
	local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	Addon.editBox = editBox
	editBox:SetAutoFocus(false)
	editBox:SetHeight(20)
	-- Above the rows, and outside the ScrollBox so it is never clipped: the header it
	-- annotates lives two levels down inside the scroll target.
	editBox:SetFrameLevel(Addon.listBox:GetFrameLevel() + 60)
	editBox:Hide()
	editBox:SetScript("OnEnterPressed", function() Addon:CommitEdit() end)
	editBox:SetScript("OnEscapePressed", function() Addon:CancelEdit() end)
	editBox:SetScript("OnEditFocusLost", function() Addon:CommitEdit() end)

	function Addon:BeginRename(catID)
		if InCombatLockdown() then return end
		self.editing = catID
		self.editingNeedsFocus = true
		self:Refresh()
	end

	function Addon:CommitEdit()
		local catID = self.editing
		if not catID then return end
		self.editing = nil
		self.editingNeedsFocus = nil
		local text = editBox:GetText()
		editBox:Hide()
		editBox:ClearFocus()
		self:RenameCategory(catID, text)
	end

	function Addon:CancelEdit()
		if not self.editing then return end
		self.editing = nil
		self.editingNeedsFocus = nil
		editBox:Hide()
		editBox:ClearFocus()
		self:Refresh()
	end

	-- Runs at the end of every ScrollBox update, plain scrolling included. The editor is
	-- parented to the window rather than to a row, so recycling cannot strand it - but that
	-- also means this is the only thing that ever re-anchors it.
	function Addon:OnListUpdated()
		-- Play here, not in Refresh: the frame is only realised once the scroll lands,
		-- and this fires on every list update including that one.
		if self.flash then
			if GetTime() > self.flash.expires then
				self.flash = nil
			else
				local want = self.flash
				local target = self.listBox:FindFrameByPredicate(function(_frame, entry)
					local id = entry.kind == "cat" and entry.catID or entry.outfitID
					return entry.kind == want.kind and id == want.id
				end)
				if target and target.FlashAnim then
					self.flash = nil
					target.FlashAnim:Stop()
					target.FlashAnim:Play()
				end
			end
		end

		if self.editing then
			local header = self.listBox:FindFrameByPredicate(function(_rowFrame, entry)
				return entry.kind == "cat" and entry.catID == self.editing
			end)

			if header then
				editBox:ClearAllPoints()
				editBox:SetPoint("LEFT", header.Arrow, "RIGHT", 4, 0)
				editBox:SetWidth(header:GetWidth() - 60)
				editBox:Show()
				if self.editingNeedsFocus then
					self.editingNeedsFocus = nil
					local cat = MogtrotCharDB.cats[self.editing]
					editBox:SetText(cat and cat.name or "")
					editBox:SetFocus()
					editBox:HighlightText()
				end
			else
				-- The category scrolled out of view, so drop the edit. Cleared by hand rather
				-- than through CancelEdit, which refreshes and would re-enter this update.
				-- Clearing self.editing first is what makes the resulting OnEditFocusLost a
				-- no-op instead of a rename.
				self.editing = nil
				self.editingNeedsFocus = nil
				editBox:Hide()
				editBox:ClearFocus()
			end
		end

		local view = self.listView
		local total = view:GetDataProviderSize()
		self.positionText = (total > 0 and self.listBox:HasScrollableExtent())
			and string.format("rows %d-%d of %d", view:GetDataIndexBegin(), view:GetDataIndexEnd(), total)
			or nil
		self:UpdateNotice()
	end

	local function RemoveEscapeFrame()
		for index = #UISpecialFrames, 1, -1 do
			if UISpecialFrames[index] == "MogtrotFrame" then
				table.remove(UISpecialFrames, index)
			end
		end
	end

	function Addon:SetEscapeClosing(enabled)
		RemoveEscapeFrame()
		if enabled then table.insert(UISpecialFrames, "MogtrotFrame") end
	end

	-- Blizzard cannot hide a frame referenced by secure controls while combat is
	-- locked down. Outside combat, UISpecialFrames gives the window normal ESC behavior.
	Addon:SetEscapeClosing(not InCombatLockdown())

	-- Secure toggle: lets "/click MogtrotToggle" and a keybinding open the frame,
	-- legally, even in combat. Deliberately unparented and never shown.
	local toggle = CreateFrame("Button", "MogtrotToggle", nil, "SecureHandlerClickTemplate")
	toggle:SetSize(1, 1)
	toggle:RegisterForClicks("AnyUp")
	toggle:SetFrameRef("main", frame)
	toggle:SetAttribute("_onclick", [[
		local f = self:GetFrameRef("main")
		if f:IsShown() then
			f:Hide()
		else
			f:Show()
		end
	]])

	-- The ordinary Mogtrot route, with a conditional secure proxy to LiteMount's
	-- published LM_B1 button when the pure plan delegates.
	local summonClick = CreateFrame("Button", "MogtrotSummon", nil,
		"SecureActionButtonTemplate")
	summonClick:SetSize(1, 1)
	summonClick:RegisterForClicks("AnyDown", "AnyUp")
	summonClick:SetAttribute("useOnKeyDown", false)

	local function ClearSummonClick()
		summonClick:SetAttribute("type", nil)
		summonClick:SetAttribute("*clickbutton1", nil)
	end

	summonClick:SetScript("PreClick", function()
		if InCombatLockdown() then
			Addon:SummonForActiveOutfit(false)
			return
		end
		ClearSummonClick()
		if Addon:SummonForActiveOutfit(true) then
			summonClick:SetAttribute("type", "click")
			summonClick:SetAttribute("*clickbutton1", _G.LM_B1)
		end
	end)
	summonClick:SetScript("PostClick", function()
		if not InCombatLockdown() then ClearSummonClick() end
	end)
	summonClick:RegisterEvent("PLAYER_REGEN_DISABLED")
	summonClick:SetScript("OnEvent", function()
		ClearSummonClick()
	end)

	BINDING_HEADER_MOGTROT = "Mogtrot"
	_G["BINDING_NAME_CLICK MogtrotToggle:LeftButton"] = "Toggle outfit list"
	_G["BINDING_NAME_CLICK MogtrotSummon:LeftButton"] = "Summon a mount for this outfit"

	-- Opens Blizzard's outfit list, where locking, renaming and icons live. That window
	-- can be shown anywhere - no transmogrifier needed - but it takes a real click on a
	-- secure handler: calling Click() from addon code carries taint and is refused.
	--
	-- Styled by hand rather than with UIPanelButtonTemplate: combining templates lets the
	-- button template's OnLoad replace SecureHandlerBaseTemplate's, and that OnLoad is what
	-- installs SetFrameRef and the restricted environment. Re-running it by hand is not an
	-- option either, since the template's own OnClick has to stay untainted.
	local blizzardListButton = CreateFrame("Button", "MogtrotBlizzardList", frame,
		"SecureHandlerClickTemplate")
		blizzardListButton:SetSize(MainWindow.HeaderButtonHeight, MainWindow.HeaderButtonHeight)
	blizzardListButton:SetPoint("RIGHT", frame.SettingsButton, "LEFT", -4, 0)
	blizzardListButton:RegisterForClicks("AnyUp")

	blizzardListButton.Icon = blizzardListButton:CreateTexture(nil, "ARTWORK")
	blizzardListButton.Icon:SetAllPoints()
	blizzardListButton.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	-- Blizzard's own transmogrify icon, the one their transmogrifier UI uses, so the
	-- button reads as "their window" rather than as another Mogtrot control. Falls
	-- back to the equip spell's icon if the art is ever renamed.
	blizzardListButton.Icon:SetTexture("Interface\\Icons\\INV_Misc_EngGizmos_19")
	if not blizzardListButton.Icon:GetTexture() then
		blizzardListButton.Icon:SetTexture(C_Spell.GetSpellTexture(EQUIP_SPELL_ID))
	end
	blizzardListButton.Icon:SetVertexColor(0.75, 0.75, 0.75)
	blizzardListButton:SetAttribute("_onclick", [[
		local f = self:GetFrameRef("transmog")
		if not f then return end
		if f:IsShown() then
			f:Hide()
		else
			f:Show()
		end
	]])
	blizzardListButton:SetScript("PreClick", function(self)
		if InCombatLockdown() then return end
		-- Blizzard_Transmog is load-on-demand, so it may not exist until now.
		if not TransmogFrame and Transmog_LoadUI then
			Transmog_LoadUI()
		end
		if TransmogFrame then
			self:SetFrameRef("transmog", TransmogFrame)
		end
	end)
	blizzardListButton:SetScript("OnEnter", function(self)
		self.Icon:SetVertexColor(1, 1, 1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Blizzard's outfit list")
		GameTooltip:AddLine("Locking, renaming and icons only work there. No NPC needed.",
			0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	local function LayoutTitleBar()
		local rightControls = 26 + MainWindow.HeaderButtonHeight * 2 + 4 + 8
		local available = MainWindow.Width - UI.Pad - rightControls
			- frame.NewCategoryButton:GetWidth() - 4
		frame.Title:SetWidth(math.max(20, math.min(frame.Title:GetStringWidth(), available)))
	end

	blizzardListButton:SetScript("OnLeave", function(self)
		self.Icon:SetVertexColor(0.75, 0.75, 0.75)
		GameTooltip:Hide()
	end)

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
		GameTooltip:AddLine("... on the right opens this outfit's menu", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Drag to reorder", 0.6, 0.6, 0.6)
		GameTooltip:AddLine("Lock from Blizzard's outfit list - no NPC needed", 0.5, 0.5, 0.5)
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

	-- The wear gauge. Fixed width rather than a bar across the row: the row's width
	-- shrinks with nesting depth, so a proportional bar would put a nested outfit and a
	-- top-level one on different scales and stop being comparable, which is the only
	-- thing a bar is for. Anchored to the right edge, where indent never reaches, and
	-- ending level with the name so it clears the mount and menu buttons.
	local WEAR_BAR_W, WEAR_BAR_H = 56, 3
	-- Mogtrot's own light blue, deliberately outside the vocabulary already on this row:
	-- green and yellow belong to the lint dot, gold to the active row and the flash.
	local WEAR_COLOUR = { 0.35, 0.68, 1 }

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
		row.Name:SetPoint("RIGHT", -42, 0)
		row.Name:SetJustifyH("LEFT")
		row.Name:SetWordWrap(false)

		-- The mount slot: a button so it can be clicked, always drawn so the column is
		-- straight and so an outfit with no mounts still has somewhere to click. A
		-- texture alone could not take the click, and the row underneath would wear the
		-- outfit instead.
		row.MountButton = CreateFrame("Button", nil, row)
		row.MountButton:SetSize(22, MainWindow.RowHeight)
		row.MountButton:SetPoint("RIGHT", -34, 0)
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

		-- This row has no room for "11/16", so it carries the state as a dot and the
		-- detail in the tooltip. Immediately left of the name rather than out in the
		-- indicator column: it describes the outfit, so it reads as part of the name.
		-- A greyscale orb tinted per state, rather than a flat colour block: the same
		-- texture reads as a dot instead of a square, and takes any colour.
		row.LintDot = row:CreateTexture(nil, "OVERLAY")
		row.LintDot:SetTexture("Interface\\COMMON\\Indicator-Gray")
		row.LintDot:SetSize(11, 11)
		row.LintDot:SetPoint("RIGHT", row.Name, "LEFT", -2, 0)

		-- A StatusBar rather than a texture, so the widget does the proportional fill
		-- and nothing here has to know the row's width at paint time. A pooled row
		-- cannot be trusted to report that anyway: the view sizes it around the
		-- initialiser, so a recycled frame answers for whatever it was last.
		-- Created hidden, since a frame is shown by default and only a worn outfit
		-- should carry one. The 42 matches row.Name's right inset.
		row.WearBar = CreateFrame("StatusBar", nil, row)
		row.WearBar:SetSize(WEAR_BAR_W, WEAR_BAR_H)
		row.WearBar:SetPoint("BOTTOMRIGHT", -64, 1)
		row.WearBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
		row.WearBar:SetMinMaxValues(0, 1)
		row.WearBar:Hide()

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

		-- The menu also lives on a button of its own, so reaching it never depends on
		-- what right-click happens to be bound to.
		row.MenuButton = CreateFrame("Button", nil, row)
		row.MenuButton:SetSize(18, MainWindow.RowHeight)
		row.MenuButton:SetPoint("RIGHT", 0, 0)
		row.MenuButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row.MenuButton.Text = row.MenuButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		row.MenuButton.Text:SetAllPoints()
		row.MenuButton.Text:SetText("...")
		row.MenuButton.Text:SetTextColor(0.7, 0.7, 0.7)
		row.MenuButton:SetScript("OnClick", function(self)
			local parent = self:GetParent()
			if parent.outfitID then ShowOutfitMenu(parent) end
		end)
		row.MenuButton:SetScript("OnEnter", function(self)
			self.Text:SetTextColor(1, 1, 1)
		end)
		row.MenuButton:SetScript("OnLeave", function(self)
			self.Text:SetTextColor(0.7, 0.7, 0.7)
		end)

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

	-- Read fresh per row rather than cached across a refresh, for two reasons: the open
	-- interval grows, so a cached snapshot would freeze the bar of the outfit being
	-- worn; and rows are realised by scrolling long after the last refresh, when a
	-- cache would be stale in exactly the way pooled frames punish.
	function Addon:PaintWearBar(row, outfitID)
		local bar = row.WearBar
		if not bar then return end

		if not Wear.ShowInList(MogtrotDB) then
			bar:Hide()
			return
		end

		local snapshot = self:WearSnapshot()
		local seconds = snapshot.totals[outfitID] or 0
		-- Nothing at all for an outfit never worn, so "never" and "barely" do not
		-- read as the same thing, and 40 untouched rows carry no clutter.
		if seconds <= 0 then
			bar:Hide()
			return
		end

		local heat = Wear.Heat(snapshot.max, seconds)
		bar:SetValue(heat)
		bar:SetStatusBarColor(WEAR_COLOUR[1], WEAR_COLOUR[2], WEAR_COLOUR[3], 0.45 + 0.55 * heat)
		bar:Show()
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

		row.outfitID = info.outfitID
		row.outfitName = info.name
		row.Icon:SetTexture(info.icon)
		row.Name:SetText(info.name)
		row.Name:ClearAllPoints()
		row.Name:SetPoint("LEFT", row.Icon, "RIGHT", Lint.NameInset(MogtrotDB), 0)
		row.Name:SetPoint("RIGHT", -64, 0)
		row.Active:SetShown(info.outfitID == activeOutfitID)
		row.MenuButton:Show()

		-- A pooled frame arrives carrying whatever the drag and hover handlers last left on it.
		row:SetAlpha(1)
		row.Highlight:Hide()

		local mounts = MogtrotCharDB.mounts[info.outfitID]
		local firstMountID, mountCount = nil, 0
		for mountID in pairs(mounts or {}) do
			mountCount = mountCount + 1
			if not firstMountID or mountID < firstMountID then firstMountID = mountID end
		end

		-- The slot is always shown, so an outfit with no mounts is an empty square to
		-- click rather than nothing at all. Pooled rows arrive carrying the last
		-- outfit's state, so both branches have to set everything.
		row.MountButton:Show()
		if firstMountID then
			local _name, _spellID, mountIcon = C_MountJournal.GetMountInfoByID(firstMountID)
			row.MountIcon:SetTexture(mountIcon)
			row.MountIcon:Show()
			row.MountCount:SetText(mountCount > 1 and mountCount or "")
			row.MountCount:SetShown(mountCount > 1)
		else
			row.MountIcon:Hide()
			row.MountCount:Hide()
		end

		local titleCount = CountOutfitTitles(info.outfitID)
		row.TitleButton:Show()
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

		-- Same rule: both branches of this set everything, including the hidden one.
		self:PaintWearBar(row, info.outfitID)

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
			self.clearRow.MenuButton:Hide()
			self.clearRow.LockOverlay:Hide()
			-- "Show equipped gear" is not an outfit, so it has no mount slot and nothing
			-- to measure.
			self.clearRow.MountButton:Hide()
			self.clearRow.TitleButton:Hide()
			self.clearRow.LintDot:Hide()
			self.clearRow:SetAttribute("type", "outfit")
			self.clearRow:SetAttribute("action", "clear")
			self.clearRow.Cooldown:Clear()
			self.clearRow:Show()
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
			self.Background:SetColorTexture(0.35, 0.35, 0.42, 0.8)
		end)
		header:SetScript("OnLeave", function(self)
			self.Background:SetColorTexture(0.25, 0.25, 0.3, 0.7)
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
		header.Background:SetColorTexture(0.25, 0.25, 0.3, 0.7)
		header:SetAlpha(1)
	end

	-- Returns where the current drag would land:
	--   { mode = "into", catID }                     drop inside a category
	--   { mode = "outfit", catID, index }            insert an outfit at a position
	--   { mode = "cat", parentID, index }            insert a category at a position
	function Addon:GetDropTarget()
		local drag = self.drag
		if not drag then return end

		local char = MogtrotCharDB
		local _, cursorY = GetCursorPosition()
		cursorY = cursorY / UIParent:GetEffectiveScale()

		-- A row scrolled half out of the list still has real edges, because the ScrollBox
		-- clips it rather than moving it. Without this the cursor could resolve to a row the
		-- user cannot see, and the drop would land somewhere they never pointed at.
		local listTop, listBottom = self.listBox:GetTop(), self.listBox:GetBottom()
		if not listTop or not listBottom then return end
		if cursorY > listTop or cursorY < listBottom then return end

		-- Read from the frames the view currently has realised. Nothing is cached: a
		-- recycling view reassigns frames to different entries as it scrolls.
		return self.listBox:ForEachFrame(function(rowFrame, entry)
			local frameTop, frameBottom = rowFrame:GetTop(), rowFrame:GetBottom()
			if not frameTop or not frameBottom then return end

			-- Hit-test against the visible part, but measure the thirds against the whole
			-- row, so a half-clipped row still splits where its edges really are.
			if cursorY > math.min(frameTop, listTop) or cursorY < math.max(frameBottom, listBottom) then
				return
			end

			local height = frameTop - frameBottom
			local fromTop = frameTop - cursorY

			if entry.kind == "cat" then
				local cat = char.cats[entry.catID]
				if not cat then return end

				if drag.kind == "outfit" then
					-- Anywhere on a header means "put it in this category".
					return { mode = "into", catID = entry.catID, anchor = rowFrame }
				end

				-- Dragging a category: edges reorder, the middle re-parents.
				if fromTop < height * 0.3 then
					local siblings = Tree.SiblingList(char, cat.parent)
					return { mode = "cat", parentID = cat.parent, index = Tree.IndexInList(siblings, entry.catID),
						anchor = rowFrame, edge = "TOP" }
				elseif fromTop > height * 0.7 then
					local siblings = Tree.SiblingList(char, cat.parent)
					return { mode = "cat", parentID = cat.parent, index = (Tree.IndexInList(siblings, entry.catID) or 0) + 1,
						anchor = rowFrame, edge = "BOTTOM" }
				end
				return { mode = "into", catID = entry.catID, anchor = rowFrame }
			end

			-- Over an outfit row.
			if drag.kind == "cat" then
				return { mode = "into", catID = entry.catID, anchor = rowFrame }
			end
			if fromTop < height * 0.5 then
				return { mode = "outfit", catID = entry.catID, index = entry.indexInCat,
					anchor = rowFrame, edge = "TOP" }
			end
			return { mode = "outfit", catID = entry.catID, index = entry.indexInCat + 1,
				anchor = rowFrame, edge = "BOTTOM" }
		end)
	end

	function Addon:FinishDrag()
		local drag = self.drag
		if not drag then return end

		-- Resolve the target before clearing the drag: GetDropTarget needs it.
		local target = self:GetDropTarget()

		self.drag = nil
		frame.InsertMarker:Hide()
		frame.DropInto:Hide()
		if not target then return end

		if drag.kind == "outfit" then
			if target.mode == "into" then
				self:MoveOutfit(drag.outfitID, target.catID)
			elseif target.mode == "outfit" then
				self:MoveOutfit(drag.outfitID, target.catID, target.index)
			end
		else
			if target.mode == "into" then
				self:MoveCategory(drag.catID, target.catID)
			elseif target.mode == "cat" then
				self:MoveCategory(drag.catID, target.parentID, target.index)
			end
		end
	end

	frame:SetScript("OnUpdate", function()
		if not Addon.drag then
			-- Keep the preview up while the mouse is anywhere over either window, so
			-- moving between rows does not flicker it.
			if Addon:PreviewIsShown() and not frame:IsMouseOver() and not Addon:IsPreviewHovered() then
				Addon:HidePreview()
			end
			return
		end

		local target = Addon:GetDropTarget()
		local marker, into = frame.InsertMarker, frame.DropInto

		if not target or not target.anchor then
			marker:Hide()
			into:Hide()
			return
		end

		if target.mode == "into" then
			marker:Hide()
			into:ClearAllPoints()
			into:SetPoint("TOPLEFT", target.anchor, "TOPLEFT", 0, 0)
			into:SetPoint("BOTTOMRIGHT", target.anchor, "BOTTOMRIGHT", 0, 0)
			into:Show()
		else
			into:Hide()
			marker:ClearAllPoints()
			marker:SetPoint("LEFT", target.anchor, "LEFT", 0, 0)
			marker:SetPoint("RIGHT", target.anchor, "RIGHT", 0, 0)
			marker:SetPoint("TOP", target.anchor, target.edge == "TOP" and "TOP" or "BOTTOM", 0, 1)
			marker:Show()
		end
	end)

	-- Pixel height of the scrolling area. Defaults to a row count, like Plumber's fixed
	-- ten-row list, then clamped so it can never exceed the screen at any UI scale.
	function Addon:GetListHeight()
		local height = MogtrotDB.listHeight or (MainWindow.DefaultListRows * MainWindow.RowHeight)
		local ceiling = math.max(MainWindow.MinListHeight, UIParent:GetHeight() - 220)
		return math.max(MainWindow.MinListHeight, math.min(height, MainWindow.MaxListHeight, ceiling))
	end

	function Addon:SetListHeight(height)
		MogtrotDB.listHeight = math.max(MainWindow.MinListHeight, math.min(height, MainWindow.MaxListHeight))
		self:UpdateListSize()
	end

	-- The grip drives this every frame while it is held, so it stops at geometry. Resizing
	-- the ScrollBox is enough on its own: it re-lays-out from its own size-changed handler,
	-- and no entry has to be rebuilt for that.
	function Addon:UpdateListSize()
		local contentHeight = self:GetListHeight()

		self.listBox:SetHeight(contentHeight)

		local clearRow = self:EnsureClearRow()
		clearRow:ClearAllPoints()
		-- Pinned below the list rather than after the last entry, so it does not move.
		clearRow:SetPoint("TOPLEFT", frame, "TOPLEFT", UI.Pad,
			-(UI.Pad + 18 + MainWindow.SearchRowHeight + contentHeight))

		-- Constant: chrome + list budget + the pinned row + footer.
		frame:SetHeight(UI.Pad + 18 + MainWindow.SearchRowHeight + contentHeight + MainWindow.RowHeight + 26)
	end

	function Addon:UpdateNotice()
		if InCombatLockdown() then
			frame.Notice:SetText("In combat - wearing an outfit is disabled")
		elseif self.positionText then
			frame.Notice:SetText(self.positionText)
		else
			frame.Notice:SetText("Drag rows and categories to organise")
		end
	end

	-- Greys the list and stops it taking clicks, because the game refuses to wear an
	-- outfit in combat and a row that looks live but does nothing is worse than one
	-- that looks unavailable. Only the list dims: the window, its scrollbar, the close
	-- button and ESC all keep working, which is the point of the rows not being
	-- protected. Applied to the box rather than per row, so pooled frames cannot
	-- arrive carrying a stale state.
	function Addon:SetCombatDimmed(dimmed)
		local clearRow = self:EnsureClearRow()

		if not self.combatShield then
			-- A frame that eats mouse input, rather than disabling each row. Rows are
			-- pooled, so per-row state would have to be re-applied on every paint and
			-- would be wrong the moment one was recycled mid-combat. EnableMouse on the
			-- list box would not do it either: it does not stop children being clicked.
			local shield = CreateFrame("Frame", nil, frame)
			shield:SetFrameLevel(self.listBox:GetFrameLevel() + 100)
			shield:SetPoint("TOPLEFT", self.listBox, "TOPLEFT", 0, 0)
			shield:SetPoint("BOTTOMRIGHT", clearRow, "BOTTOMRIGHT", 0, 0)
			shield:EnableMouse(true)
			shield:Hide()
			self.combatShield = shield
		end

		self.listBox:SetAlpha(dimmed and 0.45 or 1)
		clearRow:SetAlpha(dimmed and 0.45 or 1)
		self.combatShield:SetShown(dimmed)
		self:UpdateNotice()
	end

	function Addon:Refresh(whileHidden)
		if not whileHidden and not frame:IsShown() then return end

		self:SyncOutfits()
		self:UpdateListSize()
		self:PaintClearRow()

		local entries = self:BuildEntries()

		-- A fresh entry table every time means the view never recycles across a refresh, so
		-- rows are always repainted from current data. What is retained is a scroll
		-- percentage, not an entry index, which is how every Blizzard list behaves.
		local retain = ScrollBoxConstants.RetainScrollPosition
		if self.scrollToTop then
			retain = ScrollBoxConstants.DiscardScrollPosition
		end
		self.scrollToTop = nil
		self.listBox:SetDataProvider(CreateDataProvider(entries), retain)

		-- Scroll to something that just moved, so a move from a window does not leave
		-- the user looking at where it used to be. Requested by id and resolved against
		-- the list that now exists: entries are rebuilt every refresh, so holding the
		-- old entry table would scroll to something that no longer is.
		local reveal = self.reveal
		self.reveal = nil
		-- Handed to OnListUpdated rather than played here: the frame may not be
		-- realised until the scroll lands. Time-bounded so a row that never comes into
		-- view does not flash minutes later when it finally does.
		if reveal then self.flash = { kind = reveal.kind, id = reveal.id, expires = GetTime() + 3 } end
		if reveal then
			for i, entry in ipairs(entries) do
				local id = entry.kind == "cat" and entry.catID or entry.outfitID
				if entry.kind == reveal.kind and id == reveal.id then
					self.listBox:ScrollToElementDataIndex(i)
					break
				end
			end
		end

		local titleText = "Outfits"
		if self.searchText then
			local matches = 0
			for _, entry in ipairs(entries) do
				if entry.kind == "outfit" then matches = matches + 1 end
			end
			titleText = string.format("Outfits - %d shown", matches)
		end
		frame.Title:SetText(titleText)
		LayoutTitleBar()

		self:UpdateNotice()
	end

	function Addon:UpdateCooldowns()
		self.listBox:ForEachFrame(function(row)
			if row.outfitID then UpdateRowCooldown(row) end
		end)
	end

	frame:SetScript("OnShow", function()
		-- Combat may show the prepared window, but cannot rebuild its protected rows.
		if InCombatLockdown() then return end
		Addon:Refresh()
		Addon:SetCombatDimmed(false)
	end)

	frame:SetScript("OnHide", function()
		Addon:CancelEdit()
		Addon:ClosePicker()
		ns.CloseSearchPicker()
		Addon:HidePreview()
		frame.SearchBox:SetText("")
		Addon.searchText = nil
		Addon.scrollToTop = true
	end)


	return {
		frame = frame,
		accountMacroCount = AccountMacroCount,
	}
end

ns.MainWindowUI = MainWindowUI
return MainWindowUI
