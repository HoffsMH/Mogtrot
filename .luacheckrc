-- Run with: luacheck .
--
-- WoW's environment is not one of luacheck's built-in stds. The list below is the
-- set of globals these files actually reference, read out of the compiled chunks:
--   luac5.1 -l -p *.lua | grep -E 'SETGLOBAL|GETGLOBAL'
-- Re-run that after adding a call to an API not already here.

std = "lua51"
max_line_length = 120

-- Addon files start `local ADDON_NAME, ns = ...` and mostly want only the second.
-- A leading underscore is this codebase's way of saying "the API returns this
-- and we do not want it". Ignoring them is what lets the whole run be clean,
-- and a clean run is what makes luacheck useful as a gate: it already catches
-- a function defined twice in one file, which reads correctly and runs stale.
ignore = { "211/ADDON_NAME", "21./_.*" }

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
	"DRESS_UP_FRAME_MODEL_SCENE_ID",
	"CHECK_ALL",
	"UNCHECK_ALL",
	"C_MountJournal",
	"C_AddOns",
	"AuraUtil",
	"C_AlliedRaces",
	"C_Item",
	"C_Map",
	"ClearInspectPlayer",
	"C_ToyBox",
	"C_Container",
	"C_TooltipInfo",
	"PlayerHasToy",
	"ITEM_SPELL_TRIGGER_ONUSE",
	"C_Secrets",
	"C_UnitAuras",
	"C_PaperDollInfo",
	"C_Spell",
	"C_Timer",
	"C_TransmogOutfitInfo",
	"C_TransmogCollection",
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
	"GetInspectSpecialization",
	"GetSubZoneText",
	"GetTime",
	"GetZoneText",
	"IsMounted",
	"IsUnitModelReadyForUI",
	"issecretvalue",
	"UnitExists",
	"UnitFactionGroup",
	"UnitPVPName",
	"IsInInstance",
	"NotifyInspect",
	"UnitSex",
	"UnitClass",
	"UnitRace",
	"UnitLevel",
	"C_PlayerInfo",
	"C_BarberShop",
	"PlayerLocation",
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
	"RAID_CLASS_COLORS",
	"IsControlKeyDown",
	"GetClassAtlas",
	"strsplit",
	"C_CreatureInfo",
	"ReloadUI",
	"ScrollBoxConstants",
	"ScrollBoxListMixin",
	"ScrollUtil",
	"SendChatMessage",
	"Settings",
	"TRANSMOG_OUTFIT_NAME_DEFAULT",
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
	"tinsert",
	"wipe",
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
files["ProbeRenderUI.lua"] = { ignore = { "331/ns" } }

files["spec/"] = {
	std = "lua51+busted",
	-- The stub file is what defines these for the test runner.
	globals = { "strlower", "strtrim" },
}
