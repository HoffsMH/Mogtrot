-- Help text is chat text with no pure layer, so it is checked by reading the
-- source.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

describe("help text", function()
	-- Debug, diagnostic and report commands live in the private specs tree.
	it("offers only player commands", function()
		local source = Read("Commands.lua")
		for _, name in ipairs({ "debug", "probe", "inspect", "state", "macro",
			"wear", "slots", "library bodies", "nudge", "mountzoom", "why", "capture" }) do
			assert.is_nil(source:find('{ "' .. name, 1, true), "a " .. name .. " help row")
			assert.is_nil(source:find('cmd == "' .. name, 1, true), "a " .. name .. " command")
		end
		assert.is_nil(source:find("DevCommands", 1, true))
		assert.is_nil(source:find("Diagnostics", 1, true))
	end)

	-- The donor debug commands live in the private specs tree, not the addon.
	it("offers no donor command", function()
		local source = Read("Commands.lua")
		assert.is_nil(source:find('{ "donor', 1, true), "a donor help row")
		assert.is_nil(source:find('cmd == "donor"', 1, true), "a donor command")
		assert.is_nil(source:find("DonorLabUI", 1, true))
		assert.is_nil(source:find("DonorCoverageUI", 1, true))
	end)
end)

