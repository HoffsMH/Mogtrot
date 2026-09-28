local _, ns = ...

-- Handles /mogtrot commands and their user-facing responses.
local Commands = {}

function Commands.Register(Addon, deps)
	local frame = deps.frame
	local LiteMountFallbackAvailable = deps.liteMountFallbackAvailable
	local FALLBACK_MODES = deps.fallbackModes

local HELP = {
	{ "(nothing)", "toggle the outfit window" },
	{ "preview", "hover preview of the outfit, on or off" },
	{ "say", "announce a change of outfit in /say on shift-click" },
	{ "quiet", "silence Mogtrot's chat output" },
	{ "summon", "summon a mount linked to the outfit you are wearing" },
	{ "fallback", "what that key does when the outfit has no mounts" },
	{ "fallback <what>", "random, pinned, litemount or off" },
	{ "snap", "save the look of the player you target into the library" },
	{ "library", "open the library of captured looks" },
}

local function ShowHelp()
	Addon:Warn("commands, after /mogtrot (or /mogt):")
	local function Print(entry)
		print(("  |cffffd100%-17s|r %s"):format(entry[1], entry[2]))
	end
	for _, entry in ipairs(HELP) do Print(entry) end
end

SLASH_MOGTROT1 = "/mogtrot"
SLASH_MOGTROT2 = "/mogt"
SlashCmdList.MOGTROT = function(msg)
	local cmd = msg and strlower(strtrim(msg)) or ""

	if cmd == "help" or cmd == "?" then
		ShowHelp()
		return
	end

	if cmd == "preview" then
		MogtrotDB.previewEnabled = not MogtrotDB.previewEnabled
		if not MogtrotDB.previewEnabled then Addon:HidePreview() end
		Addon:Say("hover preview %s.", MogtrotDB.previewEnabled and "on" or "off")
		return
	end

	if cmd == "say" then
		MogtrotDB.announceEnabled = (MogtrotDB.announceEnabled == false)
		Addon:Say("shift-click announcements %s.",
			MogtrotDB.announceEnabled and "on" or "off")
		return
	end

	if cmd == "quiet" then
		MogtrotDB.quiet = not MogtrotDB.quiet
		-- Keeps the Quiet mode checkbox in step if the panel is open.
		if Settings and Settings.NotifyUpdate and ns.SettingsUI then
			Settings.NotifyUpdate(ns.SettingsUI.QUIET_SETTING)
		end
		Addon:Warn("chat output %s.", MogtrotDB.quiet and "silenced" or "on")
		return
	end

	if cmd == "summon" then
		Addon:SummonForActiveOutfit(false)
		return
	end

	if cmd == "fallback" then
		Addon:Say(Addon:SummonFallbackText())
		Addon:Say("change it with /mogtrot fallback random, pinned, litemount or off, "
			.. "or in Mogtrot's settings.")
		Addon:Say("to pin a mount, right-click its card in the mount picker and choose Pin.")
		return
	end

	local fallback = cmd:match("^fallback%s+(%S+)$")
	if fallback then
		if fallback == "litemount" and not LiteMountFallbackAvailable() then
			Addon:Say("LiteMount isn't ready.")
		elseif FALLBACK_MODES[fallback] then
			Addon:SetSummonFallback({ mode = fallback })
		else
			Addon:Say("use /mogtrot fallback random, pinned, litemount or off.")
		end
		return
	end

	if cmd == "snap" then
		if ns.SnapCapture then
			ns.SnapCapture.Target(Addon)
		else
			Addon:Warn("capture unavailable: the capture module is not loaded.")
		end
		return
	end
	if cmd == "library" then
		if InCombatLockdown() then
			Addon:Warn("not while you are in combat.")
		elseif ns.LibraryUI then
			ns.LibraryUI.Toggle()
		else
			Addon:Warn("library unavailable: the library window is not loaded.")
		end
		return
	end

	if cmd ~= "" then
		Addon:Say("no such command: %s", cmd)
		ShowHelp()
		return
	end

	if InCombatLockdown() then
		UIErrorsFrame:AddMessage("Mogtrot: can't open in combat; use the Toggle outfit list keybinding.",
			1, 0.3, 0.3)
		return
	end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end
end

ns.Commands = Commands
return Commands
