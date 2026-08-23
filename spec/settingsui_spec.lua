describe("SettingsUI", function()
	it("accepts non-negative whole pin-expiration days", function()
		local shared = {}
		local SettingsUI = assert(loadfile("SettingsUI.lua"))("Mogtrot", shared)
		assert.equal(0, SettingsUI.ParsePinDays("0"))
		assert.equal(365, SettingsUI.ParsePinDays("365"))
		assert.is_nil(SettingsUI.ParsePinDays(""))
		assert.is_nil(SettingsUI.ParsePinDays("1.5"))
		assert.is_nil(SettingsUI.ParsePinDays("-1"))
		assert.is_nil(SettingsUI.ParsePinDays("days"))
	end)

	it("passes search-tag intent to Blizzard button initializers", function()
		local shared = {}
		local SettingsUI = assert(loadfile("SettingsUI.lua"))("Mogtrot", shared)
		local initializers = {}
		_G.Settings = {
			VarType = { String = "string", Boolean = "boolean" },
			RegisterVerticalLayoutCategory = function()
				return {}, { AddInitializer = function(_, value) table.insert(initializers, value) end }
			end,
			RegisterProxySetting = function() return {} end,
			CreateCheckbox = function() end,
			CreateDropdown = function() end,
			CreateControlTextContainer = function() return { Add = function() end, GetData = function() return {} end } end,
			RegisterAddOnCategory = function() end,
		}
		_G.CreateSettingsButtonInitializer = function(_, _, _, _, addSearchTags)
			assert.is_not_nil(addSearchTags)
			return {}
		end
		_G.MogtrotDB = {}
		local addon = { Debug = function() end, Refresh = function() end }
		SettingsUI.Attach(addon, {
			Wear = { ShowInList = function() return false end, SetShowInList = function() end },
			Lint = { ShowInList = function() return false end, SetShowInList = function() end },
			getLiteMount = function() return false end,
			liteMountFallbackAvailable = function() return false end,
			fallbackModes = {},
			frame = { SettingsButton = { Enable = function() end, Icon = { SetVertexColor = function() end } } },
			titles = {
				FallbackTitleLabel = function() return "None chosen" end,
				FallbackMode = function() return "random" end,
				SetFallbackMode = function() end,
				OpenFallbackPicker = function() end,
			},
		})
		addon:RegisterSettings()
		assert.equal(1, #initializers)
	end)

	it("uses the pin-days text field instead of a fixed dropdown", function()
		local shared = {}
		local SettingsUI = assert(loadfile("SettingsUI.lua"))("Mogtrot", shared)
		local templates = {}
		_G.Settings = {
			VarType = { String = "string", Boolean = "boolean" },
			RegisterVerticalLayoutCategory = function()
				return {}, { AddInitializer = function() end }
			end,
			RegisterProxySetting = function() return {} end,
			CreateCheckbox = function() end,
			CreateDropdown = function() end,
			CreateControlTextContainer = function()
				return { Add = function() end, GetData = function() return {} end }
			end,
			CreateElementInitializer = function(template, data)
				table.insert(templates, { template = template, data = data })
				return {}
			end,
			RegisterAddOnCategory = function() end,
		}
		_G.CreateSettingsButtonInitializer = function() return {} end
		_G.MogtrotDB = { autoPinNewMountDays = 11 }
		local addon = { Debug = function() end, Refresh = function() end }
		SettingsUI.Attach(addon, {
			Wear = { ShowInList = function() return false end, SetShowInList = function() end },
			Lint = { ShowInList = function() return false end, SetShowInList = function() end },
			getLiteMount = function() return false end,
			liteMountFallbackAvailable = function() return false end,
			fallbackModes = {},
			frame = { SettingsButton = { Enable = function() end, Icon = { SetVertexColor = function() end } } },
			titles = {
				FallbackTitleLabel = function() return "None chosen" end,
				FallbackMode = function() return "random" end,
				SetFallbackMode = function() end,
				OpenFallbackPicker = function() end,
			},
		})
		addon:RegisterSettings()

		assert.equal(1, #templates)
		assert.equal("MogtrotPinDaysSettingTemplate", templates[1].template)
		assert.equal("11", templates[1].data.getText())
		templates[1].data.setText("23")
		assert.equal(23, MogtrotDB.autoPinNewMountDays)
		assert.is_false(templates[1].data.setText("1.5"))
		assert.equal(23, MogtrotDB.autoPinNewMountDays)
	end)
end)
