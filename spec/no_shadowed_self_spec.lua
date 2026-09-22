-- A colon definition already injects self, so naming a first parameter self or
-- _self shifts every real argument one place right. Callers keep using the
-- colon, so the last argument silently arrives nil and every read returns the
-- empty default. Nothing errors, which is why only the sources catch it.
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

-- Anchored on the newline so a definition on the first line is not missed.
local function ShadowedSelf(body)
	local found = {}
	for name in ("\n" .. body):gmatch("\n%s*function ([%w_]+:[%w_]+)%s*%(%s*_?self%s*[,%)]") do
		found[#found + 1] = name
	end
	return found
end

describe("no shadowed self", function()
	it("never names a colon method's first parameter self", function()
		local files = SourceFiles()
		assert.is_true(#files > 10)
		for _, path in ipairs(files) do
			for _, name in ipairs(ShadowedSelf(Read(path))) do
				assert.equal(nil, name,
					path .. " declares " .. name .. " with an explicit self")
			end
		end
	end)

	it("recognises the shape it is looking for", function()
		assert.same({ "Addon:Broken" },
			ShadowedSelf("function Addon:Broken(_self, outfitID)\nend\n"))
		assert.same({ "Addon:AlsoBroken" },
			ShadowedSelf("function Addon:AlsoBroken(self)\nend\n"))
		assert.same({}, ShadowedSelf("function Addon:Fine(outfitID)\nend\n"))
		assert.same({}, ShadowedSelf("function Addon.Fine(self, outfitID)\nend\n"))
	end)
end)
