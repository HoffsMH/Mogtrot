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
				entry.borrowed = nil
			end
			return entry
		end
	end
end

-- The free card body of this key that rank(entry) scores highest, first
-- found on a tie. rank is optional.
local function BestOfKey(self, wantedKey, rank)
	local best, bestRank
	for _, entry in ipairs(self.entries) do
		if not entry.card and not entry.pane and not entry.staging and wantedKey ~= nil
			and entry.key == wantedKey then
			local score = rank and rank(entry) or 0
			if best == nil or score > bestRank then best, bestRank = entry, score end
		end
	end
	return best
end

-- rank(entry) is optional and picks among several free bodies of the key,
-- such as the same shape lent by different donors.
function CharacterModelPool:Acquire(card, wantedKey, rank)
	self:Release(card)

	local keyed = BestOfKey(self, wantedKey, rank)
	if keyed then
		keyed.card = card
		return keyed
	end

	-- At the cap a body built on your unit goes before a borrowed one: it can
	-- be built again anywhere, and a borrowed one needs its donor back.
	local empty, oldest, oldestBorrowed
	for _, entry in ipairs(self.entries) do
		if not entry.card and not entry.pane and not entry.staging then
			if entry.key == nil then
				empty = empty or entry
			elseif entry.borrowed then
				oldestBorrowed = oldestBorrowed or entry
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
			entry = oldest or oldestBorrowed
		end
	end
	if not entry then return nil end
	entry.card = card
	return entry
end

-- An entry to build one more body of this key into, or nil once the key
-- already has want bodies (default 1) cards can stand in. Pane twins do not
-- count: no card can take one. With a donor, that donor also gets a body of
-- the key of its own, unless rank is given and donorRank does not beat the
-- best body of the key already held.
function CharacterModelPool:Warm(wantedKey, want, donor, rank, donorRank)
	want = want or 1
	local empty, have, mine, best = nil, 0, 0, nil
	for _, entry in ipairs(self.entries) do
		if entry.key == wantedKey and not entry.pane then
			have = have + 1
			if donor ~= nil and entry.donorGUID == donor then mine = mine + 1 end
			if rank then
				local score = rank(entry)
				if best == nil or score > best then best = score end
			end
		end
		if not entry.card and not entry.pane and entry.key == nil then
			empty = empty or entry
		end
	end
	local better = best == nil or (donorRank or 0) > best
	local ownFirst = donor ~= nil and mine == 0 and better
	if have >= want and not ownFirst then return nil end
	if empty then return empty end
	if #self.entries >= self.limit then return nil end
	return Add(self)
end

-- No entry is free to build a body into, so a new donor would add nothing.
function CharacterModelPool:Full()
	if #self.entries < self.limit then return false end
	for _, entry in ipairs(self.entries) do
		if not entry.card and not entry.pane and entry.key == nil then return false end
	end
	return true
end

-- Whether any borrowed body a card can stand in is ready.
function CharacterModelPool:HoldsBorrowed()
	for _, entry in ipairs(self.entries) do
		if entry.borrowed and entry.key ~= nil and entry.actor and not entry.pane
			and not entry.staging then
			return true
		end
	end
	return false
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

-- How many bodies cards can stand in carry each key, held or free. Pane
-- twins are left out.
--
-- Find answers whether one exists anywhere, which is the wrong question for
-- anyone deciding whether more need building: Acquire will not hand over a
-- body another card is standing in, so two cards wanting one key need two
-- bodies. Counting existence instead of supply declares the work finished
-- while a card is still waiting for its own.
function CharacterModelPool:CountByKey()
	local counts = {}
	for _, entry in ipairs(self.entries) do
		if entry.key ~= nil and not entry.pane and not entry.staging then
			counts[entry.key] = (counts[entry.key] or 0) + 1
		end
	end
	return counts
end

function CharacterModelPool:FindPane(wantedKey)
	for _, entry in ipairs(self.entries) do
		if entry.pane and entry.key == wantedKey and entry.actor and not entry.staging then
			return entry
		end
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

-- A free built body of exactly this key, now held by card; never builds.
-- rank(entry) is optional, as for Acquire.
function CharacterModelPool:Take(card, wantedKey, rank)
	local best, bestRank
	for _, entry in ipairs(self.entries) do
		if not entry.card and not entry.pane and not entry.staging and entry.actor
			and wantedKey ~= nil and entry.key == wantedKey then
			local score = rank and rank(entry) or 0
			if best == nil or score > bestRank then best, bestRank = entry, score end
		end
	end
	if best then best.card = card end
	return best
end

-- A body built while its donor is still being taken carries staging (the
-- donor's GUID) and is hidden from cards, the pane and the counts until
-- Settle. Warm still counts it, so the same donor does not build it twice.
function CharacterModelPool:Settle(donor)
	for _, entry in ipairs(self.entries) do
		if donor ~= nil and entry.staging == donor then entry.staging = nil end
	end
end

-- Empties every body staged for this donor so another can be built into it.
function CharacterModelPool:Drop(donor)
	for _, entry in ipairs(self.entries) do
		if donor ~= nil and entry.staging == donor then
			entry.staging, entry.key, entry.actor = nil, nil, nil
			entry.borrowed, entry.donorRace, entry.donorGUID, entry.donorFaction = nil, nil, nil, nil
		end
	end
end

ns.CharacterModelPool = CharacterModelPool
return CharacterModelPool
