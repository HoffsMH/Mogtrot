-- A function defined twice in one file is not a syntax error and not a failing
-- test: the later definition silently wins, and the code you are reading is
-- not the code that runs. That is only catchable by reading the sources.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local function SourceFiles()
	local names = {}
	local pipe = assert(io.popen("ls *.lua"))
	for name in pipe:lines() do names[#names + 1] = name end
	pipe:close()
	return names
end

-- Both spellings of a definition, and both anchored so a definition on the
-- very first line is not missed:
--   function Module.Name(...)
--   Module.Name = function(...)
local function Definitions(body)
	local counts, order = {}, {}
	local function count(name)
		if counts[name] == nil then order[#order + 1] = name end
		counts[name] = (counts[name] or 0) + 1
	end
	for name in ("\n" .. body):gmatch("\n%s*function ([%w_]+[%.:][%w_]+)%s*%(") do
		count(name)
	end
	for name in ("\n" .. body):gmatch("\n%s*([%w_]+%.[%w_]+)%s*=%s*function%s*%(") do
		count(name)
	end
	return counts, order
end

describe("no duplicate definitions", function()
	it("defines each function once per file", function()
		local files = SourceFiles()
		assert.is_true(#files > 10)
		for _, path in ipairs(files) do
			local counts, order = Definitions(Read(path))
			for _, name in ipairs(order) do
				assert.equal(1, counts[name],
					path .. " defines " .. name .. " " .. counts[name] .. " times")
			end
		end
	end)

	it("reads something at all", function()
		-- Named against a function that is part of the addon rather than a
		-- probe, so deleting a probe cannot quietly disarm this guard.
		local counts = Definitions(Read("Diagnostics.lua"))
		assert.equal(1, counts["Diagnostics.Handle"])
		assert.equal(1, counts["Diagnostics.ShowState"])
	end)
end)
