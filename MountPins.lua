local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Tracks mounts the account acquired and the pins used by summon choices.
local MountPins = {}

MountPins.DefaultAutoPinDays = 7

local function Records(account)
	account.mountPins = account.mountPins or {}
	return account.mountPins
end

local function Days(account)
	local days = tonumber(account.autoPinNewMountDays)
	if not days or days < 0 then return MountPins.DefaultAutoPinDays end
	return math.floor(days)
end

local function SetExpiration(record, days, now)
	record.permanent = days == 0 or nil
	record.expiresAt = days > 0 and now + days * 86400 or nil
end

function MountPins.RecordAcquired(account, mountID, acquiredAt)
	if type(mountID) ~= "number" or type(acquiredAt) ~= "number" then return false end
	local records = Records(account)
	local record = records[mountID]
	if record and record.acquiredAt then return false end
	record = record or {}
	record.acquiredAt = acquiredAt
	if account.autoPinNewMounts ~= false and not record.suppressed then
		SetExpiration(record, Days(account), acquiredAt)
	end
	records[mountID] = record
	return true
end

function MountPins.Unpin(account, mountID)
	local record = Records(account)[mountID]
	if not record then return end
	record.manual = nil
	record.permanent = nil
	record.expiresAt = nil
	record.suppressed = true
end

function MountPins.Pin(account, mountID, now)
	local records = Records(account)
	local record = records[mountID] or {}
	SetExpiration(record, Days(account), now)
	record.manual = nil
	record.suppressed = nil
	records[mountID] = record
end

function MountPins.Keep(account, mountID)
	MountPins.Pin(account, mountID, time and time() or os.time())
end

function MountPins.SetDaysRemaining(account, mountID, days, now)
	days = tonumber(days)
	if not days or days < 0 or days ~= math.floor(days) then return false end
	local record = Records(account)[mountID]
	if not record or not MountPins.IsPinned(account, mountID, now) then return false end
	SetExpiration(record, days, now)
	record.manual = nil
	record.suppressed = nil
	return true
end

function MountPins.DaysRemaining(account, mountID, now)
	local record = Records(account)[mountID]
	if not record or not MountPins.IsPinned(account, mountID, now) then return nil end
	if record.permanent then return 0 end
	return math.max(0, math.ceil((record.expiresAt - now) / 86400))
end

function MountPins.IsPinned(account, mountID, now)
	local record = Records(account)[mountID]
	if not record or record.suppressed then return false end
	if record.permanent or record.manual then return true end
	return type(record.expiresAt) == "number" and record.expiresAt > now
end

function MountPins.ActiveSet(account, now)
	local set = {}
	for mountID in pairs(Records(account)) do
		if MountPins.IsPinned(account, mountID, now) then set[mountID] = true end
	end
	return set
end

function MountPins.Recent(account, now)
	local rows = {}
	for mountID, record in pairs(Records(account)) do
		if record.acquiredAt then
			local status = "expired"
			if (record.manual or record.permanent) and not record.suppressed then
				status = "manual"
			elseif record.suppressed then
				status = "unpinned"
			elseif MountPins.IsPinned(account, mountID, now) then
				status = "automatic"
			end
			table.insert(rows, {
				mountID = mountID,
				acquiredAt = record.acquiredAt,
				status = status,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.acquiredAt ~= b.acquiredAt then return a.acquiredAt > b.acquiredAt end
		return a.mountID < b.mountID
	end)
	return rows
end

ns.MountPins = MountPins
return MountPins
