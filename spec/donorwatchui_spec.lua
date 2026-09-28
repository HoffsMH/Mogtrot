-- Passive pickup runs from login, takes every player whose body is new, and
-- builds the donors it queued one after another, a few steps a frame.
describe("DonorWatchUI", function()
	local DonorWatchUI, frames, units, now, clock, calls, ns, full

	local function FakeFrame()
		local frame = { events = {} }
		function frame:RegisterEvent(event) self.events[event] = true end
		function frame:UnregisterEvent(event) self.events[event] = nil end
		function frame:SetScript(name, fn) self[name] = fn end
		return frame
	end

	local function Fire(event, ...)
		for _, frame in ipairs(frames) do
			if frame.events[event] and frame.OnEvent then frame.OnEvent(frame, event, ...) end
		end
	end

	-- One frame of the builder, 1/60 s later.
	local function Frame()
		now = now + 1 / 60
		for _, frame in ipairs(frames) do
			if frame.OnUpdate then frame.OnUpdate(frame, 1 / 60) end
		end
	end

	local function Player(guid, raceID, sex, faction)
		return { guid = guid, raceID = raceID, raceFile = "R" .. raceID, sex = sex or 3,
			faction = faction or "Horde" }
	end

	local function Log(kind, detail)
		calls[#calls + 1] = kind .. ":" .. tostring(detail)
	end

	local function Of(kind)
		local out = {}
		for _, call in ipairs(calls) do
			local k, detail = call:match("^(%a+):(.*)$")
			if k == kind then out[#out + 1] = detail end
		end
		return out
	end

	before_each(function()
		frames, units, now, clock, calls, full = {}, {}, 100, 0, {}, false
		units.player = Player("ME", 52, 2, "Alliance")
		_G.CreateFrame = function()
			local frame = FakeFrame()
			frames[#frames + 1] = frame
			return frame
		end
		_G.C_Timer = { NewTicker = function() return {} end, After = function() end }
		_G.GetTime = function() return now end
		_G.debugprofilestop = function() return clock end
		_G.InCombatLockdown = function() return false end
		_G.IsInInstance = function() return false end
		_G.UnitExists = function(unit) return units[unit] ~= nil end
		_G.UnitIsPlayer = function(unit) return units[unit] ~= nil end
		_G.UnitIsUnit = function(a, b) return units[a] ~= nil and units[a] == units[b] end
		_G.UnitSex = function(unit) return units[unit] and units[unit].sex end
		_G.UnitRace = function(unit)
			local who = units[unit]
			if not who then return nil end
			return who.raceFile, who.raceFile, who.raceID
		end
		_G.UnitFactionGroup = function(unit) return units[unit] and units[unit].faction end
		_G.UnitGUID = function(unit) return units[unit] and units[unit].guid end
		_G.IsUnitModelReadyForUI = function() return true end

		ns = { DonorWatch = assert(loadfile("DonorWatch.lua"))("Mogtrot", {}) }
		ns.LibraryBodies = {
			DonorFacts = function(unit)
				local who = units[unit]
				return { guid = who.guid, sex = who.sex, raceID = who.raceID,
					raceFile = who.raceFile, faction = who.faction }
			end,
			WarmBody = function(record, token, _, guid)
				clock = clock + 5
				Log("warm", guid .. "|" .. record.id .. "|" .. token)
				return true, "key" .. record.id
			end,
			SettleDonor = function(guid) Log("settle", guid) end,
			DropDonor = function(guid) Log("drop", guid) end,
			PoolFull = function() return full end,
		}
		ns.LibraryUI = {
			WarmPlan = function()
				return { { record = { id = 1 }, want = 1 }, { record = { id = 2 }, want = 1 } }
			end,
			BodiesArrived = function(_, donor) Log("arrived", donor.guid) end,
		}
		DonorWatchUI = assert(loadfile("DonorWatchUI.lua"))("Mogtrot", ns)
	end)

	after_each(function()
		for _, name in ipairs({ "CreateFrame", "C_Timer", "GetTime", "debugprofilestop",
			"InCombatLockdown", "IsInInstance", "UnitExists", "UnitIsPlayer", "UnitIsUnit",
			"UnitSex", "UnitRace", "UnitFactionGroup", "UnitGUID", "IsUnitModelReadyForUI" }) do
			_G[name] = nil
		end
	end)

	local function Settle(frames_)
		for _ = 1, frames_ or 600 do Frame() end
	end

	it("listens for players from login, with the library never opened", function()
		Fire("PLAYER_ENTERING_WORLD")
		local listening = false
		for _, frame in ipairs(frames) do
			if frame.events.UPDATE_MOUSEOVER_UNIT then listening = true end
		end
		assert.is_true(listening)
	end)

	it("takes several players seen in a row and builds them in the order seen", function()
		units.nameplate1 = Player("A", 10)
		units.nameplate2 = Player("B", 2)
		units.nameplate3 = Player("C", 4, 3, "Alliance")
		for index = 1, 3 do Fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. index) end
		Settle()
		assert.same({ "A", "B", "C" }, Of("settle"))
		assert.same({ "A|1|nameplate1", "A|2|nameplate1", "B|1|nameplate2",
			"B|2|nameplate2", "C|1|nameplate3", "C|2|nameplate3" }, Of("warm"))
		assert.same({ "A", "B", "C" }, Of("arrived"))
	end)

	it("skips a second player whose race, sex and faction are already taken", function()
		units.nameplate1 = Player("A", 10)
		units.nameplate2 = Player("A2", 10)
		Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
		Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
		Settle()
		assert.same({ "A" }, Of("settle"))
	end)

	it("takes nobody of your own sex", function()
		units.nameplate1 = Player("M", 10, 2)
		Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
		Settle()
		assert.same({}, Of("warm"))
	end)

	it("drops a queued donor who leaves reach, and builds the rest", function()
		units.mouseover = Player("B", 2)
		Fire("UPDATE_MOUSEOVER_UNIT")
		units.mouseover = nil
		units.nameplate1 = Player("A", 10)
		Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
		Settle()
		assert.same({ "A" }, Of("settle"))
		assert.same({ "B" }, Of("drop"))
		-- Dropped cleanly: the same player can be taken when seen again.
		units.mouseover = Player("B", 2)
		Fire("UPDATE_MOUSEOVER_UNIT")
		Settle()
		assert.same({ "A", "B" }, Of("settle"))
	end)

	it("takes nobody while the body pool is full", function()
		full = true
		units.nameplate1 = Player("A", 10)
		Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
		Settle()
		assert.same({}, Of("warm"))
	end)

	-- The draw checks and their wake-up call are gone: nothing waits on them.
	it("has no background draw checks", function()
		assert.is_nil(DonorWatchUI.Wake)
		assert.is_nil(DonorWatchUI.Offered)
		assert.is_nil(DonorWatchUI.Covering)
	end)
end)
