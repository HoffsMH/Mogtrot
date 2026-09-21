local _, ns = ...

-- Handles /mogtrot commands and their user-facing responses.
local Commands = {}

function Commands.RepairOutfitLooks(charDB, accountDB, guid, keepOutfitID)
	if type(charDB) ~= "table" or type(accountDB) ~= "table" or not guid then return 0 end
	charDB.looks = type(charDB.looks) == "table" and charDB.looks or {}
	local kept = charDB.looks[keepOutfitID]
	for outfitID in pairs(charDB.looks) do charDB.looks[outfitID] = nil end
	if kept then charDB.looks[keepOutfitID] = kept end

	local repaired = 0
	local records = accountDB.library and accountDB.library.records or {}
	for _, record in pairs(records) do
		if record.source == "mine" and record.origin == "outfit"
			and record.guid == guid and record.originID ~= keepOutfitID
			and record.look ~= "" then
			record.look = ""
			repaired = repaired + 1
		end
	end
	return repaired
end

function Commands.Register(Addon, deps)
	local frame = deps.frame
	local Diagnostics = deps.diagnostics
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
	{ "wear", "how long each outfit has been worn" },
	{ "capture", "re-capture the outfit you are wearing" },
	{ "slots scan", "check every outfit again, including ones already checked" },
	{ "slots wipe", "forget every measurement, so the next scan redoes it" },
	{ "macro", "check the three action bar macros, for a bug report" },
	{ "state", "print what Mogtrot can see, for a bug report" },
	{ "probe", "dump what this client build actually exposes" },
	{ "probe library", "why the library transfer button is hidden" },
	{ "probe ingest <id>", "show what the bulk importer read for one outfit" },
	{ "probe look <id>", "what the client says about each piece of a stored look" },
	{ "probe layer", "one draggable model above the Transmog window" },
	{ "probe body <id>", "render one creature display ID wearing your outfit" },
	{ "probe donors", "which units the library could borrow a body from now" },
	{ "probe actors", "which bodies the dress-up scene can actually pose" },
	{ "probe auras", "every aura on the player you target, for form research" },
	{ "probe secret", "what this client will tell you about each unit here" },
	{ "probe secret watch", "take that census in combat, shown when it drops" },
	{ "inspect", "capture the appearance list of the player you target" },
	{ "snap", "save the look of the player you target into the library" },
	{ "library", "every look you have captured, four to a row" },
	{ "library repair", "clear bad outfit scans after the preview scanner test" },
	{ "library bodies", "which model file each body key actually drew" },
}

