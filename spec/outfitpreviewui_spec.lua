-- Most of the preview is frame code, so what matters there is read from the
-- source. The look choice and the pairing window's dock decision are pure and
-- called directly.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local PREVIEW = Read("OutfitPreviewUI.lua")

describe("outfit preview model setup", function()
	it("builds every preview through one builder", function()
		local builders = 0
		for _ in PREVIEW:gmatch('CreateFrame%("DressUpModel"') do
			builders = builders + 1
		end
		assert.equal(1, builders)
		local uses = 0
		for _ in PREVIEW:gmatch("BuildOutfitPreview%(\"") do uses = uses + 1 end
		assert.is_true(uses > 1, "OutfitPreviewUI.lua no longer shares its builder")
	end)

	it("leaves transmog choices off on a model that draws the player's face", function()
		-- Blizzard sets this flag only where a helm or a mannequin skin covers
		-- the head; on a bare player model it costs the face.
		assert.is_nil(PREVIEW:match("SetUseTransmogChoices"))
	end)
end)

describe("OutfitPreviewUI.PreviewLook", function()
	local OutfitPreviewUI = require("OutfitPreviewUI")

	it("shows the last worn appearance before the outfit's definition", function()
		local char = { worn = { [5] = "worn" }, looks = { [5] = "defined", [6] = "only" } }
		assert.equal("worn", OutfitPreviewUI.PreviewLook(char, 5))
		assert.equal("only", OutfitPreviewUI.PreviewLook(char, 6))
		assert.is_nil(OutfitPreviewUI.PreviewLook(char, 7))
		assert.is_nil(OutfitPreviewUI.PreviewLook({}, 5))
	end)
end)

describe("pairing window dock", function()
	local OutfitPreviewUI = require("OutfitPreviewUI")
	-- A pairing window spanning x 100..500 and y 200..600.
	local function Dock(x, y) return OutfitPreviewUI.PairingDock(x, y, 100, 500, 200, 600) end

	it("docks to the nearer of the left and right edges", function()
		assert.equal("left", (Dock(60, 400)))
		assert.equal("left", (Dock(250, 400)))
		assert.equal("right", (Dock(350, 400)))
		assert.equal("right", (Dock(700, 400)))
	end)

	it("never docks above or below the window", function()
		assert.equal("left", (Dock(200, 900)))
		assert.equal("right", (Dock(480, 900)))
		assert.equal("left", (Dock(150, -50)))
		assert.equal("right", (Dock(420, -50)))
	end)

	it("keeps the right edge on a tie", function()
		assert.equal("right", (Dock(300, 400)))
	end)

	it("places the preview along the edge where the cursor is, clamped", function()
		assert.equal(0.5, select(2, Dock(60, 400)))
		assert.equal(0, select(2, Dock(60, -50)))
		assert.equal(1, select(2, Dock(60, 900)))
	end)

	it("opens the chooser on the side the preview leaves free", function()
		assert.equal("left", OutfitPreviewUI.ChooserSide("right"))
		assert.equal("right", OutfitPreviewUI.ChooserSide("left"))
		assert.equal("left", OutfitPreviewUI.ChooserSide(nil))
	end)
end)

describe("main window left edge", function()
	local OutfitPreviewUI = require("OutfitPreviewUI")
	local function Frame(shown) return { IsShown = function() return shown end } end

	it("is the sidebar while it shows, so the preview docks beyond it", function()
		local window = Frame(true)
		window.Sidebar = Frame(true)
		assert.equal(window.Sidebar, OutfitPreviewUI.LeftEdge(window))
	end)

	it("is the window itself with no sidebar showing", function()
		local window = Frame(true)
		assert.equal(window, OutfitPreviewUI.LeftEdge(window))
		window.Sidebar = Frame(false)
		assert.equal(window, OutfitPreviewUI.LeftEdge(window))
	end)
end)
