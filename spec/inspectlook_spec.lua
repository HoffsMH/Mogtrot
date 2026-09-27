-- Turning another player's inspected appearance into the look shape Mogtrot
-- already stores. The counts matter as much as the table: an inspect that has
-- not finished looks exactly like a player wearing nothing.
local InspectLook = require("InspectLook")

describe("InspectLook", function()
	describe("FromTransmogList", function()
		it("keeps appearance, secondary and illusion per slot", function()
			local look = InspectLook.FromTransmogList({
				[1] = { appearanceID = 111, secondaryAppearanceID = 222, illusionID = 333 },
			})
			assert.same({ 111, 222, 333 }, look[1])
		end)

		it("counts filled slots apart from empty ones", function()
			local _, filled, empty = InspectLook.FromTransmogList({
				[1] = { appearanceID = 111 },
				[3] = { appearanceID = 0 },
				[5] = { appearanceID = 222 },
			})
			assert.equal(2, filled)
			assert.equal(1, empty)
		end)

		it("defaults a missing secondary or illusion to no transmog", function()
			local look = InspectLook.FromTransmogList({ [1] = { appearanceID = 111 } })
			assert.same({ 111, 0, 0 }, look[1])
		end)

		it("coerces whatever the client hands back", function()
			local look = InspectLook.FromTransmogList({
				[2] = { appearanceID = "77", secondaryAppearanceID = false },
			})
			assert.same({ 77, 0, 0 }, look[2])
		end)

		it("ignores entries that are not slot tables", function()
			local look = InspectLook.FromTransmogList({ [1] = "junk", junk = { appearanceID = 5 } })
			assert.same({}, look)
		end)

		it("reads an absent list as nothing rather than erroring", function()
			local look, filled, empty = InspectLook.FromTransmogList(nil)
			assert.same({}, look)
			assert.equal(0, filled)
			assert.equal(0, empty)
		end)
	end)
end)
