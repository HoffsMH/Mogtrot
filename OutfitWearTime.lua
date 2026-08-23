local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Tracks how long each outfit has been worn and prepares totals for the outfit
-- list, tooltip, and wear report.

local Wear = {}

function Wear.ShowInList(settings)
	return settings ~= nil and settings.showWearInList == true
end

function Wear.SetShowInList(settings, enabled)
	if settings then settings.showWearInList = enabled and true or false end
end

Wear.MIN_HEAT = 0.06

local DAY, HOUR, MINUTE = 86400, 3600, 60

local function ElapsedSeconds(startedAt, now)
	if type(startedAt) ~= "number" or type(now) ~= "number" then return 0 end
	if now <= startedAt then return 0 end
	return now - startedAt
end

function Wear.NewSession(store)
	return { store = store or {} }
end

function Wear.Close(session, now, stamp)
	if not session then return 0 end

	local outfitID = session.id
	local elapsed = ElapsedSeconds(session.since, now)
	session.id, session.since = nil, nil
	if outfitID == nil or elapsed <= 0 then return 0 end

	local store = session.store
	if not store then return 0 end

	local record = store[outfitID]
	if type(record) ~= "table" then
		record = { seconds = 0 }
		store[outfitID] = record
	end
	record.seconds = (tonumber(record.seconds) or 0) + elapsed
	if stamp ~= nil then record.last = stamp end

	return elapsed
end

function Wear.Switch(session, outfitID, now, stamp)
	if not session then return 0 end
	if session.id ~= nil and session.id == outfitID then return 0 end

	local accrued = Wear.Close(session, now, stamp)
	if outfitID ~= nil then
		session.id, session.since = outfitID, now
	end

	return accrued
end

function Wear.Total(session, outfitID, now)
	if not session or outfitID == nil then return 0 end

	local record = session.store and session.store[outfitID]
	local seconds = (type(record) == "table" and tonumber(record.seconds)) or 0
	if session.id == outfitID then
		seconds = seconds + ElapsedSeconds(session.since, now)
	end

	return seconds
end

function Wear.Snapshot(session, now, liveOutfitIDs)
	local totals = {}
	local maxSeconds, totalSeconds, outfitCount = 0, 0, 0

	local function IncludeOutfit(outfitID)
		if outfitID == nil or totals[outfitID] then return end
		if liveOutfitIDs and not liveOutfitIDs[outfitID] then return end

		local seconds = Wear.Total(session, outfitID, now)
		if seconds <= 0 then return end

		totals[outfitID] = seconds
		totalSeconds = totalSeconds + seconds
		outfitCount = outfitCount + 1
		if seconds > maxSeconds then maxSeconds = seconds end
	end

	for outfitID in pairs((session and session.store) or {}) do
		IncludeOutfit(outfitID)
	end
	if session then IncludeOutfit(session.id) end

	return {
		totals = totals,
		max = maxSeconds,
		sum = totalSeconds,
		count = outfitCount,
	}
end

function Wear.Heat(maxSeconds, seconds)
	if type(maxSeconds) ~= "number" or maxSeconds <= 0 then return 0 end
	if type(seconds) ~= "number" or seconds <= 0 then return 0 end

	local heat = math.sqrt(math.min(seconds / maxSeconds, 1))

	return math.max(heat, Wear.MIN_HEAT)
end

function Wear.Share(totalSeconds, seconds)
	if type(totalSeconds) ~= "number" or totalSeconds <= 0 then return 0 end
	if type(seconds) ~= "number" or seconds <= 0 then return 0 end

	return math.min(seconds / totalSeconds, 1)
end

function Wear.Format(seconds)
	seconds = math.floor(tonumber(seconds) or 0)
	if seconds < 0 then seconds = 0 end

	local days = math.floor(seconds / DAY)
	local hours = math.floor((seconds % DAY) / HOUR)
	local minutes = math.floor((seconds % HOUR) / MINUTE)

	if days > 0 then
		return hours > 0 and ("%dd %dh"):format(days, hours) or ("%dd"):format(days)
	end
	if hours > 0 then
		return minutes > 0 and ("%dh %dm"):format(hours, minutes) or ("%dh"):format(hours)
	end
	if minutes > 0 then
		return ("%dm"):format(minutes)
	end

	return ("%ds"):format(seconds)
end

function Wear.Top(snapshot, limit)
	local list = {}

	for outfitID, seconds in pairs((snapshot and snapshot.totals) or {}) do
		table.insert(list, { outfitID = outfitID, seconds = seconds })
	end

	table.sort(list, function(a, b)
		if a.seconds ~= b.seconds then return a.seconds > b.seconds end
		return a.outfitID < b.outfitID
	end)

	if limit then
		for index = #list, limit + 1, -1 do
			table.remove(list, index)
		end
	end

	return list
end

ns.Wear = Wear
return Wear
