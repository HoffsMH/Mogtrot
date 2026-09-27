require("spec.helpers")

local MountFilter = require("MountFilter")

-- Enum.MountType values, used only to show a mount's type no longer narrows.
local GROUND, FLYING = 0, 1

local function mount(id, name, fields)
	local m = { mountID = id, name = name, search = name:lower() }
	for k, v in pairs(fields or {}) do m[k] = v end
	return m
end

local function names(list)
	local out = {}
	for _, m in ipairs(list) do table.insert(out, m.name) end
	return out
end

local function state(fields)
	local s = MountFilter.DefaultState()
	for k, v in pairs(fields or {}) do s[k] = v end
	return s
end

describe("MountFilter.Apply", function()
	it("keeps the order it was given", function()
		-- The list is ranked once when the window opens, so a filter that sorted
		-- would move a card under the cursor.
		local list = { mount(1, "Zebra"), mount(2, "Aardvark"), mount(3, "Mule") }
		assert.same({ "Zebra", "Aardvark", "Mule" }, names(MountFilter.Apply(list, state())))
	end)

	it("passes everything through with no filter at all", function()
		local list = { mount(1, "Zebra"), mount(2, "Aardvark") }
		assert.same({ "Zebra", "Aardvark" }, names(MountFilter.Apply(list, nil)))
	end)

	it("matches the search against the prepared lowercase name", function()
		local list = { mount(1, "Swift Zebra"), mount(2, "Aardvark") }
		assert.same({ "Swift Zebra" }, names(MountFilter.Apply(list, state({ query = "zebra" }))))
	end)

	it("shows only chosen mounts under chosen-only", function()
		local list = { mount(1, "Zebra"), mount(2, "Aardvark") }
		local out = MountFilter.Apply(list, state({ chosenMode = "chosen" }), { [2] = true })
		assert.same({ "Aardvark" }, names(out))
	end)

	it("shows only unchosen mounts under unchosen-only", function()
		local list = { mount(1, "Zebra"), mount(2, "Aardvark") }
		local out = MountFilter.Apply(list, state({ chosenMode = "unchosen" }), { [2] = true })
		assert.same({ "Zebra" }, names(out))
	end)

	it("shows everything when the chosen cut is off", function()
		local list = { mount(1, "Zebra"), mount(2, "Aardvark") }
		assert.same({ "Zebra", "Aardvark" },
			names(MountFilter.Apply(list, state({ chosenMode = "all" }), { [2] = true })))
		assert.same({ "Zebra", "Aardvark" },
			names(MountFilter.Apply(list, state(), { [2] = true })))
	end)

	it("keeps the order it was given under either chosen cut", function()
		-- A mode change subsets the ranking; it never re-sorts.
		local list = { mount(1, "Zebra"), mount(2, "Aardvark"), mount(3, "Mule") }
		assert.same({ "Zebra", "Mule" },
			names(MountFilter.Apply(list, state({ chosenMode = "unchosen" }), { [2] = true })))
		assert.same({ "Zebra", "Mule" },
			names(MountFilter.Apply(list, state({ chosenMode = "chosen" }),
				{ [1] = true, [3] = true })))
	end)

	it("composes search with chosen-only", function()
		local list = { mount(1, "Swift Zebra"), mount(2, "Slow Zebra"), mount(3, "Aardvark") }
		local out = MountFilter.Apply(list, state({ query = "zebra", chosenMode = "chosen" }),
			{ [2] = true, [3] = true })
		assert.same({ "Slow Zebra" }, names(out))
	end)
end)

describe("MountFilter favourites", function()
	it("shows only favourites when asked", function()
		local list = { mount(1, "Loved", { isFavorite = true }), mount(2, "Ignored") }
		assert.same({ "Loved" }, names(MountFilter.Apply(list, state({ favoritesOnly = true }))))
	end)
end)

describe("MountFilter and mounts the outfit already has", function()
	it("shows a chosen mount that is not a favourite", function()
		local list = { mount(1, "Plain"), mount(2, "Other") }
		local out = MountFilter.Apply(list, state({ favoritesOnly = true }), { [1] = true })
		assert.same({ "Plain" }, names(out))
	end)

	it("still hides a chosen mount the search does not match", function()
		-- Search is the user naming a thing; a category filter is browsing.
		local list = { mount(1, "Mule"), mount(2, "Zebra") }
		local out = MountFilter.Apply(list, state({ query = "zebra" }), { [1] = true })
		assert.same({ "Zebra" }, names(out))
	end)

	it("drops the always-show bypass under unchosen-only", function()
		-- The bypass exists so a link can always be seen and removed. Left on here
		-- it would hand back exactly the mounts this mode was asked to hide, which
		-- is the filter looking broken rather than the link being safe.
		local favs = state({ favoritesOnly = true, chosenMode = "unchosen" })
		local pair = { mount(1, "Plain"), mount(2, "Loved", { isFavorite = true }) }
		assert.same({ "Loved" }, names(MountFilter.Apply(pair, favs, { [1] = true })))
	end)
end)

