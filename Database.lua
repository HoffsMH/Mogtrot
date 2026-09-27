local _, ns = ...
if type(ns) ~= "table" then ns = {} end

local Tree = ns.Tree or require("Tree")
local CategoryColor = ns.CategoryColor or require("CategoryColor")
local Library = ns.Library or require("Library")

-- Initializes and upgrades the account settings and per-character outfit data
-- saved by Mogtrot.
--
-- Targets: account version 3 (generic pin domains, outfit library), character version 8
-- (link maps, pin opt-outs, rotations, worn looks apart from definitions, definitions
-- re-read once more). Migration order matters: version
-- checks gate everything; legacy records are normalized before keys move;
-- old keys are deleted only after a successful move; the version field is
-- written last. Unsupported future versions return their stores untouched -
-- composition gates on that instead of lazily re-creating nested structures.
local Database = {}

local ACCOUNT_VERSION = 3
local CHAR_VERSION = 8
local DEFAULT_CATEGORIES = { "Tier", "Non-tier sets", "Simple" }

-- Only absent values fall back to defaults: false and 0 are caller choices.
-- A mount pin is a shortcut you refresh; a hearthstone pin is a choice about
-- which stone belongs with a look, and that does not go stale, so it never
-- expires unless somebody asks it to.
local MOUNT_PIN_DAYS = 7
local HEARTHSTONE_PIN_DAYS = 0

local function DefaultPinDomain(domain, days)
	if domain == nil then
		return { autoNew = true, days = days, records = {} }
	end
	if domain.records == nil then domain.records = {} end
	if domain.autoNew == nil then domain.autoNew = true end
	if domain.days == nil then domain.days = days end
	return domain
end

local function EnsurePinDomains(account)
	local pins = account.pins
	if pins == nil then
		pins = {}
		account.pins = pins
	end
	pins.mounts = DefaultPinDomain(pins.mounts, MOUNT_PIN_DAYS)
	pins.hearthstones = DefaultPinDomain(pins.hearthstones, HEARTHSTONE_PIN_DAYS)
	return pins
end

local function InitAccount(account)
	if account.previewEnabled == nil then account.previewEnabled = true end
	if account.hideEmptyCategories == nil then account.hideEmptyCategories = false end
	-- The setter writes only true or false, so nil means never changed.
	if account.matchTargetMount == nil then account.matchTargetMount = true end
	account.minimap = account.minimap or {}
	if account.minimap.hide == nil then account.minimap.hide = false end
	account.titleFallbackMode = account.titleFallbackMode or "random"
	-- What the hearth key does with nothing linked; see HearthPick.Mode.
	account.hearthFallbackMode = account.hearthFallbackMode or "pinned"
	-- How long an archived snapshot is kept. Zero never expires, which is how
	-- somebody who keeps everything says so.
	if account.archiveDays == nil then account.archiveDays = 30 end
	-- Where the snap pop-up sits; dragging it rewrites this.
	local snap = account.snapConfirmPosition
	if type(snap) ~= "table" or type(snap.point) ~= "string"
		or type(snap.relPoint) ~= "string" or type(snap.x) ~= "number"
		or type(snap.y) ~= "number" then
		account.snapConfirmPosition = { point = "TOP", relPoint = "TOP", x = 0, y = -140 }
	end
	EnsurePinDomains(account)
	-- Additive and self-gating: a library from a newer build is left alone.
	Library.Migrate(account)
end

-- Normalizes legacy v1 pin records in place: manual pins become permanent,
-- automatic pins with only an autoExpiresAt become fixed expirations. The
-- legacy fields themselves are removed. Old autoPinNewMountDays governs the
-- fallback window exactly as before.
local function NormalizeLegacyMountPinRecords(account)
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
end

-- Moves account v1 mount-pin state into pins.mounts. Returns false when a
-- mixed source/destination collision makes the move unsafe; the caller then
-- aborts the whole account migration without mutating anything. An identical
-- reference (an interrupted earlier migration) is allowed and idempotent.
local function MoveMountPins(account, hadMountsDomain)
	local records = account.mountPins
	if records == nil then
		return true
	end
	local mounts = account.pins.mounts
	-- A records table that merely came from EnsurePinDomains' default is not
	-- a collision; only a pre-existing domain with different records is.
	if hadMountsDomain and mounts.records ~= records then
		return false
	end

	NormalizeLegacyMountPinRecords(account)

	mounts.records = records
	if account.autoPinNewMounts ~= nil then
		mounts.autoNew = account.autoPinNewMounts
	end
	if account.autoPinNewMountDays ~= nil then
		mounts.days = account.autoPinNewMountDays
	end

	-- Old keys go only after the move succeeded.
	account.mountPins = nil
	account.autoPinNewMounts = nil
	account.autoPinNewMountDays = nil
	return true
end

local function MigrateAccount(account, hadMountsDomain)
	if not MoveMountPins(account, hadMountsDomain) then
		return false
	end
	account.shufflePinnedMounts = nil
	account.fallbackTitleName = nil
	account.version = ACCOUNT_VERSION
	return true
end

