-- The packed look. Every case here came out of a real capture, because the
-- shapes that look impossible in the abstract are the ones that turned up.
local LookCodec = require("LookCodec")

describe("LookCodec", function()
	describe("Encode", function()
		it("writes slots in ascending order", function()
			assert.equal("1:5,0,0;16:7,0,0",
				LookCodec.Encode({ [16] = { 7, 0, 0 }, [1] = { 5, 0, 0 } }))
		end)

		it("keeps split shoulders whose two values are equal", function()
			-- Seen on a live troll: appearance and secondary both 69650.
			assert.equal("3:69650,69650,0",
				LookCodec.Encode({ [3] = { 69650, 69650, 0 } }))
		end)

		it("keeps two weapons sharing an appearance but differing by illusion", function()
			-- Seen on a live orc: same transmog, Galaxy and Felshatter.
			assert.equal("16:168940,0,8553;17:168940,0,8549", LookCodec.Encode({
				[16] = { 168940, 0, 8553 }, [17] = { 168940, 0, 8549 },
			}))
		end)

		it("drops a slot that is entirely empty", function()
			assert.equal("1:5,0,0",
				LookCodec.Encode({ [1] = { 5, 0, 0 }, [11] = { 0, 0, 0 } }))
		end)

		it("keeps a slot carrying only an illusion", function()
			assert.equal("16:0,0,8549", LookCodec.Encode({ [16] = { 0, 0, 8549 } }))
		end)

		it("encodes a look with nothing worn as an empty string", function()
			assert.equal("", LookCodec.Encode({ [1] = { 0, 0, 0 } }))
		end)

		it("coerces whatever the client handed back", function()
			assert.equal("1:7,0,0", LookCodec.Encode({ [1] = { "7", false, nil } }))
		end)

		it("ignores non-numeric slot keys", function()
			assert.equal("1:5,0,0",
				LookCodec.Encode({ [1] = { 5, 0, 0 }, junk = { 9, 0, 0 } }))
		end)

		it("refuses anything that is not a look", function()
			assert.is_nil(LookCodec.Encode(nil))
			assert.is_nil(LookCodec.Encode("1:5,0,0"))
		end)
	end)

	describe("Decode", function()
		it("round-trips a real capture", function()
			local look = {
				[1] = { 69593, 0, 0 }, [3] = { 69650, 69650, 0 },
				[16] = { 293195, 0, 8549 },
			}
			assert.same(look, LookCodec.Decode(LookCodec.Encode(look)))
		end)

		it("reads an empty string as an empty look, not as nil", function()
			assert.same({}, LookCodec.Decode(""))
		end)

		it("returns nil for a corrupted string rather than a naked character", function()
			assert.is_nil(LookCodec.Decode("1:5,0"))
			assert.is_nil(LookCodec.Decode("1:5,0,0;garbage"))
			assert.is_nil(LookCodec.Decode("x:5,0,0"))
			assert.is_nil(LookCodec.Decode(nil))
			assert.is_nil(LookCodec.Decode({}))
		end)
	end)

	describe("Key", function()
		it("is the same for two characters who look identical", function()
			local a = LookCodec.Key({ [1] = { 5, 0, 0 } }, 6, 2)
			local b = LookCodec.Key({ [1] = { 5, 0, 0 } }, 6, 2)
			assert.equal(a, b)
		end)

		it("differs when the race differs", function()
			assert.is_not.equal(LookCodec.Key({ [1] = { 5, 0, 0 } }, 6, 2),
				LookCodec.Key({ [1] = { 5, 0, 0 } }, 4, 2))
		end)

		it("differs when the sex differs", function()
			assert.is_not.equal(LookCodec.Key({ [1] = { 5, 0, 0 } }, 6, 2),
				LookCodec.Key({ [1] = { 5, 0, 0 } }, 6, 3))
		end)

		it("takes an already-encoded look without re-encoding it", function()
			assert.equal(LookCodec.Key({ [1] = { 5, 0, 0 } }, 6, 2),
				LookCodec.Key("1:5,0,0", 6, 2))
		end)

		it("ignores identity entirely, which is the point", function()
			-- No name, realm or guid appears anywhere in the key.
			local key = LookCodec.Key("1:5,0,0", 6, 2)
			assert.equal("1:5,0,0|6|2", key)
		end)

		it("refuses a look it cannot encode", function()
			assert.is_nil(LookCodec.Key(nil, 6, 2))
		end)
	end)
end)

