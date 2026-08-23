local MountPick = require("MountPick")

-- Answers isUsable for the ids in `usable`, and a refusal for everything else.
local function Usability(usable, err)
	local seen = {}
	local function ask(mountID)
		seen[mountID] = (seen[mountID] or 0) + 1
		if usable[mountID] then return true end
		return false, err
	end
	return ask, seen
end

local function Pick(n) return function() return n end end

-- One starred mount, and the usability that lets the favourite rung fire. The
-- rung draws for itself now, so owning a favourite is not enough on its own.
local function Favourites() return { [901] = true } end
local function FavUsable() return Usability({ [901] = true }) end

-- A Plan request with every injection answering "nothing here", so each spec sets
-- only the part it is about. Counters go on the request so a spec can assert that
-- an expensive question was never asked.
local function Request(over)
	local request = {
		hasOutfit = false,
		set = nil,
		fallback = {},
		liteMountAvailable = false,
		usable = function() return false end,
		random = Pick(1),
		asked = { mountInfo = 0, favourite = 0, collection = 0 },
	}
	request.mountInfo = function() return false end
	request.favourites = function() return {} end
	request.collection = function() return {} end

	for key, value in pairs(over or {}) do request[key] = value end

	local mountInfo, favourites = request.mountInfo, request.favourites
	local collection = request.collection
	request.mountInfo = function(mountID)
		request.asked.mountInfo = request.asked.mountInfo + 1
		return mountInfo(mountID)
	end
	request.favourites = function()
		request.asked.favourite = request.asked.favourite + 1
		return favourites()
	end
	request.collection = function()
		request.asked.collection = request.asked.collection + 1
		return collection()
	end
	return request
end

describe("MountPick.Sorted", function()
	it("returns nothing for an empty or absent set", function()
		assert.same({}, MountPick.Sorted({}))
		assert.same({}, MountPick.Sorted(nil))
	end)

	it("orders ascending", function()
		-- These do not come out of pairs in order on either 5.1 or LuaJIT.
		assert.same({ 5, 7, 12 }, MountPick.Sorted({ [12] = true, [5] = true, [7] = true }))
	end)
end)

describe("MountPick.Plan, target match", function()
	it("uses a valid target before linked mounts and LiteMount fallback", function()
		local plan = MountPick.Plan(Request({
			targetMountID = 777,
			hasOutfit = true,
			set = { [101] = true },
			fallback = { mode = "litemount" },
			liteMountAvailable = true,
		}))
		assert.same({ action = "summon", mountID = 777, from = "target" }, plan)
	end)
end)

describe("MountPick.Choose", function()
	it("returns nothing, and no reason, for an empty set", function()
		local ask = Usability({})
		local mountID, reason = MountPick.Choose({}, ask, Pick(1))
		assert.is_nil(mountID)
		assert.is_nil(reason)

		mountID, reason = MountPick.Choose(nil, ask, Pick(1))
		assert.is_nil(mountID)
		assert.is_nil(reason)
	end)

	it("summons the only usable mount", function()
		local ask = Usability({ [101] = true })
		assert.equals(101, MountPick.Choose({ [101] = true }, ask, Pick(1)))
	end)

	it("draws only from the usable mounts", function()
		local ask = Usability({ [102] = true, [104] = true })
		local set = { [101] = true, [102] = true, [103] = true, [104] = true }
		assert.equals(102, MountPick.Choose(set, ask, Pick(1)))
		assert.equals(104, MountPick.Choose(set, ask, Pick(2)))
	end)

	it("sizes the draw by the usable pool, not by the set", function()
		local ask = Usability({ [103] = true })
		local size
		MountPick.Choose({ [101] = true, [102] = true, [103] = true }, ask, function(n)
			size = n
			return 1
		end)
		assert.equals(1, size)
	end)

	it("returns the client's own refusal when nothing is usable", function()
		local ask = Usability({}, "You can't do that while indoors")
		local mountID, reason = MountPick.Choose({ [101] = true }, ask, Pick(1))
		assert.is_nil(mountID)
		assert.equals("You can't do that while indoors", reason)
	end)

	it("reports the first refusal rather than the last", function()
		local function ask(mountID)
			return false, "no for " .. mountID
		end
		local _, reason = MountPick.Choose({ [12] = true, [5] = true, [7] = true }, ask, Pick(1))
		assert.equals("no for 5", reason)
	end)

	it("survives a refusal that carries no reason", function()
		local ask = Usability({})
		local mountID, reason = MountPick.Choose({ [101] = true }, ask, Pick(1))
		assert.is_nil(mountID)
		assert.is_nil(reason)
	end)

	it("asks about every mount, exactly once per pick", function()
		local ask, seen = Usability({ [101] = true, [102] = true })
		MountPick.Choose({ [101] = true, [102] = true }, ask, Pick(1))
		assert.same({ [101] = 1, [102] = 1 }, seen)
	end)

	it("re-reads usability on every pick rather than holding it", function()
		-- The whole point: usability is situational, so a mount refused indoors
		-- has to become available again by walking outside, with no cache to clear.
		local indoors = true
		local function ask()
			if indoors then return false, "Can only use outside" end
			return true
		end
		local set = { [101] = true }
		assert.is_nil(MountPick.Choose(set, ask, Pick(1)))
		indoors = false
		assert.equals(101, MountPick.Choose(set, ask, Pick(1)))
	end)
end)

