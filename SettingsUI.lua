local _, ns = ...

local Pins = ns.Pins or require("Pins")

-- Builds Mogtrot controls in Blizzard settings.
local SettingsUI = {}

SettingsUI.QUIET_SETTING = "MOGTROT_QUIET"

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
	local Lint = deps.Lint
	local LiteMountFallbackAvailable = deps.liteMountFallbackAvailable
	local FALLBACK_MODES = deps.fallbackModes
	local frame = deps.frame
	local Titles = deps.titles
	local Minimap = deps.minimap

local function MountPinDomain()
	return Pins.Domain(MogtrotDB, "mounts")
end

local function HearthstonePinDomain()
	return Pins.Domain(MogtrotDB, "hearthstones")
end

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
		Settings.VarType.String, "Summon fallback", "pinned", GetMode, SetMode)

	Settings.CreateDropdown(category, setting, Options,
		"What the summon key does when no outfit is on, or the outfit you are "
		.. "wearing has no mounts linked to it.")
end

function Addon:RegisterHearthFallbackSetting(category)
	if not (Settings.CreateDropdown and Settings.CreateControlTextContainer
		and Settings.VarType and Settings.VarType.String) then
		return
	end

	local function Options()
		local container = Settings.CreateControlTextContainer()
		container:Add("random", "A random hearthstone",
			"A hearthstone toy you own if one is ready, otherwise any hearthstone "
				.. "you own. Pins are passed over.")
		container:Add("pinned", "A pinned hearthstone",
			"Choose among the hearthstones pinned in Mogtrot, or a random one you "
				.. "own when none is pinned and ready.")
		container:Add("off", "Nothing, just say why",
			"The key stays strictly outfit-only and explains itself instead.")
		return container:GetData()
	end

	local setting = Settings.RegisterProxySetting(category, "MOGTROT_HEARTH_FALLBACK",
		Settings.VarType.String, "If no hearthstone is linked", "pinned",
		function() return Addon:HearthFallbackMode() end,
		function(value) Addon:SetHearthFallbackMode(value) end)
	Settings.CreateDropdown(category, setting, Options,
		"What the hearthstone key does when no outfit is on, or the outfit you are "
			.. "wearing has no linked hearthstone ready.")
end

-- A days field in the pin-days template. get returns the text to show, set
-- takes the typed text and returns whether it was stored.
local function AddDaysRow(layout, name, tooltip, get, set)
	if not Settings.CreateElementInitializer then return end
	layout:AddInitializer(Settings.CreateElementInitializer(
		"MogtrotPinDaysSettingTemplate", {
			name = name,
			tooltip = tooltip,
			getText = get,
			setText = set,
		}))
end

local function AddHeader(layout, name)
	local create = _G.CreateSettingsListSectionHeaderInitializer
	if create then layout:AddInitializer(create(name)) end
end

local function PinDaysAccess(domainOf, default)
	local function Get()
		local domain = domainOf()
		if domain and domain.days ~= nil then return tostring(domain.days) end
		return default
	end
	local function Set(value)
		local days = SettingsUI.ParsePinDays(value)
		if days == nil then return false end
		local domain = domainOf()
		if not domain then return false end
		domain.days = days
		return true
	end
	return Get, Set
end

local function AutoPinAccess(domainOf)
	local function Get()
		local domain = domainOf()
		if not domain then return true end
		return domain.autoNew ~= false
	end
	local function Set(value)
		local domain = domainOf()
		if not domain then return false end
		domain.autoNew = value and true or false
		return true
	end
	return Get, Set
end

