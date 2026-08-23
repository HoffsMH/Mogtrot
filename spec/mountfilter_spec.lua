require("spec.helpers")

local MountFilter = require("MountFilter")

-- Enum.MountType, which is what the buckets are keyed by. Named here rather than
-- read from the client, because that is the point of this file being pure.
local GROUND, FLYING, AQUATIC, SKYRIDING = 0, 1, 2, 3
local ALL_TYPES = { GROUND, FLYING, AQUATIC, SKYRIDING }

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
	local s = MountFilter.DefaultState(ALL_TYPES)
	for k, v in pairs(fields or {}) do s[k] = v end
	return s
end

local function ticked(...)
	local s = MountFilter.DefaultState(ALL_TYPES)
	MountFilter.SetAllTypes(s, false)
	for _, value in ipairs({ ... }) do s.types[value] = true end
	return s
end

describe("MountFilter.Apply", function()
	it("keeps the order it was given", function()
		-- The list is ranked once when the window opens, so a filter that sorted
		-- would move a card under the cursor.
		local list = {
			mount(1, "Zebra", { types = { [GROUND] = true } }),
			mount(2, "Aardvark", { types = { [GROUND] = true } }),
			mount(3, "Mule", { types = { [GROUND] = true } }),
		}
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

describe("MountFilter type filtering", function()
	it("hides a mount whose types are all unticked", function()
		local list = {
			mount(1, "Drake", { types = { [FLYING] = true } }),
			mount(2, "Mule", { types = { [GROUND] = true } }),
		}
		assert.same({ "Drake" }, names(MountFilter.Apply(list, ticked(FLYING))))
	end)

	it("keeps a mount matching any one of its types", function()
		-- Nothing says a mount lands in a single bucket, so the walk records a set.
		local list = { mount(1, "Otter", { types = { [GROUND] = true, [AQUATIC] = true } }) }
		assert.same({ "Otter" }, names(MountFilter.Apply(list, ticked(AQUATIC))))
		assert.same({}, names(MountFilter.Apply(list, ticked(FLYING))))
	end)

	it("never hides a mount whose type is unknown", function()
		-- A walk that failed or was skipped must make the filters do less, not
		-- make mounts disappear.
		local list = {
			mount(1, "Unclassified"),
			mount(2, "Empty", { types = {} }),
			mount(3, "Mule", { types = { [GROUND] = true } }),
		}
		assert.same({ "Unclassified", "Empty" }, names(MountFilter.Apply(list, ticked(FLYING))))
	end)

	it("hides every classified mount when no type is ticked", function()
		local list = {
			mount(1, "Mule", { types = { [GROUND] = true } }),
			mount(2, "Drake", { types = { [FLYING] = true } }),
		}
		assert.same({}, names(MountFilter.Apply(list, ticked())))
	end)

	it("shows only favourites when asked", function()
		local list = { mount(1, "Loved", { isFavorite = true }), mount(2, "Ignored") }
		assert.same({ "Loved" }, names(MountFilter.Apply(list, state({ favoritesOnly = true }))))
	end)
end)

describe("MountFilter and mounts the outfit already has", function()
	it("shows a chosen mount the type filter would hide", function()
		local list = {
			mount(1, "Mule", { types = { [GROUND] = true } }),
			mount(2, "Ox", { types = { [GROUND] = true } }),
		}
		local out = MountFilter.Apply(list, ticked(FLYING), { [1] = true })
		assert.same({ "Mule" }, names(out))
	end)

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
		local list = {
			mount(1, "Mule", { types = { [GROUND] = true } }),
			mount(2, "Drake", { types = { [FLYING] = true } }),
		}
		local s = ticked(FLYING)
		s.chosenMode = "unchosen"
		assert.same({ "Drake" }, names(MountFilter.Apply(list, s, { [1] = true })))

		-- Chosen and a favourite-only filter, same rule.
		local favs = state({ favoritesOnly = true, chosenMode = "unchosen" })
		local pair = { mount(1, "Plain"), mount(2, "Loved", { isFavorite = true }) }
		assert.same({ "Loved" }, names(MountFilter.Apply(pair, favs, { [1] = true })))
	end)
end)

describe("MountFilter.DefaultState", function()
	it("ticks every type the client offers", function()
		local s = MountFilter.DefaultState(ALL_TYPES)
		assert.is_true(MountFilter.IsDefault(s))
		for _, value in ipairs(ALL_TYPES) do assert.is_true(s.types[value]) end
	end)

	it("starts with the chosen cut off", function()
		assert.equals("all", MountFilter.DefaultState(ALL_TYPES).chosenMode)
	end)

	it("is not default with a type unticked, favourites on, or a chosen cut on",
		function()
			local s = MountFilter.DefaultState(ALL_TYPES)
			s.types[GROUND] = nil
			assert.is_false(MountFilter.IsDefault(s))

			s = MountFilter.DefaultState(ALL_TYPES)
			s.favoritesOnly = true
			assert.is_false(MountFilter.IsDefault(s))

			s = MountFilter.DefaultState(ALL_TYPES)
			s.chosenMode = "chosen"
			assert.is_false(MountFilter.IsDefault(s))

			s = MountFilter.DefaultState(ALL_TYPES)
			s.chosenMode = "unchosen"
			assert.is_false(MountFilter.IsDefault(s))
		end)

	it("clears the chosen cut on reset but leaves search alone", function()
		-- The chosen cut lives in the dropdown now, so the dropdown's reset owns
		-- it. Search still has its own box, with the text still in it.
		local s = state({ query = "zebra", chosenMode = "unchosen", favoritesOnly = true })
		s.types[FLYING] = nil
		MountFilter.Reset(s)

		assert.is_true(MountFilter.IsDefault(s))
		assert.equals("zebra", s.query)
		assert.equals("all", s.chosenMode)
	end)
end)

describe("MountFilter.ShouldShowLinkedMountNotice", function()
	it("stays quiet with nothing for a link to bypass", function()
		-- Every type ticked and no favourites filter: the rule is on but nothing
		-- would have hidden a link, so the sentence describes an invisible thing.
		assert.is_false(MountFilter.ShouldShowLinkedMountNotice(state()))
		assert.is_false(MountFilter.ShouldShowLinkedMountNotice(nil))
	end)

	it("explains itself under a type or favourites narrowing", function()
		assert.is_true(MountFilter.ShouldShowLinkedMountNotice(ticked(FLYING)))
		assert.is_true(MountFilter.ShouldShowLinkedMountNotice(state({ favoritesOnly = true })))
	end)

	it("stays quiet under either chosen cut, however else it is narrowed", function()
		-- Vacuous under "chosen", where everything shown is on the outfit, and false
		-- under "unchosen", which is the mode that turns the bypass off. Sharing a
		-- menu with the control that falsifies it is why this is not a static line.
		for _, mode in ipairs({ "chosen", "unchosen" }) do
			local s = ticked(FLYING)
			s.chosenMode = mode
			assert.is_false(MountFilter.ShouldShowLinkedMountNotice(s))

			s = state({ favoritesOnly = true, chosenMode = mode })
			assert.is_false(MountFilter.ShouldShowLinkedMountNotice(s))

			assert.is_false(MountFilter.ShouldShowLinkedMountNotice(state({ chosenMode = mode })))
		end
	end)

	it("is not fooled by the search box, which narrows nothing it bypasses", function()
		assert.is_false(MountFilter.ShouldShowLinkedMountNotice(state({ query = "zebra" })))
	end)
end)

describe("MountFilter.Describe", function()
	local labels = {
		[GROUND] = "Ground", [FLYING] = "Flying",
		[AQUATIC] = "Aquatic", [SKYRIDING] = "Skyriding",
	}

	it("says nothing when nothing is narrowed", function()
		assert.is_nil(MountFilter.Describe(state(), labels))
		-- Search is not described: the box it was typed into is still on screen.
		assert.is_nil(MountFilter.Describe(state({ query = "zebra" }), labels))
		assert.is_nil(MountFilter.Describe(state({ chosenMode = "all" }), labels))
	end)

	it("names the chosen cut first, ahead of the type and favourite narrowings",
		function()
			assert.equals("on this outfit",
				MountFilter.Describe(state({ chosenMode = "chosen" }), labels))
			assert.equals("not on this outfit",
				MountFilter.Describe(state({ chosenMode = "unchosen" }), labels))

			local s = ticked(FLYING)
			s.chosenMode = "unchosen"
			s.favoritesOnly = true
			assert.equals("not on this outfit + Flying + favourites",
				MountFilter.Describe(s, labels))
		end)

	it("names the ticked types", function()
		assert.equals("Flying, Skyriding", MountFilter.Describe(ticked(FLYING, SKYRIDING), labels))
	end)

	it("reports having no types ticked rather than saying nothing", function()
		assert.equals("no types", MountFilter.Describe(ticked(), labels))
	end)

	it("adds favourites to whatever else is on", function()
		local s = ticked(FLYING)
		s.favoritesOnly = true
		assert.equals("Flying + favourites", MountFilter.Describe(s, labels))
		assert.equals("favourites", MountFilter.Describe(state({ favoritesOnly = true }), labels))
	end)
end)

describe("MountFilter.Verify", function()
	local function buckets(map)
		local out = {}
		for mountID, value in pairs(map) do out[mountID] = { [value] = true } end
		return out
	end

	it("counts collected mounts the walk never placed", function()
		local types = buckets({ [1] = GROUND })
		local unknown = select(3, MountFilter.Verify(types, { 1, 2, 3 }))
		assert.equals(2, unknown)
	end)

	it("accepts a spread across categories", function()
		local types = buckets({ [1] = GROUND, [2] = FLYING, [3] = AQUATIC })
		assert.is_true(MountFilter.Verify(types, { 1, 2, 3 }))
	end)

	it("accepts an empty category, which is not evidence of anything", function()
		-- A client that offers no Skyriding type filter walks an empty bucket, and
		-- that is correct rather than broken. InjectType fills it from elsewhere.
		local types = buckets({ [1] = GROUND, [2] = FLYING })
		assert.is_true(MountFilter.Verify(types, { 1, 2 }))
	end)

	it("rejects a category holding almost the whole collection", function()
		-- The signature of a filter that did not take: the walk records the
		-- unfiltered list as one category. Every mount is placed, so a coverage
		-- count sees nothing wrong.
		local types = {}
		for id = 1, 20 do types[id] = { [GROUND] = true } end
		local collected = {}
		for id = 1, 20 do collected[id] = id end

		local ok, reason = MountFilter.Verify(types, collected)
		assert.is_false(ok)
		assert.is_truthy(reason:find("20 of 20", 1, true))
	end)

	it("rejects a walk that placed nothing at all", function()
		local ok, reason = MountFilter.Verify({}, { 1, 2 })
		assert.is_false(ok)
		assert.equals("no mount landed in any category", reason)
	end)

	it("survives being handed nothing at all", function()
		local ok, _, unknown = MountFilter.Verify(nil, nil)
		assert.is_true(ok)
		assert.equals(0, unknown)

		-- A walk that was skipped: every collected mount is unknown, and nothing
		-- along the way is allowed to error on the missing table.
		local none = select(3, MountFilter.Verify(nil, { 1, 2 }))
		assert.equals(2, none)
	end)
end)

describe("MountFilter.InjectType", function()
	it("adds a category the walk could not produce", function()
		local types = { [1] = { [FLYING] = true } }
		MountFilter.InjectType(types, { 1, 2 }, SKYRIDING)
		assert.same({ [FLYING] = true, [SKYRIDING] = true }, types[1])
		assert.same({ [SKYRIDING] = true }, types[2])
	end)

	it("keeps what the walk already said, so ticking Flying still finds it", function()
		local types = { [1] = { [FLYING] = true } }
		MountFilter.InjectType(types, { 1 }, SKYRIDING)
		assert.is_true(types[1][FLYING])
	end)

	it("survives a missing list or category", function()
		assert.same({}, MountFilter.InjectType({}, nil, SKYRIDING))
		assert.same({}, MountFilter.InjectType({}, { 1 }, nil))
	end)
end)

describe("MountFilter.OverlapCount", function()
	it("counts how many of a list the walk already placed in a category", function()
		local types = { [1] = { [FLYING] = true }, [2] = { [GROUND] = true } }
		assert.equals(1, MountFilter.OverlapCount(types, { 1, 2, 3 }, FLYING))
		assert.equals(0, MountFilter.OverlapCount(types, { 1, 2, 3 }, SKYRIDING))
		assert.equals(0, MountFilter.OverlapCount(nil, { 1 }, FLYING))
	end)
end)