describe("MountPick.Plan, the outfit's own mounts", function()
	local mountType = { Ground = 0, Flying = 1, Aquatic = 2, Dragonriding = 3 }

	it("summons from the set and says where it came from", function()
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = { [101] = true, [102] = true },
			usable = Usability({ [101] = true, [102] = true }),
			random = Pick(2),
		}))
		assert.equals("summon", plan.action)
		assert.equals(102, plan.mountID)
		assert.equals("outfit", plan.from)
		-- No cause: nothing to explain, so nothing is said.
		assert.is_nil(plan.cause)
	end)

	it("refuses in the client's own words when the set is all refused, and does "
		.. "not fall back", function()
		-- The situational case. A favourite would be refused for the same reason
		-- indoors, and the client's wording already says what is wrong.
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = { [101] = true },
			usable = Usability({}, "Can only use outside"),
			fallback = { mode = "random" },
			favourites = function() return { [901] = true } end,
		}))
		assert.equals("refuse", plan.action)
		assert.equals("unusable", plan.reason)
		assert.equals("Can only use outside", plan.detail)
		assert.is_nil(plan.cause)
	end)

	it("never asks the fallback's questions when the set answers", function()
		local request = Request({
			hasOutfit = true,
			set = { [101] = true },
			usable = Usability({ [101] = true }),
			fallback = { mode = "random" },
		})
		MountPick.Plan(request)
		assert.same({ mountInfo = 0, favourite = 0, collection = 0 }, request.asked)
	end)

	it("prefers by situation after filtering linked mounts for usability", function()
		local ask, seen = Usability({ [101] = true, [102] = true, [103] = true })
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = { [101] = true, [102] = true, [103] = true, [104] = true },
			usable = ask,
			preference = {
				types = {
					[101] = { [mountType.Ground] = true },
					[102] = { [mountType.Flying] = true },
					[103] = { [mountType.Aquatic] = true },
					[104] = { [mountType.Dragonriding] = true },
				},
				situation = { advancedFlyable = true },
				mountType = mountType,
			},
		}))
		assert.equals(102, plan.mountID)
		assert.equals("flying", plan.preferenceTier)
		assert.same({ 101, 102, 103 }, plan.candidates)
		assert.same({ 102 }, plan.viableCandidates)
		assert.same({ [101] = 1, [102] = 1, [103] = 1, [104] = 1 }, seen)
	end)

	it("keeps flat random when classification is unavailable", function()
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = { [101] = true, [102] = true },
			usable = Usability({ [101] = true, [102] = true }),
			random = Pick(2),
			preference = {
				types = nil,
				situation = { flyable = true },
				mountType = mountType,
			},
		}))
		assert.equals(102, plan.mountID)
		assert.equals("all", plan.preferenceTier)
	end)

	it("falls back when every linked mount is ground-only in a flying area", function()
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = { [101] = true },
			usable = Usability({ [101] = true, [901] = true, [902] = true }),
			fallback = { mode = "random" },
			favourites = function() return { [901] = true, [902] = true } end,
			collection = function() return { [101] = true, [901] = true, [902] = true } end,
			preference = {
				types = {
					[101] = { [mountType.Ground] = true },
					[901] = { [mountType.Ground] = true },
					[902] = { [mountType.Flying] = true },
				},
				situation = { flyable = true },
				mountType = mountType,
				requirePreferred = true,
			},
		}))
		assert.equals("summon", plan.action)
		assert.equals(902, plan.mountID)
		assert.equals("favourite", plan.from)
		assert.equals("unsuitable", plan.cause)
	end)

	it("skips ground-only favourites when the collection has a flying mount", function()
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = { [101] = true },
			usable = Usability({ [101] = true, [901] = true, [902] = true }),
			fallback = { mode = "random" },
			favourites = function() return { [901] = true } end,
			collection = function() return { [901] = true, [902] = true } end,
			preference = {
				types = {
					[101] = { [mountType.Ground] = true },
					[901] = { [mountType.Ground] = true },
					[902] = { [mountType.Flying] = true },
				},
				situation = { flyable = true },
				mountType = mountType,
				requirePreferred = true,
			},
		}))
		assert.equals(902, plan.mountID)
		assert.equals("collection", plan.from)
	end)

	it("still refuses when every linked mount is unusable", function()
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = { [101] = true, [102] = true },
			usable = Usability({}, "Can only use outside"),
			random = function() error("preference must not draw") end,
			preference = {
				types = { [102] = { [mountType.Flying] = true } },
				situation = { flyable = true },
				mountType = mountType,
			},
		}))
		assert.equals("refuse", plan.action)
		assert.equals("unusable", plan.reason)
		assert.equals("Can only use outside", plan.detail)
	end)

	it("does not apply outfit preference to fallback mounts", function()
		local plan = MountPick.Plan(Request({
			favourites = function() return { [901] = true, [902] = true } end,
			usable = Usability({ [901] = true, [902] = true }),
			random = Pick(2),
			preference = {
				types = { [901] = { [mountType.Ground] = true } },
				situation = {},
				mountType = mountType,
			},
		}))
		assert.equals(902, plan.mountID)
		assert.equals("favourite", plan.from)
		assert.is_nil(plan.preferenceTier)
	end)
