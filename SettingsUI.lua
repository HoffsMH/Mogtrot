local _, ns = ...

-- Builds Mogtrot controls in Blizzard settings.
local SettingsUI = {}

function SettingsUI.ParsePinDays(value)
	if type(value) ~= "string" or not value:match("^%d+$") then return nil end
	return tonumber(value)
end

MogtrotPinDaysSettingMixin = {}

function MogtrotPinDaysSettingMixin:OnLoad()
	SettingsListElementMixin.OnLoad(self)
end

function MogtrotPinDaysSettingMixin:Init(initializer)
	SettingsListElementMixin.Init(self, initializer)
	self.Days:SetText(self.data.getText())
	self.Days:SetCursorPosition(0)
end

function MogtrotPinDaysSettingMixin:Release()
	SettingsListElementMixin.Release(self)
end

function MogtrotPinDaysSettingMixin:RestoreValue()
	self.Days:SetText(self.data.getText())
	self.Days:SetCursorPosition(0)
end

function MogtrotPinDaysSettingMixin:OnTextChanged(editBox, userInput)
	if not userInput or editBox:GetText() == "" then return end
	if not self.data.setText(editBox:GetText()) then
		self:RestoreValue()
	end
end

function MogtrotPinDaysSettingMixin:Commit(editBox)
	if editBox:GetText() == "" or not self.data.setText(editBox:GetText()) then
		self:RestoreValue()
	end
end

function SettingsUI.Attach(Addon, deps)
	local Wear = deps.Wear
	local Lint = deps.Lint
	local LiteMountFallbackAvailable = deps.liteMountFallbackAvailable
	local FALLBACK_MODES = deps.fallbackModes
	local frame = deps.frame
	local Titles = deps.titles

function Addon:RegisterTitleFallbackSetting(category, layout)
	if not Titles or not Settings.CreateDropdown then return end
	local function Options()
		local container = Settings.CreateControlTextContainer()
		container:Add("random", "Choose random")
		container:Add("clear", "Clear title")
		container:Add("pinned", "Use pinned: " .. Titles:FallbackTitleLabel())
		return container:GetData()
	end
	local setting = Settings.RegisterProxySetting(category, "MOGTROT_TITLE_FALLBACK",
		Settings.VarType.String, "If no title is linked", "random",
		function() return Titles:FallbackMode() end,
		function(value) Titles:SetFallbackMode(value) end)
	Settings.CreateDropdown(category, setting, Options,
		"What title to use when the active outfit has no available linked title.")
	local createButton = _G.CreateSettingsButtonInitializer
	if createButton then
		layout:AddInitializer(createButton("Pinned title", "Choose", function()
			Titles:OpenFallbackPicker()
		end, "Choose the title used by the pinned fallback.", true))
	end
end

function Addon:RegisterFallbackSetting(category)
	if not (Settings.CreateDropdown and Settings.CreateControlTextContainer
		and Settings.VarType and Settings.VarType.String) then
		self:Debug("settings dropdown unavailable, fallback mode stays on the slash command")
		return
	end

	local function Options()
		local container = Settings.CreateControlTextContainer()
		container:Add("random", "A random mount",
			"A favourite if you have any, otherwise anything you own.")
		container:Add("pinned", "A pinned mount",
			"Choose among the mounts pinned in Mogtrot.")
		if LiteMountFallbackAvailable() then
			container:Add("litemount", "LiteMount",
				"Let the summon keybinding or action-bar macro securely call LiteMount "
					.. "when the active outfit has no linked mounts.")
		end
		container:Add("off", "Nothing, just say why",
			"The key stays strictly outfit-only and explains itself instead.")
		return container:GetData()
	end

	local function GetMode() return Addon:FallbackMode() end
	local function SetMode(value)
		if not FALLBACK_MODES[value] then return end
		Addon:SetSummonFallback({ mode = value })
	end

	local setting = Settings.RegisterProxySetting(category, "MOGTROT_SUMMON_FALLBACK",
		Settings.VarType.String, "Summon fallback", "random", GetMode, SetMode)

	Settings.CreateDropdown(category, setting, Options,
		"What the summon key does when no outfit is on, or the outfit you are "
		.. "wearing has no mounts linked to it.")
