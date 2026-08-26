-- Run with: luacheck .
--
-- WoW's environment is not one of luacheck's built-in stds. The list below is the
-- set of globals these files actually reference, read out of the compiled chunks:
--   luac5.1 -l -p *.lua | grep -E 'SETGLOBAL|GETGLOBAL'
-- Re-run that after adding a call to an API not already here.

std = "lua51"
max_line_length = 120

-- Addon files start `local ADDON_NAME, ns = ...` and mostly want only the second.
ignore = { "211/ADDON_NAME" }

-- Saved variables, the slash-command bindings, and SlashCmdList, whose MOGTROT
-- field the addon assigns.
globals = {
	"BINDING_HEADER_MOGTROT",
	"BINDING_NAME_MOGTROT_SUMMON_MOUNT",
	"MogtrotCharDB",
	"MogtrotDB",
	"MogtrotDevCharDB",
	"MogtrotDevDB",
	-- Called by Bindings.xml, whose body runs in the global environment.
	"MogtrotSummonMount",
	"SLASH_MOGTROT1",
	"SLASH_MOGTROT2",
	"SlashCmdList",
	"StaticPopupDialogs",
}

read_globals = {
	"CAMERA_MODIFICATION_TYPE_DISCARD",
	"CAMERA_TRANSITION_TYPE_IMMEDIATE",
	"CHECK_ALL",
	"UNCHECK_ALL",
	"C_MountJournal",
	"C_AddOns",
	"C_Secrets",
	"C_UnitAuras",
	"C_PaperDollInfo",
	"C_Spell",
	"C_Timer",
	"C_TransmogOutfitInfo",
	"ColorPickerFrame",
	"Constants",
	"Enum",
	"CooldownFrame_Clear",
	"CooldownFrame_Set",
	"CopyTable",
	"CreateDataProvider",
	"CreateFrame",
	"CreateMacro",
	"EditMacro",
	"GetMacroBody",
	"GetMacroInfo",
	"GetNumMacros",
	"MAX_ACCOUNT_MACROS",
	"MAX_CHARACTER_MACROS",
	"PickupMacro",
	"CreateScrollBoxListGridView",
	"CreateScrollBoxListLinearView",
	"debugprofilestop",
	"EventUtil",
	"GameTooltip",
	"GameTooltip_Hide",
	"GetBindingKey",
	"GetBuildInfo",
	"GetCursorPosition",
	"GetTime",
	"IsMounted",
	"issecretvalue",
	"UnitExists",
	"UnitIsPlayer",
	"IconSelectorPopupFrameModes",
	"InCombatLockdown",
	"IsAltKeyDown",
	"IsShiftKeyDown",
	"ItemUtil",
	-- The split-shoulder display strings, used only while shoulders are edited apart.
	"LEFTSHOULDERSLOT",
	"RIGHTSHOULDERSLOT",
	-- The Mount Journal's own filter vocabulary: the three collected settings, and
	-- the five Enum.MountType labels plus their heading.
	"LE_MOUNT_JOURNAL_FILTER_COLLECTED",
	"LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED",
	"LE_MOUNT_JOURNAL_FILTER_UNUSABLE",
	"MOUNT_JOURNAL_FILTER_AQUATIC",
	"MOUNT_JOURNAL_FILTER_DRAGONRIDING",
	"MOUNT_JOURNAL_FILTER_FLYING",
	"MOUNT_JOURNAL_FILTER_GROUND",
	"MOUNT_JOURNAL_FILTER_RIDEALONG",
	"MOUNT_JOURNAL_FILTER_TYPE",
	"Menu",
	"MenuResponse",
	"MenuUtil",
	"RED_FONT_COLOR",
	"ReloadUI",
	"ScrollBoxConstants",
	"ScrollBoxListMixin",
	"ScrollUtil",
	"SendChatMessage",
	"Settings",
	"Transmog_LoadUI",
	"TransmogFrame",
	"UIErrorsFrame",
	"UIParent",
	"UISpecialFrames",
	"StaticPopup_Show",
	"UnitGUID",
	"UnitName",
	"hooksecurefunc",
	"strlower",
	"strtrim",
	"tCompare",
	"tDeleteItem",
	-- Epoch seconds. WoW's global, not os.time.
	"date",
	"time",
}

-- These publish onto ns and also return the module, so a test runner can require
-- them. On the require path ns is a throwaway table that nothing reads back, which
-- is the whole point of the fallback and not worth reporting.
files["Tree.lua"] = { ignore = { "331/ns" } }
files["MountIndex.lua"] = { ignore = { "331/ns" } }
files["MountFilter.lua"] = { ignore = { "331/ns" } }
files["MountPick.lua"] = { ignore = { "331/ns" } }
files["TargetMount.lua"] = { ignore = { "331/ns" } }
files["Lint.lua"] = { ignore = { "331/ns" } }
files["Macro.lua"] = { ignore = { "331/ns" } }
files["MountPins.lua"] = { ignore = { "331/ns" } }

files["spec/"] = {
	std = "lua51+busted",
	-- The stub file is what defines these for the test runner.
	globals = { "strlower", "strtrim" },
}
