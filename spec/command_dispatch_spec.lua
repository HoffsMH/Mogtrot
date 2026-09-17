-- Commands.lua reaches into Diagnostics by name at runtime, so a function
-- deleted or renamed there fails only when a player types the command. The
-- syntax checks pass, the suite passes, and the slash command errors. Reading
-- both sources is the only way to catch it before the client does.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local function Defined(path)
	local names = {}
	for name in Read(path):gmatch("function Diagnostics%.([%w_]+)%s*%(") do
		names[name] = true
	end
	return names
end

local function Dispatched(path)
	local names = {}
	for name in Read(path):gmatch("Diagnostics%.([%w_]+)%s*%(") do
		names[name] = true
	end
	return names
end

describe("command dispatch", function()
	it("calls only Diagnostics functions that exist", function()
		local defined = Defined("Diagnostics.lua")
		for name in pairs(Dispatched("Commands.lua")) do
			assert.is_true(defined[name] == true,
				"Commands.lua calls Diagnostics." .. name .. ", which is not defined")
		end
	end)

	it("reads sources that actually define and call something", function()
		assert.is_true(next(Defined("Diagnostics.lua")) ~= nil)
		assert.is_true(next(Dispatched("Commands.lua")) ~= nil)
	end)
end)