function Addon:RegisterSettings()
	if self.settingsCategory or not Settings or not Settings.RegisterAddOnCategory then
		return
	end

	local category, layout = Settings.RegisterVerticalLayoutCategory("Mogtrot")
	self.settingsCategory = category

	local function Checkbox(key, name, default, get, set, tooltip)
		local setting = Settings.RegisterProxySetting(category, key,
			Settings.VarType.Boolean, name, default, get, set)
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	AddHeader(layout, "General")
	Checkbox("MOGTROT_SHOW_MINIMAP_BUTTON", "Show minimap button", true,
		function() return Minimap:IsShown() end,
		function(value) Minimap:SetShown(value) end,
		"Shows a draggable button around the minimap. Mogtrot remains available in "
			.. "Blizzard's addon compartment when hidden.")
	Checkbox("MOGTROT_SHOW_MACRO_CONTROLS", "Show action bar setup icons", true,
		function() return Addon:SetupIconsShown() end,
		function(value) Addon:SetSetupIconsShown(value) end,
		"Shows the Mount, Hearth and Mogtrot window icons on the outfit window's sidebar "
			.. "until you drag each to an action bar. Snap and Random outfit always show.")
	-- The same flag /mogtrot quiet toggles; Commands.lua notifies this row.
	Checkbox(SettingsUI.QUIET_SETTING, "Quiet mode", false,
		function() return MogtrotDB.quiet and true or false end,
		function(value) MogtrotDB.quiet = value and true or false end,
		"Silences Mogtrot's chat messages and the pop-up that confirms a new snapshot. "
			.. "Warnings still show. /mogtrot quiet toggles the same setting.")

	AddHeader(layout, "Outfit list")
	Checkbox("MOGTROT_SHOW_COMPLETENESS_IN_LIST", "Show outfit completeness in list", false,
		function() return Lint.ShowInList(MogtrotDB) end,
		function(value)
			Lint.SetShowInList(MogtrotDB, value)
			Addon:Refresh()
		end,
		"Shows a circle for unset outfit slots or missing ground and flying mounts. "
			.. "Gray means the outfit has not been checked yet.")

	AddHeader(layout, "Mounts")
	self:RegisterFallbackSetting(category)
	Checkbox("MOGTROT_MATCH_TARGET_MOUNT", "Match target's mount", true,
		function() return MogtrotDB.matchTargetMount and true or false end,
		function(value) MogtrotDB.matchTargetMount = value and true or false end,
		"When a targeted player is on a mount you own and can use here, summon the same "
			.. "mount. Restricted or unidentified targets use the normal outfit and "
			.. "fallback choices.")
	local getAutoMount, setAutoMount = AutoPinAccess(MountPinDomain)
	Checkbox("MOGTROT_AUTO_PIN_MOUNTS", "Auto-pin new mounts", true,
		getAutoMount, setAutoMount,
		"Keeps each newly acquired mount pinned for the selected number of days.")
	local getMountDays, setMountDays = PinDaysAccess(MountPinDomain, "7")
	AddDaysRow(layout, "Mount pins expire in",
		"Used for future automatic and manual pins. 0 never expires.",
		getMountDays, setMountDays)

	AddHeader(layout, "Hearthstones")
	self:RegisterHearthFallbackSetting(category)
	local getAutoHearth, setAutoHearth = AutoPinAccess(HearthstonePinDomain)
	Checkbox("MOGTROT_AUTO_PIN_HEARTHSTONES", "Auto-pin new hearthstones", true,
		getAutoHearth, setAutoHearth,
		"Keeps each newly acquired hearthstone pinned for the selected number of days.")
	local getHearthDays, setHearthDays = PinDaysAccess(HearthstonePinDomain, "0")
	AddDaysRow(layout, "Hearthstone pins expire in",
		"Used for future hearthstone pins. 0 never expires.",
		getHearthDays, setHearthDays)

	AddHeader(layout, "Titles")
	self:RegisterTitleFallbackSetting(category, layout)

	-- Archiving a snapshot is one click with no confirmation, and a snapshot of
	-- a stranger cannot be captured again, so how long an accident stays
	-- recoverable is the user's call rather than ours.
	AddHeader(layout, "Library")
	AddDaysRow(layout, "Archived snapshots expire after",
		"Archiving a snapshot hides it rather than deleting it. 0 never expires.",
		function()
			local db = MogtrotDB
			if type(db) == "table" and db.archiveDays ~= nil then
				return tostring(db.archiveDays)
			end
			return "30"
		end,
		function(value)
			local days = SettingsUI.ParsePinDays(value)
			if days == nil then return false end
			if type(MogtrotDB) ~= "table" then return false end
			MogtrotDB.archiveDays = days
			return true
		end)

	Settings.RegisterAddOnCategory(category)
	frame.SettingsButton:Enable()
	frame.SettingsButton.Icon:SetVertexColor(0.75, 0.75, 0.75)
end
end

ns.SettingsUI = SettingsUI
return SettingsUI
