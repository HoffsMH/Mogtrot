local LibraryDetailUI = assert(loadfile("LibraryDetailUI.lua"))("Mogtrot", {})

describe("LibraryDetailUI placeholder", function()
	it("treats an unspecified look as blank", function()
		assert.is_false(LibraryDetailUI.HasLook({ look = "" }))
		assert.is_true(LibraryDetailUI.HasLook({ look = "1:101,0,0" }))
	end)
end)

describe("LibraryDetailUI icon ownership", function()
	it("tints only appearances known to be uncollected", function()
		assert.same({ 1, 0.35, 0.35 }, { LibraryDetailUI.IconColor(false) })
		assert.same({ 1, 1, 1 }, { LibraryDetailUI.IconColor(true) })
		assert.same({ 1, 1, 1 }, { LibraryDetailUI.IconColor(nil) })
	end)
end)

describe("LibraryDetailUI adjacent placement", function()
	it("uses the right side when it fits and otherwise the roomier side", function()
		assert.equal("RIGHT", LibraryDetailUI.AnchorSide(100, 900, 1920, 400, 8))
		assert.equal("LEFT", LibraryDetailUI.AnchorSide(500, 1500, 1600, 400, 8))
		assert.equal("RIGHT", LibraryDetailUI.AnchorSide(100, 1500, 1600, 400, 8))
	end)
end)

describe("LibraryDetailUI library button", function()
	it("opens the library without toggling it closed", function()
		local calls, reanchors = 0, 0
		local oldReanchor = LibraryDetailUI.Reanchor
		LibraryDetailUI.Reanchor = function(frame)
			assert.equal("library", frame.name)
			reanchors = reanchors + 1
		end
		assert.is_true(LibraryDetailUI.OpenLibrary({
			Show = function()
				calls = calls + 1
				return { name = "library" }
			end,
		}))
		LibraryDetailUI.Reanchor = oldReanchor
		assert.equal(1, calls)
		assert.equal(1, reanchors)
		assert.is_false(LibraryDetailUI.OpenLibrary(nil))
	end)
end)

describe("LibraryDetailUI transmog slot selection", function()
	-- The pane keys its icons on inventory slots, which is what a stored look
	-- is keyed on. Blizzard's preview matches on Enum.TransmogOutfitSlot. The
	-- two overlap without agreeing: inventory 8 is Feet, outfit slot 8 is Hand,
	-- so passing one where the other is wanted highlights the wrong slot and
	-- raises no error.
	local INVSLOT_FEET, OUTFIT_SLOT_FEET = 8, 11

	-- Blizzard's own conversion takes a zero-based inventory slot.
	local function Convert(zeroBased)
		assert.equal(INVSLOT_FEET - 1, zeroBased)
		return OUTFIT_SLOT_FEET
	end

	it("converts the inventory slot before asking for the frame", function()
		local selected = 0
		local slot = { OnSelect = function() selected = selected + 1 end }
		local preview = {
			GetSlotFrame = function(_, outfitSlot, kind)
				assert.equal(OUTFIT_SLOT_FEET, outfitSlot)
				assert.equal(7, kind)
				return slot
			end,
		}
		assert.is_true(LibraryDetailUI.SelectTransmogSlot(preview, INVSLOT_FEET, 7,
			Convert))
		assert.equal(1, selected)
	end)

	it("maps an inventory slot to its outfit slot", function()
		assert.equal(OUTFIT_SLOT_FEET,
			LibraryDetailUI.OutfitSlotFor(INVSLOT_FEET, Convert))
	end)

	-- The client documents this call as able to return nothing.
	it("does nothing when the client will not name an outfit slot", function()
		local asked = false
		local preview = { GetSlotFrame = function() asked = true end }
		assert.is_false(LibraryDetailUI.SelectTransmogSlot(preview, 8, 7,
			function() return nil end))
		assert.is_false(asked)
	end)
end)

describe("LibraryDetailUI appearance ownership", function()
	it("tints collected appearances this character cannot use", function()
		assert.is_true(LibraryDetailUI.ShouldTint("collected_unusable"))
		assert.is_false(LibraryDetailUI.ShouldTint("collected_other"))
		assert.is_false(LibraryDetailUI.ShouldTint("pending"))
	end)

	it("accepts a collected usable sibling of the stored source", function()
		local infos = {
			[10] = { name = "Stored", visualID = 7, isCollected = false,
				playerCanCollect = true },
			[11] = { name = "Owned twin", visualID = 7, isCollected = true,
				useErrorType = 0 },
		}
		local collection = {
			GetSourceInfo = function(id) return infos[id] end,
			GetAllAppearanceSources = function() return { 10, 11 } end,
		}
		assert.equal("collected_other",
			LibraryDetailUI.CollectionState(10, collection, 0))
	end)
end)

describe("LibraryDetailUI library shortcut", function()
	it("offers the library when it is not on screen", function()
		assert.is_true(LibraryDetailUI.ShouldOfferLibrary({
			IsOpen = function() return false end,
		}))
	end)

	it("withholds it when the library is already up", function()
		assert.is_false(LibraryDetailUI.ShouldOfferLibrary({
			IsOpen = function() return true end,
		}))
	end)

	-- An older build without the question still gets a working button.
	it("offers it when nothing can answer", function()
		assert.is_true(LibraryDetailUI.ShouldOfferLibrary(nil))
		assert.is_true(LibraryDetailUI.ShouldOfferLibrary({}))
	end)
end)

describe("LibraryDetailUI ctrl-click preview", function()
	it("hands the stored source straight to the dressing room", function()
		local got
		assert.is_true(LibraryDetailUI.DressUpSource({ source = 211091 },
			function(id) got = id end))
		assert.equal(211091, got)
	end)

	it("does nothing for an empty slot", function()
		local called = false
		local function Note() called = true end
		assert.is_false(LibraryDetailUI.DressUpSource({ empty = true }, Note))
		assert.is_false(LibraryDetailUI.DressUpSource({ source = 0 }, Note))
		assert.is_false(LibraryDetailUI.DressUpSource(nil, Note))
		assert.is_false(called)
	end)
end)
