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
