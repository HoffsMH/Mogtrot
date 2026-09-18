-- Commands.lua reaches into other modules by name at runtime, so a function
-- deleted or renamed there fails only when a player types the command. The
-- syntax checks pass, the suite passes, and the slash command errors. Reading
-- both sources is the only way to catch it before the client does.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local function Defined(path, module)
	local names = {}
	for name in Read(path):gmatch("function " .. module .. "%.([%w_]+)%s*%(") do
		names[name] = true
	end
	return names
end

-- Diagnostics arrives as an upvalue, so its calls are unqualified; every other
-- module is reached through the addon namespace.
local function Dispatched(path)
	local calls = {}
	for name in Read(path):gmatch("Diagnostics%.([%w_]+)%s*%(") do
		calls[#calls + 1] = { module = "Diagnostics", fn = name }
	end
	for module, name in Read(path):gmatch("ns%.([%w_]+)%.([%w_]+)%s*%(") do
		calls[#calls + 1] = { module = module, fn = name }
	end
	return calls
end

describe("command dispatch", function()
	it("calls only functions the target module defines", function()
		local calls = Dispatched("Commands.lua")
		assert.is_true(#calls > 0)
		for _, call in ipairs(calls) do
			local path = call.module .. ".lua"
			local file = io.open(path, "r")
			assert.is_truthy(file, "Commands.lua calls " .. call.module
				.. ", which has no source file")
			file:close()
			local defined = Defined(path, call.module)
			assert.is_true(defined[call.fn] == true,
				"Commands.lua calls " .. call.module .. "." .. call.fn
					.. ", which is not defined")
		end
	end)

	it("reaches the modules the library work added", function()
		local wanted = { SnapCapture = "Target", LibraryUI = "Toggle" }
		local found = {}
		for _, call in ipairs(Dispatched("Commands.lua")) do
			found[call.module] = found[call.module] or {}
			found[call.module][call.fn] = true
		end
		for module, fn in pairs(wanted) do
			assert.is_true(found[module] ~= nil and found[module][fn] == true,
				"Commands.lua no longer calls " .. module .. "." .. fn)
		end
	end)

	it("lists every command it dispatches in its own help", function()
		local body = Read("Commands.lua")
		local help = {}
		for entry in body:gmatch('{ "([^"]+)", "[^"]*" }') do
			help[entry] = true
		end
		for cmd in body:gmatch('if cmd == "([^"]+)" then') do
			-- A help entry may carry an argument placeholder, so "probe body"
			-- is covered by "probe body <id>".
			local listed = help[cmd] == true
			if not listed then
				for entry in pairs(help) do
					if entry:sub(1, #cmd + 1) == cmd .. " " then listed = true end
				end
			end
			assert.is_true(listed or cmd == "help" or cmd == "?",
				"/mogtrot " .. cmd .. " is dispatched but not in the help list")
		end
	end)
end)
