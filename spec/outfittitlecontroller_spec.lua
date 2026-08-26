local Controller = require("OutfitTitleController")

local function NewController(active)
	local set = {}
	local model = {
		Count = function() return 2 end,
		Choose = function() return 12 end,
		Get = function() return { [12] = true } end,
		Record = function(_, outfitID, titleID) table.insert(set, { outfitID, titleID }) end,
	}
	local controller = Controller.New({
		model = model,
		char = {},
		getActiveOutfitID = function() return active.value end,
		getCurrentTitle = function() return 4 end,
		setCurrentTitle = function(id) table.insert(set, id) end,
		knownTitles = function() return { [12] = true } end,
	})
	return controller, set
end

describe("OutfitTitleController", function()
	it("keeps the outfit preview beside its title picker", function()
		local config, shown, hidden
		local controller = Controller.New({
			model = { Get = function() return {} end }, char = {},
			picker = { BuildItems = function() return {} end },
			getNumTitles = function() return 0 end,
			isTitleKnown = function() return false end,
			getTitleName = function() end,
			playerName = function() return "Bitrot" end,
			outfitName = function() return "Jester" end,
			openSearchPicker = function(value) config = value end,
			showOutfitPreview = function(owner, outfitID, label)
				shown = { owner, outfitID, label }
			end,
			hideOutfitPreview = function() hidden = true end,
		})

		controller:OpenPicker(37)
		local owner = {}
		config.onOpen(owner)
		config.onClose()

		assert.same({ owner, 37, "Choosing titles for Jester" }, shown)
		assert.is_true(hidden)
	end)

	it("rotates during a Mogtrot outfit click", function()
		local active = { value = 7 }
		local controller, set = NewController(active)
		assert.is_true(controller:OnOutfitClick(8))
		assert.same({ 12, { 8, 12 } }, set)
	end)

	it("does nothing when the click cannot set a title", function()
		local active = { value = 7 }
		local controller, set = NewController(active)
		controller.canSetTitle = function() return false end
		assert.is_false(controller:OnOutfitClick(8))
		assert.same({}, set)
	end)
end)

describe("OutfitTitleController fallback", function()
	local function Choose(mode, pin, known)
		local chosen
		local controller = Controller.New({
			model = { Choose = function() end, Get = function() return {} end },
			char = { titles = {}, titleRotation = {} },
			account = { titleFallbackMode = mode, fallbackTitleID = pin },
			getActiveOutfitID = function() return 8 end,
			getCurrentTitle = function() return 2 end,
			setCurrentTitle = function(id) chosen = id end,
			knownTitles = function() return known end,
			random = function(n) return n end,
		})
		controller:OnOutfitClick(8)
		return chosen
	end

	it("chooses a random known title when no linked title is eligible", function()
		assert.equal(9, Choose("random", nil, { [2] = true, [9] = true }))
	end)

	it("clears the title when configured", function()
		assert.equal(-1, Choose("clear", nil, { [2] = true, [9] = true }))
	end)

	it("uses a known pin and retains an unknown pin while falling back", function()
		assert.equal(5, Choose("pinned", 5, { [2] = true, [5] = true }))
		assert.equal(9, Choose("pinned", 5, { [2] = true, [9] = true }))
	end)

	it("pins only the numeric title ID", function()
		local account = {}
		local config
		local controller = Controller.New({
			model = {}, char = {}, account = account,
			picker = { BuildItems = function() return { { titleID = 5, name = "Elder Mog" } } end },
			getNumTitles = function() return 1 end,
			isTitleKnown = function() return true end,
			getTitleName = function() return "Elder %s" end,
			playerName = function() return "Mog" end,
			openSearchPicker = function(value) config = value end,
		})
		controller:OpenFallbackPicker()
		config.buttons[1].onClick({ config.items[1] })
		assert.equal(5, account.fallbackTitleID)
		assert.is_nil(account.fallbackTitleName)
	end)
end)
