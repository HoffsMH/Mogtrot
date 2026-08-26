local StartupGuard = require("StartupGuard")

describe("StartupGuard", function()
	it("recognizes both addon load orders", function()
		assert.equal("MogtrotDev", StartupGuard.OtherName("Mogtrot"))
		assert.equal("Mogtrot", StartupGuard.OtherName("MogtrotDev"))
		assert.is_nil(StartupGuard.OtherName("SomethingElse"))
	end)

	it("does nothing when the other addon is not installed", function()
		local queried = false
		local conflict = StartupGuard.IsConflict("Mogtrot", {
			getInfo = function() return nil end,
			getEnableState = function()
				queried = true
				return 2
			end,
		})

		assert.is_false(conflict)
		assert.is_false(queried)
	end)

	it("does nothing when the other addon is disabled", function()
		local conflict = StartupGuard.IsConflict("Mogtrot", {
			getInfo = function() return {} end,
			getEnableState = function() return 0 end,
		})

		assert.is_false(conflict)
	end)

	it("blocks either addon when both are enabled", function()
		local deps = {
			getInfo = function() return {} end,
			getEnableState = function() return 2 end,
		}

		assert.is_true(StartupGuard.IsConflict("Mogtrot", deps))
		assert.is_true(StartupGuard.IsConflict("MogtrotDev", deps))
	end)

	it("disables the unselected addon before reloading", function()
		local calls = {}
		StartupGuard.Resolve("MogtrotDev", "Player-1-0001",
			function(name, character)
				table.insert(calls, "disable:" .. name .. ":" .. character)
			end,
			function() table.insert(calls, "reload") end)

		assert.same({ "disable:Mogtrot:Player-1-0001", "reload" }, calls)
	end)

	it("keeps production and development SavedVariables separate", function()
		assert.same({ "MogtrotDB", "MogtrotCharDB" },
			{ StartupGuard.DatabaseNames("Mogtrot") })
		assert.same({ "MogtrotDevDB", "MogtrotDevCharDB" },
			{ StartupGuard.DatabaseNames("MogtrotDev") })
	end)

	it("keeps both TOC runtime file lists in parity", function()
		local function Read(path)
			local metadata, files = {}, {}
			for line in io.lines(path) do
				local key, value = line:match("^## ([^:]+):%s*(.+)$")
				if key then
					metadata[key] = value
				elseif line ~= "" and not line:match("^#") then
					table.insert(files, line)
				end
			end
			return metadata, files
		end

		local releaseMetadata, releaseFiles = Read("Mogtrot.toc")
		local devMetadata, devFiles = Read("MogtrotDev.toc")

		assert.equal("MogtrotDB", releaseMetadata.SavedVariables)
		assert.equal("MogtrotDevDB", devMetadata.SavedVariables)
		assert.equal("MogtrotDevCharDB", devMetadata.SavedVariablesPerCharacter)
		assert.is_nil(devMetadata["X-Curse-Project-ID"])
		assert.same(releaseFiles, devFiles)
	end)
end)
