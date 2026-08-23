local SummonDecision = require("SummonDecision")

local function Snapshot(overrides)
	local snapshot = {
		collection = {
			[101] = { collected = true, usable = true, favorite = true, name = "A" },
			[102] = { collected = true, usable = true, name = "B" },
		},
		situation = {},
		outfit = nil,
		preferences = { fallbackMode = "random", matchTarget = false },
		integrations = { liteMountReady = false },
		shuffle = {},
		random = function() return 1 end,
		now = 0,
	}
	for key, value in pairs(overrides or {}) do snapshot[key] = value end
	return snapshot
end

describe("SummonDecision.Decide", function()
	it("keeps mounted and combat guards in the pure precedence table", function()
		local mounted = SummonDecision.Decide(Snapshot({ situation = { mounted = true } }))
		assert.equals("dismiss", mounted.intent.action)

		local combat = SummonDecision.Decide(Snapshot({ situation = { combat = true } }))
		assert.equals("refuse", combat.intent.action)
		assert.equals("combat", combat.intent.reason)
	end)

	it("puts a valid enabled target ahead of linked mounts", function()
		local result = SummonDecision.Decide(Snapshot({
			situation = { targetMountID = 102 },
			preferences = { fallbackMode = "random", matchTarget = true },
			outfit = { id = 7, name = "Set", linkedMountIDs = { [101] = true } },
		}))
		assert.equals(102, result.intent.mountID)
		assert.equals("target", result.intent.from)
	end)

	it("returns shuffle state with an outfit choice", function()
		local result = SummonDecision.Decide(Snapshot({
			outfit = { id = 7, name = "Set",
				linkedMountIDs = { [101] = true, [102] = true } },
		}))
		assert.equals("outfit", result.intent.from)
		assert.is_table(result.shuffle)
		assert.same({ 101, 102 }, result.intent.viableCandidates)
	end)

	it("mixes active pins into an outfit when enabled", function()
		local result = SummonDecision.Decide(Snapshot({
			outfit = { id = 7, name = "Set", linkedMountIDs = { [101] = true } },
			pinnedMountIDs = { [102] = true },
			preferences = { fallbackMode = "random", shufflePinned = true },
			random = function(n) return n end,
		}))
		assert.equals(102, result.intent.mountID)
		assert.same({ 101, 102 }, result.intent.viableCandidates)
	end)

	it("uses capability-safe pins as a fallback set", function()
		local mountType = { Ground = 0, Flying = 1, Aquatic = 2, Dragonriding = 3 }
		local result = SummonDecision.Decide(Snapshot({
			situation = { flyable = true },
			pinnedMountIDs = { [101] = true, [102] = true },
			preferences = { fallbackMode = "pinned" },
			mountTypes = {
				[101] = { [mountType.Ground] = true },
				[102] = { [mountType.Flying] = true },
			},
			mountType = mountType,
			requirePreferred = true,
		}))
		assert.equals(102, result.intent.mountID)
		assert.equals("fallback", result.intent.from)
	end)

	it("delegates only an active outfit with no links", function()
		local result = SummonDecision.Decide(Snapshot({
			outfit = { id = 7, name = "Set", linkedMountIDs = {} },
			preferences = { fallbackMode = "litemount", matchTarget = false },
			integrations = { liteMountReady = true },
		}))
		assert.equals("litemount", result.intent.action)
	end)

	it("preserves the flying requirement through the controller snapshot", function()
		local mountType = { Ground = 0, Flying = 1, Aquatic = 2, Dragonriding = 3 }
		local result = SummonDecision.Decide(Snapshot({
			situation = { flyable = true },
			outfit = { id = 7, name = "Set", linkedMountIDs = { [101] = true } },
			mountTypes = {
				[101] = { [mountType.Ground] = true },
				[102] = { [mountType.Flying] = true },
			},
			mountType = mountType,
			requirePreferred = true,
		}))
		assert.equals(102, result.intent.mountID)
		assert.equals("collection", result.intent.from)
		assert.equals("unsuitable", result.intent.cause)
	end)
end)

describe("SummonDecision.Transition", function()
	it("commits staged shuffle history on cast start", function()
		local decided = SummonDecision.Decide(Snapshot({
			outfit = { id = 7, name = "Set",
				linkedMountIDs = { [101] = true, [102] = true } },
		}))
		local staged = SummonDecision.Transition(decided.shuffle, {
			type = "stage", outfitID = 7, mountID = decided.intent.mountID,
			spellID = 1001, now = 0,
		})
		local confirmed = SummonDecision.Transition(staged, {
			type = "cast-start", spellID = 1001, castGUID = "cast-1", now = 1,
		})
		assert.equals(decided.intent.mountID, confirmed.lastMountID)
	end)
end)
