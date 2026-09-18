local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local CharacterModelPool = {}
CharacterModelPool.__index = CharacterModelPool

function CharacterModelPool.New(limit, holder)
	return setmetatable({
		limit = limit,
		holder = holder,
		entries = {},
	}, CharacterModelPool)
end

function CharacterModelPool:Holder()
	return self.holder
end

local function Add(self)
	local entry = {}
	self.entries[#self.entries + 1] = entry
	return entry
end

function CharacterModelPool:Release(card)
	for _, entry in ipairs(self.entries) do
		if entry.card == card then
			entry.card = nil
			if entry.key == nil then
				entry.actor = nil
				entry.note = nil
			end
			return entry
		end
	end
end

function CharacterModelPool:Acquire(card, wantedKey)
	self:Release(card)

	local empty, oldest
	for _, entry in ipairs(self.entries) do
		if not entry.card and not entry.pane then
			if wantedKey and entry.key == wantedKey then
				entry.card = card
				return entry
			end
			if entry.key == nil then
				empty = empty or entry
			else
				oldest = oldest or entry
			end
		end
	end

	local entry = empty
	if not entry then
		if #self.entries < self.limit then
			entry = Add(self)
		else
			entry = oldest
		end
	end
	if not entry then return nil end
	entry.card = card
	return entry
end

function CharacterModelPool:Warm(wantedKey)
	local empty
	for _, entry in ipairs(self.entries) do
		if entry.key == wantedKey then return nil end
		if not entry.card and not entry.pane and entry.key == nil then
			empty = empty or entry
		end
	end
	if empty then return empty end
	if #self.entries >= self.limit then return nil end
	return Add(self)
end

function CharacterModelPool:WarmPane(wantedKey)
	local empty
	for _, entry in ipairs(self.entries) do
		if entry.pane and entry.key == wantedKey then return entry end
		if entry.pane and not entry.card and entry.key == nil then
			empty = empty or entry
		end
	end
	if empty then return empty end
	if #self.entries >= self.limit then return nil end
	local entry = Add(self)
	entry.pane = true
	return entry
end

function CharacterModelPool:Find(wantedKey)
	for _, entry in ipairs(self.entries) do
		if entry.key == wantedKey then return entry end
	end
end

function CharacterModelPool:FindPane(wantedKey)
	for _, entry in ipairs(self.entries) do
		if entry.pane and entry.key == wantedKey and entry.actor then return entry end
	end
end

function CharacterModelPool:BorrowPane(wantedKey)
	local entry = self:FindPane(wantedKey)
	if not entry then return nil end
	local previous = self.paneEntry
	self.paneEntry = entry
	return entry, previous
end

function CharacterModelPool:ReturnPane()
	local entry = self.paneEntry
	self.paneEntry = nil
	return entry
end

ns.CharacterModelPool = CharacterModelPool
return CharacterModelPool