describe("MountFilter.DefaultState", function()
	it("starts default", function()
		assert.is_true(MountFilter.IsDefault(MountFilter.DefaultState()))
	end)

	it("starts with the chosen cut off", function()
		assert.equals("all", MountFilter.DefaultState().chosenMode)
	end)

	it("is not default with favourites on or a chosen cut on",
		function()
			local s = MountFilter.DefaultState()
			s.favoritesOnly = true
			assert.is_false(MountFilter.IsDefault(s))

			s = MountFilter.DefaultState()
			s.chosenMode = "chosen"
			assert.is_false(MountFilter.IsDefault(s))

			s = MountFilter.DefaultState()
			s.chosenMode = "unchosen"
			assert.is_false(MountFilter.IsDefault(s))
		end)

	it("clears the chosen cut on reset but leaves search alone", function()
		-- The chosen cut lives in the dropdown now, so the dropdown's reset owns
		-- it. Search still has its own box, with the text still in it.
		local s = state({ query = "zebra", chosenMode = "unchosen", favoritesOnly = true })
		MountFilter.Reset(s)

		assert.is_true(MountFilter.IsDefault(s))
		assert.equals("zebra", s.query)
		assert.equals("all", s.chosenMode)
	end)
end)

describe("MountFilter.ShouldShowLinkedMountNotice", function()
	it("stays quiet with nothing for a link to bypass", function()
		-- No favourites filter: the rule is on but nothing would have hidden a
		-- link, so the sentence describes an invisible thing.
		assert.is_false(MountFilter.ShouldShowLinkedMountNotice(state()))
		assert.is_false(MountFilter.ShouldShowLinkedMountNotice(nil))
	end)

	it("explains itself under a favourites narrowing", function()
		assert.is_true(MountFilter.ShouldShowLinkedMountNotice(state({ favoritesOnly = true })))
	end)

	it("stays quiet under either chosen cut, however else it is narrowed", function()
		-- Vacuous under "chosen", where everything shown is on the outfit, and false
		-- under "unchosen", which is the mode that turns the bypass off. Sharing a
		-- menu with the control that falsifies it is why this is not a static line.
		for _, mode in ipairs({ "chosen", "unchosen" }) do
			local s = state({ favoritesOnly = true, chosenMode = mode })
			assert.is_false(MountFilter.ShouldShowLinkedMountNotice(s))

			assert.is_false(MountFilter.ShouldShowLinkedMountNotice(state({ chosenMode = mode })))
		end
	end)

	it("is not fooled by the search box, which narrows nothing it bypasses", function()
		assert.is_false(MountFilter.ShouldShowLinkedMountNotice(state({ query = "zebra" })))
	end)
end)

describe("the pairing window's mount filters", function()
	local function Read(path)
		local file = assert(io.open(path, "r"))
		local body = file:read("*a")
		file:close()
		return body
	end

	it("offer no mount type filter", function()
		local s = MountFilter.DefaultState()
		assert.is_nil(s.types)
		assert.is_nil(MountFilter.SetAllTypes)
		assert.is_nil(MountFilter.Verify)
		assert.is_nil(MountFilter.InjectType)
		-- A type set on a mount no longer narrows anything.
		local list = { mount(1, "Drake", { types = { [FLYING] = true } }) }
		s.types = { [GROUND] = true }
		assert.same({ "Drake" }, names(MountFilter.Apply(list, s)))
	end)

	it("never read or write the player's Mount Journal filters", function()
		for _, path in ipairs({ "MountCollection.lua", "MountPickerUI.lua", "Core.lua" }) do
			local body = Read(path)
			for _, needle in ipairs({ "SetTypeFilter", "SetSourceFilter",
				"SetCollectedFilterSetting", "IsValidTypeFilter", "GetDisplayedMountID",
				"MOUNT_JOURNAL_FILTER_TYPE" }) do
				assert.is_nil(body:find(needle, 1, true), path .. " contains " .. needle)
			end
		end
	end)
end)
