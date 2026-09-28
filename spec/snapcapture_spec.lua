describe("SnapCapture inspect ownership", function()
	local names = {
		"AuraUtil", "C_Map", "C_MountJournal", "C_PaperDollInfo", "C_PlayerInfo",
		"C_Secrets", "C_Timer", "C_TransmogCollection", "ClearInspectPlayer",
		"C_SpecializationInfo", "CreateFrame", "GetBuildInfo", "GetSubZoneText",
		"GetZoneText", "InCombatLockdown", "IsUnitModelReadyForUI", "MogtrotDB",
		"NotifyInspect", "UnitClass",
		"UnitExists", "UnitFactionGroup", "UnitGUID", "UnitIsPlayer", "UnitLevel",
		"UnitName", "UnitPVPName", "UnitRace", "UnitSex", "issecretvalue", "time",
	}
	local saved

	before_each(function()
		saved = {}
		for _, name in ipairs(names) do saved[name] = _G[name] end
	end)

	after_each(function()
		for _, name in ipairs(names) do _G[name] = saved[name] end
	end)

	local function Load()
		local scripts, timers, notices = {}, {}, {}
		local reads, saves, clears, unregisters = 0, 0, 0, 0
		local targetGUID = "Player-target"
		local existing

		_G.CreateFrame = function()
			return {
				RegisterEvent = function() end,
				UnregisterAllEvents = function() unregisters = unregisters + 1 end,
				SetScript = function(_, kind, fn) scripts[kind] = fn end,
			}
		end
		_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
		_G.C_TransmogCollection = {
			GetInspectItemTransmogInfoList = function()
				reads = reads + 1
				return { [16] = { appearanceID = 304340 } }
			end,
		}
		_G.ClearInspectPlayer = function() clears = clears + 1 end
		_G.NotifyInspect = function() end
		_G.InCombatLockdown = function() return false end
		_G.IsUnitModelReadyForUI = function() return true end
		_G.UnitExists = function(unit) return unit == "target" end
		_G.UnitIsPlayer = function() return true end
		_G.UnitGUID = function(unit)
			if unit == "player" then return "Player-self" end
			return targetGUID
		end
		_G.UnitName = function() return "Target", "Aegwynn" end
		_G.UnitRace = function() return "Tauren", "Tauren", 6 end
		_G.UnitSex = function() return 2 end
		_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
		_G.UnitLevel = function() return 90 end
		_G.UnitFactionGroup = function() return "Horde" end
		_G.C_SpecializationInfo = { GetInspectSpecialization = function() return 72 end }
		_G.GetZoneText = function() return "Silvermoon City" end
		_G.GetSubZoneText = function() return "The Bazaar" end
		_G.GetBuildInfo = function() return "12.1.0", "", "", 120100 end
		_G.time = function() return 100 end
		_G.MogtrotDB = { library = { records = {} } }

		local ns = {
			InspectLook = {
				FromTransmogList = function(list)
					return { [16] = { list[16].appearanceID, 0, 0 } }, 1
				end,
			},
			Library = {
				Snap = function(facts) return facts end,
				Writable = function() return true end,
				Find = function() return existing end,
				Add = function()
					saves = saves + 1
					if existing then return existing, false end
					return 1, true
				end,
			},
		}
		local confirmed, hidden, warmed = {}, {}, {}
		local uiFails = false
		ns.LibraryUI = {
			Refresh = function() end,
		}
		ns.LibraryBodies = {
			WarmBody = function(record, unit)
				warmed[#warmed + 1] = { record = record, unit = unit }
			end,
		}
		ns.SnapConfirmUI = {
			ConfirmSnap = function(record, isNew, token, liveUnit, recheck)
				if uiFails then error("no frame") end
				confirmed[#confirmed + 1] = { record = record, isNew = isNew, token = token,
					liveUnit = liveUnit, recheck = recheck }
			end,
			HideConfirm = function(token) hidden[#hidden + 1] = token end,
		}
		local addon = {
			Say = function(_, text) notices[#notices + 1] = text end,
			Warn = function(_, text) notices[#notices + 1] = text end,
		}
		local capture = assert(loadfile("SnapCapture.lua"))("Mogtrot", ns)
		return {
			capture = capture, addon = addon, scripts = scripts, timers = timers,
			notices = notices, confirmed = confirmed, hidden = hidden, warmed = warmed,
			setExisting = function(id, record)
				existing = id
				MogtrotDB.library.records[id] = record
			end,
			failUI = function() uiFails = true end,
			answer = function(guid)
				scripts.OnEvent(nil, "INSPECT_READY", guid or "Player-target")
			end,
			reads = function() return reads end,
			saves = function() return saves end,
			clears = function() return clears end,
			unregisters = function() return unregisters end,
			setGUID = function(guid) targetGUID = guid end,
		}
	end

	it("cancels an in-flight inspect before starting another", function()
		local h = Load()
		local notified = 0
		_G.NotifyInspect = function() notified = notified + 1 end
		h.capture.Target(h.addon)
		h.capture.Target(h.addon)
		assert.equal(2, notified)
		assert.equal(1, h.unregisters())
	end)

	it("reads the shared appearance buffer in the matching event handler", function()
		local h = Load()
		h.capture.Target(h.addon)
		h.scripts.OnEvent(nil, "INSPECT_READY", "Player-target")
		assert.equal(1, h.reads())
		assert.equal(1, #h.confirmed)
	end)

	it("ignores an inspect event for a different GUID", function()
		local h = Load()
		h.capture.Target(h.addon)
		h.scripts.OnEvent(nil, "INSPECT_READY", "Player-somebody-else")
		assert.equal(0, h.reads())
		assert.equal(0, h.saves())
	end)

	-- A secret cannot be compared at all in the client; here it is modelled as
	-- a value that would match, so using it at all shows.
	it("ignores an inspect event whose GUID is secret", function()
		local h = Load()
		h.capture.Target(h.addon)
		_G.issecretvalue = function(value) return value == "Player-target" end
		h.scripts.OnEvent(nil, "INSPECT_READY", "Player-target")
		_G.issecretvalue = nil
		assert.equal(0, h.reads())
		assert.equal(0, h.saves())
	end)

	it("refuses a target whose identity is secret, before inspecting", function()
		local h = Load()
		local notified = 0
		_G.NotifyInspect = function() notified = notified + 1 end
		_G.C_Secrets = { ShouldUnitIdentityBeSecret = function() return true end }
		h.capture.Target(h.addon)
		assert.equal(0, notified)
		assert.is_nil(h.scripts.OnEvent)
		assert.equal(0, h.saves())
		assert.equal(1, #h.notices)
		assert.truthy(h.notices[1]:find("identity is hidden", 1, true))
	end)

	it("refuses a target with no GUID, before inspecting", function()
		local h = Load()
		local notified = 0
		_G.NotifyInspect = function() notified = notified + 1 end
		_G.C_Secrets = { ShouldUnitIdentityBeSecret = function() return false end }
		h.setGUID(nil)
		h.capture.Target(h.addon)
		assert.equal(0, notified)
		assert.is_nil(h.scripts.OnEvent)
		assert.equal(0, h.saves())
		assert.equal(1, #h.notices)
		assert.truthy(h.notices[1]:find("can't snap", 1, true))
	end)

	it("refuses a target whose GUID comes back secret, before inspecting", function()
		local h = Load()
		local notified = 0
		_G.NotifyInspect = function() notified = notified + 1 end
		_G.C_Secrets = { ShouldUnitIdentityBeSecret = function() return false end }
		_G.issecretvalue = function(value) return value == "Player-target" end
		h.capture.Target(h.addon)
		assert.equal(0, notified)
		assert.is_nil(h.scripts.OnEvent)
		assert.equal(0, h.saves())
		assert.equal(1, #h.notices)
		assert.truthy(h.notices[1]:find("can't snap", 1, true))
	end)

	it("inspects a target whose identity is not secret", function()
		local h = Load()
		local notified = 0
		_G.NotifyInspect = function() notified = notified + 1 end
		_G.C_Secrets = { ShouldUnitIdentityBeSecret = function() return false end }
		h.capture.Target(h.addon)
		h.scripts.OnEvent(nil, "INSPECT_READY", "Player-target")
		assert.equal(1, notified)
		assert.equal(1, #h.confirmed)
	end)
	describe("confirmation", function()
		it("shows the capture and saves nothing while it is up", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.answer()
			assert.equal(1, #h.confirmed)
			assert.equal("Target", h.confirmed[1].record.name)
			assert.is_true(h.confirmed[1].isNew)
			assert.equal(0, h.saves())
			assert.truthy(h.capture.Pending())
		end)

		it("saves on Confirm and says so", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.answer()
			assert.is_true(h.capture.Resolve(h.confirmed[1].token, true))
			assert.equal(1, h.saves())
			assert.is_nil(h.capture.Pending())
			assert.truthy(h.notices[#h.notices]:find("saved", 1, true))
			assert.equal(h.confirmed[1].token, h.hidden[1])
		end)

		it("saves nothing on Cancel and says it was discarded", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.answer()
			assert.is_true(h.capture.Resolve(h.confirmed[1].token, false))
			assert.equal(0, h.saves())
			assert.is_nil(h.capture.Pending())
			assert.truthy(h.notices[#h.notices]:find("discarded", 1, true))
		end)

		it("confirms by default when the time runs out", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.answer()
			assert.equal(1, #h.timers)
			h.timers[1]()
			assert.equal(1, h.saves())
		end)

		it("answers one choice only; a late timer or click does nothing", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.answer()
			local token = h.confirmed[1].token
			assert.is_true(h.capture.Resolve(token, false))
			h.timers[1]()
			assert.is_false(h.capture.Resolve(token, true))
			assert.equal(0, h.saves())
		end)

		it("keeps a pending capture before starting the next snap", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.answer()
			h.capture.Target(h.addon)
			assert.equal(1, h.saves())
			assert.is_nil(h.capture.Pending())
			h.answer()
			assert.equal(2, #h.confirmed)
			assert.equal(1, h.saves())
		end)

		it("holds a repeat sighting unchanged until Confirm", function()
			local h = Load()
			local held = { id = 7, name = "Target", seenCount = 4 }
			h.setExisting(7, held)
			h.capture.Target(h.addon)
			h.answer()
			assert.is_false(h.confirmed[1].isNew)
			assert.equal(held, h.confirmed[1].record)
			assert.equal(0, h.saves())
			h.capture.Resolve(h.confirmed[1].token, false)
			assert.equal(0, h.saves())
			assert.equal(4, held.seenCount)
		end)

		it("saves at once when chat output is silenced", function()
			local h = Load()
			MogtrotDB.quiet = true
			h.capture.Target(h.addon)
			h.answer()
			assert.equal(1, h.saves())
			assert.equal(0, #h.confirmed)
			assert.is_nil(h.capture.Pending())
		end)

		it("saves at once when the answer lands in combat", function()
			local h = Load()
			h.capture.Target(h.addon)
			_G.InCombatLockdown = function() return true end
			h.answer()
			assert.equal(1, h.saves())
			assert.equal(0, #h.confirmed)
		end)

		it("saves at once when the pop-up cannot be shown", function()
			local h = Load()
			h.failUI()
			h.capture.Target(h.addon)
			h.answer()
			assert.equal(1, h.saves())
			assert.is_nil(h.capture.Pending())
		end)

		it("confirms nothing when nothing was captured", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.answer("Player-somebody-else")
			assert.equal(0, #h.confirmed)
			assert.is_nil(h.capture.Pending())
		end)
	end)

	describe("the pop-up's body", function()
		it("is built from the target while it is still the player captured", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.answer()
			assert.equal("target", h.confirmed[1].liveUnit)
		end)

		it("falls back when the target changed before the answer", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.setGUID("Player-somebody-else")
			h.answer("Player-target")
			assert.equal(1, #h.confirmed)
			assert.is_nil(h.confirmed[1].liveUnit)
		end)

		it("falls back when the target's model is not ready", function()
			local h = Load()
			_G.IsUnitModelReadyForUI = function() return false end
			h.capture.Target(h.addon)
			h.answer()
			assert.is_nil(h.confirmed[1].liveUnit)
		end)

		-- The client can answer not ready at the inspect answer and ready a
		-- moment later, so the pop-up asks again with the same pin.
		it("hands the pop-up a recheck that finds the target once it is ready", function()
			local h = Load()
			local ready = false
			_G.IsUnitModelReadyForUI = function() return ready end
			h.capture.Target(h.addon)
			h.answer()
			local recheck = h.confirmed[1].recheck
			assert.is_function(recheck)
			assert.is_nil(recheck())
			ready = true
			assert.equal("target", recheck())
			h.setGUID("Player-somebody-else")
			assert.is_nil(recheck())
		end)

		-- Only passive donors lend bodies to the library.
		it("borrows no body for the library from the target", function()
			local h = Load()
			h.capture.Target(h.addon)
			h.answer()
			assert.equal(0, #h.warmed)
			assert.is_table(h.confirmed[1].record)
		end)

		it("falls back when the target is gone", function()
			local h = Load()
			h.capture.Target(h.addon)
			_G.UnitExists = function() return false end
			h.answer()
			assert.is_nil(h.confirmed[1].liveUnit)
		end)
	end)

	describe("LiveBodyAllowed", function()
		local capture = assert(loadfile("SnapCapture.lua"))("Mogtrot", {})

		it("allows only the same player, identity readable, model ready", function()
			assert.is_true(capture.LiveBodyAllowed("G1", "G1", false, true))
			assert.is_false(capture.LiveBodyAllowed("G1", "G2", false, true))
			assert.is_false(capture.LiveBodyAllowed("G1", "G1", true, true))
			assert.is_false(capture.LiveBodyAllowed("G1", "G1", false, false))
			assert.is_false(capture.LiveBodyAllowed("G1", nil, false, true))
			assert.is_false(capture.LiveBodyAllowed(nil, nil, false, true))
		end)
	end)

	describe("LiveRetry", function()
		local capture = assert(loadfile("SnapCapture.lua"))("Mogtrot", {})

		it("asks again every tenth of a second for about a second", function()
			assert.equal("check", capture.LiveRetry(0.1, 0.1))
			assert.equal("wait", capture.LiveRetry(0.15, 0.05))
			assert.equal("check", capture.LiveRetry(1.0, 0.1))
		end)

		it("stops after the second", function()
			assert.equal("stop", capture.LiveRetry(1.05, 0.2))
		end)

		it("stops on anything it cannot read", function()
			assert.equal("stop", capture.LiveRetry(nil, 0.1))
		end)
	end)

	describe("ConfirmFraction", function()
		local capture = assert(loadfile("SnapCapture.lua"))("Mogtrot", {})

		it("starts empty and fills over the duration", function()
			assert.equal(0, capture.ConfirmFraction(0, 3))
			assert.equal(0.5, capture.ConfirmFraction(1.5, 3))
			assert.equal(1, capture.ConfirmFraction(3, 3))
		end)

		it("never leaves the bar's range", function()
			assert.equal(1, capture.ConfirmFraction(5, 3))
			assert.equal(0, capture.ConfirmFraction(-1, 3))
		end)

		it("reads a missing or zero duration as over", function()
			assert.equal(1, capture.ConfirmFraction(0, 0))
			assert.equal(1, capture.ConfirmFraction(nil, nil))
		end)

		it("lasts three seconds", function()
			assert.equal(3, capture.CONFIRM_SECONDS)
		end)
	end)
end)
