-- Mounts and hearthstones are one pairing window. These tripwires stop the old
-- separate hearthstone window coming back.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

describe("pairing window", function()
	it("leaves no old hearthstone window file behind", function()
		assert.is_nil(io.open("HearthstonePickerUI.lua", "r"))
		for _, toc in ipairs({ "Mogtrot.toc", "MogtrotDev.toc" }) do
			assert.is_nil(Read(toc):find("HearthstonePickerUI", 1, true), toc)
		end
	end)

	it("creates no second window", function()
		for _, path in ipairs({ "Core.lua", "MountPickerUI.lua", "LibraryUI.lua",
			"LibraryCards.lua", "LibraryBodies.lua", "SnapConfirmUI.lua",
			"MainWindowUI.lua", "MainWindowMenus.lua", "MacroSidebarUI.lua",
			"MainWindowRows.lua", "MainWindowDrag.lua" }) do
			assert.is_nil(Read(path):find("MogtrotHearthstonePicker", 1, true), path)
		end
	end)
end)
