local Wear = require("OutfitWearTime")

-- The two clocks are always passed explicitly, so every interval below is exact.
-- now is monotonic session time; stamp is the epoch value that outlives a session.
local function NewSession(store)
	return Wear.NewSession(store)
end

describe("Wear.ShowInList", function()
	it("defaults off and requires an explicit opt-in", function()
		assert.is_false(Wear.ShowInList(nil))
		assert.is_false(Wear.ShowInList({}))
		assert.is_false(Wear.ShowInList({ showWearInList = false }))
		assert.is_true(Wear.ShowInList({ showWearInList = true }))
	end)

	it("persists through the shared setting table", function()
		local settings = {}
		Wear.SetShowInList(settings, true)
		assert.is_true(Wear.ShowInList(settings))
		Wear.SetShowInList(settings, false)
		assert.is_false(Wear.ShowInList(settings))
	end)
end)

describe("Wear.Close", function()
	it("does nothing when no interval is open", function()
		local session = NewSession()
		assert.equal(0, Wear.Close(session, 100, 1000))
		assert.same({}, session.store)
	end)

	it("accrues the open interval and forgets it", function()
		local session = NewSession()
		Wear.Switch(session, 7, 100, 1000)

		assert.equal(60, Wear.Close(session, 160, 1060))
		assert.equal(60, session.store[7].seconds)
		assert.is_nil(session.id)
		assert.is_nil(session.since)
	end)

	it("adds to what an outfit already had", function()
		local session = NewSession({ [7] = { seconds = 90 } })
		Wear.Switch(session, 7, 100, 1000)
		Wear.Close(session, 110, 1010)

		assert.equal(100, session.store[7].seconds)
	end)

	it("stamps last with when the outfit came off, not when it went on", function()
		local session = NewSession()
		Wear.Switch(session, 7, 100, 1000)
		Wear.Close(session, 160, 1060)

		assert.equal(1060, session.store[7].last)
	end)

	it("writes no record for an interval that measured nothing", function()
		local session = NewSession()
		Wear.Switch(session, 7, 100, 1000)

		assert.equal(0, Wear.Close(session, 100, 1000))
		assert.is_nil(session.store[7])
	end)

	it("treats a clock that went backwards as no time at all", function()
		local session = NewSession()
		Wear.Switch(session, 7, 100, 1000)

		assert.equal(0, Wear.Close(session, 40, 940))
		assert.is_nil(session.store[7])
	end)

	-- Closing twice is the shape of logout arriving after the addon already closed.
	it("is safe to call twice", function()
		local session = NewSession()
		Wear.Switch(session, 7, 100, 1000)
		Wear.Close(session, 160, 1060)
		Wear.Close(session, 300, 1200)

		assert.equal(60, session.store[7].seconds)
	end)
end)

describe("Wear.Switch", function()
	it("opens an interval when nothing was open", function()
		local session = NewSession()
		assert.equal(0, Wear.Switch(session, 7, 100, 1000))
		assert.equal(7, session.id)
		assert.equal(100, session.since)
	end)

	it("closes the old outfit before opening the new one", function()
		local session = NewSession()
		Wear.Switch(session, 7, 100, 1000)
		Wear.Switch(session, 8, 160, 1060)

		assert.equal(60, session.store[7].seconds)
		assert.equal(8, session.id)
		assert.equal(160, session.since)
	end)

	-- The login timer calls this a second time, and the outfit-changed event fires
	-- for edits that do not change which outfit is on. Either restarting the
	-- interval would silently discard everything it had earned.
	it("leaves the interval alone when the same outfit is already open", function()
		local session = NewSession()
		Wear.Switch(session, 7, 100, 1000)
		Wear.Switch(session, 7, 160, 1060)

		assert.equal(100, session.since)
		assert.is_nil(session.store[7])
		assert.equal(60, Wear.Total(session, 7, 160))
	end)

	it("closes without opening when there is no active outfit", function()
		local session = NewSession()
		Wear.Switch(session, 7, 100, 1000)
		Wear.Switch(session, nil, 160, 1060)

		assert.equal(60, session.store[7].seconds)
		assert.is_nil(session.id)
	end)

	it("opens nothing when there was nothing open and nothing to open", function()
		local session = NewSession()
		Wear.Switch(session, nil, 100, 1000)

		assert.is_nil(session.id)
		assert.same({}, session.store)
	end)
end)

