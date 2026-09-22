-- Generic pin model contract, ported from the mount-pin lifecycle. One domain
-- per store: numeric IDs or string GUIDs, never mixed. The record shape, expiry
-- math and statuses carry over unchanged; mount vocabulary does not.
local Pins = require("Pins")

describe("Pins", function()
	-- A domain is the caller-provided storage plus the settings the model
	-- reads. `domain.records` holds pinRecord tables by ID. `ordering` is the
	-- injected same-domain ID ordering used to break Recent ties
	-- deterministically; string domains pass their exact GUID ordering.
	local function Domain(overrides)
		local domain = {
			records = {},
			autoNew = true,
			days = 7,
		}
		for k, v in pairs(overrides or {}) do domain[k] = v end
		return domain
	end

	-- The comparator compares homogeneous IDs directly (`a < b`): byte order
	-- for strings, numeric order for numbers. No stringifying, so numeric IDs
	-- never sort lexicographically.
	local function Ascending(a, b) return a < b end

	describe("RecordAcquired", function()
		it("stamps acquisition and expiration from the domain days", function()
			local domain = Domain({ days = 14 })
			assert.is_true(Pins.RecordAcquired(domain, "pet-1", 1000))
			assert.same({ acquiredAt = 1000, expiresAt = 1000 + 14 * 86400 },
				domain.records["pet-1"])
			assert.is_true(Pins.IsPinned(domain, "pet-1", 1001))
		end)

		it("records a new acquisition once", function()
			local domain = Domain()
			assert.is_true(Pins.RecordAcquired(domain, "pet-1", 1000))
			assert.equal(1000, domain.records["pet-1"].acquiredAt)
			assert.equal(1000 + 7 * 86400, domain.records["pet-1"].expiresAt)
			assert.is_false(Pins.RecordAcquired(domain, "pet-1", 2000))
			assert.equal(1000, domain.records["pet-1"].acquiredAt)
		end)
		it("preserves a permanent pin when stamping its first acquisition", function()
			local domain = Domain({ records = { ["pet-1"] = { permanent = true } } })
			assert.is_true(Pins.RecordAcquired(domain, "pet-1", 2000))
			assert.same({ acquiredAt = 2000, permanent = true }, domain.records["pet-1"])
			assert.is_true(Pins.IsPinned(domain, "pet-1", 2000 + 365 * 86400))
		end)

		it("does not auto-pin when the domain disables it", function()
			local domain = Domain({ autoNew = false })
			Pins.RecordAcquired(domain, "pet-1", 1000)
			assert.same({ acquiredAt = 1000 }, domain.records["pet-1"])
			assert.is_false(Pins.IsPinned(domain, "pet-1", 1001))
		end)

		it("does not auto-pin an acquisition the user suppressed", function()
			local domain = Domain({ records = { ["pet-1"] = { acquiredAt = 100, suppressed = true } } })
			assert.is_false(Pins.RecordAcquired(domain, "pet-1", 2000))
			assert.same({ acquiredAt = 100, suppressed = true }, domain.records["pet-1"])
		end)

		it("keeps each pin's acquisition-time expiration", function()
			local domain = Domain({ days = 14 })
			Pins.RecordAcquired(domain, "pet-1", 1000)
			local sevenDaysLater = 1000 + 7 * 86400
			assert.is_true(Pins.IsPinned(domain, "pet-1", sevenDaysLater))
			domain.days = 6
			assert.is_true(Pins.IsPinned(domain, "pet-1", sevenDaysLater))
			domain.days = 8
			assert.is_true(Pins.IsPinned(domain, "pet-1", sevenDaysLater))
		end)

		it("rejects non-number acquiredAt and never invents one", function()
			local domain = Domain()
			assert.is_false(Pins.RecordAcquired(domain, "pet-1", nil))
			assert.is_nil(domain.records["pet-1"])
		end)

		it("days = 0 pins permanently with no expiration field", function()
			local domain = Domain({ days = 0 })
			Pins.RecordAcquired(domain, "pet-1", 1000)
			assert.same({ acquiredAt = 1000, permanent = true }, domain.records["pet-1"])
			assert.is_true(Pins.IsPinned(domain, "pet-1", 9999999))
		end)
	end)

	describe("Pin and Keep", function()
		it("pins manually using the domain's current default days", function()
			local domain = Domain({ days = 6 })
			Pins.Pin(domain, "pet-1", 1000)
			assert.equal(1000 + 6 * 86400, domain.records["pet-1"].expiresAt)
			assert.is_true(Pins.IsPinned(domain, "pet-1", 1001))
		end)

		it("clears suppression when repinning without inventing legacy state", function()
			local domain = Domain({ records = { ["pet-1"] = { acquiredAt = 100, suppressed = true } } })
			Pins.Pin(domain, "pet-1", 1000)
			assert.is_nil(domain.records["pet-1"].suppressed)
			assert.is_true(Pins.IsPinned(domain, "pet-1", 1001))
		end)

		it("repins an automatic pin via Keep using a supplied clock", function()
			local domain = Domain()
			Pins.RecordAcquired(domain, "pet-1", 1000)
			local now = 9000000
			Pins.Keep(domain, "pet-1", now)
			assert.is_true(Pins.IsPinned(domain, "pet-1", now + 1))
			assert.is_true(Pins.IsPinned(domain, "pet-1", now + 7 * 86400 - 1))
			assert.is_false(Pins.IsPinned(domain, "pet-1", now + 7 * 86400))
		end)
	end)

	describe("Unpin", function()
		it("unpins and suppresses the same acquisition", function()
			local domain = Domain()
			Pins.RecordAcquired(domain, "pet-1", 1000)
			Pins.Unpin(domain, "pet-1")
			assert.is_false(Pins.IsPinned(domain, "pet-1", 1001))
			assert.is_false(Pins.RecordAcquired(domain, "pet-1", 2000))
		end)

		it("clears pin state but keeps the acquisition stamp", function()
			local domain = Domain({ records = { ["pet-1"] = { acquiredAt = 100, permanent = true, note = "x" } } })
			Pins.Unpin(domain, "pet-1")
			assert.same({ acquiredAt = 100, suppressed = true, note = "x" }, domain.records["pet-1"])
		end)
	end)

	describe("SetDaysRemaining", function()
		it("edits remaining days without losing acquisition history", function()
			local domain = Domain({ records = { ["pet-1"] = { acquiredAt = 500, expiresAt = 900 } } })
			assert.is_true(Pins.SetDaysRemaining(domain, "pet-1", 3, 800))
			assert.same({ acquiredAt = 500, expiresAt = 800 + 3 * 86400 }, domain.records["pet-1"])
			assert.is_true(Pins.SetDaysRemaining(domain, "pet-1", 0, 2000))
			assert.same({ acquiredAt = 500, permanent = true }, domain.records["pet-1"])
		end)

		it("refuses non-integer or negative days and unpinned IDs", function()
			local domain = Domain({ records = { ["pet-1"] = { acquiredAt = 500, expiresAt = 900 } } })
			assert.is_false(Pins.SetDaysRemaining(domain, "pet-1", -1, 800))
			assert.is_false(Pins.SetDaysRemaining(domain, "pet-1", 1.5, 800))
			assert.is_false(Pins.SetDaysRemaining(domain, "pet-2", 3, 800))
			assert.is_false(Pins.SetDaysRemaining(domain, "pet-1", 3, 900))
		end)
	end)

	describe("DaysRemaining", function()
		it("counts whole days left while pinned, nil once expired", function()
			local domain = Domain({ records = { ["pet-1"] = { acquiredAt = 100, expiresAt = 100 + 86400 } } })
			assert.equal(1, Pins.DaysRemaining(domain, "pet-1", 100))
			assert.equal(1, Pins.DaysRemaining(domain, "pet-1", 100 + 12 * 3600))
			assert.is_nil(Pins.DaysRemaining(domain, "pet-1", 100 + 86400))
			assert.is_nil(Pins.DaysRemaining(domain, "pet-1", 100 + 86401))
		end)

		it("reports 0 for permanent pins", function()
			local domain = Domain({ records = { ["pet-1"] = { permanent = true } } })
			assert.equal(0, Pins.DaysRemaining(domain, "pet-1", 500))
		end)
	end)

	describe("expiry boundaries", function()
		it("expires exactly at expiresAt: pinned strictly before, not at or after", function()
			local domain = Domain({ days = 1 })
			Pins.RecordAcquired(domain, "pet-1", 1000)
			local edge = 1000 + 86400
			assert.is_true(Pins.IsPinned(domain, "pet-1", edge - 1))
			assert.is_false(Pins.IsPinned(domain, "pet-1", edge))
			assert.is_false(Pins.IsPinned(domain, "pet-1", edge + 1))
			assert.is_nil(Pins.ActiveSet(domain, edge)["pet-1"])
		end)

		it("pins only the acquired copy's expiration, not later settings", function()
			local domain = Domain({ days = 14 })
			Pins.RecordAcquired(domain, "pet-1", 1000)
			local sevenDaysLater = 1000 + 7 * 86400
			domain.days = 6
			assert.is_true(Pins.IsPinned(domain, "pet-1", sevenDaysLater))
			domain.days = 8
			assert.is_true(Pins.IsPinned(domain, "pet-1", sevenDaysLater))
		end)
	end)

	describe("ActiveSet", function()
		it("returns IDs of currently pinned records only", function()
			local domain = Domain({ days = 1, records = {
				["pet-1"] = { acquiredAt = 100, expiresAt = 100 + 86400 },
				["pet-2"] = { permanent = true },
				["pet-3"] = { acquiredAt = 100, suppressed = true },
			} })
			local set = Pins.ActiveSet(domain, 100 + 86401)
			assert.same({ ["pet-2"] = true }, set)
		end)

		it("returns an empty table for an empty domain", function()
			assert.same({}, Pins.ActiveSet(Domain(), 1000))
		end)
	end)

	describe("Recent", function()
		it("lists acquisitions newest first, then by injected ID order", function()
			local domain = Domain({ days = 1, records = {
				["pet-1"] = { acquiredAt = 100, suppressed = true },
				["pet-2"] = { acquiredAt = 300, permanent = true },
				["pet-3"] = { acquiredAt = 200, expiresAt = 200 + 86400 },
			} })
			local rows = Pins.Recent(domain, 400, Ascending)
			assert.same({ "pet-2", "pet-3", "pet-1" },
				{ rows[1].id, rows[2].id, rows[3].id })
		end)

		it("keeps an expired acquisition distinguishable from an unpinned one", function()
			local domain = Domain({ days = 1, records = {
				["pet-1"] = { acquiredAt = 100, expiresAt = 100 + 86400 },
				["pet-2"] = { acquiredAt = 90, suppressed = true },
			} })
			local rows = Pins.Recent(domain, 100 + 86401, Ascending)
			assert.same({ "expired", "unpinned" }, { rows[1].status, rows[2].status })
		end)

		it("preserves exact string GUID keys in id output", function()
			local guid = "Pet-0xC0FFEE-0002" -- case and punctuation must survive
			local domain = Domain({ records = { [guid] = { acquiredAt = 100, permanent = true } } })
			local rows = Pins.Recent(domain, 200, Ascending)
			assert.equal(1, #rows)
			assert.equal(guid, rows[1].id)
			assert.equal("manual", rows[1].status)
		end)

		it("sorts equal-time IDs by the injected order, byte-wise for GUIDs", function()
			local domain = Domain({ records = {
				["pet-b"] = { acquiredAt = 100 },
				["pet-B"] = { acquiredAt = 100 },
				["pet-a"] = { acquiredAt = 100 },
			} })
			local rows = Pins.Recent(domain, 200, Ascending)
			assert.same({ "pet-B", "pet-a", "pet-b" },
				{ rows[1].id, rows[2].id, rows[3].id })
		end)

		it("skips records without an acquisition stamp", function()
			local domain = Domain({ records = { ["pet-1"] = { permanent = true } } })
			assert.same({}, Pins.Recent(domain, 200, Ascending))
		end)
	end)

	describe("history preservation", function()
		it("keeps unknown record fields through every operation", function()
			local domain = Domain({ days = 14, records = { ["pet-1"] = { acquiredAt = 500, label = "favourite" } } })
			Pins.SetDaysRemaining(domain, "pet-1", 3, 800)
			assert.equal("favourite", domain.records["pet-1"].label)
			Pins.Unpin(domain, "pet-1")
			assert.equal("favourite", domain.records["pet-1"].label)
			Pins.Pin(domain, "pet-1", 2000)
			assert.equal("favourite", domain.records["pet-1"].label)
		end)

		it("carries no legacy manual field into generic fixtures", function()
			local domain = Domain({ days = 1, records = {
				["pet-1"] = { acquiredAt = 100, permanent = true },
				["pet-2"] = { acquiredAt = 100, expiresAt = 100 + 86400 },
			} })
			local set = Pins.ActiveSet(domain, 100 + 86401)
			assert.same({ ["pet-1"] = true }, set)
			assert.is_nil(domain.records["pet-1"].manual)
		end)
		it("tracks numeric IDs through the same lifecycle", function()
			local domain = Domain({ days = 14 })
			assert.is_true(Pins.RecordAcquired(domain, 42, 1000))
			assert.equal(1000 + 14 * 86400, domain.records[42].expiresAt)
			assert.is_true(Pins.IsPinned(domain, 42, 1001))
			Pins.Unpin(domain, 42)
			assert.is_false(Pins.IsPinned(domain, 42, 1001))
		end)

		it("preserves exact string GUID keys through every operation", function()
			local guid = "Pet-0xC0FFEE-0002" -- case and punctuation must survive
			local domain = Domain({ days = 1 })
			assert.is_true(Pins.RecordAcquired(domain, guid, 1000))
			assert.is_not_nil(domain.records[guid])
			assert.is_nil(domain.records[string.lower(guid)])
			assert.is_true(Pins.IsPinned(domain, guid, 1001))
			local rows = Pins.Recent(domain, 1001, Ascending)
			assert.equal(1, #rows)
			assert.equal(guid, rows[1].id)
		end)
	end)
end)
