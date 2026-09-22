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
