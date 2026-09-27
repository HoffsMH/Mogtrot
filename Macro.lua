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
	[Macro.SNAP] = { body = "/mogtrot snap", name = "Mogtrot Snap", fixedIcon = 1109100 },
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
		-- A macro showing a spell or item reports that id instead of its index.
		local kind, macroIndex, subType = getActionInfo(slot)
		if kind == "macro" and subType ~= "spell" and subType ~= "item" then
			local command = Macro.CommandOf(getBody(macroIndex))
			if command then found[command] = true end
		end
	end
	return found
end

function Macro.DragShown(forceShown, placed, command)
	return forceShown or not placed[command]
end

-- The main window's sidebar, top to bottom.
Macro.SIDEBAR = { Macro.SNAP, Macro.SUMMON, Macro.HEARTH, Macro.LEAST, Macro.OPEN }

-- Setup icons invite a drag: they glow, hide while their macro is on a bar,
-- and the setup-icons setting turns them off. Snap and least always show.
Macro.SETUP = { [Macro.SUMMON] = true, [Macro.HEARTH] = true, [Macro.OPEN] = true }

-- setupShown  the setup-icons setting
-- placed      command -> true for each Mogtrot macro on an action slot
--
-- Returns the icons to show, in order, each { command, glow }.
function Macro.Sidebar(setupShown, placed)
	local shown = {}
	for _, command in ipairs(Macro.SIDEBAR) do
		local setup = Macro.SETUP[command] == true
		if not setup or (setupShown and not placed[command]) then
			shown[#shown + 1] = { command = command, glow = setup }
		end
	end
	return shown
end

-- What a user can type for a command. Snap, summon and open run as addon
-- code, so /mogt does them. A hearth or an outfit change needs a secure
-- click, and so does summon when it hands over to LiteMount; for those the
-- line is the macro's own /click.
function Macro.TypedLine(command, liteMountFallback)
	if command == Macro.OPEN then return "/mogt" end
	if command == Macro.SNAP then return "/mogt snap" end
	if command == Macro.SUMMON and not liteMountFallback then return "/mogt summon" end
	local def = Macro.DEFS[command]
	return def and def.target and "/click " .. def.target or nil
end

local SIDEBAR_TIPS = {
	[Macro.SNAP] = { "Snap", "Press this to snapshot another player's appearance. "
		.. "You can also drag this to your bars or type %s while targeting another player." },
	[Macro.SUMMON] = { "Mount",
		"Drag this to replace your mount button on your bars or type %s." },
	[Macro.HEARTH] = { "Hearth",
		"Drag this to replace your hearthstone on your bars or type %s." },
	[Macro.LEAST] = { "Random outfit", "A random outfit, starting with those you "
		.. "haven't used much. You can also drag this to your bars or type %s." },
	[Macro.OPEN] = { "Mogtrot window",
		"Drag this to your bars or type %s to open this window." },
}

-- Returns the tooltip title and text for a sidebar icon.
function Macro.SidebarTip(command, liteMountFallback)
	local tip = SIDEBAR_TIPS[command]
	if not tip then return nil end
	return tip[1], tip[2]:format(Macro.TypedLine(command, liteMountFallback))
end

-- OPEN and LEAST have fixed icons Mogtrot owns, so a macro the user renamed or
-- a client that substituted its fallback icon gets corrected on the next
-- refresh.
--
-- SUMMON and HEARTH own no constant: what they should show depends on what the
-- active outfit is linked to, which only the caller can read. It arrives as
-- wantedIcon, and a command with a fixed icon ignores it, so a caller can pass
-- one for every command without deciding which kind it is.
--
-- Either way an icon already correct returns nil, because the only consumer
-- writes with EditMacro and there is no reason to write what is already there.
function Macro.IconToApply(command, currentIcon, wantedIcon)
	local fixed = Macro.FixedIcon(command)
	if fixed then
		if currentIcon ~= fixed then return fixed end
		return nil
	end
	if wantedIcon and currentIcon ~= wantedIcon then
		return wantedIcon
	end
	return nil
end

ns.Macro = Macro
return Macro
