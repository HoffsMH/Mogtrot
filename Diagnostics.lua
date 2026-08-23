local _, ns = ...


-- Prints runtime state used in bug reports.
local Diagnostics = {}

function Diagnostics.ShowState(Addon, deps)
	local captureModel = deps.captureModel()
	local NO_TRANSMOG = deps.noTransmog
	local Wear = deps.Wear
	local WearSession = deps.wearSession
	local activeID = C_TransmogOutfitInfo.GetActiveOutfitID()
	local cached, links = 0, 0
	for _ in pairs(MogtrotCharDB.looks or {}) do cached = cached + 1 end
	for _ in pairs(MogtrotCharDB.mounts or {}) do links = links + 1 end

	local slots, list = 0, captureModel and captureModel:GetItemTransmogInfoList()
	if list then
		for _, entry in pairs(list) do
			if type(entry) == "table" and entry.appearanceID
				and entry.appearanceID ~= NO_TRANSMOG then
				slots = slots + 1
			end
		end
	end

	Addon:Say("active outfit %s, %d cached look(s), %d outfit(s) with mounts.",
		tostring(activeID), cached, links)
	Addon:Say("capture model %s, %d slot(s) readable.",
		captureModel and "ready" or "not created", slots)
	local measured, incomplete = 0, 0
	for outfitID in pairs(MogtrotCharDB.slots or {}) do
		if Addon:LintState(outfitID) ~= "unknown" then
			measured = measured + 1
			if Addon:LintState(outfitID) == "short" then incomplete = incomplete + 1 end
		end
	end
	Addon:Say("%d outfit(s) checked for slots, %d with something unset.", measured, incomplete)

	local wear = Addon:WearSnapshot()
	Addon:Say("wear time %s tracked across %d outfit(s), interval open on %s.",
		Wear.Format(wear.sum), wear.count, tostring(WearSession().id))

	Addon:Say(Addon:SummonBindingText())
	Addon:Say(Addon:SummonFallbackText())
end


function Diagnostics.Handle(Addon, deps, cmd)
	local Macro = deps.Macro
	local AccountMacroCount = deps.accountMacroCount
	if cmd == "debug" then
		MogtrotDB.debug = not MogtrotDB.debug
		Addon:Warn("debug output %s.", MogtrotDB.debug and "on" or "off")
		return
	end
	
	local nudge = cmd:match("^nudge%s+(-?[%d%.]+)$")
	if MogtrotDB.debug and nudge then
		MogtrotDB.cardNudge = tonumber(nudge) or 0
		Addon:Debug("card nudge = %s", tostring(MogtrotDB.cardNudge))
		Addon:RepaintMountCards()
		return
	end
	
	if MogtrotDB.debug and cmd == "usable" then
		local shown = 0
		for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
			local name, _s, _i, _a, _u, _t, _f, _fs, _fa, hidden, collected =
				C_MountJournal.GetMountInfoByID(mountID)
			if collected and not hidden and shown < 6 then
				shown = shown + 1
				local usable, err = C_MountJournal.GetMountUsabilityByID(mountID, true)
				Addon:Debug("%s: usable=%s err=%s", tostring(name), tostring(usable),
					tostring(err))
			end
		end
		Addon:Debug("flyable=%s advFlyable=%s drivable=%s submerged=%s indoors=%s",
			tostring(IsFlyableArea and IsFlyableArea()),
			tostring(IsAdvancedFlyableArea and IsAdvancedFlyableArea()),
			tostring(IsDrivableArea and IsDrivableArea()),
			tostring(IsSubmerged and IsSubmerged()),
			tostring(IsIndoors and IsIndoors()))
		return
	end
	
	local why = cmd:match("^why%s+(.+)$")
	if MogtrotDB.debug and why then
		local index = ns.MountIndex.Build(MogtrotCharDB)
		local shown = 0
		for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
			local name, _spellID, _i, _a, _u, _s, _isFavorite, _fs, _f, hidden, collected =
				C_MountJournal.GetMountInfoByID(mountID)
			if collected and not hidden and shown < 8
				and name and strlower(name):find(why, 1, true) then
				shown = shown + 1
				Addon:Debug("%s: pairings=%d pinned=%s", name,
					#(index[mountID] or {}),
					tostring(ns.MountPins.IsPinned(MogtrotDB, mountID, time())))
			end
		end
		if shown == 0 then Addon:Debug("no collected mount matching '%s'", why) end
		return
	end
	
	if MogtrotDB.debug and cmd == "mounttypes" then
		Addon:ReportMountTypes()
		return
	end
	
	if cmd == "macro" then
		for _, command in ipairs(Macro.ORDER) do
			Addon:Say("wanted %s: %s", command, (Macro.Body(command):gsub("\n", " | ")))
		end
	
		local count = AccountMacroCount()
		local found = {}
		for index = 1, count do
			local body = GetMacroBody(index)
			local command = Macro.CommandOf(body)
			if command then
				found[command] = true
				local name, icon = GetMacroInfo(index)
				Addon:Say("slot %d %s: name=%s icon=%s", index, command,
					tostring(name), tostring(icon))
				for line in tostring(body):gmatch("[^\n]+") do
					Addon:Say("  line: %q", line)
				end
			end
		end
	
		for _, command in ipairs(Macro.ORDER) do
			if not found[command] then
				Addon:Say("no %s macro among %d general macros", command, count)
			end
		end
		return
	end
	
	if MogtrotDB.debug and cmd == "card" then
		local card = _G["MogtrotMountCard1"]
		if not card then
			Addon:Debug("no cards built yet - open the mount picker first")
			return
		end
		Addon:Debug("card1 mount=%s id=%s onclick=%s summon=%s",
			tostring(card.mountName), tostring(card.mountID),
			tostring(card:GetScript("OnClick") ~= nil),
			tostring(C_MountJournal.SummonByID ~= nil))
		return
	end
	return false
end

ns.Diagnostics = Diagnostics
return Diagnostics
