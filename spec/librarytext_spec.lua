-- What a library card, its detail pane and the snap confirmation say.
local LibraryText = require("LibraryText")

describe("LibraryText", function()
	it("names mirrored outfits and identifies their owner", function()
		local record = { source = "mine", origin = "outfit", originName = "Crimson",
			name = "Alpha", realm = "Aegwynn", look = "1:5,0,0" }
		assert.equal("Crimson", LibraryText.Title(record))
		assert.equal("Alpha-Aegwynn, 1 piece", LibraryText.Subtitle(record))
	end)
	local function Record(over)
		local r = {
			id = 3, source = "snap", look = "1:5,0,0;16:9,0,4",
			name = "Thunderhoof", realm = "Aegwynn",
			raceID = 6, raceFile = "Tauren", sex = 2,
		}
		for k, v in pairs(over or {}) do
			if v == "nil" then r[k] = nil else r[k] = v end
		end
		return r
	end

	describe("Confirmation", function()
		it("says a new look was captured, by name and realm", function()
			assert.equal("Thunderhoof-Aegwynn captured",
				LibraryText.Confirmation(Record(), true))
		end)

		it("says a repeat sighting was seen again rather than captured", function()
			assert.equal("Thunderhoof-Aegwynn seen again",
				LibraryText.Confirmation(Record(), false))
		end)

		it("says so when the capture got no name, rather than inventing one", function()
			assert.equal("Look #3 captured, no name given",
				LibraryText.Confirmation(Record({ name = "nil", realm = "nil" }), true))
		end)

		it("answers nothing for a missing record", function()
			assert.equal("", LibraryText.Confirmation(nil, true))
		end)
	end)

	describe("Title", function()
		it("names them with their realm", function()
			assert.equal("Thunderhoof-Aegwynn", LibraryText.Title(Record()))
		end)

		it("drops the realm when the capture had none", function()
			assert.equal("Thunderhoof", LibraryText.Title(Record({ realm = "nil" })))
		end)

		it("falls back to the container name for one of yours", function()
			assert.equal("Hallowfall", LibraryText.Title(Record({
				name = "nil", realm = "nil", originName = "Hallowfall",
			})))
		end)

		it("falls back to the id when nobody could be named", function()
			assert.equal("Look #3", LibraryText.Title(Record({
				name = "nil", realm = "nil",
			})))
		end)

		it("does not read an empty name as a name", function()
			assert.equal("Look #3", LibraryText.Title(Record({ name = "" })))
		end)

		it("adds a class-colored class name to a card title", function()
			assert.equal("Thunderhoof-Aegwynn | |cffaad372Hunter|r",
				LibraryText.CardTitle(Record(), "Hunter", "ffaad372"))
		end)

		it("keeps the ordinary title when class details are unavailable", function()
			assert.equal("Thunderhoof-Aegwynn", LibraryText.CardTitle(Record()))
		end)
	end)

	-- The pane title row has buttons on it and a long name already crowds
	-- them, so the class goes on the full-width line below instead.
	describe("class on a snapshot subtitle", function()
		local function Snap()
			return { source = "snap", raceFile = "NightElf", sex = 3,
				look = "1:5,0,0" }
		end

		it("names the class after the body", function()
			assert.equal("Night Elf woman Rogue, 1 piece",
				LibraryText.Subtitle(Snap(), "Rogue"))
		end)

		it("reads the same as before when the class is unknown", function()
			assert.equal("Night Elf woman, 1 piece", LibraryText.Subtitle(Snap()))
			assert.equal("Night Elf woman, 1 piece", LibraryText.Subtitle(Snap(), ""))
		end)

		-- One of mine already carries its class on the card title.
		it("leaves my own records alone", function()
			assert.equal("Alpha-Aegwynn, 1 piece", LibraryText.Subtitle({
				source = "mine", origin = "outfit", name = "Alpha",
				realm = "Aegwynn", look = "1:5,0,0", scanned = true }, "Rogue"))
		end)
	end)

	describe("an outfit with no pieces", function()
		local function Outfit(look, scanned)
			return { source = "mine", origin = "outfit", originName = "Red",
				name = "Alpha", realm = "Aegwynn", look = look, scanned = scanned }
		end

		it("says an unread outfit has not been captured", function()
			assert.equal("Alpha-Aegwynn, not captured yet",
				LibraryText.Subtitle(Outfit("", false)))
		end)

		it("says an outfit read as empty sets nothing", function()
			assert.equal("Alpha-Aegwynn, nothing set",
				LibraryText.Subtitle(Outfit("", true)))
		end)

		it("still counts pieces where there are some", function()
			assert.equal("Alpha-Aegwynn, 1 piece",
				LibraryText.Subtitle(Outfit("1:5,0,0", true)))
		end)
	end)

	describe("Subtitle", function()
		it("names the body and counts the pieces", function()
			assert.equal("Tauren man, 2 pieces", LibraryText.Subtitle(Record()))
		end)

		it("says one piece in the singular", function()
			assert.equal("Tauren man, 1 piece",
				LibraryText.Subtitle(Record({ look = "1:5,0,0" })))
		end)

		it("says so plainly when the race was never answered", function()
			assert.equal("Unknown race, 2 pieces",
				LibraryText.Subtitle(Record({ raceFile = "nil" })))
		end)

		it("names races the way the game does, not by their file names", function()
			assert.equal("Undead", LibraryText.RaceName("Scourge"))
			assert.equal("Kul Tiran", LibraryText.RaceName("KulTiran"))
			assert.equal("Highmountain Tauren", LibraryText.RaceName("HighmountainTauren"))
			assert.equal("Mag'har Orc", LibraryText.RaceName("MagharOrc"))
			assert.is_nil(LibraryText.RaceName(nil))
		end)

		it("omits a sex the client did not answer", function()
			assert.equal("Tauren, 2 pieces", LibraryText.Subtitle(Record({ sex = "nil" })))
		end)
	end)
end)