local function InitCharacter(char)
	char.looks = char.looks or {}
	char.worn = char.worn or {}
	char.slots = char.slots or {}
	char.lookPending = char.lookPending or {}
	char.mounts = char.mounts or {}
	char.wear = char.wear or {}
	char.titles = char.titles or {}
	char.titleRotation = char.titleRotation or {}
	char.cats = char.cats or {}
	char.roots = char.roots or {}
	char.assign = char.assign or {}

	if char.hearthstones == nil then char.hearthstones = {} end
	local optOut = char.pinOptOut
	if optOut == nil then
		optOut = {}
		char.pinOptOut = optOut
	end
	optOut.mounts = optOut.mounts or {}
	optOut.hearthstones = optOut.hearthstones or {}
	local rotations = char.rotations
	if rotations == nil then
		rotations = {}
		char.rotations = rotations
	end
	rotations.hearthstones = rotations.hearthstones or {}
end

-- Moves character v4 noPinnedShuffle into pinOptOut.mounts. Same collision
-- contract as the account move: distinct source and destination abort, an
-- identical reference continues.
local function MoveNoPinnedShuffle(char)
	local moved = char.noPinnedShuffle
	if moved == nil then
		return true
	end
	local optOut = char.pinOptOut
	if optOut == nil then
		optOut = {}
		char.pinOptOut = optOut
	end
	if optOut.mounts ~= nil and optOut.mounts ~= moved then
		return false
	end
	optOut.mounts = moved
	char.noPinnedShuffle = nil
	return true
end

local function HasSavedTree(char)
	return char.nextID ~= nil
		or char.cats ~= nil
		or char.roots ~= nil
		or char.assign ~= nil
end

-- Normalizes saved category colors and converts old single-mount links to
-- sets. Shared by every supported pre-v5 character shape.
local function NormalizeCharacter(char)
	for _, cat in pairs(char.cats) do
		cat.color = CategoryColor.Normalize(cat.color)
	end
	for outfitID, value in pairs(char.mounts) do
		if type(value) == "number" then
			char.mounts[outfitID] = { [value] = true }
		end
	end
end

local function MigrateCharacter(char)
	local hadSavedTree = HasSavedTree(char)
	local knownCharacter = char.version == 2 or char.version == 3 or char.version == 4
		or char.version == 5 or char.version == 6 or char.version == 7
	local legacyCharacter = char.version == nil and hadSavedTree

	-- Collision check before any mutation: a distinct destination table for
	-- the noPinnedShuffle move aborts the whole character migration.
	if char.noPinnedShuffle ~= nil and not MoveNoPinnedShuffle(char) then
		return false
	end

	InitCharacter(char)

	if knownCharacter or legacyCharacter then
		NormalizeCharacter(char)
		-- Before v6 the wear capture wrote looks, and a slot the outfit leaves
		-- empty rendered equipped gear; v6's sweep could store a definition read
		-- before it had landed; before v8 a split shoulder's hidden side was
		-- stored as empty. Nothing says which, so the next sweep reads every
		-- definition again and clears this.
		char.rereadLooks = true
	else
		-- A fresh character can still carry old single-mount links.
		for outfitID, value in pairs(char.mounts) do
			if type(value) == "number" then
				char.mounts[outfitID] = { [value] = true }
			end
		end
		-- Fresh character: default category tree with protected Unsorted last.
		char.nextID = 1
		for _, name in ipairs(DEFAULT_CATEGORIES) do
			table.insert(char.roots, Tree.CreateCategoryNode(char, name, nil, false))
		end
		table.insert(char.roots, Tree.CreateCategoryNode(char, Tree.UNSORTED_NAME, nil, true))
	end

	char.version = CHAR_VERSION
	return true
end

-- Returns account, char. A store at an unsupported future version is
-- returned untouched so composition can gate on it; a migration collision
-- leaves that store unmutated at its old version.
function Database.MigrateOrInit(account, char)
	local accountOK
	if account == nil then
		account = {}
		InitAccount(account)
		account.version = ACCOUNT_VERSION
	elseif account.version == nil or account.version < ACCOUNT_VERSION then
		if account.version == nil or account.version == 1 then
			-- Collision probe first: never mutate an unsafe move.
			accountOK = true
			if account.mountPins ~= nil and account.pins ~= nil
				and account.pins.mounts ~= nil and account.pins.mounts.records ~= nil
				and account.pins.mounts.records ~= account.mountPins then
				accountOK = false
			end
		elseif account.version == 2 then
			-- v2 to v3 only adds the library, so nothing moves and nothing collides.
			accountOK = true
		else
			accountOK = false
		end
		if accountOK then
			local hadMountsDomain = account.pins ~= nil
				and account.pins.mounts ~= nil
			InitAccount(account)
			MigrateAccount(account, hadMountsDomain)
		end
	elseif account.version == ACCOUNT_VERSION then
		InitAccount(account)
	end

	if char == nil then
		char = {}
		MigrateCharacter(char)
	elseif char.version == nil or char.version < CHAR_VERSION then
		MigrateCharacter(char)
	end

	return account, char
end

ns.Database = Database
return Database