-- The client answers -1 for a weapon's secondary appearance, so a look string
-- carries negatives and a decoder that only accepts digits loses the record.
describe("LookCodec negatives", function()
	it("encodes a negative secondary the client handed back", function()
		assert.equal("16:219536,-1,0",
			LookCodec.Encode({ [16] = { 219536, -1, 0 } }))
	end)

	it("decodes it back to the same numbers", function()
		local look = LookCodec.Decode("16:219536,-1,0")
		assert.same({ 219536, -1, 0 }, look[16])
	end)

	it("round trips a real capture carrying one", function()
		local text = "1:79915,0,0;16:219536,-1,0"
		assert.equal(text, LookCodec.Encode(LookCodec.Decode(text)))
	end)

	it("drops a slot holding nothing but negatives", function()
		assert.equal("", LookCodec.Encode({ [5] = { 0, -1, 0 }, [7] = { -1, -1, -1 } }))
	end)

	it("keeps a slot whose appearance is real even when its secondary is not", function()
		assert.equal("5:42,-1,0", LookCodec.Encode({ [5] = { 42, -1, 0 } }))
	end)

	it("still refuses a string that is not numbers", function()
		assert.is_nil(LookCodec.Decode("16:219536,-,0"))
		assert.is_nil(LookCodec.Decode("16:219536,--1,0"))
	end)
end)

-- An outfit's definition, from what the viewed outfit says about each slot.
-- Shaped on Devnull's Outfit 2: shirt, weapons and tabard left empty while
-- gear is equipped there.
describe("LookCodec.FromSlotInfos", function()
	local ASSIGNED, UNASSIGNED, EQUIPPED, HIDDEN = 1, 0, 2, 3
	local function Info(displayType, transmogID)
		return { displayType = displayType, transmogID = transmogID }
	end

	it("keeps assigned parts and stores every other slot as empty", function()
		local look = LookCodec.FromSlotInfos({
			{ slotID = 1, primary = Info(ASSIGNED, 302897) },
			{ slotID = 3, primary = Info(ASSIGNED, 302899), secondary = Info(ASSIGNED, 302899) },
			{ slotID = 4, primary = Info(UNASSIGNED, 83202) },
			{ slotID = 16, primary = Info(EQUIPPED, 219532), illusion = Info(UNASSIGNED, 0) },
			{ slotID = 17, primary = Info(HIDDEN, 219583) },
		}, ASSIGNED)

		assert.same({ 302897, 0, 0 }, look[1])
		assert.same({ 302899, 302899, 0 }, look[3])
		assert.same({ 0, 0, 0 }, look[4])
		assert.same({ 0, 0, 0 }, look[16])
		assert.same({ 0, 0, 0 }, look[17])
	end)

	it("keeps an assigned illusion and an assigned secondary on their own", function()
		local look = LookCodec.FromSlotInfos({
			{ slotID = 16, primary = Info(ASSIGNED, 168940), illusion = Info(ASSIGNED, 8553) },
			{ slotID = 3, primary = Info(ASSIGNED, 5), secondary = Info(UNASSIGNED, 6) },
		}, ASSIGNED)

		assert.same({ 168940, 0, 8553 }, look[16])
		assert.same({ 5, 0, 0 }, look[3])
	end)

	it("reads a missing slot info as empty and skips entries with no slot", function()
		local look = LookCodec.FromSlotInfos({
			{ slotID = 5 },
			{ primary = Info(ASSIGNED, 9) },
		}, ASSIGNED)

		assert.same({ [5] = { 0, 0, 0 } }, look)
	end)
end)
