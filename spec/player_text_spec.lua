-- Player-visible text is built across many files and often across several
-- lines, so these read every string literal in the runtime sources. Comments
-- are skipped; anything inside quotes counts, since any of it can reach chat,
-- a tooltip or a label.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local function RuntimeFiles()
	local files = {}
	for line in Read("Mogtrot.toc"):gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") then
			files[#files + 1] = line:match("^%s*(.-)%s*$")
		end
	end
	return files
end

-- Closing bracket of a long string or comment opened at i, as "]==]".
local function LongClose(source, i)
	local level = source:match("^%[(=*)%[", i)
	if not level then return nil end
	return "]" .. level .. "]", #level + 2
end

-- Every string literal in source, with its line, comments left out.
local function Literals(source)
	local out, i, n, line = {}, 1, #source, 1
	local function Advance(to)
		local _, count = source:sub(i, to - 1):gsub("\n", "")
		line = line + count
		i = to
	end
	while i <= n do
		local c = source:sub(i, i)
		if c == "-" and source:sub(i, i + 1) == "--" then
			local close, width = LongClose(source, i + 2)
			local stop
			if close then
				stop = source:find(close, i + 2 + width, true)
				stop = stop and stop + #close or n + 1
			else
				stop = source:find("\n", i, true) or n + 1
			end
			Advance(stop)
		elseif c == '"' or c == "'" then
			local j, parts = i + 1, {}
			while j <= n do
				local d = source:sub(j, j)
				if d == "\\" then
					parts[#parts + 1] = source:sub(j, j + 1)
					j = j + 2
				elseif d == c then
					break
				else
					parts[#parts + 1] = d
					j = j + 1
				end
			end
			out[#out + 1] = { text = table.concat(parts), line = line }
			Advance(j + 1)
		elseif c == "[" and LongClose(source, i) then
			local close, width = LongClose(source, i)
			local stop = source:find(close, i + width, true) or n
			out[#out + 1] = { text = source:sub(i + width, stop - 1), line = line }
			Advance(stop + #close)
		else
			i = i + 1
			if c == "\n" then line = line + 1 end
		end
	end
	return out
end

local function EachLiteral(visit)
	for _, path in ipairs(RuntimeFiles()) do
		for _, literal in ipairs(Literals(Read(path))) do
			visit(path, literal)
		end
	end
end

-- The subcommands the slash handler answers, read from its own branches.
local function RegisteredCommands()
	local source = Read("Commands.lua")
	local known = {}
	for word in source:gmatch('cmd == "(%a+)"') do known[word] = true end
	for word in source:gmatch('cmd:match%("%^(%a+)') do known[word] = true end
	return known
end

describe("player text", function()
	it("reads literals and skips comments", function()
		local found = Literals('-- "a"\nlocal x = "b" --[[ "c" ]] .. [[d]]\n')
		assert.equal(2, #found)
		assert.equal("b", found[1].text)
		assert.equal(2, found[1].line)
		assert.equal("d", found[2].text)
	end)

	it("names only slash commands that exist", function()
		local known = RegisteredCommands()
		assert.is_true(known.snap and known.fallback and true or false)
		local bad = {}
		EachLiteral(function(path, literal)
			for word in literal.text:gmatch("/mogt%a*%s+(%a+)") do
				if not known[word] then
					bad[#bad + 1] = ("%s:%d /mogtrot %s"):format(path, literal.line, word)
				end
			end
		end)
		assert.same({}, bad)
	end)

	it("never says donor", function()
		local bad = {}
		EachLiteral(function(path, literal)
			if literal.text:lower():find("%f[%a]donors?%f[%A]") then
				bad[#bad + 1] = ("%s:%d %s"):format(path, literal.line, literal.text)
			end
		end)
		assert.same({}, bad)
	end)
end)
