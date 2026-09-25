-- The preview is frame code with no pure layer, so what matters here is read
-- from the source the way picker_parity_spec reads the two pickers.
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

describe("outfit preview source", function()
	it("shows the last worn appearance before the outfit's definition", function()
		local body = PREVIEW:match("local function RenderOutfitPreview.-\nend")
		assert.is_truthy(body:find("(worn and worn[outfitID]) or (looks and looks[outfitID])", 1, true))
	end)
end)
