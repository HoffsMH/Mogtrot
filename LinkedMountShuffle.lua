local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = {} end

local LinkedMountShuffle = {}
LinkedMountShuffle.__index = LinkedMountShuffle

local function SortedCopy(candidateMountIDs)
	local sorted = {}
	for _, mountID in ipairs(candidateMountIDs or {}) do
		table.insert(sorted, mountID)
	end
	table.sort(sorted)
	return sorted
end

local function Signature(candidateMountIDs)
	local parts = {}
	for index, mountID in ipairs(candidateMountIDs) do parts[index] = tostring(mountID) end
	return table.concat(parts, ",")
end

function LinkedMountShuffle.New(random, pendingSeconds)
	return setmetatable({ random = random, pendingSeconds = pendingSeconds or 10 },
		LinkedMountShuffle)
end

local STATE_FIELDS = {
	"outfitID", "candidateSignature", "remainingMountIDs", "lastMountID", "pending",
}

local function CopyState(source, target)
	for _, key in ipairs(STATE_FIELDS) do
		local value = source and source[key]
		if type(value) == "table" then
			local copy = {}
			for innerKey, innerValue in pairs(value) do copy[innerKey] = innerValue end
			value = copy
		end
		target[key] = value
	end
	return target
end

function LinkedMountShuffle.FromState(state, random, pendingSeconds)
	return CopyState(state, LinkedMountShuffle.New(random, pendingSeconds))
end

function LinkedMountShuffle:State()
	return CopyState(self, {})
end

function LinkedMountShuffle:Refill(candidateMountIDs)
	local remainingMountIDs = SortedCopy(candidateMountIDs)
	for index = #remainingMountIDs, 2, -1 do
		local other = self.random(index)
		remainingMountIDs[index], remainingMountIDs[other] =
			remainingMountIDs[other], remainingMountIDs[index]
	end

	if #remainingMountIDs >= 2
		and remainingMountIDs[#remainingMountIDs] == self.lastMountID then
		remainingMountIDs[1], remainingMountIDs[#remainingMountIDs] =
			remainingMountIDs[#remainingMountIDs], remainingMountIDs[1]
	end
	self.remainingMountIDs = remainingMountIDs
end

function LinkedMountShuffle:Expire(now)
	if self.pending and now - self.pending.stagedAt >= self.pendingSeconds then
		self.pending = nil
	end
end

function LinkedMountShuffle:Choose(outfitID, candidateMountIDs, now)
	self:Expire(now)
	local sorted = SortedCopy(candidateMountIDs)
	local signature = Signature(sorted)
	if self.outfitID ~= outfitID then
		self.outfitID = outfitID
		self.remainingMountIDs = nil
		self.lastMountID = nil
		self.pending = nil
	end
	if self.candidateSignature ~= signature then
		self.remainingMountIDs = nil
		self.pending = nil
	end
	self.candidateSignature = signature

	if #sorted == 0 then return nil end
	if not self.remainingMountIDs or #self.remainingMountIDs == 0 then
		self:Refill(sorted)
	end

	return self.remainingMountIDs[#self.remainingMountIDs]
end

function LinkedMountShuffle:Select(outfitID, plan, now)
	if plan.action == "summon" and plan.from == "outfit" then
		plan.mountID = self:Choose(outfitID, plan.viableCandidates, now)
	else
		self.pending = nil
	end
	return plan
end

function LinkedMountShuffle:Stage(outfitID, mountID, spellID, now)
	self.pending = {
		outfitID = outfitID,
		mountID = mountID,
		spellID = spellID,
		stagedAt = now,
	}
end

function LinkedMountShuffle:Sent(spellID, castGUID)
	local pending = self.pending
	if not pending or pending.spellID ~= spellID then return false end
	pending.castGUID = castGUID
	return true
end

local function Matches(pending, spellID, castGUID)
	if not pending or pending.spellID ~= spellID then return false end
	return pending.castGUID == nil or pending.castGUID == castGUID
end

function LinkedMountShuffle:Confirm(spellID, castGUID, now)
	self:Expire(now)
	local pending = self.pending
	if not Matches(pending, spellID, castGUID) then return false end

	for index, mountID in ipairs(self.remainingMountIDs or {}) do
		if mountID == pending.mountID then
			table.remove(self.remainingMountIDs, index)
			self.lastMountID = mountID
			break
		end
	end
	self.pending = nil
	return true
end

function LinkedMountShuffle:Cancel(spellID, castGUID)
	if not Matches(self.pending, spellID, castGUID) then return false end
	self.pending = nil
	return true
end

function LinkedMountShuffle:ClearPending()
	self.pending = nil
end

ns.LinkedMountShuffle = LinkedMountShuffle
return LinkedMountShuffle
