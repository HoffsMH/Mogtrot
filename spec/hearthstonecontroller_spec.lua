-- Fail-first tests for the dependency-injected HearthstoneController
-- (plan checkpoint 35). Everything impure is injected: the curated registry
-- shapes the candidate pool, an adapter supplies live ownership/usability/
-- cooldown, rotation state is caller-owned per outfit, and the secure button
-- is a plain attribute-recording fake. No real protected call is possible in
-- a unit test: the controller only installs attributes and the harness (or
-- MH in game) dispatches. No globals, no WoW API, no clock. Which rung of the
-- fallback ladder answers is HearthPick's; what is asserted here is the live
-- reads feeding it and the attributes and feedback that come back out.
--
-- API under contract:
--   HearthstoneController.New(deps) where deps = {
--       registry,          -- curated definitions (entries: itemID -> kind)
--       collection,        -- HearthstoneCollection-shaped reads:
--                          --   Rows(adapter, registry), UsableInfo, Cooldown
--       adapter,           -- live-ownership adapter handed to collection
--       links,             -- outfitID -> { [itemID] = true }
--       pins,              -- { [itemID] = true } active account pins
--       pinsOptOut,        -- outfitID -> true
--       rotationStates,    -- caller-owned per-outfit Rotation state map
--       random,            -- function(n) -> 1..n
--       hasActiveOutfit,   -- function() -> bool
--       activeOutfitID,    -- function() -> outfitID
--       button,            -- attribute fake: SetAttribute(name, value)
--       combat,            -- function() -> bool
--       warn,              -- function(message) for refusal feedback
--       say,               -- function(message) for what just happened
--   }
--   controller:PreClick()   -- installs secure attributes for one action
--   controller:PostClick()  -- commits the rotation once, clears attributes
local HearthstoneController = require("HearthstoneController")

