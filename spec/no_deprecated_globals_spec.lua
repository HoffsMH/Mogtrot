-- 12.1 defines these globals only while the loadDeprecationFallbacks CVar is
-- on (Blizzard_DeprecatedChatInfo and friends). Code that calls them breaks
-- for a player who turns the fallbacks off; the C_ namespaced forms do not.
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

local DEPRECATED = { "SendChatMessage", "GetInspectSpecialization" }

describe("release code", function()
	it("calls no global that exists only as a deprecation fallback", function()
		for _, path in ipairs(SourceFiles()) do
			-- Comments may name them; only code is checked.
			local body = Read(path):gsub("%-%-[^\n]*", "")
			for _, name in ipairs(DEPRECATED) do
				for start in body:gmatch("()" .. name) do
					local before = start > 1 and body:sub(start - 1, start - 1) or ""
					assert.is_true(before == ".", ("%s calls the global %s"):format(path, name))
				end
			end
		end
	end)
end)
