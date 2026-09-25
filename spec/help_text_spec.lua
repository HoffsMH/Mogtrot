-- Help and picker labels are frame and chat text with no pure layer, so they
-- are checked by reading the sources against the values they describe.
local Macro = require("Macro")

local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

describe("help text", function()
	it("names every macro that /mogtrot macro checks", function()
		local row = Read("Commands.lua"):match('{%s*"macro",%s*"([^"]*)"')
		assert.is_string(row)
		for _, command in ipairs(Macro.ORDER) do
			assert.is_truthy(row:find(command, 1, true),
				"the macro help row does not mention " .. command)
		end
	end)
end)

describe("fallback picker", function()
	it("labels as default the mode that is actually the default", function()
		local body = Read("SummonController.lua")
		local default = body:match('local DEFAULT_FALLBACK_MODE = "(%w+)"')
		assert.is_string(default)
		local labelled
		for item in body:gmatch("{ name = .-preselected") do
			if item:find('note = "default', 1, true) then
				labelled = item:match('mode = "(%w+)"')
			end
		end
		assert.equals(default, labelled)
	end)
end)
