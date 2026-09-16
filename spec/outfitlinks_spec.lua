-- Pure multi-link store contract over a caller-owned domain:
-- store[outfitID] = { [linkedID] = true }. IDs may be numeric (mount, hearth
-- itemID) or exact string GUIDs (battle pets); the module never coerces them.
-- Signatures follow the current Core mount-link methods so the cutover keeps
-- its messages and semantics.
local OutfitLinks = require("OutfitLinks")

describe("OutfitLinks", function()
	-- A fresh store plus a Spy framework: every helper takes the store first,
	-- like the Core methods they will replace.
	local function Store(initial)
		return initial or {}
	end

	describe("Get", function()
		it("returns the linked set without creating absent outfit entries", function()
			local store = Store()
			local links = OutfitLinks.Get(store, 7)
			assert.same({}, links)
			assert.is_nil(store[7])
		end)

		it("returns the live set for a linked outfit", function()
			local links = { [101] = true }
			local store = Store({ [7] = links })
			assert.equal(links, OutfitLinks.Get(store, 7))
		end)
	end)

	describe("Count", function()
		it("counts links and reports zero for absent outfits", function()
			local store = Store({ [7] = { [101] = true, [102] = true } })
			assert.equal(2, OutfitLinks.Count(store, 7))
			assert.equal(0, OutfitLinks.Count(store, 8))
		end)
	end)

	describe("Toggle", function()
		it("adds a missing link and removes a present one", function()
			local store = Store({ [7] = { [101] = true } })
			assert.is_true(OutfitLinks.Toggle(store, 7, 102))
			assert.is_false(OutfitLinks.Toggle(store, 7, 101))
			assert.same({ [102] = true }, store[7])
		end)

		it("deletes the outfit set when the last link is removed", function()
			local store = Store({ [7] = { [101] = true } })
			OutfitLinks.Toggle(store, 7, 101)
			assert.is_nil(store[7])
		end)

		it("creates the set on first add for a numeric outfitID", function()
			local store = Store()
			OutfitLinks.Toggle(store, 7, "Pet-0xA")
			assert.same({ ["Pet-0xA"] = true }, store[7])
		end)
	end)

	describe("Replace", function()
		it("replaces the outfit set with the caller's set without aliasing", function()
			local incoming = { [102] = true, [103] = true }
			local store = Store({ [7] = { [101] = true } })
			OutfitLinks.Replace(store, 7, incoming)
			assert.same({ [102] = true, [103] = true }, store[7])
			assert.is_not_equal(incoming, store[7])
			assert.same({ [102] = true, [103] = true }, incoming)
		end)

		it("deletes the outfit set when the replacement is empty", function()
			local store = Store({ [7] = { [101] = true } })
			OutfitLinks.Replace(store, 7, {})
			assert.is_nil(store[7])
		end)

		it("treats a nil replacement as empty", function()
			local store = Store({ [7] = { [101] = true } })
			OutfitLinks.Replace(store, 7, nil)
			assert.is_nil(store[7])
		end)
	end)

	describe("Copy", function()
		it("replaces the target and reports added/had/total", function()
			local store = Store({
				[1] = { [101] = true, [102] = true },
				[2] = { [101] = true, [105] = true },
			})
			local added, had, total =
				OutfitLinks.Copy(store, 1, 2, false)
			assert.equal(1, added) -- 102 is new; 101 already there
			assert.equal(2, had)
			assert.equal(2, total)
			assert.same({ [101] = true, [102] = true }, store[2])
		end)

		it("merges into the target without aliasing source or target", function()
			local source = { [101] = true }
			local target = { [105] = true }
			local store = Store({ [1] = source, [2] = target })
			local added, had, total = OutfitLinks.Copy(store, 1, 2, true)
			assert.equal(1, added)
			assert.equal(1, had)
			assert.equal(2, total)
			assert.same({ [101] = true, [105] = true }, store[2])
			assert.is_not_equal(source, store[2])
			assert.is_not_equal(target, store[2])
			assert.same({ [101] = true }, source)
		end)

		it("returns zero counts and no change when the source is absent or empty", function()
			local store = Store({ [2] = { [101] = true } })
			local added, had, total = OutfitLinks.Copy(store, 9, 2, false)
			assert.equal(0, added)
			assert.equal(0, had) -- caller decides the empty-source message path
			assert.equal(0, total)
			assert.same({ [101] = true }, store[2])
		end)

		it("preserves exact string GUID links when copying", function()
			local guid = "Pet-0xC0FFEE-0002"
			local store = Store({ [1] = { [guid] = true } })
			OutfitLinks.Copy(store, 1, 2, false)
			assert.same({ [guid] = true }, store[2])
		end)
	end)

	describe("Apply", function()
		it("adds the link to selected outfits and removes it from unselected", function()
			local store = Store({
				[1] = { [101] = true },
				[2] = {},
				[3] = { [101] = true },
			})
			local added, removed = OutfitLinks.Apply(store, 101,
				{ [1] = false, [2] = true, [3] = true })
			assert.equal(1, added)
			assert.equal(1, removed)
			assert.is_nil(store[1]) -- last link removed, set deleted
			assert.same({ [101] = true }, store[2])
			assert.same({ [101] = true }, store[3])
		end)

		it("leaves outfits untouched when the choice matches", function()
			local store = Store({ [1] = { [101] = true } })
			local added, removed = OutfitLinks.Apply(store, 101, { [1] = true })
			assert.equal(0, added)
			assert.equal(0, removed)
			assert.same({ [101] = true }, store[1])
		end)

		it("takes the selection as a set of outfit IDs", function()
			local store = Store()
			local added = OutfitLinks.Apply(store, "Pet-0xA", { [7] = true })
			assert.equal(1, added)
			assert.same({ ["Pet-0xA"] = true }, store[7])
		end)
	end)

	describe("IndexByLinked", function()
		it("maps each linked ID to its sorted outfit-ID list", function()
			local store = Store({
				[7] = { [101] = true, [103] = true },
				[2] = { [101] = true },
				[5] = { [102] = true },
			})
			local index = OutfitLinks.IndexByLinked(store)
			assert.same({ 2, 7 }, index[101])
			assert.same({ 5 }, index[102])
			assert.same({ 7 }, index[103])
			assert.is_nil(index[104])
		end)

		it("handles numeric and string linked IDs side by side", function()
			local guid = "Pet-0xC0FFEE-0002"
			local store = Store({ [7] = { [guid] = true }, [2] = { [42] = true } })
			local index = OutfitLinks.IndexByLinked(store)
			assert.same({ 7 }, index[guid])
			assert.same({ 2 }, index[42])
		end)

		it("returns an empty index for an empty store", function()
			assert.same({}, OutfitLinks.IndexByLinked(Store()))
		end)
	end)

	describe("Clean", function()
		it("deletes only dead-outfit keys", function()
			local store = Store({
				[1] = { [101] = true },
				[2] = { [102] = true },
				[3] = { [103] = true },
			})
			OutfitLinks.Clean(store, { [1] = true, [3] = true })
			assert.same({ [101] = true }, store[1])
			assert.is_nil(store[2])
			assert.same({ [103] = true }, store[3])
		end)

		it("is a no-op when every outfit still exists", function()
			local store = Store({ [1] = { [101] = true } })
			OutfitLinks.Clean(store, { [1] = true })
			assert.same({ [101] = true }, store[1])
		end)
	end)
end)
