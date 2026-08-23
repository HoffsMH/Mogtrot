local TargetMount = require("TargetMount")

local function Inspect(records)
	return function(mountID) return records[mountID] end
end

describe("TargetMount.Resolve", function()
	it("does nothing when disabled or target data is restricted", function()
		assert.equals("disabled", select(2, TargetMount.Resolve({ enabled = false }, Inspect({}))))
		assert.equals("secret", select(2, TargetMount.Resolve({ enabled = true, reason = "secret" }, Inspect({}))))
	end)

	it("accepts an exact collected usable mount", function()
		local match = TargetMount.Resolve({ enabled = true, exactMountID = 42 }, Inspect({
			[42] = { exists = true, collected = true, usable = true, name = "Swift Test" },
		}))
		assert.same({ mountID = 42, name = "Swift Test", reason = "accepted", source = "exact" }, match)
	end)

	it("rejects an unowned, hidden, or unusable exact mount", function()
		local base = { enabled = true, exactMountID = 42 }
		assert.equals("unowned", select(2, TargetMount.Resolve(base, Inspect({
			[42] = { exists = true, collected = false, usable = true },
		}))))
		assert.equals("hidden", select(2, TargetMount.Resolve(base, Inspect({
			[42] = { exists = true, collected = true, hidden = true, usable = true },
		}))))
		local _, reason, detail = TargetMount.Resolve(base, Inspect({
			[42] = { exists = true, collected = true, usable = false, error = "Not here" },
		}))
		assert.equals("unusable", reason)
		assert.equals("Not here", detail)
	end)

	it("accepts only one equivalent-name match", function()
		local match = TargetMount.Resolve({ enabled = true, nameMatches = { 7 } }, Inspect({
			[7] = { exists = true, collected = true, usable = true },
		}))
		assert.equals(7, match.mountID)
		assert.equals("equivalent", match.source)
		assert.equals("ambiguous", select(2, TargetMount.Resolve({
			enabled = true, nameMatches = { 7, 8 },
		}, Inspect({}))))
	end)

	it("uses an owned faction equivalent when the exact mount is unavailable", function()
		local match = TargetMount.Resolve({
			enabled = true, exactMountID = 7, nameMatches = { 8 },
		}, Inspect({
			[7] = { exists = true, collected = false, usable = false },
			[8] = { exists = true, collected = true, usable = true },
		}))
		assert.equals(8, match.mountID)
		assert.equals("equivalent", match.source)
	end)

	it("reports unidentified when neither route matches", function()
		assert.equals("unidentified", select(2, TargetMount.Resolve({
			enabled = true, nameMatches = {},
		}, Inspect({}))))
	end)
end)
