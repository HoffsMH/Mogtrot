describe("MainWindowMenus copy labels", function()
	local Menus

	before_each(function()
		Menus = assert(loadfile("MainWindowMenus.lua"))("Mogtrot", {})
	end)

	-- The count on a copy button is how many outfits the click writes to, not
	-- how many links it copies, so the label names the outfits.
	it("names the outfits the click writes to", function()
		assert.equal("Add to 1 outfit", Menus.TargetLabel("Add", "to", 1))
		assert.equal("Add to 3 outfits", Menus.TargetLabel("Add", "to", 3))
		assert.equal("Replace on 1 outfit", Menus.TargetLabel("Replace", "on", 1))
		assert.equal("Replace on 12 outfits", Menus.TargetLabel("Replace", "on", 12))
	end)

	it("counts links and outfits in words", function()
		assert.equal("no mounts", Menus.Plural(0, "mount"))
		assert.equal("1 title", Menus.Plural(1, "title"))
		assert.equal("4 hearthstones", Menus.Plural(4, "hearthstone"))
	end)
end)
