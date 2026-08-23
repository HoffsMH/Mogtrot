local _, ns = ...
if type(ns) ~= "table" then ns = {} end

local Tree = ns.Tree or require("Tree")

-- Initializes and upgrades the account settings and per-character outfit data
-- saved by Mogtrot.
local Database = {}

local ACCOUNT_VERSION = 1
local CHAR_VERSION = 3
local DEFAULT_CATEGORIES = { "Tier", "Non-tier sets", "Simple" }

local function InitAccount(account)
	account.mountPins = account.mountPins or {}
	if account.autoPinNewMounts == nil then account.autoPinNewMounts = true end
	account.autoPinNewMountDays = account.autoPinNewMountDays or 7
	if account.previewEnabled == nil then account.previewEnabled = true end
	account.titleFallbackMode = account.titleFallbackMode or "random"
end

local function MigrateAccount(account)
	for _, record in pairs(account.mountPins) do
		if record.manual then
			record.permanent = true
		elseif record.acquiredAt and not record.expiresAt and not record.suppressed then
			record.expiresAt = record.acquiredAt
				+ (tonumber(account.autoPinNewMountDays) or 7) * 86400
		end
		record.manual = nil
		record.autoExpiresAt = nil
	end
	account.shufflePinnedMounts = nil
	account.fallbackTitleName = nil
	account.version = ACCOUNT_VERSION
end

local function InitCharacter(char)
	char.looks = char.looks or {}
	char.slots = char.slots or {}
	char.mounts = char.mounts or {}
	char.wear = char.wear or {}
	char.titles = char.titles or {}
	char.titleRotation = char.titleRotation or {}
	char.noPinnedShuffle = char.noPinnedShuffle or {}
	char.cats = char.cats or {}
	char.roots = char.roots or {}
	char.assign = char.assign or {}
end

local function HasSavedTree(char)
	return char.nextID ~= nil
		or char.cats ~= nil
		or char.roots ~= nil
		or char.assign ~= nil
end

function Database.MigrateOrInit(account, char)
	account = account or {}
	char = char or {}

	InitAccount(account)
	if account.version == nil or account.version == ACCOUNT_VERSION then
		MigrateAccount(account)
	end

	local hadSavedTree = HasSavedTree(char)
	InitCharacter(char)

	local knownCharacter = char.version == 2 or char.version == CHAR_VERSION
	local legacyCharacter = char.version == nil and hadSavedTree
	if knownCharacter or legacyCharacter then
		for outfitID, value in pairs(char.mounts) do
			if type(value) == "number" then
				char.mounts[outfitID] = { [value] = true }
			end
		end
		char.version = CHAR_VERSION
		return account, char
	end

	if char.version ~= nil then
		return account, char
	end

	for outfitID, value in pairs(char.mounts) do
		if type(value) == "number" then
			char.mounts[outfitID] = { [value] = true }
		end
	end
	char.version = CHAR_VERSION
	char.nextID = 1

	for _, name in ipairs(DEFAULT_CATEGORIES) do
		table.insert(char.roots, Tree.CreateCategoryNode(char, name, nil, false))
	end

	-- Keep the protected Unsorted category last in the main window.
	local unsortedID = Tree.CreateCategoryNode(char, Tree.UNSORTED_NAME, nil, true)
	table.insert(char.roots, unsortedID)
	return account, char
end

ns.Database = Database
return Database
