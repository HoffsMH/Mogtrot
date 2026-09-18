-- A module that is not in the TOC does not exist in game, and the release and
-- dev builds diverging is a bug that only shows up on whichever one the player
-- happens to run. Both are checked against the files on disk.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local function Listed(path)
	local order, seen = {}, {}
	for line in Read(path):gmatch("[^\r\n]+") do
		local name = line:match("^([%w_]+%.lua)%s*$")
		if name then
			order[#order + 1] = name
			seen[name] = true
		end
	end
	return order, seen
end

local function SourceFiles()
	local names = {}
	local pipe = assert(io.popen("ls *.lua"))
	for name in pipe:lines() do
		-- The luacheck config is configuration, not a module.
		if name ~= ".luacheckrc" then names[#names + 1] = name end
	end
	pipe:close()
	return names
end

describe("TOC", function()
	local release, releaseSet = Listed("Mogtrot.toc")
	local dev, devSet = Listed("MogtrotDev.toc")

	it("lists every module in the release build", function()
		for _, name in ipairs(SourceFiles()) do
			assert.is_true(releaseSet[name] == true,
				name .. " is not listed in Mogtrot.toc")
		end
	end)

	it("loads the same files in the same order in both builds", function()
		assert.same(release, dev)
	end)

	it("lists nothing that is not on disk", function()
		for _, name in ipairs(release) do
			local file = io.open(name, "r")
			assert.is_truthy(file, "Mogtrot.toc lists " .. name .. ", which is missing")
			if file then file:close() end
		end
	end)

	it("loads every module before the first file that requires it", function()
		local position = {}
		for index, name in ipairs(release) do position[name] = index end
		-- A module reached through ns at load time must already have run.
		local dependencies = {
			["Database.lua"] = { "Library.lua", "Tree.lua", "CategoryColor.lua" },
			["Library.lua"] = { "LookCodec.lua" },
			["LibraryText.lua"] = { "LookCodec.lua" },
			-- These reach each other through ns at call time rather than at
			-- load, so getting the order wrong fails in game and not here
			-- unless it is written down.
			["LibraryUI.lua"] = {
				"Library.lua", "LibraryText.lua", "LookCodec.lua", "RaceBody.lua",
				"DonorBody.lua", "ProbeRenderUI.lua", "CopyBox.lua", "ClientProbe.lua",
			},
			["LibraryDetailUI.lua"] = { "LibraryText.lua", "LibraryUI.lua" },
			["SnapCapture.lua"] = {
				"Library.lua", "InspectLook.lua", "FormDefinitions.lua",
				"RaceBody.lua", "LibraryUI.lua",
			},
			["ProbeRenderUI.lua"] = { "ClientProbe.lua" },
		}
		for file, needed in pairs(dependencies) do
			for _, other in ipairs(needed) do
				assert.is_true(position[other] ~= nil and position[file] ~= nil
					and position[other] < position[file],
					other .. " must load before " .. file)
			end
		end
	end)

	it("read something at all", function()
		assert.is_true(#release > 10)
		assert.is_true(#SourceFiles() > 10)
	end)
end)