end

function Addon:RegisterSettings()
	if self.settingsCategory or not Settings or not Settings.RegisterAddOnCategory then
		return
	end

	local category, layout = Settings.RegisterVerticalLayoutCategory("Mogtrot")
	self.settingsCategory = category
	local function GetWearInList() return Wear.ShowInList(MogtrotDB) end
	local function SetWearInList(value)
		Wear.SetShowInList(MogtrotDB, value)
		Addon:Refresh()
	end
	local wearListSetting = Settings.RegisterProxySetting(category, "MOGTROT_SHOW_WEAR_IN_LIST",
		Settings.VarType.Boolean, "Show time worn in list", false, GetWearInList, SetWearInList)
	Settings.CreateCheckbox(category, wearListSetting,
		"Shows a bar comparing each outfit's logged-in wear time with your most-worn outfit.")

	local function GetCompletenessInList() return Lint.ShowInList(MogtrotDB) end
	local function SetCompletenessInList(value)
		Lint.SetShowInList(MogtrotDB, value)
		Addon:Refresh()
	end
	local completenessSetting = Settings.RegisterProxySetting(category,
		"MOGTROT_SHOW_COMPLETENESS_IN_LIST", Settings.VarType.Boolean,
		"Show outfit completeness in list", false, GetCompletenessInList,
		SetCompletenessInList)
	Settings.CreateCheckbox(category, completenessSetting,
		"Shows a circle for unset outfit slots or missing ground and flying mounts. "
		.. "Gray means the outfit has not been checked yet.")

	local function GetTargetMatch() return MogtrotDB.matchTargetMount and true or false end
	local function SetTargetMatch(value) MogtrotDB.matchTargetMount = value and true or false end
	local targetSetting = Settings.RegisterProxySetting(category, "MOGTROT_MATCH_TARGET_MOUNT",
		Settings.VarType.Boolean, "Match target's mount", false, GetTargetMatch, SetTargetMatch)
	Settings.CreateCheckbox(category, targetSetting,
		"When a targeted player is on a mount you own and can use here, summon the same mount. "
		.. "Restricted or unidentified targets use the normal outfit and fallback choices.")

	local autoPinSetting = Settings.RegisterProxySetting(category, "MOGTROT_AUTO_PIN_MOUNTS",
		Settings.VarType.Boolean, "Automatically pin new mounts", true,
		function() return MogtrotDB.autoPinNewMounts ~= false end,
		function(value) MogtrotDB.autoPinNewMounts = value and true or false end)
	Settings.CreateCheckbox(category, autoPinSetting,
		"Keeps each newly acquired mount pinned for the selected number of days.")

	if Settings.CreateElementInitializer then
		local function GetPinDays()
			return tostring(MogtrotDB.autoPinNewMountDays or 7)
		end
		local function SetPinDays(value)
			local days = SettingsUI.ParsePinDays(value)
			if days == nil then return false end
			MogtrotDB.autoPinNewMountDays = days
			return true
		end
		layout:AddInitializer(Settings.CreateElementInitializer(
			"MogtrotPinDaysSettingTemplate", {
				name = "Pins default to expiring in",
				tooltip = "Used for future automatic and manual pins. 0 never expires.",
				getText = GetPinDays,
				setText = SetPinDays,
			}))
	end

	self:RegisterFallbackSetting(category)
	self:RegisterTitleFallbackSetting(category, layout)

	Settings.RegisterAddOnCategory(category)
	frame.SettingsButton:Enable()
	frame.SettingsButton.Icon:SetVertexColor(0.75, 0.75, 0.75)
	self:Debug("settings category registered")
end
end

ns.SettingsUI = SettingsUI
return SettingsUI
