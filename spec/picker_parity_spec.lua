-- Mounts and hearthstones are one pairing window: one frame, one grid and one
-- card, with a body per domain. Frame code has no pure layer to test, so the
-- shape that matters is checked by reading the sources.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local function Count(body, pattern)
	local n = 0
	for _ in body:gmatch(pattern) do n = n + 1 end
	return n
end

local PAIRING = Read("MountPickerUI.lua")

describe("pairing window", function()
	it("builds one grid for both domains", function()
		assert.equal(1, Count(PAIRING, "CreateScrollBoxListGridView"))
	end)

	it("paints a card for either domain", function()
		assert.is_truthy(PAIRING:match("hearthstones%s*=%s*function%(card"),
			"MountPickerUI.lua has no hearthstone card body")
		assert.is_truthy(PAIRING:match("mounts%s*=%s*function%(card"),
			"MountPickerUI.lua has no mount card body")
	end)

	it("paints a chosen card gold", function()
		assert.is_truthy(PAIRING:find("0.18, 0.14, 0.02, 0.9, 1, 0.82, 0", 1, true))
	end)

	it("shows both pin star states", function()
		assert.is_truthy(PAIRING:match("auctionhouse%-icon%-favorite\""))
		assert.is_truthy(PAIRING:match("auctionhouse%-icon%-favorite%-off"))
	end)

	-- A removed file stays loaded until the client restarts, so it is emptied
	-- rather than dropped from the TOC. Code left in it would still run.
	it("leaves no code in the old hearthstone window", function()
		local body = Read("HearthstonePickerUI.lua")
		body = body:gsub("%-%-[^\n]*", ""):gsub("%s+", "")
		assert.equal("", body)
	end)

	it("creates no second window", function()
		for _, path in ipairs({ "Core.lua", "MountPickerUI.lua", "LibraryUI.lua",
			"MainWindowUI.lua" }) do
			assert.is_nil(Read(path):find("MogtrotHearthstonePicker", 1, true), path)
		end
	end)
end)
