describe("MainWindowUI library control", function()
	local MainWindowUI

	before_each(function()
		MainWindowUI = assert(loadfile("MainWindowUI.lua"))("Mogtrot", {})
	end)

	it("uses Blizzard's quest log book icon", function()
		assert.equal("Interface\\QuestFrame\\UI-QuestLog-BookIcon",
			MainWindowUI.LibraryIcon)
	end)

	it("opens the outfit library through its public toggle", function()
		local toggles = 0
		assert.is_true(MainWindowUI.OpenLibrary({
			Toggle = function() toggles = toggles + 1 end,
		}))
		assert.equal(1, toggles)
	end)

	it("refuses to open when the library is unavailable", function()
		assert.is_false(MainWindowUI.OpenLibrary(nil))
		assert.is_false(MainWindowUI.OpenLibrary({}))
	end)

	it("keeps settings named in its tooltip but not on the title bar", function()
		assert.equal("", MainWindowUI.SettingsLabel)
		assert.equal("Mogtrot settings", MainWindowUI.SettingsTooltip)
	end)
end)

-- A keybinding clicks the summon button on the key going down and again on it
-- coming up. The secure action fires on the up edge, so the choice is made
-- there and the down edge does nothing.
describe("MainWindowUI summon button", function()
	local MainWindowUI, summons, button, addon

	before_each(function()
		MainWindowUI = assert(loadfile("MainWindowUI.lua"))("Mogtrot", {})
		summons = {}
		button = { SetAttribute = function() end }
		addon = {
			SummonForActiveOutfit = function(_, allowDelegate)
				summons[#summons + 1] = allowDelegate
				return false
			end,
		}
		_G.InCombatLockdown = function() return false end
	end)

	after_each(function() _G.InCombatLockdown = nil end)

	it("summons once per key press", function()
		MainWindowUI.SummonPreClick(button, addon, true)
		MainWindowUI.SummonPreClick(button, addon, false)
		assert.same({ true }, summons)
	end)

	it("summons once per key press in combat too", function()
		_G.InCombatLockdown = function() return true end
		MainWindowUI.SummonPreClick(button, addon, true)
		MainWindowUI.SummonPreClick(button, addon, false)
		assert.same({ false }, summons)
	end)
end)

-- The window holds secure buttons, so the game refuses to resize, move or hide
-- it in combat. Layout asked for then waits for combat to end.
describe("MainWindowUI combat layout", function()
	local MainWindowUI, inCombat, layout, applied

	before_each(function()
		MainWindowUI = assert(loadfile("MainWindowUI.lua"))("Mogtrot", {})
		inCombat = false
		applied = {}
		layout = MainWindowUI.CombatSafeLayout(function() return inCombat end)
	end)

	local function apply(name)
		return function() applied[#applied + 1] = name end
	end

	it("applies a layout at once out of combat", function()
		assert.is_true(layout.Request(apply("a")))
		assert.same({ "a" }, applied)
		assert.is_false(layout.Pending())
	end)

	it("queues a layout asked for in combat instead of applying it", function()
		inCombat = true
		assert.is_false(layout.Request(apply("a")))
		assert.same({}, applied)
		assert.is_true(layout.Pending())
	end)

	it("applies only the latest queued layout, once, when combat ends", function()
		inCombat = true
		layout.Request(apply("a"))
		layout.Request(apply("b"))
		assert.is_false(layout.Flush())
		assert.same({}, applied)
		inCombat = false
		assert.is_true(layout.Flush())
		assert.is_false(layout.Flush())
		assert.same({ "b" }, applied)
	end)

	it("has nothing to flush when nothing was queued", function()
		assert.is_false(layout.Flush())
		assert.same({}, applied)
	end)

	it("offers the close button only out of combat", function()
		assert.is_true(MainWindowUI.CloseAllowed(false))
		assert.is_false(MainWindowUI.CloseAllowed(true))
	end)
end)
