-- Core defines its outfit-link operations as methods on Addon, and the
-- pairing window attaches its own methods to the same table. A picker method
-- with the same name silently replaces Core's, and because Core's injected
-- callback then routes back into the picker the two call each other until the
-- stack gives out. Reading the sources is the only way to catch it: both
-- definitions are valid Lua and neither file is wrong on its own.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local function Definitions(path)
	local names = {}
	for name in Read(path):gmatch("function Addon[.:]([%w_]+)%s*%(") do
		names[name] = true
	end
	return names
end

describe("Addon namespace", function()
	it("has no pairing window method that shadows a Core method", function()
		local methods = Definitions("Core.lua")
		for name in pairs(Definitions("MountPickerUI.lua")) do
			assert.is_nil(methods[name],
				"MountPickerUI.lua defines Addon." .. name
					.. ", which replaces Core's Addon:" .. name)
		end
	end)

	-- Guards the pattern above: a typo in it would make the check pass by
	-- finding nothing at all.
	it("reads sources that actually define something", function()
		assert.is_true(next(Definitions("Core.lua")) ~= nil)
		assert.is_true(Definitions("MountPickerUI.lua").OpenHearthstonePicker == true)
	end)
end)
