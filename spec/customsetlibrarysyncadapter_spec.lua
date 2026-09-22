local Adapter = require("CustomSetLibrarySyncAdapter")

describe("CustomSetLibrarySyncAdapter", function()
	it("converts Blizzard item lists without a Transmog frame", function()
		local api = {
			GetCustomSets = function() return { 9 } end,
			GetCustomSetInfo = function(id)
				assert.equal(9, id)
				return "Azure", 123
			end,
			GetCustomSetItemTransmogInfoList = function(id)
				assert.equal(9, id)
				return { [1] = { appearanceID = 456 } }
			end,
		}
		local sets, trustworthy = Adapter.ReadSets(api, function(list)
			return { [1] = { list[1].appearanceID, 0, 0 } }
		end)
		assert.is_true(trustworthy)
		assert.same({ { customSetID = 9, name = "Azure", icon = 123,
			look = { [1] = { 456, 0, 0 } } } }, sets)
	end)

	it("marks a successful empty enumeration as trustworthy", function()
		local sets, trustworthy = Adapter.ReadSets({
			GetCustomSets = function() return {} end,
			GetCustomSetInfo = function() end,
			GetCustomSetItemTransmogInfoList = function() end,
		}, function() end)
		assert.same({}, sets)
		assert.is_true(trustworthy)
	end)
end)
