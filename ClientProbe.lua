local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Pure half of the client probe. The addon's pinned Blizzard source can lag
-- the live build, so guessing which functions exist is how an hour gets lost.
-- This enumerates instead: the caller hands over what it found and this turns
-- it into a report. Tables in, no frames, no C_ calls.
local ClientProbe = {}

-- Model widget methods worth knowing about, grouped by the question each one
-- answers. Presence is the finding; these are never called here.
ClientProbe.WIDGET_METHODS = {
	body = {
		"SetUnit", "SetModelByUnit", "SetCustomRace", "SetRaceGenderOptions",
		"SetModelByCreatureDisplayID", "SetModelByFileID", "SetDisplayInfo",
		"GetDisplayInfo", "SetPlayerModelFromGlues",
	},
	dress = {
		"Undress", "TryOn", "SetItemTransmogInfo", "SetAutoDress",
		"SetUseTransmogChoices", "SetSheathed", "UndressSlot",
	},
	motion = {
		"SetAnimation", "HasAnimation", "FreezeAnimation", "PlayAnimKit",
		"ApplySpellVisualKit", "SetSpellVisualKit",
	},
	framing = {
		"SetPortraitZoom", "SetPosition", "SetFacing", "SetCustomCamera",
		"SetViewTranslation", "SetModelAlpha",
	},
}

-- Namespaces to enumerate wholesale. Every function name is dumped, because
-- the useful one is usually the one nobody thought to look for.
ClientProbe.NAMESPACES = {
	"C_BarberShop", "C_PlayerInfo", "C_TransmogSets", "C_TransmogCollection",
	"C_Transmog", "C_TransmogOutfitInfo", "C_ModelInfo", "C_RecentAllies",
	"C_CharacterCustomization", "C_CharacterServices", "C_AccountInfo",
}

local function SortedKeys(map)
	local keys = {}
	for key in pairs(map or {}) do keys[#keys + 1] = tostring(key) end
	table.sort(keys)
	return keys
end

-- has(name) -> truthy when the name exists. Returns present and absent, both
-- sorted, so a diff between two client builds is a plain text diff.
function ClientProbe.Presence(names, has)
	local present, absent = {}, {}
	for _, name in ipairs(names or {}) do
		if type(has) == "function" and has(name) then
			present[#present + 1] = name
		else
			absent[#absent + 1] = name
		end
	end
	table.sort(present)
	table.sort(absent)
	return present, absent
end

local function Section(lines, title)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "== " .. title
end

local function List(lines, label, names)
	if #names == 0 then
		lines[#lines + 1] = label .. ": none"
		return
	end
	lines[#lines + 1] = ("%s (%d): %s"):format(label, #names, table.concat(names, " "))
end

-- findings = {
--   build, widgets = { [widgetName] = function(method) -> bool },
--   namespaces = { [nsName] = { fnName = true } or false },
--   units = { { label, fields = { {name, value} } } },
--   calls = { { name, result } },
-- }
function ClientProbe.Lines(findings)
	local lines = { "Mogtrot client probe" }
	lines[#lines + 1] = "build: " .. tostring((findings or {}).build or "unknown")

	for _, widget in ipairs((findings or {}).widgets or {}) do
		Section(lines, "widget " .. tostring(widget.name))
		if not widget.has then
			lines[#lines + 1] = "could not be created"
		else
			for _, group in ipairs({ "body", "dress", "motion", "framing" }) do
				local present, absent = ClientProbe.Presence(
					ClientProbe.WIDGET_METHODS[group], widget.has)
				List(lines, group .. " present", present)
				List(lines, group .. " MISSING", absent)
			end
		end
	end

	for _, entry in ipairs((findings or {}).namespaces or {}) do
		Section(lines, "namespace " .. tostring(entry.name))
		if not entry.functions then
			lines[#lines + 1] = "absent"
		else
			List(lines, "functions", SortedKeys(entry.functions))
		end
	end

	for _, unit in ipairs((findings or {}).units or {}) do
		Section(lines, "unit " .. tostring(unit.label))
		for _, field in ipairs(unit.fields or {}) do
			lines[#lines + 1] = ("  %s = %s"):format(tostring(field[1]), tostring(field[2]))
		end
	end

	local calls = (findings or {}).calls
	if calls and #calls > 0 then
		Section(lines, "calls")
		for _, call in ipairs(calls) do
			lines[#lines + 1] = ("  %s -> %s"):format(tostring(call[1]), tostring(call[2]))
		end
	end

	return lines
end

-- SetItemTransmogInfo answers with an ItemTryOnReason, not a boolean. Every
-- slot that reports anything other than Success is a slot the viewer is not
-- seeing, which is the difference between "applied" and "worked".
ClientProbe.TRY_ON_REASON = {
	[0] = "ok",
	[1] = "wrongRace",
	[2] = "notEquippable",
	[3] = "pending",
}

-- Returns a tally keyed by reason name, plus how many slots are still worth
-- retrying. Only pending is worth retrying: the other refusals are permanent
-- for this body.
function ClientProbe.TryOnTally(reasons)
	local tally, retryable, total = {}, 0, 0
	for _, reason in pairs(reasons or {}) do
		local name = ClientProbe.TRY_ON_REASON[reason] or ("reason " .. tostring(reason))
		tally[name] = (tally[name] or 0) + 1
		total = total + 1
		if reason == 3 then retryable = retryable + 1 end
	end
	return tally, retryable, total
end

-- Stable text for a tally, busiest first, so two runs can be compared.
function ClientProbe.TallyText(tally)
	local names = {}
	for name in pairs(tally or {}) do names[#names + 1] = name end
	table.sort(names, function(a, b)
		if tally[a] ~= tally[b] then return tally[a] > tally[b] end
		return a < b
	end)
	local parts = {}
	for _, name in ipairs(names) do
		parts[#parts + 1] = ("%s=%d"):format(name, tally[name])
	end
	return #parts > 0 and table.concat(parts, " ") or "nothing applied"
end

ns.ClientProbe = ClientProbe
return ClientProbe