local function ShowHelp()
	Addon:Warn("commands, as /mogtrot or /mogt")
	for _, entry in ipairs(HELP) do
		print(("  |cffffd100%-17s|r %s"):format(entry[1], entry[2]))
	end
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
		Addon:Warn("chat output %s.", MogtrotDB.quiet and "silenced" or "on")
		return
	end

	if cmd == "capture" then
		Addon:CaptureActiveLook(true)
		return
	end

	if cmd == "wear" then
		Addon:WearReport()
		return
	end

	if cmd == "summon" then
		Addon:SummonForActiveOutfit(false)
		return
	end

	if cmd == "fallback" then
		Addon:Say(Addon:SummonFallbackText())
		Addon:Say("change it with /mogtrot fallback random, pinned, litemount or off - or in Mogtrot's "
			.. "settings panel, where the mode lives too.")
		Addon:Say("to pin a mount, right-click its card in the mount picker and choose Pin.")
		return
	end

	local fallback = cmd:match("^fallback%s+(%S+)$")
	if fallback then
		if fallback == "litemount" and not LiteMountFallbackAvailable() then
			Addon:Say("LiteMount's compatibility button is unavailable.")
		elseif FALLBACK_MODES[fallback] then
			Addon:SetSummonFallback({ mode = fallback })
		else
			Addon:Say("use /mogtrot fallback random, pinned, litemount or off.")
		end
		return
	end

	if cmd == "slots wipe" then
		local n = 0
		for outfitID in pairs(MogtrotCharDB.slots or {}) do
			MogtrotCharDB.slots[outfitID] = nil
			n = n + 1
		end
		Addon:Say("forgot %d slot record(s). /reload to watch the scan run again, or "
			.. "/mogtrot slots scan to do it now.", n)
		Addon:Changed()
		return
	end

	if cmd == "slots scan" then
		local all, verbose = true, true
		Addon:BeginLintSweep(all, verbose)
		return
	end

	if cmd == "state" then
		Diagnostics.ShowState(Addon, deps)
		return
	end
	if cmd == "probe" then
		Diagnostics.ProbeClient(Addon, deps)
		return
	end
	if cmd == "probe library" then
		Diagnostics.ProbeLibraryTransfer(Addon, deps)
		return
	end
	if cmd == "probe ingest" then
		Diagnostics.ProbeOutfitIngest(Addon, deps, nil)
		return
	end
	local probeIngest = cmd:match("^probe ingest%s+(%d+)$")
	if probeIngest then
		Diagnostics.ProbeOutfitIngest(Addon, deps, tonumber(probeIngest))
		return
	end
	if cmd == "probe look" then
		Diagnostics.ProbeLook(Addon, deps, nil)
		return
	end
	local probeLook = cmd:match("^probe look%s+(%d+)$")
	if probeLook then
		Diagnostics.ProbeLook(Addon, deps, tonumber(probeLook))
		return
	end
	if cmd == "probe layer" then
		Diagnostics.ProbeLayer(Addon, deps)
		return
	end
	local probeBody = cmd:match("^probe body%s+(%S+)$")
	if probeBody then
		Diagnostics.ProbeBody(Addon, deps, probeBody)
		return
	end
	if cmd == "probe body" then
		Diagnostics.ProbeBody(Addon, deps, nil)
		return
	end
	if cmd == "probe donors" then
		Diagnostics.ProbeDonors(Addon, deps)
		return
	end
	if cmd == "probe actors" then
		Diagnostics.ProbeActors(Addon, deps)
		return
	end
	if cmd == "probe auras" then
		Diagnostics.ProbeAuras(Addon, deps)
		return
	end
	if cmd == "probe secret" then
		Diagnostics.ProbeSecret(Addon, deps, false)
		return
	end
	if cmd == "probe secret watch" then
		Diagnostics.ProbeSecret(Addon, deps, true)
		return
	end
	if cmd == "inspect" then
		Diagnostics.InspectTargetLook(Addon, deps)
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
	if cmd == "library bodies" then
		local ui = ns.LibraryUI
		if not (ui and ui.BodyAudit) then
			Addon:Warn("the library has not been opened yet.")
			return
		end
		local lines = ui.BodyAudit()
		for _, line in ipairs(lines) do Addon:Say(line) end
		if ns.CopyBox then ns.CopyBox.Show("Mogtrot body audit", lines) end
		return
	end
	if cmd == "library repair" then
		local repaired = Commands.RepairOutfitLooks(MogtrotCharDB, MogtrotDB,
			UnitGUID("player"), 2)
		Addon:Warn("cleared %d bad outfit scan(s); kept outfit 2.", repaired)
		if ns.LibraryUI and ns.LibraryUI.Refresh then ns.LibraryUI.Refresh() end
		return
	end

	if Diagnostics.Handle(Addon, deps, cmd) then return end

	if cmd ~= "" then
		Addon:Say("no such command: %s", cmd)
		ShowHelp()
		return
	end

	if InCombatLockdown() then
		UIErrorsFrame:AddMessage("Mogtrot: use the keybinding or /click MogtrotToggle in combat.", 1, 0.3, 0.3)
		return
	end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end
end

ns.Commands = Commands
return Commands
