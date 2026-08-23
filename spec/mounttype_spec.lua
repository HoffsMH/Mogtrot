local MountType = require("MountType")

local TYPE = { Ground = 0, Flying = 1, Aquatic = 2, Dragonriding = 3 }

describe("MountType.Classify", function()
	it("classifies ground", function()
		assert.same({ [TYPE.Ground] = true }, MountType.Classify(230, TYPE))
	end)

	it("classifies aquatic and amphibious types", function()
		assert.same({ [TYPE.Aquatic] = true }, MountType.Classify(232, TYPE))
		assert.same({ [TYPE.Ground] = true, [TYPE.Aquatic] = true },
			MountType.Classify(412, TYPE))
	end)

	it("classifies flying and skyriding combinations", function()
		assert.same({ [TYPE.Flying] = true }, MountType.Classify(242, TYPE))
		assert.same({ [TYPE.Flying] = true, [TYPE.Dragonriding] = true },
			MountType.Classify(424, TYPE))
	end)

	it("classifies multi-situation mounts", function()
		assert.same({
			[TYPE.Flying] = true,
			[TYPE.Aquatic] = true,
			[TYPE.Dragonriding] = true,
		}, MountType.Classify(436, TYPE))
	end)

	it("leaves unknown and internal types unclassified", function()
		assert.is_nil(MountType.Classify(999, TYPE))
		assert.is_nil(MountType.Classify(426, TYPE))
		assert.is_nil(MountType.Classify(230, nil))
	end)
end)
