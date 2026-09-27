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

	it("uses the pin-days text field instead of a fixed dropdown", function()
		local shared = {}
		local SettingsUI = assert(loadfile("SettingsUI.lua"))("Mogtrot", shared)
		local templates = {}
		local proxySettings = {}
		_G.Settings = {
			VarType = { String = "string", Boolean = "boolean" },
			RegisterVerticalLayoutCategory = function()
				return {}, { AddInitializer = function() end }
			end,
			RegisterProxySetting = function(_, key, _, _, _, getter, setter)
				proxySettings[key] = { get = getter, set = setter }
				return {}
			end,
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
		_G.MogtrotDB = { pins = {
			mounts = { autoNew = true, days = 11, records = {} },
		} }
		local addon = { Debug = function() end, Refresh = function() end }
		SettingsUI.Attach(addon, {
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

		-- Mount pins, hearthstone pins, and archive retention.
		assert.equal(3, #templates)
		assert.equal("MogtrotPinDaysSettingTemplate", templates[1].template)
		assert.equal("11", templates[1].data.getText())
		templates[1].data.setText("23")
		assert.equal(23, MogtrotDB.pins.mounts.days)
		assert.is_false(templates[1].data.setText("1.5"))
		assert.equal(23, MogtrotDB.pins.mounts.days)
		assert.is_true(templates[1].data.setText("0"))
		assert.equal("0", templates[1].data.getText())
		assert.equal(0, MogtrotDB.pins.mounts.days)

		local autoPin = proxySettings.MOGTROT_AUTO_PIN_MOUNTS
		assert.is_true(autoPin.get())
		assert.is_true(autoPin.set(false))
		assert.is_false(MogtrotDB.pins.mounts.autoNew)
	end)
end)

describe("SettingsUI sections", function()
	local rows, proxies, dropdowns, addon

	before_each(function()
		local SettingsUI = assert(loadfile("SettingsUI.lua"))("Mogtrot", {})
		rows, proxies, dropdowns = {}, {}, {}
		local function Row(value) table.insert(rows, value) end
		_G.Settings = {
			VarType = { String = "string", Boolean = "boolean" },
			RegisterVerticalLayoutCategory = function()
				return {}, { AddInitializer = function(_, initializer) Row(initializer.row) end }
			end,
			RegisterProxySetting = function(_, key, _, name, default, getter, setter)
				proxies[key] = { name = name, default = default, get = getter, set = setter }
				return { row = name, key = key }
			end,
			CreateCheckbox = function(_, setting, tooltip)
				proxies[setting.key].tooltip = tooltip
				Row(setting.row)
			end,
			CreateDropdown = function(_, setting, options)
				dropdowns[setting.key] = options
				Row(setting.row)
			end,
			CreateControlTextContainer = function()
				local data = {}
				return {
					Add = function(_, value, label) table.insert(data, { value = value, label = label }) end,
					GetData = function() return data end,
				}
			end,
			CreateElementInitializer = function(_, data) return { row = data.name } end,
			RegisterAddOnCategory = function() end,
		}
		_G.CreateSettingsButtonInitializer = function(name) return { row = name } end
		_G.CreateSettingsListSectionHeaderInitializer = function(name)
			return { row = "# " .. name }
		end
		_G.MogtrotDB = { pins = {
			mounts = { autoNew = true, days = 7, records = {} },
			hearthstones = { autoNew = true, days = 0, records = {} },
		} }
		addon = { Debug = function() end, Refresh = function() end }
		function addon.HearthFallbackMode() return MogtrotDB.hearthFallbackMode or "pinned" end
		function addon.SetHearthFallbackMode(_, value) MogtrotDB.hearthFallbackMode = value end
		SettingsUI.Attach(addon, {
			Lint = { ShowInList = function() return false end, SetShowInList = function() end },
			liteMountFallbackAvailable = function() return false end,
			fallbackModes = {},
			frame = { SettingsButton = { Enable = function() end, Icon = { SetVertexColor = function() end } } },
			titles = {
				FallbackTitleLabel = function() return "None chosen" end,
				FallbackMode = function() return "random" end,
				SetFallbackMode = function() end,
				OpenFallbackPicker = function() end,
			},
			minimap = { IsShown = function() return true end, SetShown = function() end },
		})
		addon:RegisterSettings()
	end)

	after_each(function()
		_G.Settings = nil
		_G.CreateSettingsButtonInitializer = nil
		_G.CreateSettingsListSectionHeaderInitializer = nil
		_G.MogtrotDB = nil
	end)

	it("groups every row under its section header, in order", function()
		assert.same({
			"# General",
			"Show minimap button",
			"Show action bar setup icons",
			"Quiet mode",
			"# Outfit list",
			"Show outfit completeness in list",
			"# Mounts",
			"Summon fallback",
			"Match target's mount",
			"Auto-pin new mounts",
			"Mount pins expire in",
			"# Hearthstones",
			"If no hearthstone is linked",
			"Auto-pin new hearthstones",
			"Hearthstone pins expire in",
			"# Titles",
			"If no title is linked",
			"Pinned title",
			"# Library",
			"Archived snapshots expire after",
		}, rows)
	end)

	-- The saved key is absent until changed, which shows the icons.
	it("shows the action bar setup icons by default", function()
		assert.is_true(proxies.MOGTROT_SHOW_MACRO_CONTROLS.default)
	end)

	it("matches the target's mount by default", function()
		local setting = proxies.MOGTROT_MATCH_TARGET_MOUNT
		assert.is_true(setting.default)
		assert.is_nil(setting.tooltip:find("off by default", 1, true))
	end)

	it("offers the hearthstone fallback the summon fallback offers", function()
		local setting = proxies.MOGTROT_HEARTH_FALLBACK
		assert.equals("pinned", setting.default)
		local values = {}
		for _, option in ipairs(dropdowns.MOGTROT_HEARTH_FALLBACK()) do
			table.insert(values, option.value)
		end
		assert.same({ "random", "pinned", "off" }, values)

		assert.equals("pinned", setting.get())
		setting.set("off")
		assert.equals("off", MogtrotDB.hearthFallbackMode)
		assert.equals("off", setting.get())
	end)

	it("binds quiet mode to the saved flag the slash command toggles", function()
		local setting = proxies.MOGTROT_QUIET
		assert.is_false(setting.default)
		assert.is_false(setting.get())
		setting.set(true)
		assert.is_true(MogtrotDB.quiet)
		MogtrotDB.quiet = false
		assert.is_false(setting.get())
		assert.truthy(setting.tooltip:find("chat", 1, true))
		assert.truthy(setting.tooltip:find("pop-up", 1, true))
	end)
end)

describe("SettingsUI layout", function()
	it("puts the pin-days control in Blizzard's own control column", function()
		local file = assert(io.open("SettingsUI.xml", "r"))
		local body = file:read("*a")
		file:close()
		-- Blizzard's SettingsCheckboxControlMixin, slider and checkbox-with-
		-- control mixins all anchor LEFT to the row's CENTER at -80. A row that
		-- picks its own offset starts a second column, which is visible in the
		-- panel and invisible everywhere else.
		local offset = body:match('<Anchor point="LEFT" relativePoint="CENTER" x="(%-?%d+)"/>')
		assert.equal("-80", offset)
	end)
end)
