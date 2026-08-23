local MountPreference = require("MountPreference")

local TYPE = { Ground = 0, Flying = 1, Aquatic = 2, Dragonriding = 3 }
local TYPES = {
	[101] = { [TYPE.Ground] = true },
	[102] = { [TYPE.Flying] = true },
	[103] = { [TYPE.Aquatic] = true },
	[104] = { [TYPE.Dragonriding] = true },
	[105] = { [TYPE.Ground] = true, [TYPE.Flying] = true },
}

local function Pick(index)
	return function() return index end
end

local function Choose(candidates, situation, index, types)
	return MountPreference.Choose(candidates, types or TYPES, situation, TYPE, Pick(index or 1))
end

describe("MountPreference.Choose", function()
	it("prefers aquatic mounts only while submerged", function()
		local mountID, tier = Choose({ 101, 102, 103 }, { submerged = true })
		assert.equals(103, mountID)
		assert.equals("aquatic", tier)
	end)

	it("does not treat surface swimming as submerged", function()
		local mountID, tier = Choose({ 101, 102, 103 }, {
			swimming = true,
			flyable = true,
		})
		assert.equals(102, mountID)
		assert.equals("flying", tier)
	end)

	it("prefers skyriding in an advanced-flyable area", function()
		local mountID, tier = Choose({ 101, 102, 104 }, { advancedFlyable = true })
		assert.equals(104, mountID)
		assert.equals("dragonriding", tier)
	end)

	it("uses flying when an advanced-flyable area has no skyriding candidate", function()
		local mountID, tier = Choose({ 101, 102 }, { advancedFlyable = true })
		assert.equals(102, mountID)
		assert.equals("flying", tier)
	end)

	it("prefers flying in an ordinary flyable area", function()
		local mountID, tier = Choose({ 101, 102 }, { flyable = true })
		assert.equals(102, mountID)
		assert.equals("flying", tier)
	end)

	it("prefers ground where flight is unavailable", function()
		local mountID, tier = Choose({ 101, 102 }, {})
		assert.equals(101, mountID)
		assert.equals("ground", tier)
	end)

	it("allows a mount in every type it carries", function()
		assert.equals(105, Choose({ 101, 105 }, { flyable = true }))
		assert.equals(105, Choose({ 102, 105 }, {}))
	end)

	it("draws randomly within the preferred bucket", function()
		local types = {
			[201] = { [TYPE.Flying] = true },
			[202] = { [TYPE.Flying] = true },
			[203] = { [TYPE.Ground] = true },
		}
		local mountID = Choose({ 201, 202, 203 }, { flyable = true }, 2, types)
		assert.equals(202, mountID)
	end)

	it("falls back across every candidate when the preferred bucket is empty", function()
		local mountID, tier = Choose({ 101, 102 }, { submerged = true }, 2)
		assert.equals(102, mountID)
		assert.equals("all", tier)
	end)

	it("falls back across every candidate when classification is absent", function()
		local mountID, tier = MountPreference.Choose(
			{ 101, 102 }, nil, { flyable = true }, TYPE, Pick(2))
		assert.equals(102, mountID)
		assert.equals("all", tier)
	end)

	it("keeps unknown mounts available to the flat fallback", function()
		local mountID, tier = Choose({ 102, 999 }, { flyable = true }, 2)
		assert.equals(999, mountID)
		assert.equals("all", tier)
	end)

	it("returns nothing for no usable candidates", function()
		local mountID, tier = Choose({}, { flyable = true })
		assert.is_nil(mountID)
		assert.equals("all", tier)
	end)
end)