end)

describe("MountPick.Plan, LiteMount fallback", function()
	it("delegates an active outfit with no linked mounts when LiteMount is available",
		function()
			local plan = MountPick.Plan(Request({
				hasOutfit = true,
				set = {},
				fallback = { mode = "litemount" },
				liteMountAvailable = true,
			}))
			assert.equals("litemount", plan.action)
			assert.equals("nomounts", plan.cause)
		end)

	it("refuses explicitly when LiteMount is unavailable", function()
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = {},
			fallback = { mode = "litemount" },
			liteMountAvailable = false,
		}))
		assert.equals("refuse", plan.action)
		assert.equals("litemountunavailable", plan.reason)
		assert.equals("nomounts", plan.cause)
	end)

	it("preserves the ordinary fallback ladder with no active outfit", function()
		local plan = MountPick.Plan(Request({
			fallback = { mode = "litemount" },
			liteMountAvailable = true,
			favourites = Favourites,
			usable = FavUsable(),
		}))
		assert.equals("summon", plan.action)
		assert.equals(901, plan.mountID)
		assert.equals("favourite", plan.from)
		assert.equals("nooutfit", plan.cause)
	end)

	it("summons a usable linked mount", function()
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = { [101] = true },
			fallback = { mode = "litemount" },
			liteMountAvailable = true,
			usable = Usability({ [101] = true }),
		}))
		assert.same({ action = "summon", mountID = 101, from = "outfit",
			candidates = { 101 }, viableCandidates = { 101 } }, plan)
	end)

	it("refuses when every linked mount is unusable", function()
		local plan = MountPick.Plan(Request({
			hasOutfit = true,
			set = { [101] = true },
			fallback = { mode = "litemount" },
			liteMountAvailable = true,
			usable = Usability({}, "Can only use outside"),
		}))
		assert.same({ action = "refuse", reason = "unusable",
			detail = "Can only use outside" }, plan)
	end)
end)

describe("MountPick.Plan, the fallback", function()

	it("falls back with no outfit active, which is a new character's normal state",
		function()
			local plan = MountPick.Plan(Request({
				favourites = Favourites, usable = FavUsable(),
			}))
			assert.equals("summon", plan.action)
			assert.equals(901, plan.mountID)
			assert.equals("favourite", plan.from)
			assert.equals("nooutfit", plan.cause)
		end)

	it("falls back when the active outfit has no mounts linked", function()
		local plan = MountPick.Plan(Request({
			hasOutfit = true, set = {}, favourites = Favourites, usable = FavUsable(),
		}))
		assert.equals("favourite", plan.from)
		assert.equals("nomounts", plan.cause)
	end)

	it("defaults to the random favourite when nothing is configured", function()
		-- Absence has to mean the default, because that is what every character
		-- that has never touched the setting looks like.
		local plan = MountPick.Plan(Request({
			fallback = nil, favourites = Favourites, usable = FavUsable(),
		}))
		assert.equals("favourite", plan.from)
	end)

	it("refuses with the cause when the fallback is off", function()
		local plan = MountPick.Plan(Request({
			fallback = { mode = "off" }, favourites = Favourites,
		}))
		assert.equals("refuse", plan.action)
		assert.equals("nooutfit", plan.reason)
		assert.equals("nooutfit", plan.cause)
	end)

	it("refuses only once there is no mount on the character at all", function()
		-- A brand new character: no outfit, no favourites, and nothing collected.
		local plan = MountPick.Plan(Request({}))
		assert.equals("refuse", plan.action)
		assert.equals("nocollection", plan.reason)
		assert.equals("nooutfit", plan.cause)
	end)

	it("asks about favourites only when that rung is reached", function()
		local request = Request({ fallback = { mode = "off" } })
		MountPick.Plan(request)
		assert.equals(0, request.asked.favourite)
	end)
end)

