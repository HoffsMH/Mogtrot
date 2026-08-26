require("spec.wow_stubs")
local Macro = require("Macro")

-- A body list as the adapter hands it over: slot 1..n, nil where GetMacroBody
-- gave nothing back.
local function Reader(bodies)
	return function(slot) return bodies[slot] end
end

local function Plan(bodies, command, maxMacros)
	return Macro.Plan(bodies.n or #bodies, Reader(bodies), command, maxMacros or 30)
end

describe("Macro.Body", function()
	it("is the marker line then the click", function()
		assert.equals("#mogtrot:open\n/click MogtrotToggle", Macro.Body("open"))
	end)

	it("clicks the summon button for the summon command", function()
		assert.equals("#mogtrot:summon\n/click MogtrotSummon", Macro.Body("summon"))
	end)

	it("stays on the dispatcher when a fallback route is supplied", function()
		assert.equals("#mogtrot:summon\n/click MogtrotSummon",
			Macro.Body("summon", "litemount"))
	end)

	it("round-trips through CommandOf", function()
		assert.equals("open", Macro.CommandOf(Macro.Body("open")))
		assert.equals("summon", Macro.CommandOf(Macro.Body("summon")))
	end)

	it("answers nothing for a command it does not define", function()
		assert.is_nil(Macro.Body("wear"))
	end)

	it("fits a macro body twice over", function()
		for _, command in ipairs(Macro.ORDER) do
			assert.is_true(#Macro.Body(command) < 255)
		end
	end)
end)

describe("Macro.RepairPlan", function()
	it("repairs the generated double-dispatch summon body", function()
		local bodies = { "#mogtrot:summon\n/click MogtrotSummon\n/click LM_B1" }
		assert.equals(1, Macro.RepairPlan(1, Reader(bodies), "summon"))
	end)

	it("leaves the stable body and user edits alone", function()
		assert.is_nil(Macro.RepairPlan(1,
			Reader({ "#mogtrot:summon\n/click MogtrotSummon" }), "summon"))
		assert.is_nil(Macro.RepairPlan(1,
			Reader({ "#mogtrot:summon\n/click MogtrotSummon\n/say mounted" }), "summon"))
	end)
end)

describe("Macro.DEFS", function()
	it("defines every command in ORDER", function()
		assert.equals(2, #Macro.ORDER)
		for _, command in ipairs(Macro.ORDER) do
			assert.is_table(Macro.DEFS[command])
		end
	end)

	-- Two macros exist at once, so a shared name would make the list unreadable and
	-- a shared click target would make both do the same thing.
	it("gives each command its own name and click target", function()
		local names, targets = {}, {}
		for _, command in ipairs(Macro.ORDER) do
			local def = Macro.DEFS[command]
			assert.is_nil(names[def.name])
			assert.is_nil(targets[def.target])
			names[def.name], targets[def.target] = true, true
		end
	end)

	it("keeps every name inside the 16-character cap", function()
		for _, command in ipairs(Macro.ORDER) do
			assert.is_true(#Macro.NameOf(command) <= 16)
		end
	end)

	it("answers nothing for a command it does not define", function()
		assert.is_nil(Macro.NameOf("wear"))
	end)
end)

describe("Macro.CommandOf", function()
	it("reads the command out of the marker", function()
		assert.equals("open", Macro.CommandOf("#mogtrot:open\n/click MogtrotToggle"))
	end)

	it("finds a marker that is not the first line", function()
		assert.equals("open", Macro.CommandOf("#showtooltip\n#mogtrot:open\n/click MogtrotToggle"))
	end)

	it("ignores a doubled hash", function()
		assert.is_nil(Macro.CommandOf("##mogtrot:open\n/click MogtrotToggle"))
	end)

	it("ignores a longer prefix", function()
		assert.is_nil(Macro.CommandOf("#mogtrotfoo:open\n/click MogtrotToggle"))
	end)

	it("ignores the marker mid-line", function()
		assert.is_nil(Macro.CommandOf("/say #mogtrot:open"))
	end)

	it("ignores another addon's marker", function()
		assert.is_nil(Macro.CommandOf("#plumber:outfit\n/click PLMR_OUTFIT"))
	end)

	it("answers nothing for a body that is not a string", function()
		assert.is_nil(Macro.CommandOf(nil))
		assert.is_nil(Macro.CommandOf(42))
	end)
end)

describe("Macro.Find", function()
	it("returns the slot carrying our marker", function()
		local bodies = { "/dance", "#mogtrot:open\n/click MogtrotToggle", "/wave" }
		assert.equals(2, Macro.Find(3, Reader(bodies), "open"))
	end)

	it("returns nothing when no slot carries it", function()
		local bodies = { "/dance", "#plumber:outfit\n/click PLMR_OUTFIT" }
		assert.is_nil(Macro.Find(2, Reader(bodies), "open"))
	end)

	it("skips a slot with no body rather than stopping there", function()
		local bodies = { [1] = "/dance", [3] = "#mogtrot:open\n/click MogtrotToggle" }
		assert.equals(3, Macro.Find(3, Reader(bodies), "open"))
	end)

	it("does not match a different command", function()
		local bodies = { "#mogtrot:summon\n/click MogtrotSummon" }
		assert.is_nil(Macro.Find(1, Reader(bodies), "open"))
	end)

	it("tells the two commands apart when both exist", function()
		local bodies = {
			"#mogtrot:open\n/click MogtrotToggle",
			"#mogtrot:summon\n/click MogtrotSummon",
		}
		assert.equals(1, Macro.Find(2, Reader(bodies), "open"))
		assert.equals(2, Macro.Find(2, Reader(bodies), "summon"))
	end)

	it("reads nothing when there are no character macros at all", function()
		assert.is_nil(Macro.Find(0, Reader({}), "open"))
	end)
end)

describe("Macro.Plan", function()
	it("reuses a macro we already own", function()
		local bodies = { "/dance", "#mogtrot:open\n/click MogtrotToggle" }
		local action, slot = Plan(bodies, "open")
		assert.equals("reuse", action)
		assert.equals(2, slot)
	end)

	it("reuses one the user has edited and renamed", function()
		local bodies = { "#mogtrot:open\n/click MogtrotToggle\n/say ready" }
		local action, slot = Plan(bodies, "open")
		assert.equals("reuse", action)
		assert.equals(1, slot)
	end)

	it("creates when we own none and there is room", function()
		assert.equals("create", Plan({ "/dance" }, "open"))
	end)

	it("creates when there are no character macros at all", function()
		assert.equals("create", Plan({}, "open"))
	end)

	it("refuses when every slot is taken", function()
		local bodies = {}
		for i = 1, 30 do bodies[i] = "/dance" end
		assert.equals("full", Plan(bodies, "open"))
	end)

	it("still reuses ours when every slot is taken", function()
		local bodies = {}
		for i = 1, 30 do bodies[i] = "/dance" end
		bodies[30] = "#mogtrot:open\n/click MogtrotToggle"
		local action, slot = Plan(bodies, "open")
		assert.equals("reuse", action)
		assert.equals(30, slot)
	end)

	-- A count over the cap should read as full rather than as room, so a client
	-- that ever reports more than the constant cannot talk us into a create.
	it("refuses when the count is already past the cap", function()
		local bodies = { n = 31 }
		for i = 1, 31 do bodies[i] = "/dance" end
		assert.equals("full", Plan(bodies, "open"))
	end)

	it("creates on the last free slot", function()
		local bodies = {}
		for i = 1, 29 do bodies[i] = "/dance" end
		assert.equals("create", Plan(bodies, "open"))
	end)

	-- One free slot and neither macro made: one of them can be created and, after
	-- that, the other cannot. Owning one says nothing about the other.
	it("plans each command on its own", function()
		local bodies = {}
		for i = 1, 29 do bodies[i] = "/dance" end
		assert.equals("create", Plan(bodies, "open"))
		assert.equals("create", Plan(bodies, "summon"))

		bodies[30] = "#mogtrot:open\n/click MogtrotToggle"
		local action, slot = Plan(bodies, "open")
		assert.equals("reuse", action)
		assert.equals(30, slot)
		assert.equals("full", Plan(bodies, "summon"))
	end)
end)

describe("Macro.CanOffer", function()
	it("is true when there is room", function()
		assert.is_true(Macro.CanOffer(0, Reader({}), "open", 30))
	end)

	it("is true when ours already exists, full or not", function()
		local bodies = {}
		for i = 1, 30 do bodies[i] = "/dance" end
		bodies[7] = "#mogtrot:open\n/click MogtrotToggle"
		assert.is_true(Macro.CanOffer(30, Reader(bodies), "open", 30))
	end)

	it("is false when full and none of them is ours", function()
		local bodies = {}
		for i = 1, 30 do bodies[i] = "/dance" end
		assert.is_false(Macro.CanOffer(30, Reader(bodies), "open", 30))
	end)

	-- The answer is per command, so a full list with our open macro in it still
	-- offers the open one and honestly refuses the summon one.
	it("answers differently for the two commands on a full list", function()
		local bodies = {}
		for i = 1, 30 do bodies[i] = "/dance" end
		bodies[7] = "#mogtrot:open\n/click MogtrotToggle"
		assert.is_true(Macro.CanOffer(30, Reader(bodies), "open", 30))
		assert.is_false(Macro.CanOffer(30, Reader(bodies), "summon", 30))
	end)
end)

describe("Macro.ActionBarCommands", function()
	local function Actions(entries)
		return function(slot)
			local entry = entries[slot]
			if not entry then return nil end
			return entry.kind, entry.id
		end
	end

	it("reports each Mogtrot macro independently", function()
		local bodies = {
			[4] = "#mogtrot:open\n/click MogtrotToggle",
			[9] = "#mogtrot:summon\n/click MogtrotSummon",
		}
		local actions = {
			[2] = { kind = "macro", id = 9 },
			[17] = { kind = "macro", id = 4 },
		}
		local found = Macro.ActionBarCommands(24, Actions(actions), Reader(bodies))
		assert.is_true(found.open)
		assert.is_true(found.summon)
	end)

	it("does not report the absent macro", function()
		local bodies = {
			[4] = "#mogtrot:open\n/click MogtrotToggle",
			[9] = "#mogtrot:summon\n/click MogtrotSummon",
		}
		local actions = { [2] = { kind = "macro", id = 4 } }
		local found = Macro.ActionBarCommands(24, Actions(actions), Reader(bodies))
		assert.is_true(found.open)
		assert.is_nil(found.summon)
	end)

	it("ignores non-macro actions with a matching numeric id", function()
		local bodies = {
			[4] = "#mogtrot:open\n/click MogtrotToggle",
			[9] = "#mogtrot:summon\n/click MogtrotSummon",
		}
		local actions = {
			[2] = { kind = "spell", id = 9 },
			[17] = { kind = "macro", id = 4 },
		}
		local found = Macro.ActionBarCommands(24, Actions(actions), Reader(bodies))
		assert.is_true(found.open)
		assert.is_nil(found.summon)
	end)
end)

describe("Macro.IconToApply", function()
	it("updates a reused open macro whose icon differs", function()
		assert.equals(2869702, Macro.IconToApply("open", 136243, 2869702))
	end)

	it("leaves a reused open macro alone when its icon is current", function()
		assert.is_nil(Macro.IconToApply("open", 2869702, 2869702))
	end)

	it("never edits the summon macro icon", function()
		assert.is_nil(Macro.IconToApply("summon", 136243, 2869702))
	end)
end)