-- The slots a detail pane lays out, and what to call them.
describe("LibraryText slots", function()
	it("reads down the body and ends with what is held", function()
		local order = LibraryText.SLOT_ORDER
		assert.equal(1, order[1])
		assert.equal(16, order[#order - 2])
		assert.equal(17, order[#order - 1])
		assert.equal(19, order[#order])
	end)

	it("covers every slot a transmog can occupy and nothing else", function()
		local seen = {}
		for _, slot in ipairs(LibraryText.SLOT_ORDER) do seen[slot] = true end
		for _, slot in ipairs({ 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 19 }) do
			assert.is_true(seen[slot], "slot " .. slot .. " is missing")
		end
		assert.equal(13, #LibraryText.SLOT_ORDER)
		-- Slots no transmog ever occupies.
		assert.is_nil(seen[2])
		assert.is_nil(seen[11])
		assert.is_nil(seen[12])
		assert.is_nil(seen[14])
	end)

	it("names the slots people actually say", function()
		assert.equal("Head", LibraryText.SlotName(1))
		assert.equal("Main hand", LibraryText.SlotName(16))
		assert.equal("Tabard", LibraryText.SlotName(19))
	end)

	it("falls back to the number for a slot it does not know", function()
		assert.equal("Slot 99", LibraryText.SlotName(99))
		assert.equal("Slot nil", LibraryText.SlotName(nil))
	end)
end)

-- The paperdoll arrangement. Its only real contract is that it lays out every
-- slot exactly once, since a slot in two columns draws twice and a slot in
-- none silently disappears.
describe("LibraryText.SLOT_COLUMNS", function()
	local columns = LibraryText.SLOT_COLUMNS

	it("places every slot exactly once", function()
		local seen, total = {}, 0
		for _, side in ipairs({ "left", "right", "bottom" }) do
			for _, slot in ipairs(columns[side]) do
				assert.is_nil(seen[slot], "slot " .. slot .. " is placed twice")
				seen[slot] = side
				total = total + 1
			end
		end
		assert.equal(#LibraryText.SLOT_ORDER, total)
		for _, slot in ipairs(LibraryText.SLOT_ORDER) do
			assert.is_truthy(seen[slot], "slot " .. slot .. " is placed nowhere")
		end
	end)

	it("puts the weapons underneath, as the character sheet does", function()
		assert.same({ 16, 17 }, columns.bottom)
	end)

	it("leads each side with the slot people look at first", function()
		assert.equal(1, columns.left[1])
		assert.equal(10, columns.right[1])
	end)
end)

describe("LibraryText.CardLayout", function()
	-- The render note is a debugging aid and does not ship, so the text sits at
	-- the card's foot and the model takes the rest.
	it("leaves no room for a render note", function()
		local layout = LibraryText.CardLayout()
		assert.is_nil(layout.status)
		assert.equal(5, layout.sub)
		assert.equal(17, layout.title)
		assert.equal(33, layout.scene)
	end)
end)

-- Racial pieces are drawn only on a body of their own faction, and nothing
-- else about the card would say why they are missing.
describe("LibraryText.FactionNote", function()
	local record = { faction = "Alliance" }

	-- It replaces the card's subtitle, which has room for about 37 characters.
	it("names how many of the pieces need the record's faction", function()
		local horde = { faction = "Horde", look = "1:5,0,0;7:6,0,0" }
		assert.equal("1 of 2 pieces is Horde only",
			LibraryText.FactionNote(horde, "Alliance", 1))
		local alliance = { faction = "Alliance",
			look = "1:1,0,0;3:1,0,0;5:1,0,0;6:1,0,0;7:1,0,0;8:1,0,0;9:1,0,0;10:1,0,0;"
				.. "15:1,0,0;16:1,0,0;19:1,0,0" }
		local note = LibraryText.FactionNote(alliance, "Horde", 5)
		assert.equal("5 of 11 pieces are Alliance only", note)
		assert.is_true(#note <= 37)
	end)

	it("says nothing when every piece is on the body", function()
		assert.is_nil(LibraryText.FactionNote(record, "Horde", 0))
		assert.is_nil(LibraryText.FactionNote(record, "Horde", nil))
	end)

	it("says nothing when the body is already of that faction", function()
		assert.is_nil(LibraryText.FactionNote(record, "Alliance", 3))
	end)

	it("says nothing when either faction is unknown or neutral", function()
		assert.is_nil(LibraryText.FactionNote({}, "Horde", 3))
		assert.is_nil(LibraryText.FactionNote(record, nil, 3))
		assert.is_nil(LibraryText.FactionNote({ faction = "Neutral" }, "Horde", 3))
	end)
end)
