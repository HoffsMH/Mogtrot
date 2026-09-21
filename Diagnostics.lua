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

-- The boolean SetModelByUnit wants for usePlayerNativeForm.
--
-- C_UnitAuras.WantsAlteredForm reads as a preference and is not one. Measured
-- against a Dracthyr in each form, it is the exact inverse of
-- GetAlternateFormInfo's inAlternateForm, which makes it the value to pass
-- straight through rather than negate:
--
--   in dragon form: WantsAlteredForm true,  inAlternateForm false
--   in visage form: WantsAlteredForm false, inAlternateForm true
--
-- GetAlternateFormInfo is authoritative but answers only for the player, so it
-- is preferred there and the aura flag covers everyone else.
local function UseNativeForm(unit)
	if unit == "player" and C_PlayerInfo and C_PlayerInfo.GetAlternateFormInfo then
		local ok, _hasAlternate, inAlternate = pcall(C_PlayerInfo.GetAlternateFormInfo)
		if ok then return not inAlternate, "GetAlternateFormInfo" end
	end
	if C_UnitAuras and C_UnitAuras.WantsAlteredForm then
		local ok, wants = pcall(C_UnitAuras.WantsAlteredForm, unit)
		if ok then return wants and true or false, "WantsAlteredForm" end
	end
	return true, "nothing answered, assuming native"
end


function Diagnostics.Handle(Addon, deps, cmd)
	local Macro = deps.Macro
	local AccountMacroCount = deps.accountMacroCount

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
		return true
	end

	return false
end

-- The form read is hard-won and the capture path needs the same answer, so it
-- is published rather than repeated.
Diagnostics.UseNativeForm = UseNativeForm

ns.Diagnostics = Diagnostics
return Diagnostics
