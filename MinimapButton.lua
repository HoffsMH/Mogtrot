local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Opens Mogtrot from the minimap or Blizzard's addon compartment.
local MinimapButton = {}

local DEFAULT_ANGLE = 225

function MinimapButton.IconPath(addonName)
	return "Interface\\AddOns\\" .. addonName .. "\\Art\\MogtrotMinimap"
end

function MinimapButton.IsShown(account)
	return not (account.minimap and account.minimap.hide)
end

function MinimapButton.SetShown(account, shown)
	account.minimap = account.minimap or {}
	account.minimap.hide = not shown
end

function MinimapButton.CanDrag(parent, minimap)
	return parent == minimap
end

function MinimapButton.Coordinates(angle, width, height)
	local radians = math.rad(angle)
	return math.cos(radians) * (width / 2 + 5),
		math.sin(radians) * (height / 2 + 5)
end

function MinimapButton.Attach(Addon, deps)
	local mainWindow = deps.frame
	local iconPath = MinimapButton.IconPath(deps.addonName)
	local button = CreateFrame("Button", "MogtrotMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp")
	button:RegisterForDrag("LeftButton")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(22, 22)
	background:SetPoint("CENTER")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexture(iconPath)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.Icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local function Place(angle)
		angle = tonumber(angle) or DEFAULT_ANGLE
		local x, y = MinimapButton.Coordinates(angle, Minimap:GetWidth(), Minimap:GetHeight())
		button:ClearAllPoints()
		button:SetPoint("CENTER", Minimap, "CENTER", x, y)
		button.angle = angle
	end

	local function Toggle()
		if InCombatLockdown() then
			Addon:Warn("can't open in combat.")
			return
		end
		mainWindow:SetShown(not mainWindow:IsShown())
	end

	button:SetScript("OnClick", Toggle)
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Mogtrot")
		GameTooltip:AddLine("Left click: Toggle outfit list", 1, 1, 1)
		if MinimapButton.CanDrag(self:GetParent(), Minimap) then
			GameTooltip:AddLine("Drag: Move button", 1, 1, 1)
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	button:SetScript("OnDragStart", function(self)
		if not MinimapButton.CanDrag(self:GetParent(), Minimap) then return end
		self.dragging = true
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local x, y = GetCursorPosition()
			local angle = math.deg(math.atan2(y / scale - my, x / scale - mx))
			Place(angle)
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		if not self.dragging then return end
		self.dragging = nil
		self:SetScript("OnUpdate", nil)
		if not MogtrotDB then return end
		MogtrotDB.minimap = MogtrotDB.minimap or {}
		MogtrotDB.minimap.angle = self.angle
	end)

	Place(DEFAULT_ANGLE)
	button:Hide()

	if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		AddonCompartmentFrame:RegisterAddon({
			text = "Mogtrot",
			icon = iconPath,
			notCheckable = true,
			func = Toggle,
		})
	end

	local controller = {}
	function controller:Refresh()
		if not MogtrotDB then return end
		local state = MogtrotDB.minimap or {}
		Place(state.angle)
		button:SetShown(MinimapButton.IsShown(MogtrotDB))
	end
	function controller:IsShown()
		return MogtrotDB and MinimapButton.IsShown(MogtrotDB) or true
	end
	function controller:SetShown(shown)
		MinimapButton.SetShown(MogtrotDB, shown)
		button:SetShown(shown)
	end

	return controller
end

ns.MinimapButton = MinimapButton
return MinimapButton