describe("MountPick.Plan, no favourites either", function()
	local function Collection(set)
		return function() return set end
	end

	it("falls through to a random mount from the collection", function()
		-- The rung that stops the key dead-ending on a character with no outfit,
		-- no linked mounts and nothing starred.
		local plan = MountPick.Plan(Request({
			collection = Collection({ [101] = true, [102] = true }),
			usable = Usability({ [101] = true, [102] = true }),
			random = Pick(2),
		}))
		assert.equals("summon", plan.action)
		assert.equals(102, plan.mountID)
		-- Its own "from", because a mount that is neither the outfit's nor a
		-- favourite has one more thing to explain than the rung above it.
		assert.equals("collection", plan.from)
		assert.equals("nooutfit", plan.cause)
	end)

	it("draws only from the mounts the client will allow here", function()
		-- The same filter the outfit's own set goes through, and the same injected
		-- usability, so this rung cannot summon what rung one would have skipped.
		local request = Request({
			collection = Collection({ [101] = true, [102] = true, [103] = true }),
			usable = Usability({ [102] = true }),
			random = function(n)
				assert.equals(1, n)
				return 1
			end,
		})
		assert.equals(102, MountPick.Plan(request).mountID)
	end)

	it("refuses in the client's own words when the whole collection is refused",
		function()
			-- Indoors. Situational rather than a gap in the collection, and the two
			-- are different sentences.
			local plan = MountPick.Plan(Request({
				collection = Collection({ [101] = true }),
				usable = Usability({}, "Can only use outside"),
			}))
			assert.equals("refuse", plan.action)
			assert.equals("collectionunusable", plan.reason)
			assert.equals("Can only use outside", plan.detail)
			assert.equals("nooutfit", plan.cause)
		end)

	it("falls through to the collection when a favourite is owned but not usable "
		.. "here", function()
		-- The bug this rung was written around. Asking only whether a favourite is
		-- owned, then handing the pick to SummonByID(0), stopped the ladder dead
		-- wherever none of them could be summoned: the client picks server-side and
		-- says nothing when it cannot.
		local plan = MountPick.Plan(Request({
			favourites = Favourites,
			collection = function() return { [901] = true, [902] = true } end,
			usable = Usability({ [902] = true }, "Can only use outside"),
		}))
		assert.equals("summon", plan.action)
		assert.equals(902, plan.mountID)
		assert.equals("collection", plan.from)
	end)

	it("refuses only after the favourites are exhausted too", function()
		local plan = MountPick.Plan(Request({
			favourites = Favourites,
			collection = function() return { [901] = true } end,
			usable = Usability({}, "Can only use outside"),
		}))
		assert.equals("refuse", plan.action)
		assert.equals("collectionunusable", plan.reason)
		assert.equals("Can only use outside", plan.detail)
	end)

	it("walks the collection only when that rung is reached", function()
		-- The walk is the whole mount journal, so it is asked for on the same terms
		-- as the favourite check: never above the rung that needs it.
		local request = Request({ fallback = { mode = "off" } })
		MountPick.Plan(request)
		assert.equals(0, request.asked.collection)

		request = Request({ favourites = Favourites, usable = FavUsable() })
		MountPick.Plan(request)
		assert.equals(0, request.asked.collection)

		request = Request({
			hasOutfit = true,
			set = { [101] = true },
			usable = Usability({ [101] = true }),
		})
		MountPick.Plan(request)
		assert.equals(0, request.asked.collection)
	end)

	it("re-reads the collection on every plan rather than holding it", function()
		-- A mount collected mid-session, or an alt logged in to, has to be noticed
		-- with nothing cleared.
		local owned = {}
		local request = Request({
			collection = function() return owned end,
			usable = function() return true end,
		})
		assert.equals("refuse", MountPick.Plan(request).action)
		owned[101] = true
		assert.equals(101, MountPick.Plan(request).mountID)
	end)
end)
