local PairingHeader = require("PairingHeader")

-- The window has no title of its own: the sentence is the title, and the words
-- that can change are the controls. Everything here is about what that
-- sentence reads like and which of its words are click targets.
local function Text(segments)
	local out = {}
	for _, segment in ipairs(segments) do out[#out + 1] = segment.text end
	return table.concat(out)
end

local function Actions(segments)
	local out = {}
	for _, segment in ipairs(segments) do
		if segment.action then out[#out + 1] = segment.action end
	end
	return out
end

describe("PairingHeader.Segments", function()
	it("reads as a sentence while pairing with an outfit", function()
		assert.equal("Choosing mounts for brick chillin   3 chosen   switch to pins",
			Text(PairingHeader.Segments({ domain = "mounts", mode = "outfit",
				outfitName = "brick chillin", chosen = 3 })))
	end)

	-- Pins are account-wide, so naming an outfit there would be a lie.
	it("drops the outfit clause when showing pins", function()
		assert.equal("Choosing pinned hearthstones   3 chosen   switch to outfit",
			Text(PairingHeader.Segments({ domain = "hearthstones", mode = "pins",
				chosen = 3 })))
	end)

	it("offers the domain, the outfit and the mode as controls", function()
		assert.same({ "domain", "outfit", "mode" },
			Actions(PairingHeader.Segments({ domain = "mounts", mode = "outfit",
				outfitName = "brick chillin", chosen = 1 })))
	end)

	it("offers no outfit control where there is no outfit clause", function()
		assert.same({ "domain", "mode" },
			Actions(PairingHeader.Segments({ domain = "mounts", mode = "pins",
				chosen = 0 })))
	end)

	it("counts one thing singular", function()
		assert.is_true(Text(PairingHeader.Segments({ domain = "mounts",
			mode = "pins", chosen = 1 })):find("1 chosen", 1, true) ~= nil)
	end)

	it("names an outfit it was given no name for", function()
		local text = Text(PairingHeader.Segments({ domain = "mounts",
			mode = "outfit", chosen = 0 }))
		assert.is_true(text:find("for Outfit", 1, true) ~= nil)
	end)

	it("falls back to a whole sentence for a malformed state", function()
		assert.is_string(Text(PairingHeader.Segments(nil)))
		assert.is_string(Text(PairingHeader.Segments({})))
	end)
end)

-- Each clickable word wears the icon of the thing it names, so the sentence
-- can be read at a glance. The names are resolved to textures by the window;
-- this module never learns a file ID.
describe("PairingHeader icons", function()
	local function IconFor(state, action)
		for _, segment in ipairs(PairingHeader.Segments(state)) do
			if segment.action == action then return segment.icon end
		end
	end

	it("names the domain it is showing", function()
		assert.equal("mounts", IconFor({ domain = "mounts", mode = "outfit" }, "domain"))
		assert.equal("hearthstones",
			IconFor({ domain = "hearthstones", mode = "outfit" }, "domain"))
	end)

	it("marks the outfit word as an outfit", function()
		assert.equal("outfit", IconFor({ domain = "mounts", mode = "outfit" }, "outfit"))
	end)

	-- The mode word names where it takes you, so its icon does too.
	it("names the mode it would switch to", function()
		assert.equal("pins", IconFor({ domain = "mounts", mode = "outfit" }, "mode"))
		assert.equal("outfit", IconFor({ domain = "mounts", mode = "pins" }, "mode"))
	end)

	it("gives plain prose no icon", function()
		for _, segment in ipairs(PairingHeader.Segments({ domain = "mounts" })) do
			if not segment.action then assert.is_nil(segment.icon) end
		end
	end)
end)

describe("PairingHeader toggles", function()
	it("swaps between the two domains", function()
		assert.equal("hearthstones", PairingHeader.OtherDomain("mounts"))
		assert.equal("mounts", PairingHeader.OtherDomain("hearthstones"))
	end)

	it("swaps between the two modes", function()
		assert.equal("pins", PairingHeader.OtherMode("outfit"))
		assert.equal("outfit", PairingHeader.OtherMode("pins"))
	end)

	-- Anything unrecognised lands on the default rather than sticking.
	it("resolves an unknown domain or mode", function()
		assert.equal("hearthstones", PairingHeader.OtherDomain("bananas"))
		assert.equal("pins", PairingHeader.OtherMode(nil))
	end)
end)

-- The library wears the same header. Its two exclusive modes are the same
-- shape as the pairing window's domain word, so the mode is a word in the
-- sentence and the library has no title and no tabs either.
describe("PairingHeader.LibrarySegments", function()
	it("reads as a sentence naming what is shown and how much of it", function()
		assert.equal("Showing 50 of 247 looks from my characters",
			Text(PairingHeader.LibrarySegments({ mode = "mine", shown = 50,
				total = 247 })))
	end)

	-- The filter line below says why 50 of 247; saying "of 247" when nothing
	-- was filtered out would invent a filter.
	it("drops the comparison when nothing is filtered out", function()
		assert.equal("Showing 247 looks from snapshots",
			Text(PairingHeader.LibrarySegments({ mode = "snapshots", shown = 247,
				total = 247 })))
	end)

	it("counts one look singular", function()
		assert.equal("Showing 1 look from snapshots",
			Text(PairingHeader.LibrarySegments({ mode = "snapshots", shown = 1,
				total = 1 })))
	end)

	it("says an empty library is empty rather than counting to zero", function()
		assert.equal("Showing no looks from my characters",
			Text(PairingHeader.LibrarySegments({ mode = "mine", shown = 0,
				total = 0 })))
	end)

	it("counts none of a full library when every look is filtered out", function()
		assert.equal("Showing 0 of 247 looks from snapshots",
			Text(PairingHeader.LibrarySegments({ mode = "snapshots", shown = 0,
				total = 247 })))
	end)

	it("offers the mode as its only control", function()
		assert.same({ "libraryMode" },
			Actions(PairingHeader.LibrarySegments({ mode = "mine", shown = 3,
				total = 3 })))
	end)

	it("names the mode it is showing", function()
		local function IconFor(state)
			for _, segment in ipairs(PairingHeader.LibrarySegments(state)) do
				if segment.action == "libraryMode" then return segment.icon end
			end
		end
		assert.equal("characters", IconFor({ mode = "mine" }))
		assert.equal("snapshots", IconFor({ mode = "snapshots" }))
	end)

	it("falls back to a whole sentence for a malformed state", function()
		assert.equal("Showing no looks from snapshots",
			Text(PairingHeader.LibrarySegments(nil)))
		assert.equal("Showing no looks from snapshots",
			Text(PairingHeader.LibrarySegments({})))
	end)

	-- Same default as LibraryFilter's: anything that is not "mine" is the
	-- snapshot wall, so the sentence can never disagree with the cards.
	it("resolves an unknown mode to snapshots", function()
		assert.equal("snapshots", PairingHeader.LibraryMode("bananas"))
		assert.equal("snapshots", PairingHeader.LibraryMode(nil))
		assert.equal("mine", PairingHeader.LibraryMode("mine"))
	end)
end)

-- A word that stands for one of a fixed set opens a menu of that set, and the
-- rows in it are the words the sentence would read, so one vocabulary serves
-- both.
describe("PairingHeader.Choices", function()
	local function Values(choices)
		local out = {}
		for _, choice in ipairs(choices) do out[#out + 1] = choice.value end
		return out
	end

	it("offers both domains behind the domain word", function()
		assert.same({ "mounts", "hearthstones" },
			Values(PairingHeader.Choices("domain")))
	end)

	it("offers both library modes behind the library's mode word", function()
		assert.same({ "mine", "snapshots" },
			Values(PairingHeader.Choices("libraryMode")))
	end)

	it("reads each choice the way the sentence would", function()
		local choices = PairingHeader.Choices("libraryMode")
		assert.equal("my characters", choices[1].text)
		assert.equal("characters", choices[1].icon)
		assert.equal("snapshots", choices[2].text)
		assert.equal("snapshots", choices[2].icon)
	end)

	it("offers nothing for a word that is not one of a fixed set", function()
		assert.same({}, PairingHeader.Choices("outfit"))
		assert.same({}, PairingHeader.Choices(nil))
	end)
end)
