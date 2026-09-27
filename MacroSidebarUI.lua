local _, ns = ...

-- The Mogtrot macros: making and repairing them, their icons, the drag
-- handles that put one on the cursor, and the sidebar of macro icons on the
-- outfit list's left edge.
local MacroSidebarUI = {}

function MacroSidebarUI.Attach(Addon, deps)
	local Macro = deps.Macro
	-- Item data arrives asynchronously, so this can be nil on a cold cache and
	-- has to be asked for again later rather than trusted from load time.
	local HEARTHSTONE_ITEM_ID = 6948
	local function HearthstoneIcon()
		return C_Item and C_Item.GetItemIconByID
			and C_Item.GetItemIconByID(HEARTHSTONE_ITEM_ID) or nil
	end
	local hearthstoneIcon = HearthstoneIcon()

	-- Account macros occupy the first block of indices, so the nth is index n. None
	-- of the macros is character-specific: they open the window or dispatch through
	-- character-aware buttons. They belong to the account rather than being remade
	-- on each alt. From the client's own constant, with today's value as a
	-- fallback if a build stops defining it.
	local ACCOUNT_MACRO_CAP = MAX_ACCOUNT_MACROS or 120

	-- Blizzard's own "summon a random favourite mount" button is this spell
	-- (Blizzard_MountCollection.xml:222), so its texture is the icon a user already
	-- reads as "put me on a mount".
	local RANDOM_FAVOURITE_SPELL_ID = 150544

	-- CreateMacro wants a fileID, not a path: handed the TOC's icon path it stores
	-- the default cog instead. Spell textures are fileIDs already, and these are the
	-- icons the created macros use on the action bar. The fixed OPEN/LEAST icons
	-- live in Macro.DEFS; only the summon icon is a runtime texture.
	-- CreateMacro throws a usage error on a nil icon rather than defaulting,
	-- so nothing may reach it unanswered. The two commands with no fixed icon
	-- of their own are answered here: the mount macro wears the random
	-- favourite's spell texture, and the hearth macro wears whichever
	-- hearthstone the client will name, because which one it uses is not
	-- fixed.
	local MACRO_FALLBACK_ICON = "INTERFACE\\ICONS\\INV_MISC_QUESTIONMARK"

	local function MacroIcon(command)
		if command == Macro.SUMMON then
			return C_Spell.GetSpellTexture(RANDOM_FAVOURITE_SPELL_ID)
		end
		if command == Macro.HEARTH then
			return HearthstoneIcon() or hearthstoneIcon
		end
		return Macro.FixedIcon(command)
	end

	local function MacroDragIcon(command)
		if command == Macro.HEARTH and hearthstoneIcon then
			return hearthstoneIcon
		end
		return MacroIcon(command)
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
	-- free slot and no macros made means the first drag works and the rest do
	-- not, and each handle has to say so for itself.
	function Addon:CanOfferMacro(command)
		return Macro.CanOffer(AccountMacroCount(), AccountMacroBody, command,
			ACCOUNT_MACRO_CAP)
	end

	function Addon.UpdateMacroIcon(self, slot, command)
		if InCombatLockdown() then return false end
		local currentIcon = select(2, GetMacroInfo(slot))
		local wanted = self.WantedMacroIcon and self:WantedMacroIcon(command) or nil
		local icon = Macro.IconToApply(command, currentIcon, wanted)
		if not icon then return false end
		EditMacro(slot, nil, icon, nil)
		return true
	end

	-- Re-corrects the icons of macros Mogtrot owns: the client can substitute its
	-- fallback icon, so the refresh runs on login and after combat, not only when
	-- the user re-drags a handle.
	function Addon:UpdateOwnedMacroIcons()
		if InCombatLockdown() then return end
		-- Every command, not only the two with constants: summon and
		-- hearthstone have no fixed icon and are exactly the ones that need
		-- re-reading when the outfit moves.
		local count = AccountMacroCount()
		for _, command in ipairs(Macro.ORDER) do
			local slot = Macro.Find(count, AccountMacroBody, command)
			if slot then self:UpdateMacroIcon(slot, command) end
		end
		if self.PaintSidebarIcons then self:PaintSidebarIcons() end
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
		-- Never nil: a missing icon is a usage error, not a default, and it
		-- takes the whole drag down with it.
		local index = CreateMacro(name, MacroIcon(command) or MACRO_FALLBACK_ICON,
			body, perCharacter)
		if not index then return nil, "failed" end

		-- Trust nothing about what the client stored. CreateMacro's argument order has
		-- been got wrong before, and a macro whose body is not what we wrote runs as
		-- chat text on a bar the user has already committed to.
		local stored = GetMacroBody(index)
		if stored and strtrim(stored) ~= body then
			self:Warn("the macro did not save correctly; delete it and drag it again.")
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

	-- Separate handles rather than modifiers: every macro is discoverable by hovering,
	-- with no gesture to learn. Same button, different command behind it, so the shape
	-- lives in one place.
	local MACRO_DRAG_SIZE = 20
	local macroDragControls = {}

	-- Puts this command's macro on the cursor, making it first if need be.
	local function PickupOwnMacro(command)
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
	end

	local function AddMacroSlotWarning(command)
		-- Asked per command and per hover: with one slot left and no macro
		-- made, every handle works, and whichever is dragged first takes it.
		if not Addon:CanOfferMacro(command) then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(("No free general macro slots (%d of %d used)."):format(
				AccountMacroCount(), ACCOUNT_MACRO_CAP), 1, 0.3, 0.3, true)
		end
	end

	local function CreateMacroDrag(parent, command, title, description)
		local button = CreateFrame("Button", nil, parent)
		button:SetSize(MACRO_DRAG_SIZE, MACRO_DRAG_SIZE)
		button:RegisterForDrag("LeftButton")

		button.Icon = button:CreateTexture(nil, "ARTWORK")
		button.Icon:SetAllPoints()
		button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		button.Icon:SetTexture(MacroDragIcon(command))
		button.Icon:SetVertexColor(0.75, 0.75, 0.75)

		button:SetScript("OnEnter", function(self)
			self.Icon:SetVertexColor(1, 1, 1)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(title)
			GameTooltip:AddLine(description, 0.6, 0.6, 0.6, true)
			AddMacroSlotWarning(command)
			GameTooltip:Show()
		end)

		button:SetScript("OnLeave", function(self)
			self.Icon:SetVertexColor(0.75, 0.75, 0.75)
			GameTooltip:Hide()
		end)

		button:SetScript("OnDragStart", function() PickupOwnMacro(command) end)
		macroDragControls[command] = button

		return button
	end

	function Addon:CreateMacroDrag(parent, command, title, description)
		local button = CreateMacroDrag(parent, command, title, description)
		if self.UpdateMacroDragControls then self:UpdateMacroDragControls() end
		return button
	end

	local ACTION_SLOT_COUNT = 180

	local function ActionBarCommands()
		return Macro.ActionBarCommands(ACTION_SLOT_COUNT, GetActionInfo,
			AccountMacroBody)
	end

	-- Saved as showMacroDragControls: absent or true shows the sidebar's setup
	-- icons, false hides them.
	function Addon:SetupIconsShown()
		return not (MogtrotDB and MogtrotDB.showMacroDragControls == false)
	end

	function Addon:SetSetupIconsShown(shown)
		MogtrotDB.showMacroDragControls = shown and true or false
		self:UpdateMacroDragControls()
	end

	-- The sidebar's setup icons, and drag handles elsewhere (the library's
	-- snap), hide once their macro is on a bar.
	function Addon:UpdateMacroDragControls()
		local placed = ActionBarCommands()
		for command, button in pairs(macroDragControls) do
			button:SetShown(Macro.DragShown(false, placed, command))
		end
		if self.UpdateSidebar then self:UpdateSidebar(placed) end
	end

	-- Rescans the action bars for the drag handles and the sidebar.
	local function WatchActionBars()
		-- A login or a bar page change fires one event per slot; one scan per frame
		-- answers them all. Combat defers the sidebar, so leaving combat rescans.
		local macroControlEvents = CreateFrame("Frame")
		macroControlEvents:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
		macroControlEvents:RegisterEvent("UPDATE_MACROS")
		macroControlEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
		macroControlEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
		local macroScanQueued = false
		macroControlEvents:SetScript("OnEvent", function()
			if not MogtrotDB or macroScanQueued then return end
			macroScanQueued = true
			C_Timer.After(0, function()
				macroScanQueued = false
				Addon:UpdateMacroDragControls()
			end)
		end)
	end

	local function BuildSidebar(frame)
		-- The sidebar: one icon per Mogtrot macro, on the window's left edge.
		-- Dragged, an icon puts its macro on the cursor. Clicked, it clicks the
		-- same named button its macro /clicks, so nothing here makes a protected
		-- call of its own; snap is addon code and runs /mogtrot snap directly.
		local SIDEBAR_ICON, SIDEBAR_GAP, SIDEBAR_PAD = 32, 12, 10
		local SIDEBAR_WIDTH = SIDEBAR_ICON + 2 * SIDEBAR_PAD
		-- Blizzard's spell-activation glow, the one an action button wears on a proc.
		local GLOW_TEMPLATE = "ActionButtonSpellAlertTemplate"
		local sidebarButtons = {}

		local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		frame.Sidebar = sidebar
		sidebar:SetWidth(SIDEBAR_WIDTH)
		sidebar:SetPoint("TOPRIGHT", frame, "TOPLEFT", 2, 0)
		sidebar:SetBackdrop(frame:GetBackdrop())
		sidebar:SetBackdropColor(0, 0, 0, 0.92)
		-- Takes the clicks between icons, and moves the window like its body does.
		sidebar:EnableMouse(true)
		sidebar:RegisterForDrag("LeftButton")
		sidebar:SetScript("OnDragStart", function() frame:GetScript("OnDragStart")(frame) end)
		sidebar:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
		-- Clamping counts the sidebar, so it cannot be dragged off the left edge.
		frame:SetClampRectInsets(-(SIDEBAR_WIDTH - 2), 0, 0, 0)

		local function AddGlow(button)
			if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo(GLOW_TEMPLATE)) then return end
			local glow = CreateFrame("Frame", nil, button, GLOW_TEMPLATE)
			glow:SetSize(SIDEBAR_ICON * 1.4, SIDEBAR_ICON * 1.4)
			glow:SetPoint("CENTER")
			-- Only the loop plays. The birth flipbook, never animated, would show
			-- its whole sheet.
			glow.ProcStartFlipbook:Hide()
			-- The template's OnShow restarts the loop only with this set.
			glow.animationPlaying = true
			glow:Show()
			glow.ProcLoop:Play()
			button.Glow = glow
		end

		local function SidebarIcon(command)
			local wanted = Addon.WantedMacroIcon and Addon:WantedMacroIcon(command) or nil
			return wanted or MacroDragIcon(command) or MACRO_FALLBACK_ICON
		end

		local function CreateSidebarButton(command)
			local target = Macro.DEFS[command].target
			local button
			if target then
				button = CreateFrame("Button", nil, sidebar, "SecureActionButtonTemplate")
				button:RegisterForClicks("AnyUp")
				button:SetAttribute("useOnKeyDown", false)
				button:SetAttribute("type", "click")
				button:SetAttribute("clickbutton", _G[target])
			else
				button = CreateFrame("Button", nil, sidebar)
				button:RegisterForClicks("LeftButtonUp")
				button:SetScript("OnClick", function()
					SlashCmdList.MOGTROT(command)
				end)
			end
			button.command = command
			button:SetSize(SIDEBAR_ICON, SIDEBAR_ICON)
			button:RegisterForDrag("LeftButton")
			button:SetScript("OnDragStart", function() PickupOwnMacro(command) end)

			button.Icon = button:CreateTexture(nil, "ARTWORK")
			button.Icon:SetAllPoints()
			button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

			button:SetScript("OnEnter", function(self)
				local title, text = Macro.SidebarTip(command,
					Addon.FallbackMode and Addon:FallbackMode() == "litemount")
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				GameTooltip:SetText(title)
				GameTooltip:AddLine(text, 1, 1, 1, true)
				AddMacroSlotWarning(command)
				GameTooltip:Show()
			end)
			button:SetScript("OnLeave", GameTooltip_Hide)

			if Macro.SETUP[command] then AddGlow(button) end
			button:Hide()
			sidebarButtons[command] = button
		end

		for _, command in ipairs(Macro.SIDEBAR) do CreateSidebarButton(command) end

		-- Summon and hearth follow the outfit the way their macros' icons do.
		function Addon:PaintSidebarIcons()
			for command, button in pairs(sidebarButtons) do
				button.Icon:SetTexture(SidebarIcon(command))
			end
		end

		-- placed is the live action-bar scan unless a caller passes its own. The
		-- buttons are secure, so combat leaves the layout for PLAYER_REGEN_ENABLED.
		function Addon:UpdateSidebar(placed)
			if InCombatLockdown() then return end
			placed = placed or ActionBarCommands()
			for _, button in pairs(sidebarButtons) do button:Hide() end
			local shown = Macro.Sidebar(self:SetupIconsShown(), placed)
			for index, entry in ipairs(shown) do
				local button = sidebarButtons[entry.command]
				button:ClearAllPoints()
				button:SetPoint("TOP", sidebar, "TOP", 0,
					-(SIDEBAR_PAD + (index - 1) * (SIDEBAR_ICON + SIDEBAR_GAP)))
				if button.Glow then button.Glow:SetShown(entry.glow) end
				button:Show()
			end
			sidebar:SetHeight(2 * SIDEBAR_PAD + #shown * SIDEBAR_ICON
				+ math.max(#shown - 1, 0) * SIDEBAR_GAP)
			self:PaintSidebarIcons()
		end
	end

	return {
		MacroIcon = MacroIcon,
		WatchActionBars = WatchActionBars,
		BuildSidebar = BuildSidebar,
	}
end

ns.MacroSidebarUI = MacroSidebarUI
return MacroSidebarUI
