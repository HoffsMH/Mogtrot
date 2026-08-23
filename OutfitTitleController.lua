local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Connects outfit title links to the character title APIs and title picker.
local OutfitTitleController = {}

local function DefaultKnownTitles()
	local known = {}
	for titleID = 1, GetNumTitles() do
		if IsTitleKnown(titleID) then known[titleID] = true end
	end
	return known
end

local function RandomKnown(known, currentTitleID, random)
	local ids = {}
	for titleID in pairs(known) do
		if titleID ~= currentTitleID then table.insert(ids, titleID) end
	end
	if #ids == 0 and known[currentTitleID] then return currentTitleID end
	if #ids == 0 then return nil end
	table.sort(ids)
	return ids[(random or math.random)(#ids)]
end

function OutfitTitleController.New(deps)
	local controller = {
		model = deps.model,
		picker = deps.picker,
		char = deps.char,
		account = deps.account or {},
		getCurrentTitle = deps.getCurrentTitle,
		setCurrentTitle = deps.setCurrentTitle,
		knownTitles = deps.knownTitles or DefaultKnownTitles,
		random = deps.random or math.random,
		getNumTitles = deps.getNumTitles,
		isTitleKnown = deps.isTitleKnown,
		getTitleName = deps.getTitleName,
		openSearchPicker = deps.openSearchPicker,
		refresh = deps.refresh,
		outfitName = deps.outfitName,
		canSetTitle = deps.canSetTitle or function() return true end,
		playerName = deps.playerName,
	}
	return setmetatable(controller, { __index = OutfitTitleController })
end

function OutfitTitleController:BindStores(account, char)
	self.account = account
	self.char = char
end

function OutfitTitleController:Count(outfitID)
	return self.model.Count(self.char, outfitID)
end

function OutfitTitleController:Copy(fromOutfitID, toOutfitID, merge)
	if self:Count(fromOutfitID) == 0 then return false end
	self.model.Copy(self.char, fromOutfitID, toOutfitID, merge)
	if self.refresh then self.refresh() end
	return true
end

function OutfitTitleController:Clear(outfitID)
	if self:Count(outfitID) == 0 then return false end
	self.model.Clear(self.char, outfitID)
	if self.refresh then self.refresh() end
	return true
end

function OutfitTitleController:ChooseFallback(known, currentTitleID)
	local mode = self.account.titleFallbackMode or "random"
	if mode == "clear" then return -1 end
	if mode == "pinned" and known[self.account.fallbackTitleID] then
		return self.account.fallbackTitleID
	end
	return RandomKnown(known, currentTitleID, self.random)
end

function OutfitTitleController:OnOutfitClick(outfitID)
	if not outfitID then return false end
	if not self.canSetTitle() then return false end
	local known = self.knownTitles()
	local current = self.getCurrentTitle()
	local titleID = self.model.Choose(self.char, outfitID, known, current, self.random)
	if not titleID then titleID = self:ChooseFallback(known, current) end
	if titleID == nil then return false end
	self.setCurrentTitle(titleID)
	if outfitID and titleID ~= -1 and self.model.Get(self.char, outfitID)[titleID] then
		self.model.Record(self.char, outfitID, titleID)
	end
	return true
end

function OutfitTitleController:OpenPicker(outfitID)
	local items = self.picker.BuildItems(self.getNumTitles(), self.isTitleKnown,
		self.getTitleName, self.model.Get(self.char, outfitID), self.playerName())
	self.openSearchPicker({
		title = ("Titles for %s"):format(self.outfitName(outfitID)),
		searchHint = "Search titles",
		emptyText = "No known titles match.",
		multi = true,
		items = items,
		buttons = {{ text = "Apply", width = 90, allowEmpty = true, onClick = function(chosen)
			self.picker.Apply(self.model, self.char, outfitID, chosen)
			if self.refresh then self.refresh() end
		end }},
	})
end

function OutfitTitleController:FallbackMode()
	return self.account.titleFallbackMode or "random"
end

function OutfitTitleController:SetFallbackMode(mode)
	if mode == "random" or mode == "clear" or mode == "pinned" then
		self.account.titleFallbackMode = mode
	end
end

function OutfitTitleController:FallbackTitleLabel()
	if not self.account.fallbackTitleID then return "None chosen" end
	return self.picker.DisplayName(self.getTitleName(self.account.fallbackTitleID), self.playerName())
end

function OutfitTitleController:OpenFallbackPicker()
	local linked = self.account.fallbackTitleID and { [self.account.fallbackTitleID] = true } or {}
	local items = self.picker.BuildItems(self.getNumTitles(), self.isTitleKnown,
		self.getTitleName, linked, self.playerName())
	self.openSearchPicker({
		title = "Choose pinned title",
		searchHint = "Search titles",
		emptyText = "No known titles match.",
		items = items,
		buttons = {{ text = "Choose", width = 90, onClick = function(chosen)
			local item = chosen[1]
			if not item then return end
			self.account.fallbackTitleID = item.titleID
			self.account.titleFallbackMode = "pinned"
		end }},
	})
end

function OutfitTitleController:Clean(liveOutfits)
	self.model.Clean(self.char, liveOutfits)
end

function OutfitTitleController.Attach(Addon, deps)
	local controller = OutfitTitleController.New({
		model = deps.model,
		picker = deps.picker,
		char = MogtrotCharDB,
		account = MogtrotDB,
		getCurrentTitle = GetCurrentTitle,
		setCurrentTitle = SetCurrentTitle,
		getNumTitles = GetNumTitles,
		isTitleKnown = IsTitleKnown,
		getTitleName = GetTitleName,
		openSearchPicker = function(config) ns.OpenSearchPicker(config) end,
		refresh = function() Addon:Refresh() end,
		outfitName = function(outfitID)
			local info = Addon.outfitsByID and Addon.outfitsByID[outfitID]
			return info and info.name or "outfit"
		end,
		canSetTitle = function() return not InCombatLockdown() end,
		playerName = function() return UnitName("player") or "" end,
	})
	return controller
end

ns.OutfitTitleController = OutfitTitleController
return OutfitTitleController
