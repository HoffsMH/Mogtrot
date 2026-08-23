local MountPins = require("MountPins")

describe("MountPins", function()
	it("stores an expiration when a mount is acquired", function()
		local account = { autoPinNewMountDays = 14 }
		MountPins.RecordAcquired(account, 42, 1000)
		assert.equal(1000 + 14 * 86400, account.mountPins[42].expiresAt)
	end)

	it("pins manually using the current default expiration", function()
		local account = { autoPinNewMountDays = 6 }
		MountPins.Pin(account, 42, 1000)
		assert.equal(1000 + 6 * 86400, account.mountPins[42].expiresAt)
		assert.is_true(MountPins.IsPinned(account, 42, 1001))
	end)

	it("edits remaining days without losing acquisition history", function()
		local account = { mountPins = { [42] = { acquiredAt = 500, expiresAt = 900 } } }
		MountPins.SetDaysRemaining(account, 42, 3, 800)
		assert.same({ acquiredAt = 500, expiresAt = 800 + 3 * 86400 },
			account.mountPins[42])
		MountPins.SetDaysRemaining(account, 42, 0, 2000)
		assert.same({ acquiredAt = 500, permanent = true }, account.mountPins[42])
	end)
	it("records a new acquisition once", function()
		local account = {}
		assert.is_true(MountPins.RecordAcquired(account, 42, 1000))
		assert.equal(1000, account.mountPins[42].acquiredAt)
		assert.equal(1000 + 7 * 86400, account.mountPins[42].expiresAt)
		assert.is_true(MountPins.IsPinned(account, 42, 1001))
		assert.is_false(MountPins.RecordAcquired(account, 42, 2000))
		assert.equal(1000, account.mountPins[42].acquiredAt)
	end)

	it("does not auto-pin when the setting is disabled", function()
		local account = { autoPinNewMounts = false }
		MountPins.RecordAcquired(account, 42, 1000)
		assert.same({ acquiredAt = 1000 }, account.mountPins[42])
		assert.is_false(MountPins.IsPinned(account, 42, 1001))
	end)

	it("keeps each pin's acquisition-time expiration", function()
		local account = { autoPinNewMountDays = 14 }
		MountPins.RecordAcquired(account, 42, 1000)
		local sevenDaysLater = 1000 + 7 * 86400
		assert.is_true(MountPins.IsPinned(account, 42, sevenDaysLater))
		account.autoPinNewMountDays = 6
		assert.is_true(MountPins.IsPinned(account, 42, sevenDaysLater))
		account.autoPinNewMountDays = 8
		assert.is_true(MountPins.IsPinned(account, 42, sevenDaysLater))
	end)

	it("unpins and suppresses the same acquisition", function()
		local account = {}
		MountPins.RecordAcquired(account, 42, 1000)
		MountPins.Unpin(account, 42)
		assert.is_false(MountPins.IsPinned(account, 42, 1001))
		assert.is_false(MountPins.RecordAcquired(account, 42, 2000))
	end)

	it("repins an automatic pin using the current default", function()
		local account = {}
		MountPins.RecordAcquired(account, 42, 1000)
		MountPins.Keep(account, 42)
		assert.is_true(MountPins.IsPinned(account, 42, 9999999))
	end)

	it("expires only automatic pins", function()
		local account = { autoPinNewMountDays = 1, mountPins = {
			[1] = { acquiredAt = 100, expiresAt = 100 + 86400 },
			[2] = { acquiredAt = 100, manual = true },
		} }
		assert.same({ [2] = true }, MountPins.ActiveSet(account, 100 + 86401))
		assert.is_true(account.mountPins[2].manual)
	end)

	it("keeps an expired acquisition distinguishable from an unpinned one", function()
		local account = { autoPinNewMountDays = 1, mountPins = {
			[1] = { acquiredAt = 100, expiresAt = 100 + 86400 },
			[2] = { acquiredAt = 90, suppressed = true },
		} }
		local rows = MountPins.Recent(account, 100 + 86401)
		assert.same({ "expired", "unpinned" }, { rows[1].status, rows[2].status })
	end)

	it("lists acquisitions newest first including unpinned mounts", function()
		local account = { autoPinNewMountDays = 1, mountPins = {
			[1] = { acquiredAt = 100, suppressed = true },
			[2] = { acquiredAt = 300, manual = true },
			[3] = { acquiredAt = 200, expiresAt = 200 + 86400 },
		} }
		local rows = MountPins.Recent(account, 400)
		assert.same({ 2, 3, 1 }, { rows[1].mountID, rows[2].mountID, rows[3].mountID })
		assert.same({ "manual", "automatic", "unpinned" },
			{ rows[1].status, rows[2].status, rows[3].status })
	end)
end)
