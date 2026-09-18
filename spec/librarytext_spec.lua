-- What a library card says, and what More info dumps.
local LibraryText = require("LibraryText")

describe("LibraryText", function()
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
	end)

	describe("Subtitle", function()
		it("names the body and counts the pieces", function()
			assert.equal("Tauren male, 2 pieces", LibraryText.Subtitle(Record()))
		end)

		it("says one piece in the singular", function()
			assert.equal("Tauren male, 1 piece",
				LibraryText.Subtitle(Record({ look = "1:5,0,0" })))
		end)

		it("falls back to the numeric race when the file name is missing", function()
			assert.equal("race 6 male, 2 pieces",
				LibraryText.Subtitle(Record({ raceFile = "nil" })))
		end)

		it("says so plainly when the body was never answered", function()
			assert.equal("body unknown, 2 pieces",
				LibraryText.Subtitle(Record({ raceFile = "nil", raceID = "nil" })))
		end)

		it("omits a sex the client did not answer", function()
			assert.equal("Tauren, 2 pieces", LibraryText.Subtitle(Record({ sex = "nil" })))
		end)
	end)

	describe("Details", function()
		local function Find(lines, prefix)
			for _, line in ipairs(lines) do
				if line:sub(1, #prefix) == prefix then return line end
			end
		end

		it("leads with the two card lines", function()
			local lines = LibraryText.Details(Record())
			assert.equal("Thunderhoof-Aegwynn", lines[1])
			assert.equal("Tauren male, 2 pieces", lines[2])
		end)

		it("prints a field the capture never answered rather than dropping it", function()
			local lines = LibraryText.Details(Record())
			assert.truthy(Find(lines, "guid"))
			assert.equal("guid         -", Find(lines, "guid"))
		end)

		it("prints false as false, not as missing", function()
			local lines = LibraryText.Details(Record({ nativeForm = false }))
			assert.equal("nativeForm   false", Find(lines, "nativeForm"))
		end)

		it("breaks the look out one slot per line", function()
			local lines = LibraryText.Details(Record())
			assert.truthy(Find(lines, "  slot 1 "))
			assert.truthy(Find(lines, "  slot 16 "):find("illusion 4"))
		end)

		it("says so when the look string is corrupt", function()
			local lines = LibraryText.Details(Record({ look = "1:oops" }))
			assert.truthy(Find(lines, "  (this look string does not parse)"))
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
