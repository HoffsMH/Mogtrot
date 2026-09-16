-- Core defines its outfit-link operations as methods on Addon, and the picker
-- files attach their own click helpers to the same table. A picker that picks
-- the same name silently replaces Core's method, and because Core's injected
-- callback then routes back into the picker the two call each other until the
-- stack gives out. Reading the sources is the only way to catch it: both
-- definitions are valid Lua and neither file is wrong on its own.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local function Definitions(path, separator)
	local names = {}
	for name in Read(path):gmatch("function Addon" .. separator .. "([%w_]+)%s*%(") do
		names[name] = true
	end
	return names
end

describe("Addon namespace", function()
	local PICKERS = {
		"HearthstonePickerUI.lua",
		"BattlePetPickerUI.lua",
		"MountPickerUI.lua",
	}

	it("has no picker helper that shadows a Core method", function()
		local methods = Definitions("Core.lua", ":")
		for _, picker in ipairs(PICKERS) do
			for name in pairs(Definitions(picker, "%.")) do
				assert.is_nil(methods[name],
					picker .. " defines Addon." .. name
						.. ", which replaces Core's Addon:" .. name)
			end
		end
	end)

	-- Guards the patterns above: a typo in either would make the check pass by
	-- finding nothing at all.
	it("reads sources that actually define something", function()
		assert.is_true(next(Definitions("Core.lua", ":")) ~= nil)
		assert.is_true(next(Definitions("HearthstonePickerUI.lua", "%.")) ~= nil)
		assert.is_true(next(Definitions("BattlePetPickerUI.lua", "%.")) ~= nil)
	end)
end)
