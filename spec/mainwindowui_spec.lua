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
