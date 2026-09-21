describe("SnapCapture inspect ownership", function()
	local names = {
		"AuraUtil", "C_Map", "C_MountJournal", "C_PaperDollInfo", "C_PlayerInfo",
		"C_Secrets", "C_Timer", "C_TransmogCollection", "ClearInspectPlayer",
		"CreateFrame", "GetBuildInfo", "GetInspectSpecialization", "GetSubZoneText",
		"GetZoneText", "InCombatLockdown", "MogtrotDB", "NotifyInspect", "UnitClass",
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
		_G.GetInspectSpecialization = function() return 72 end
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
				Add = function() saves = saves + 1 return 1, true end,
			},
		}
		local addon = {
			Say = function(_, text) notices[#notices + 1] = text end,
			Warn = function(_, text) notices[#notices + 1] = text end,
		}
		local capture = assert(loadfile("SnapCapture.lua"))("Mogtrot", ns)
		return {
			capture = capture, addon = addon, scripts = scripts, timers = timers,
			notices = notices,
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
		assert.equal(1, h.saves())
		assert.equal(0, #h.timers)
	end)

	it("ignores an inspect event for a different GUID", function()
		local h = Load()
		h.capture.Target(h.addon)
		h.scripts.OnEvent(nil, "INSPECT_READY", "Player-somebody-else")
		assert.equal(0, h.reads())
		assert.equal(0, h.saves())
	end)
end)
