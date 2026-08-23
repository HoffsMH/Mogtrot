local ADDON_NAME, ns = ...
-- Loaded two ways: by the client, where ... is (name, shared table), and by
-- require in the test runner, where ... is the module name and ns is nil.
if type(ns) ~= "table" then ns = {} end

-- How much of an outfit is actually pinned down, versus how much of it falls
-- through to whatever the character happens to be wearing. Pure: plain tables and
-- a reader function in, plain tables out, no frames and no WoW API.

local Lint = {}

function Lint.ShowInList(settings)
	return settings ~= nil and settings.showCompletenessInList == true
end

function Lint.SetShowInList(settings, enabled)
	if settings then settings.showCompletenessInList = enabled and true or false end
end

function Lint.NameInset(settings)
	return Lint.ShowInList(settings) and 16 or 4
end

-- Enum.TransmogOutfitDisplayType, mirrored so this file needs no API. Core checks
-- these against the live enum on load and warns if a patch renumbers them.
Lint.DISPLAY = {
	UNASSIGNED = 0,
	ASSIGNED = 1,
	EQUIPPED = 2,
	HIDDEN = 3,
	DISABLED = 4,
}

-- Enum.TransmogOutfitSlotOption.None, for everything that is not a weapon.
Lint.OPTION_NONE = 0

local DISPLAY = Lint.DISPLAY

-- The line is stability, not intent. Assigned and Hidden are choices that stay
-- correct forever; Equipped silently changes meaning every time the player swaps
-- gear, which is the whole thing this feature exists to find. So Equipped counts
-- as missing, and MissingLines reports it apart from Unassigned because "showing
-- your own wrists" and "wrists never set" are different things to go and fix.
local COVERED = {
	[DISPLAY.ASSIGNED] = true,
	[DISPLAY.HIDDEN] = true,
}

-- One entry per thing this character can fill. A weapon slot contributes one entry
-- per enabled weapon option - shield and off-hand are options on the off-hand slot
-- rather than slots of their own - which is why the total is per character and
-- never a constant. A slot offering no options counts once, as itself.
--
-- slotInfos: { { slot = <enum>, name = "Wrist",
--                options = { { option = <enum>, name = "Shield", enabled = true } } } }
function Lint.SlotDefs(slotInfos)
	local slotDefinitions = {}

	for _, info in ipairs(slotInfos or {}) do
		local any = false
		for _, option in ipairs(info.options or {}) do
			if option.enabled then
				any = true
				table.insert(slotDefinitions, {
					slot = info.slot,
					option = option.option,
					name = option.name or info.name,
				})
			end
		end
		if not any then
			table.insert(slotDefinitions, {
				slot = info.slot,
				option = Lint.OPTION_NONE,
				name = info.name,
			})
		end
	end

	return slotDefinitions
end

-- read(slot, option) returns a displayType, or nil when the client had nothing to
-- say. A slot that reads nil is dropped from the total rather than counted against
-- the outfit: an unreadable slot is not evidence of an unfilled one. If nothing at
-- all could be read the outfit has not been measured, so this returns nil and the
-- caller shows the unknown state instead of a zero.
function Lint.Measure(slotDefinitions, readDisplayType, interfaceBuild)
	local covered, total = 0, 0
	local missingSlots = {}

	for _, slotDefinition in ipairs(slotDefinitions or {}) do
		local displayType = readDisplayType(slotDefinition.slot, slotDefinition.option)
		if displayType ~= nil and displayType ~= DISPLAY.DISABLED then
			total = total + 1
			if COVERED[displayType] then
				covered = covered + 1
			else
				table.insert(missingSlots, {
					name = slotDefinition.name,
					equipped = displayType == DISPLAY.EQUIPPED or nil,
				})
			end
		end
	end

	if total == 0 then return nil end

	return {
		covered = covered,
		total = total,
		missing = missingSlots,
		at = interfaceBuild,
	}
end

-- "unknown" is a first-class answer, not a zero. An outfit nobody has looked at
-- has no record, and a record from before a patch is not evidence about this one.
function Lint.State(record, interfaceBuild, mounts)
	if type(record) ~= "table" or record.at ~= interfaceBuild then return "unknown" end
	if type(record.total) ~= "number" or record.total <= 0 then return "unknown" end
	if type(record.covered) ~= "number" then return "unknown" end
	if mounts and (not mounts.ground or not mounts.flying) then return "short" end

	return record.covered >= record.total and "full" or "short"
end

function Lint.Summary(record, interfaceBuild)
	if Lint.State(record, interfaceBuild) == "unknown" then return "--" end
	return ("%d/%d"):format(record.covered, record.total)
end

function Lint.MissingLines(record)
	local unset, equipped = {}, {}

	for _, entry in ipairs(record and record.missing or {}) do
		table.insert(entry.equipped and equipped or unset, entry.name)
	end

	local lines = {}
	if #unset > 0 then
		table.insert(lines, "Not set: " .. table.concat(unset, ", "))
	end
	if #equipped > 0 then
		table.insert(lines, "Shows equipped gear: " .. table.concat(equipped, ", "))
	end

	return lines
end

ns.Lint = Lint
return Lint
