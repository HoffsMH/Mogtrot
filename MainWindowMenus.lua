local _, ns = ...

local Pins = ns.Pins or require("Pins")

-- The outfit list's outfit and category menus, and the pickers and dialogs
-- they open: moving, and copying or clearing an outfit's links.
local MainWindowMenus = {}

-- "no mounts", "1 mount", "3 mounts".
function MainWindowMenus.Plural(count, noun)
	if count == 0 then return ("no %ss"):format(noun) end
	if count == 1 then return ("1 %s"):format(noun) end
	return ("%d %ss"):format(count, noun)
end

-- A copy button's label once outfits are ticked: "Add to 3 outfits". The
-- count is the outfits the click writes to, not the links it copies.
function MainWindowMenus.TargetLabel(verb, preposition, count)
	return ("%s %s %s"):format(verb, preposition, MainWindowMenus.Plural(count, "outfit"))
end

function MainWindowMenus.Attach(Addon, deps)
	local Tree = deps.Tree
	local OpenTitlePicker = deps.openTitlePicker
	local CountOutfitTitles = deps.countOutfitTitles
	local CopyOutfitTitles = deps.copyOutfitTitles
	local ClearOutfitTitles = deps.clearOutfitTitles
	-- Companion pickers are optional at composition time; their entries appear in
	-- the outfit menu only when Core supplies the callbacks.
	local OpenHearthstonePicker = deps.openHearthstonePicker
	local CountOutfitHearthstones = deps.countOutfitHearthstones
	local NEW_CATEGORY_NAME = Tree.NEW_CATEGORY_NAME
	local CategoryColor = ns.CategoryColor

	local function MountPinOptOut()
		return Pins.OptOut(MogtrotCharDB, "mounts")
	end

	local function CompanionText(label, count)
		if type(count) == "number" then
			return ("%s (%d)"):format(label, count)
		end
		return label
	end

	local Plural = MainWindowMenus.Plural

	-- Categories as picker choices, counted so an empty one is not indistinguishable
	-- from a full one. The count includes sub-categories, which is what the list shows.
	local function CategoryChoices(excludeID, skipID)
		local choices = Tree.CategoryChoices(MogtrotCharDB, excludeID, skipID)
		for _, choice in ipairs(choices) do
			local count = Tree.CountOutfits(MogtrotCharDB, choice.catID)
			choice.note = Plural(count, "outfit")
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

	local function CountHearthstones(outfitID)
		local count = type(CountOutfitHearthstones) == "function"
			and CountOutfitHearthstones(outfitID) or nil
		return type(count) == "number" and count or 0
	end

	-- The per-outfit links the outfit menu can copy and clear. They differ only
	-- in noun, store and tooltip wording; dialog names are StaticPopup keys.
	local LINK_KINDS = {
		mounts = {
			noun = "mount",
			dialog = "MOGTROT_CLEAR_OUTFIT_MOUNTS",
			count = function(outfitID) return Addon:CountOutfitMounts(outfitID) end,
			copy = function(fromID, toID, merge) Addon:CopyMountsTo(fromID, toID, merge) end,
			clear = function(outfitID)
				if Addon:CountOutfitMounts(outfitID) == 0 then return end
				Addon:ClearOutfitMounts(outfitID)
			end,
			addTip = "Each selected outfit keeps the mounts it already has and gains these on top.",
			replaceTip = "Each selected outfit ends up with exactly these mounts. Whatever it had is discarded.",
		},
		titles = {
			noun = "title",
			dialog = "MOGTROT_CLEAR_OUTFIT_TITLES",
			count = CountOutfitTitles,
			copy = CopyOutfitTitles,
			clear = ClearOutfitTitles,
			addTip = "Each selected outfit keeps its titles and gains these on top.",
			replaceTip = "Each selected outfit ends up with exactly these titles.",
		},
		hearthstones = {
			noun = "hearthstone",
			dialog = "MOGTROT_CLEAR_OUTFIT_HEARTHSTONES",
			count = CountHearthstones,
			copy = function(fromID, toID, merge) Addon:CopyHearthstonesTo(fromID, toID, merge) end,
			clear = function(outfitID) Addon:ClearOutfitHearthstones(outfitID) end,
			addTip = "Each selected outfit keeps its hearthstones and gains these on top.",
			replaceTip = "Each selected outfit ends up with exactly these hearthstones.",
		},
	}

	-- One call per target rather than a bulk copy, so each outfit gets the same chat
	-- line and refresh it would get from a single copy. The target is
	-- re-checked at commit time because the window outlives the list it was built from.
	local function CopyLinksToChosen(kind, sourceOutfitID, chosen, merge)
		for _, choice in ipairs(chosen) do
			if Addon.outfitsByID and Addon.outfitsByID[choice.outfitID] then
				kind.copy(sourceOutfitID, choice.outfitID, merge)
			end
		end
	end

	local function OpenCopyLinks(kind, sourceOutfitID)
		local count = kind.count(sourceOutfitID)
		if count == 0 then return end

		local info = Addon.outfitsByID and Addon.outfitsByID[sourceOutfitID]
		local choices = Tree.OutfitChoices(MogtrotCharDB, Addon.outfitsByID, sourceOutfitID)
		for _, choice in ipairs(choices) do
			local linked = kind.count(choice.outfitID)
			choice.note = Plural(linked, kind.noun)
			choice.noteDim = linked == 0
		end

		ns.OpenSearchPicker({
			title = ("Copy %s from %s"):format(Plural(count, kind.noun),
				info and info.name or "outfit"),
			searchHint = "Search outfits and categories",
			emptyText = "No outfits match.",
			multi = true,
			items = choices,
			buttons = {
				{
					text = "Add", width = 90,
					countText = function(n) return MainWindowMenus.TargetLabel("Add", "to", n) end,
					tipTitle = "Add",
					tipBody = kind.addTip,
					onClick = function(chosen)
						CopyLinksToChosen(kind, sourceOutfitID, chosen, true)
					end,
				},
				{
					text = "Replace", width = 110, danger = true,
					countText = function(n) return MainWindowMenus.TargetLabel("Replace", "on", n) end,
					tipTitle = "Replace",
					tipBody = kind.replaceTip,
					onClick = function(chosen)
						CopyLinksToChosen(kind, sourceOutfitID, chosen, false)
					end,
				},
			},
		})
	end

	for _, kind in pairs(LINK_KINDS) do
		StaticPopupDialogs[kind.dialog] = {
			text = "Clear every linked " .. kind.noun .. " from outfit '%s'?\n\n"
				.. "This affects only this outfit and cannot be undone.",
			button1 = ("Clear %ss"):format(kind.noun),
			button2 = CANCEL or "Cancel",
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			OnAccept = function(_popup, data)
				if type(data) ~= "table" or not data.outfitID then return end
				if not C_TransmogOutfitInfo.GetOutfitInfo(data.outfitID) then
					Addon:Warn(("could not clear %ss because that outfit no longer exists.")
						:format(kind.noun))
					return
				end
				kind.clear(data.outfitID)
			end,
		}
	end

	local function ConfirmClearLinks(kind, outfitID, outfitName)
		if not outfitID or kind.count(outfitID) == 0 then return end
		StaticPopup_Show(kind.dialog, outfitName or "Outfit", nil, {
			outfitID = outfitID,
		})
	end

	-- Copy and clear, offered once the outfit has something linked.
	local function AddCopyAndClear(root, kind, outfitID, outfitName)
		root:CreateButton(("Copy %ss to..."):format(kind.noun), function()
			OpenCopyLinks(kind, outfitID)
		end)

		root:CreateButton(("Clear %ss"):format(kind.noun), function()
			ConfirmClearLinks(kind, outfitID, outfitName)
		end)
	end

	-- Opens the outfit checklist where users choose every outfit linked to one mount.
	function Addon:OpenAddMountToOutfits(mountID, mountName)
		local linked = ns.OutfitLinks.IndexByLinked(MogtrotCharDB.mounts)[mountID] or {}
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
				AddCopyAndClear(root, LINK_KINDS.mounts, outfitID, outfitName)
			end

			root:CreateCheckbox("Shuffle in pinned mounts", function()
				local mounts = MountPinOptOut()
				return not (mounts and mounts[outfitID])
			end, function()
				local mounts = MountPinOptOut()
				if not mounts then return MenuResponse.Refresh end
				mounts[outfitID] = not mounts[outfitID] and true or nil
				-- Admitting or excluding pins changes what this outfit's
				-- summon key draws from, so the macro icon is now stale.
				if Addon.CompanionChoiceChanged then Addon:CompanionChoiceChanged() end
				return MenuResponse.Refresh
			end)

			root:CreateDivider()

			local titleCount = CountOutfitTitles(outfitID)
			root:CreateButton(
				titleCount > 0 and ("Titles (%d)"):format(titleCount) or "Link titles",
				function() OpenTitlePicker(outfitID) end)

			if titleCount > 0 then
				AddCopyAndClear(root, LINK_KINDS.titles, outfitID, outfitName)
			end

			if type(OpenHearthstonePicker) == "function" then
				root:CreateDivider()
				local count = type(CountOutfitHearthstones) == "function"
					and CountOutfitHearthstones(outfitID) or nil
				root:CreateButton(CompanionText("Hearthstones", count),
					function() OpenHearthstonePicker(outfitID) end)

				if type(count) == "number" and count > 0 then
					AddCopyAndClear(root, LINK_KINDS.hearthstones, outfitID, outfitName)
				end
			end

			root:CreateDivider()

			root:CreateButton("Move outfit to...", function()
				OpenMoveOutfit(outfitID, row.outfitName)
			end)

			root:CreateButton("Move outfit up", function() Addon:MoveOutfitBySteps(outfitID, -1) end)
			root:CreateButton("Move outfit down", function() Addon:MoveOutfitBySteps(outfitID, 1) end)

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

			root:CreateButton("Change color", function()
				local original = CategoryColor.Normalize(cat.color)
				local function Apply(r, g, b)
					if Tree.SetCategoryColor(MogtrotCharDB, catID, r, g, b) then
						Addon:Refresh()
					end
				end
				ColorPickerFrame:SetupColorPickerAndShow({
					r = original.r,
					g = original.g,
					b = original.b,
					hasOpacity = false,
					swatchFunc = function()
						Apply(ColorPickerFrame:GetColorRGB())
					end,
					cancelFunc = function()
						Apply(original.r, original.g, original.b)
					end,
				})
			end)

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

	return {
		ShowOutfitMenu = ShowOutfitMenu,
		ShowCategoryMenu = ShowCategoryMenu,
	}
end

ns.MainWindowMenus = MainWindowMenus
return MainWindowMenus