describe("HearthstoneController", function()
	local HEARTH, TOY = 6948, 165802

	local function MakeDeps(overrides)
		local deps
		deps = {
			registry = {
				VERSION = 1,
				entries = {
					[HEARTH] = { kind = "item" },
					[TOY] = { kind = "toy" },
				},
			},
			adapter = {
				hasToy = function(itemID) return itemID == TOY end,
				getToyInfo = function(itemID)
					if itemID == TOY then return "Portalstone", "portal", true end
					return nil
				end,
				itemCount = function(itemID) return itemID == HEARTH and 1 or 0 end,
				totalItemCount = function(itemID) return itemID == HEARTH and 1 or 0 end,
				isUsable = function() return true, nil end,
				getCooldown = function() return 0, 0, 0 end,
				getItemName = function(itemID)
					if itemID == HEARTH then return "Hearthstone" end
				end,
				getItemIcon = function(itemID)
					if itemID == HEARTH then return "temp" end
				end,
			},
			-- HearthstoneCollection-shaped pure reads delegating to the adapter.
			collection = {
				UsableInfo = function(adapter, itemID) return adapter.isUsable(itemID) end,
				Cooldown = function(adapter, itemID) return adapter.getCooldown(itemID) end,
			},
			links = { [7] = { [HEARTH] = true } },
			pins = { [TOY] = true },
			pinsOptOut = {},
			rotationStates = {},
			random = function(n) return n end, -- deterministic: highest index
			hasActiveOutfit = function() return true end,
			activeOutfitID = function() return 7 end,
			attrs = {},
			button = {
				SetAttribute = function(_, name, value)
					deps.attrs[name] = value
				end,
			},
			combat = function() return false end,
			now = function() return 200 end,
			warn = function(msg) deps.lastWarn = msg end,
			say = function(msg) deps.lastSay = msg end,
		}
		for k, v in pairs(overrides or {}) do deps[k] = v end
		return deps
	end

	local function Attrs(deps)
		return deps.attrs
	end

	-- The adapter shape with every read answering "nothing here", so a spec
	-- states only the reads it is about.
	local function Adapter(over)
		local adapter = {
			hasToy = function() return false end,
			getToyInfo = function() return nil end,
			itemCount = function() return 0 end,
			totalItemCount = function() return 0 end,
			isUsable = function() return true, nil end,
			getCooldown = function() return 0, 0, 0 end,
			getItemName = function() return nil end,
			getItemIcon = function() return nil end,
		}
		for key, value in pairs(over or {}) do adapter[key] = value end
		return adapter
	end

	describe("PreClick attribute installation", function()
		it("installs toy secure attributes for a chosen toy", function()
			local deps = MakeDeps({
				links = { [7] = { [TOY] = true } },
				pins = {},
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("toy", Attrs(deps)["type"])
			assert.equals(TOY, Attrs(deps).toy)
			assert.is_nil(Attrs(deps).item)
		end)

		it("installs item secure attributes for a chosen carried item", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("item", Attrs(deps)["type"])
			assert.equals("item:" .. HEARTH, Attrs(deps).item)
			assert.is_nil(Attrs(deps).toy)
		end)

		it("unions active pins into links by default", function()
			local deps = MakeDeps({})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			-- Both candidates eligible; deterministic random picks the
			-- lexicographically-last kind: attributes come from the pool.
			local installed = Attrs(deps)["type"] ~= nil
			assert.is_true(installed)
			assert.is_true(Attrs(deps).toy == TOY or Attrs(deps).item == "item:" .. HEARTH)
		end)

		it("excludes pins when the outfit opts out", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = { [TOY] = true },
				pinsOptOut = { [7] = true },
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("item", Attrs(deps)["type"])
			assert.equals("item:" .. HEARTH, Attrs(deps).item)
		end)

		it("allows pins alone with no active outfit", function()
			local deps = MakeDeps({
				hasActiveOutfit = function() return false end,
				links = {},
				pins = { [TOY] = true },
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("toy", Attrs(deps)["type"])
			assert.equals(TOY, Attrs(deps).toy)
		end)

		it("filters unowned, unusable and cooldown-locked candidates at action time", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true, [TOY] = true } },
				pins = {},
				adapter = {
					hasToy = function() return false end, -- toy not owned
					getToyInfo = function() return nil end,
					itemCount = function() return 0 end, -- item carried 0
					totalItemCount = function() return 0 end,
					isUsable = function() return true, nil end,
					getCooldown = function() return 0, 0, 0 end,
					getItemName = function() return nil end,
					getItemIcon = function() return nil end,
				},
				combat = function() return false end,
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			-- Nothing survives ownership filtering: attributes stay cleared.
			assert.is_nil(Attrs(deps)["type"])
		end)

		it("skips usable candidates that are on cooldown", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
				adapter = {
					hasToy = function() return false end,
					getToyInfo = function() return nil end,
					itemCount = function() return 1 end,
					totalItemCount = function() return 1 end,
					isUsable = function() return true, nil end,
					getCooldown = function(itemID)
						if itemID == HEARTH then return 100, 600, 1 end
						return 0, 0, 0
					end,
					getItemName = function() return nil end,
					getItemIcon = function() return nil end,
				},
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.is_nil(Attrs(deps)["type"])
			assert.not_equals("", deps.lastWarn or "")
		end)

		it("leaves attributes untouched and reports a visible reason in combat", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				combat = function() return true end,
			})
			deps.attrs["type"] = "toy" -- stale attributes from an earlier click
			deps.attrs.toy = TOY
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("toy", Attrs(deps)["type"])
			assert.equals(TOY, Attrs(deps).toy)
			assert.not_equals("", deps.lastWarn or "")
		end)

		it("reports a reason when no candidate survives filtering", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
				adapter = {
					hasToy = function() return false end,
					getToyInfo = function() return nil end,
					itemCount = function() return 0 end,
					totalItemCount = function() return 0 end,
					isUsable = function() return true, nil end,
					getCooldown = function() return 0, 0, 0 end,
					getItemName = function() return nil end,
					getItemIcon = function() return nil end,
				},
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.is_nil(Attrs(deps)["type"])
			assert.not_equals("", deps.lastWarn or "")
		end)
	end)

	describe("eligibility by kind", function()
		-- A toy's item ID is not a bag item, so the client's item usability
		-- read answers unusable for every toy the player owns.
		it("uses an owned toy the item usability read calls unusable", function()
			local deps = MakeDeps({
				links = { [7] = { [TOY] = true } },
				pins = {},
				adapter = Adapter({
					hasToy = function(itemID) return itemID == TOY end,
					isUsable = function() return false end,
				}),
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("toy", Attrs(deps)["type"])
			assert.equals(TOY, Attrs(deps).toy)
		end)

		it("never asks the item usability read about a toy", function()
			local asked = false
			local deps = MakeDeps({
				links = { [7] = { [TOY] = true } },
				pins = {},
				adapter = Adapter({
					hasToy = function(itemID) return itemID == TOY end,
					isUsable = function() asked = true return true end,
				}),
			})
			HearthstoneController.New(deps):PreClick()
			assert.is_false(asked)
		end)

		it("still asks whether a carried hearthstone can be used", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
				adapter = Adapter({
					itemCount = function(itemID) return itemID == HEARTH and 1 or 0 end,
					isUsable = function() return false end,
				}),
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.is_nil(Attrs(deps)["type"])
			assert.equals("hearthstone: no hearthstone you own can be used here.",
				deps.lastWarn)
		end)
	end)

	describe("the fallback ladder", function()
		-- The linked hearthstone is carried none of, and the toy is neither
		-- linked nor pinned: it is simply owned and ready.
		local function OnlyTheToyIsReady()
			return MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
				adapter = Adapter({
					hasToy = function(itemID) return itemID == TOY end,
				}),
			})
		end

		it("uses a hearthstone the character owns when nothing linked is ready", function()
			local deps = OnlyTheToyIsReady()
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("toy", Attrs(deps)["type"])
			assert.equals(TOY, Attrs(deps).toy)
		end)

		it("states what happened rather than flashing a refusal", function()
			local deps = OnlyTheToyIsReady()
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("hearthstone: no usable linked or pinned hearthstone right now, "
				.. "so this is a random hearthstone toy.", deps.lastSay)
			assert.is_nil(deps.lastWarn)
		end)

		it("keeps quiet when the linked hearthstone is the one served", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("item:" .. HEARTH, Attrs(deps).item)
			assert.is_nil(deps.lastSay)
		end)

		it("refuses when everything owned is still on cooldown, and says so", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
				adapter = Adapter({
					hasToy = function(itemID) return itemID == TOY end,
					itemCount = function(itemID) return itemID == HEARTH and 1 or 0 end,
					getCooldown = function() return 100, 600, 1 end,
				}),
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.is_nil(Attrs(deps)["type"])
			assert.equals("hearthstone: every hearthstone you own is still on cooldown.",
				deps.lastWarn)
		end)

		it("refuses when the character owns none of the registry at all", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
				adapter = Adapter(),
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.is_nil(Attrs(deps)["type"])
			assert.equals("hearthstone: no hearthstone on this character to fall back on yet.",
				deps.lastWarn)
			-- A refusal served nothing, so it records no rotation.
			assert.is_nil(deps.rotationStates[7])
		end)
	end)

	describe("PostClick rotation commit", function()
		it("commits the rotation once and clears transient attributes", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.is_table(deps.rotationStates[7])

			controller:PostClick()
			assert.is_nil(Attrs(deps)["type"])
			assert.is_nil(Attrs(deps).item)
			-- Committed exactly once: the state records the served ID.
			assert.equal(HEARTH, deps.rotationStates[7].last)

			-- A second PostClick without a new PreClick commits nothing twice.
			controller:PostClick()
			assert.equal(HEARTH, deps.rotationStates[7].last)
		end)

		it("never retries automatically: one click, one action", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			controller:PostClick()
			-- The controller exposes no retry hook and leaves no pending
			-- state: attributes are cleared and the rotation is committed.
			assert.is_nil(Attrs(deps)["type"])
			assert.equal(HEARTH, deps.rotationStates[7].last)
		end)
	end)

	describe("no-repeat rotation", function()
		it("serves every linked item before repeating", function()
			local deps = MakeDeps({
				links = { [7] = { [TOY] = true } },
				pins = { [HEARTH] = true },
			})
			-- Unwrap the served ID from whichever attribute shape was
			-- installed: toy keeps the numeric ID, item prefixes "item:".
			local function ServedID()
				local value = Attrs(deps).toy or Attrs(deps).item
				if type(value) == "string" then
					return tonumber(value:match("^item:(%d+)$"))
				end
				return value
			end
			local served = {}
			local controller = HearthstoneController.New(deps)

			controller:PreClick()
			served[1] = ServedID()
			controller:PostClick()

			controller:PreClick()
			served[2] = ServedID()
			controller:PostClick()

			assert.equal(2, #served)
			assert.not_equals(served[1], served[2])
			assert.is_true(served[1] == TOY or served[1] == HEARTH)
			assert.is_true(served[2] == TOY or served[2] == HEARTH)
		end)
	end)

	describe("identity", function()
		it("preserves exact item IDs and never consults names", function()
			local deps = MakeDeps({
				links = { [7] = { [HEARTH] = true } },
				pins = {},
			})
			local controller = HearthstoneController.New(deps)
			controller:PreClick()
			assert.equals("item:" .. HEARTH, Attrs(deps).item)
		end)
	end)
end)
