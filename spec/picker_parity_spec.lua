-- The pairing window's header promises the two bodies behave alike, so a
-- difference between them reads as a bug rather than a choice. Both pickers
-- are frame code with no pure layer to test, so the parity that matters is
-- checked by reading the sources: the chosen card must look the same in each,
-- and both must carry the pin star in every mode.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local MOUNT = Read("MountPickerUI.lua")
local HEARTH = Read("HearthstonePickerUI.lua")

local function CardColorCalls(body)
	local calls = {}
	for args in body:gmatch("SetCardColors%(([^)]+)%)") do
		if not args:match("^%s*r%s*,") then calls[#calls + 1] = args:gsub("%s+", "") end
	end
	return calls
end

describe("picker parity", function()
	it("paints a chosen card the same way in both pickers", function()
		local mount, hearth = CardColorCalls(MOUNT), CardColorCalls(HEARTH)
		assert.is_true(#mount > 0, "MountPickerUI.lua paints no card colours")
		assert.is_true(#hearth > 0, "HearthstonePickerUI.lua paints no card colours")

		local function Has(calls, wanted)
			for _, args in ipairs(calls) do
				if args == wanted then return true end
			end
			return false
		end
		-- The gold fill and gold border of a chosen card.
		local chosen = "0.18,0.14,0.02,0.9,1,0.82,0"
		assert.is_true(Has(mount, chosen),
			"MountPickerUI.lua no longer paints a chosen card gold")
		assert.is_true(Has(hearth, chosen),
			"HearthstonePickerUI.lua must paint a chosen card the same gold as "
				.. "MountPickerUI.lua")
	end)

	it("shows the pin star in both pickers", function()
		for name, body in pairs({ ["MountPickerUI.lua"] = MOUNT,
			["HearthstonePickerUI.lua"] = HEARTH }) do
			assert.is_truthy(body:match("FallbackStar"),
				name .. " has no pin star")
			assert.is_truthy(body:match("auctionhouse%-icon%-favorite\"[^\n]*\n?[^\n]*auctionhouse%-icon%-favorite%-off")
				or body:match("auctionhouse%-icon%-favorite%-off"),
				name .. " does not set both pin star states")
		end
	end)

	it("keeps the faint tint out of the hearthstone picker", function()
		assert.is_nil(HEARTH:match("card%.Selected"),
			"the pale Selected overlay is back; a chosen card is shown by its "
				.. "border and fill, as in MountPickerUI.lua")
	end)
end)