describe("Wear.Total", function()
	it("is zero for an outfit with no record", function()
		assert.equal(0, Wear.Total(NewSession(), 7, 100))
	end)

	it("reads stored seconds for an outfit that is not on", function()
		local session = NewSession({ [7] = { seconds = 90 } })
		assert.equal(90, Wear.Total(session, 7, 100))
	end)

	-- The bar has to grow while the outfit is on rather than jumping when it comes
	-- off, so the open interval counts before it is stored.
	it("adds the open interval for the outfit that is on", function()
		local session = NewSession({ [7] = { seconds = 90 } })
		Wear.Switch(session, 7, 100, 1000)

		assert.equal(150, Wear.Total(session, 7, 160))
	end)

	it("does not add the open interval to any other outfit", function()
		local session = NewSession({ [8] = { seconds = 90 } })
		Wear.Switch(session, 7, 100, 1000)

		assert.equal(90, Wear.Total(session, 8, 160))
	end)

	-- A total that can go down is worse than one that stands still: the bar would
	-- shrink while the outfit is still on.
	it("does not subtract when the clock reads earlier than the interval start", function()
		local session = NewSession({ [7] = { seconds = 90 } })
		Wear.Switch(session, 7, 100, 1000)

		assert.equal(90, Wear.Total(session, 7, 40))
	end)
end)

describe("Wear.Snapshot", function()
	it("is empty for a session with nothing recorded", function()
		local snapshot = Wear.Snapshot(NewSession(), 100)

		assert.same({}, snapshot.totals)
		assert.equal(0, snapshot.max)
		assert.equal(0, snapshot.sum)
		assert.equal(0, snapshot.count)
	end)

	it("totals, maxes and counts what is stored", function()
		local session = NewSession({ [7] = { seconds = 90 }, [8] = { seconds = 30 } })
		local snapshot = Wear.Snapshot(session, 100)

		assert.same({ [7] = 90, [8] = 30 }, snapshot.totals)
		assert.equal(90, snapshot.max)
		assert.equal(120, snapshot.sum)
		assert.equal(2, snapshot.count)
	end)

	it("includes the open interval, and the outfit worn for the first time", function()
		local session = NewSession({ [8] = { seconds = 30 } })
		Wear.Switch(session, 7, 100, 1000)
		local snapshot = Wear.Snapshot(session, 160)

		assert.same({ [7] = 60, [8] = 30 }, snapshot.totals)
		assert.equal(60, snapshot.max)
		assert.equal(2, snapshot.count)
	end)

	it("leaves out an outfit with a zero record", function()
		local session = NewSession({ [7] = { seconds = 0 }, [8] = { seconds = 30 } })
		local snapshot = Wear.Snapshot(session, 100)

		assert.same({ [8] = 30 }, snapshot.totals)
		assert.equal(1, snapshot.count)
	end)

	-- Nothing here deletes. A deleted outfit's hours would otherwise set max
	-- forever and flatten every bar that is still real, so they are filtered out
	-- of the arithmetic and left on disk.
	it("counts only the outfits it is told still exist", function()
		local session = NewSession({ [7] = { seconds = 90 }, [8] = { seconds = 30 } })
		local snapshot = Wear.Snapshot(session, 100, { [8] = true })

		assert.same({ [8] = 30 }, snapshot.totals)
		assert.equal(30, snapshot.max)
		assert.equal(30, snapshot.sum)
		assert.equal(1, snapshot.count)
	end)

	it("does not remove the record it left out", function()
		local session = NewSession({ [7] = { seconds = 90 }, [8] = { seconds = 30 } })
		Wear.Snapshot(session, 100, { [8] = true })

		assert.equal(90, session.store[7].seconds)
	end)

	it("counts everything when it is told nothing about what exists", function()
		local session = NewSession({ [7] = { seconds = 90 }, [8] = { seconds = 30 } })
		assert.equal(2, Wear.Snapshot(session, 100, nil).count)
	end)
end)

describe("Wear.Heat", function()
	it("is zero for no time, and for no busiest outfit to measure against", function()
		assert.equal(0, Wear.Heat(100, 0))
		assert.equal(0, Wear.Heat(0, 100))
	end)

	it("is full for the busiest outfit", function()
		assert.equal(1, Wear.Heat(100, 100))
	end)

	it("never exceeds full, even if the total ran past max", function()
		assert.equal(1, Wear.Heat(100, 400))
	end)

	it("floors a real but tiny total, so worn once differs from never worn", function()
		assert.equal(Wear.MIN_HEAT, Wear.Heat(1000000, 1))
	end)

	-- The point of the curve. One dominant outfit is the normal case, and a
	-- straight fraction would put everything else within a few percent of the
	-- floor, where no bar is distinguishable from any other.
	it("separates the middle of the distribution instead of collapsing it", function()
		local max = 10000
		local quarter = Wear.Heat(max, max / 4)
		local half = Wear.Heat(max, max / 2)

		assert.equal(0.5, quarter)
		assert.is_true(half > 0.7)
		assert.is_true(half - quarter > 0.2)
	end)

	it("keeps small values clear of the floor where a fraction would not", function()
		local max = 10000
		-- A twentieth of the busiest outfit reads as a fraction of a bar, not as
		-- the minimum.
		assert.is_true(Wear.Heat(max, max / 20) > 3 * Wear.MIN_HEAT)
	end)

	it("never reorders: more time is always at least as much heat", function()
		local previous = -1
		for _, seconds in ipairs({ 1, 10, 100, 1000, 5000, 9999, 10000 }) do
			local heat = Wear.Heat(10000, seconds)
			assert.is_true(heat >= previous)
			previous = heat
		end
	end)
end)

