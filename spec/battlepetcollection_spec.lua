-- Injected-adapter contract for the battle-pet collection. The WoW side is
-- injected functions standing in for C_PetJournal: getOwnedPetIDs() ->
-- { guid, ... }, getPetInfoByID(guid) -> PetJournalPetInfo-shaped table or
-- nil, getSummonedPetGUID() -> guid or nil, getSummonInfo(guid) ->
-- summonable, reason, text. The collection is a pure read layer over them:
-- exact owned GUIDs, one record per owned copy, live display-name resolution,
-- summonability and current-summon predicates. It never mutates the adapter's
-- tables and never touches journal filters.
local BattlePetCollection = require("BattlePetCollection")

describe("BattlePetCollection", function()
	local GUID_A, GUID_B = "Pet-A", "Pet-B"

	local function Info(overrides)
		local info = {
			speciesID = 42,
			creatureID = 4200,
			displayID = 1234,
			customName = nil,
			name = "Cat",
			icon = "Interface\\Icons\\Icon_Pet_Cat",
			isFavorite = false,
		}
		for k, v in pairs(overrides or {}) do info[k] = v end
		return info
	end

	-- owned: array of GUIDs; infos: guid -> info; summoned: guid or nil;
	-- summonInfo: guid -> { summonable, reason, text }.
	local function Adapter(owned, infos, summoned, summonInfo)
		return {
			getOwnedPetIDs = function() return owned end,
			getPetInfoByID = function(guid) return infos[guid] end,
			getSummonedPetGUID = function() return summoned end,
			getSummonInfo = function(guid)
				local entry = summonInfo and summonInfo[guid]
				if entry then return entry.summonable, entry.reason, entry.text end
				return true, nil, nil
			end,
		}
	end

	describe("OwnedRows", function()
		it("returns one record per owned copy, preserving duplicate species", function()
			local owned = { GUID_A, GUID_B }
			local infos = {
				[GUID_A] = Info({ customName = "Smokey" }),
				[GUID_B] = Info(), -- same species 42, second owned copy
			}
			local rows = BattlePetCollection.OwnedRows(Adapter(owned, infos))
			assert.equal(2, #rows)
			local seen = { [rows[1].guid] = true, [rows[2].guid] = true }
			assert.same({ [GUID_A] = true, [GUID_B] = true }, seen)
			for _, row in ipairs(rows) do
				assert.equal(42, row.speciesID)
			end
		end)

		it("keeps species-level and copy-level metadata on each record", function()
			local owned = { GUID_A }
			local infos = { [GUID_A] = Info({ isFavorite = true }) }
			local row = BattlePetCollection.OwnedRows(Adapter(owned, infos))[1]
			assert.equal(GUID_A, row.guid)
			assert.equal(42, row.speciesID)
			assert.equal(4200, row.creatureID)
			assert.equal(1234, row.displayID)
			assert.equal("Interface\\Icons\\Icon_Pet_Cat", row.icon)
			assert.is_true(row.isFavorite)
		end)

		it("shows customName when present, else the species name", function()
			local owned = { GUID_A, GUID_B }
			local infos = {
				[GUID_A] = Info({ customName = "Smokey" }),
				[GUID_B] = Info(),
			}
			local rows = BattlePetCollection.OwnedRows(Adapter(owned, infos))
			local byGUID = {}
			for _, row in ipairs(rows) do byGUID[row.guid] = row end
			assert.equal("Smokey", byGUID[GUID_A].displayName)
			assert.equal("Cat", byGUID[GUID_B].displayName)
			-- The species name stays available as the subtitle.
			assert.equal("Cat", byGUID[GUID_A].name)
		end)

		it("returns a fresh list over exact GUID strings, without mutating inputs", function()
			local owned = { GUID_A }
			local infos = { [GUID_A] = Info() }
			local rows = BattlePetCollection.OwnedRows(Adapter(owned, infos))
			assert.equal(GUID_A, rows[1].guid)
			assert.is_not_equal(owned, rows)
			assert.is_not_equal(infos[GUID_A], rows[1])
			assert.equal(1, #owned)
			assert.equal(42, infos[GUID_A].speciesID)
		end)

		it("an empty first read is just empty, not proof of no pets", function()
			local rows = BattlePetCollection.OwnedRows(Adapter({}, {}))
			assert.same({}, rows)
			-- The same pure read on an adapter that now reports pets reflects it.
			local later = Adapter({ GUID_A }, { [GUID_A] = Info() })
			assert.equal(1, #BattlePetCollection.OwnedRows(later))
		end)

		it("skips copies the journal cannot describe", function()
			local owned = { GUID_A, GUID_B }
			local infos = { [GUID_A] = Info() } -- GUID_B: info not loaded
			local rows = BattlePetCollection.OwnedRows(Adapter(owned, infos))
			assert.equal(1, #rows)
			assert.equal(GUID_A, rows[1].guid)
		end)
	end)

	describe("SummonInfo", function()
		it("reports summonable, enum reason and localized text per copy", function()
			local summonInfo = {
				[GUID_A] = { summonable = false, reason = "PetIsDead", text = "dead" },
			}
			local ok, reason, text =
				BattlePetCollection.SummonInfo(Adapter({ GUID_A }, { [GUID_A] = Info() }, nil, summonInfo), GUID_A)
			assert.is_false(ok)
			assert.equals("PetIsDead", reason)
			assert.equals("dead", text)
		end)

		it("defaults to summonable when the journal has no objection", function()
			local ok, reason, text =
				BattlePetCollection.SummonInfo(Adapter({ GUID_A }, { [GUID_A] = Info() }), GUID_A)
			assert.is_true(ok)
			assert.is_nil(reason)
			assert.is_nil(text)
		end)
	end)

	describe("Current summon", function()
		it("identifies the currently summoned copy", function()
			local adapter = Adapter({ GUID_A }, { [GUID_A] = Info() }, GUID_A)
			assert.is_true(BattlePetCollection.IsSummoned(adapter, GUID_A))
			assert.is_false(BattlePetCollection.IsSummoned(adapter, "Pet-Z"))
		end)

		it("is false when nothing is summoned", function()
			local adapter = Adapter({ GUID_A }, { [GUID_A] = Info() }, nil)
			assert.is_false(BattlePetCollection.IsSummoned(adapter, GUID_A))
		end)
	end)

	describe("Pure reads", function()
		it("passes no filter arguments anywhere: journal filters untouched", function()
			local argCounts = {}
			local adapter = Adapter({ GUID_A }, { [GUID_A] = Info() })
			local ownedOld, infoOld = adapter.getOwnedPetIDs, adapter.getPetInfoByID
			adapter.getOwnedPetIDs = function(...) argCounts[#argCounts + 1] = select("#", ...) return ownedOld() end
			adapter.getPetInfoByID = function(...) argCounts[#argCounts + 1] = select("#", ...) return infoOld(...) end
			BattlePetCollection.OwnedRows(adapter)
			BattlePetCollection.IsSummoned(adapter, GUID_A)
			BattlePetCollection.SummonInfo(adapter, GUID_A)
			for _, n in ipairs(argCounts) do
				assert.is_true(n <= 1, "journal reads take at most the GUID argument")
			end
		end)

		it("keeps exact GUID strings including case", function()
			local guid = "BattlePet-0-00000C0FFEE-42"
			local rows = BattlePetCollection.OwnedRows(
				Adapter({ guid }, { [guid] = Info() }))
			assert.equal(guid, rows[1].guid)
		end)
	end)
end)
