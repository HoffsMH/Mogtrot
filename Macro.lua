local ADDON_NAME, ns = ...
-- Loaded two ways: by the client, where ... is (name, shared table), and by
-- require in the test runner, where ... is the module name and ns is nil.
if type(ns) ~= "table" then ns = {} end

-- The action-bar macro, decided from macro bodies alone. No frames, no API.
--
-- A marker line in the body is the identity, never the name. Macro names are not
-- unique and the user may rename ours, so a scan that matched on the name would
-- either miss it and make a second one or adopt somebody else's.
local Macro = {}

Macro.PREFIX = "#mogtrot:"
Macro.OPEN = "open"
Macro.SUMMON = "summon"
Macro.LEAST = "least"
Macro.HEARTH = "hearth"
Macro.SNAP = "snap"
-- Per command: the named button the body clicks, and the macro's name. MogtrotToggle
-- is the secure toggle, MogtrotSummon calls the same function as the summon
-- keybinding, and MogtrotLeastWorn chooses and wears an underused outfit.
--
-- One macro per command, so a name is never truncated to the 16-character cap,
-- uniquified, or checked against anything. Names differ so the macros are told
-- apart in the macro list; identity is the marker line, never the name.
Macro.DEFS = {
	[Macro.OPEN] = { target = "MogtrotToggle", name = "Mogtrot", fixedIcon = 2869702 },
	[Macro.SUMMON] = { target = "MogtrotSummon", name = "Mogtrot Mount" },
	[Macro.LEAST] = { target = "MogtrotLeastWorn", name = "Mogtrot Least", fixedIcon = 237285 },
	[Macro.HEARTH] = { target = "MogtrotHearthstone", name = "Mogtrot Hearth" },
	[Macro.SNAP] = { body = "/mogtrot snap", name = "Mogtrot Snap", fixedIcon = 134442 },
}

-- Fixed order, so anything listing the macros reads the same way every time.
Macro.ORDER = { Macro.OPEN, Macro.SUMMON, Macro.LEAST, Macro.HEARTH }

function Macro.NameOf(command)
	local def = Macro.DEFS[command]
	return def and def.name
end

function Macro.Body(command)
	local def = Macro.DEFS[command]
	if not def then return nil end
	return Macro.PREFIX .. command .. "\n" .. (def.body or "/click " .. def.target)
end

-- The icon Mogtrot owns for a command, or nil when the macro's icon is
-- runtime/user-chosen (summon) or the command has no definition yet.
function Macro.FixedIcon(command)
	local def = Macro.DEFS[command]
	return def and def.fixedIcon or nil
end

-- The marker has to start a line, so "##mogtrot:open" and "#mogtrotfoo:open" are
-- not ours and neither is the word appearing in the middle of a /say. Prepending
-- a newline is what gives the first line a boundary to match against; the prefix
-- itself holds no pattern-magic characters.
function Macro.CommandOf(body)
	if type(body) ~= "string" then return nil end
	return ("\n" .. body):match("\n" .. Macro.PREFIX .. "(%w+)")
end

-- count    how many macro slots are in use in the block being scanned
-- getBody  1..count -> that slot's body, or nil
--
-- Returns the slot carrying our marker, or nil. A slot with no body is skipped
-- rather than treated as the end of the list.
function Macro.Find(count, getBody, command)
	for slot = 1, count or 0 do
		if Macro.CommandOf(getBody(slot)) == command then
			return slot
		end
	end
	return nil
end

-- Returns the slot only for the generated body that double-dispatched before the
-- secure dispatcher owned LiteMount fallback. User edits never match it.
function Macro.RepairPlan(count, getBody, command)
	if command ~= Macro.SUMMON then return nil end
	local slot = Macro.Find(count, getBody, command)
	if not slot then return nil end
	local body = getBody(slot)
	if type(body) ~= "string" then return nil end
	body = body:gsub("\r\n", "\n"):match("^%s*(.-)%s*$")
	if body == Macro.Body(command) .. "\n/click LM_B1" then return slot end
	return nil
end

-- Reuse before create, always. Asked per command, so owning one macro says nothing
-- about whether the other can be made. Returns one of:
--   "reuse", slot   an existing macro carries this command's marker
--   "create"        we own none for it, and there is a free slot
--   "full"          we own none for it, and every slot is taken
function Macro.Plan(count, getBody, command, maxMacros)
	local slot = Macro.Find(count, getBody, command)
	if slot then return "reuse", slot end
	if (count or 0) >= maxMacros then return "full" end
	return "create"
end

-- Whether a drag would produce anything, asked before the drag rather than
-- reported as a failure after it.
function Macro.CanOffer(count, getBody, command, maxMacros)
	return Macro.Plan(count, getBody, command, maxMacros) ~= "full"
end

function Macro.ActionBarCommands(slotCount, getActionInfo, getBody)
	local found = {}
	for slot = 1, slotCount do
		local kind, macroIndex = getActionInfo(slot)
		if kind == "macro" then
			local command = Macro.CommandOf(getBody(macroIndex))
			if command then found[command] = true end
		end
	end
	return found
end

function Macro.DragShown(forceShown, placed, command)
	return forceShown or not placed[command]
end

-- OPEN and LEAST have fixed icons Mogtrot owns, so a macro the user renamed or
-- a client that substituted its fallback icon gets corrected on the next
-- refresh. The summon macro's icon comes from a runtime spell texture and stays
-- with whatever the user sets, and commands without a fixedIcon (summon, and
-- any command not yet defined) are never forced.
function Macro.IconToApply(command, currentIcon)
	local fixed = Macro.FixedIcon(command)
	if fixed and currentIcon ~= fixed then
		return fixed
	end
	return nil
end

ns.Macro = Macro
return Macro