describe("Wear.Share", function()
	it("is zero with nothing tracked", function()
		assert.equal(0, Wear.Share(0, 10))
		assert.equal(0, Wear.Share(100, 0))
	end)

	it("is the fraction of everything tracked", function()
		assert.equal(0.25, Wear.Share(400, 100))
	end)

	-- One outfit is all of it. Nothing should ever print 130%.
	it("never reads as more than everything", function()
		assert.equal(1, Wear.Share(100, 130))
	end)
end)

describe("Wear.Format", function()
	it("reads seconds under a minute", function()
		assert.equal("0s", Wear.Format(0))
		assert.equal("42s", Wear.Format(42))
	end)

	it("drops seconds once there are minutes", function()
		assert.equal("1m", Wear.Format(60))
		assert.equal("18m", Wear.Format(18 * 60 + 42))
	end)

	it("reads hours and minutes, and drops a zero minute", function()
		assert.equal("1h", Wear.Format(3600))
		assert.equal("4h 12m", Wear.Format(4 * 3600 + 12 * 60 + 30))
	end)

	it("reads days and hours, and never a third unit", function()
		assert.equal("2d", Wear.Format(2 * 86400))
		assert.equal("3d 4h", Wear.Format(3 * 86400 + 4 * 3600 + 59 * 60))
	end)

	it("treats nothing, and a negative, as no time", function()
		assert.equal("0s", Wear.Format(nil))
		assert.equal("0s", Wear.Format(-100))
	end)
end)

describe("Wear.Top", function()
	it("returns nothing for an empty snapshot", function()
		assert.same({}, Wear.Top(Wear.Snapshot(NewSession(), 100)))
	end)

	it("ranks by time, longest first", function()
		local session = NewSession({
			[7] = { seconds = 30 }, [8] = { seconds = 90 }, [9] = { seconds = 60 },
		})
		local top = Wear.Top(Wear.Snapshot(session, 100))

		assert.same({ 8, 9, 7 }, { top[1].outfitID, top[2].outfitID, top[3].outfitID })
		assert.equal(90, top[1].seconds)
	end)

	-- pairs does not hand these back in id order on either 5.1 or LuaJIT, so an
	-- unbroken tie would print differently twice.
	it("breaks a tie on the id, so the list is stable", function()
		local session = NewSession({
			[12] = { seconds = 60 }, [5] = { seconds = 60 }, [9] = { seconds = 60 },
		})
		local top = Wear.Top(Wear.Snapshot(session, 100))

		assert.same({ 5, 9, 12 }, { top[1].outfitID, top[2].outfitID, top[3].outfitID })
	end)

	it("cuts the list to the limit", function()
		local session = NewSession({
			[7] = { seconds = 30 }, [8] = { seconds = 90 }, [9] = { seconds = 60 },
		})
		local top = Wear.Top(Wear.Snapshot(session, 100), 2)

		assert.equal(2, #top)
		assert.equal(8, top[1].outfitID)
	end)
end)

-- The whole point of holding the open interval in memory: a session that is never
-- closed loses only that interval, and nothing on disk can be read as time that
-- passed while logged out.
describe("a session boundary", function()
	it("carries over stored seconds and no start", function()
		local store = {}
		local first = NewSession(store)
		Wear.Switch(first, 7, 100, 1000)
		Wear.Close(first, 3700, 4600)

		-- Days pass. The next session starts from a fresh clock.
		local second = NewSession(store)
		assert.equal(3600, Wear.Total(second, 7, 5))
		assert.is_nil(second.id)
		assert.is_nil(second.since)
	end)

	it("loses only the open interval when a session never closes", function()
		local store = {}
		local first = NewSession(store)
		Wear.Switch(first, 7, 100, 1000)
		Wear.Close(first, 200, 1100)
		Wear.Switch(first, 7, 200, 1100)
		-- The client crashes here: no close, and nothing about the open interval
		-- was ever written.
		assert.equal(100, store[7].seconds)

		local second = NewSession(store)
		assert.equal(100, Wear.Total(second, 7, 5))
	end)
end)
