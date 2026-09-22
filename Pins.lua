local _, ns = ...
-- Loaded two ways: by the client, where ... is (name, shared table), and by
-- require in the test runner, where ... is the module name and ns is nil.
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Pure acquisition, pin/unpin, expiry and recent-history model over one
-- caller-owned domain table. No WoW APIs, no clock, no mount vocabulary.
--
-- domain = {
--     records = { [id] = pinRecord },  ids are number or string, one type
--                                      per domain, never mixed; the model
--                                      neither infers nor rejects types
--     autoNew = true,                  false stops auto-pinning acquisitions
--     days = 7,                        default expiration for new pins; 0 pins
--                                      permanently
-- }
--
-- A pin record is exactly:
-- {
--     acquiredAt = epochSeconds, -- optional for a manual pin
--     expiresAt = epochSeconds,  -- expiring pin
--     permanent = true,          -- mutually exclusive with expiresAt
--     suppressed = true,         -- user unpinned this acquisition
-- }
-- Unknown record fields are preserved through every operation.
local Pins = {}

Pins.DefaultAutoPinDays = 7

local function Records(domain)
	domain.records = domain.records or {}
	return domain.records
end

local function Days(domain)
	-- Only nil falls back to the default: false and 0 are caller choices.
	local days = domain.days
	if days == nil then return Pins.DefaultAutoPinDays end
	return days
end

local function SetExpiration(record, days, now)
	record.permanent = days == 0 or nil
	record.expiresAt = days > 0 and now + days * 86400 or nil
end

local function IsPinned(domain, id, now)
	local record = Records(domain)[id]
	if not record or record.suppressed then return false end
	if record.permanent then return true end
	return type(record.expiresAt) == "number" and record.expiresAt > now
end

function Pins.RecordAcquired(domain, id, acquiredAt)
	if type(acquiredAt) ~= "number" then return false end
	local records = Records(domain)
	local record = records[id]
	if record and record.acquiredAt then return false end
	record = record or {}
	record.acquiredAt = acquiredAt
	if domain.autoNew ~= false and not record.suppressed and not record.permanent then
		SetExpiration(record, Days(domain), acquiredAt)
	end
	records[id] = record
	return true
end

function Pins.Unpin(domain, id)
	local record = Records(domain)[id]
	if not record then return end
	record.permanent = nil
	record.expiresAt = nil
	record.suppressed = true
end

function Pins.Pin(domain, id, now)
	local records = Records(domain)
	local record = records[id] or {}
	SetExpiration(record, Days(domain), now)
	record.suppressed = nil
	records[id] = record
end

function Pins.Keep(domain, id, now)
	Pins.Pin(domain, id, now)
end

function Pins.SetDaysRemaining(domain, id, days, now)
	if type(days) ~= "number" or days < 0 or days ~= math.floor(days) then
		return false
	end
	if not IsPinned(domain, id, now) then return false end
	local record = Records(domain)[id]
	SetExpiration(record, days, now)
	record.suppressed = nil
	return true
end

function Pins.DaysRemaining(domain, id, now)
	local record = Records(domain)[id]
	if not IsPinned(domain, id, now) then return nil end
	if record.permanent then return 0 end
	return math.max(0, math.ceil((record.expiresAt - now) / 86400))
end

Pins.IsPinned = IsPinned

function Pins.ActiveSet(domain, now)
	local set = {}
	for id in pairs(Records(domain)) do
		if IsPinned(domain, id, now) then set[id] = true end
	end
	return set
end

-- Recent rows carry the pinned status vocabulary the current UI reads:
-- "manual" (a permanent pin), "automatic", "expired" and "unpinned".
function Pins.Recent(domain, now, compare)
	local rows = {}
	for id, record in pairs(Records(domain)) do
		if record.acquiredAt then
			local status = "expired"
			if record.permanent and not record.suppressed then
				status = "manual"
			elseif record.suppressed then
				status = "unpinned"
			elseif IsPinned(domain, id, now) then
				status = "automatic"
			end
			rows[#rows + 1] = {
				id = id,
				acquiredAt = record.acquiredAt,
				status = status,
			}
		end
	end
	table.sort(rows, function(a, b)
		if a.acquiredAt ~= b.acquiredAt then return a.acquiredAt > b.acquiredAt end
		return compare(a.id, b.id)
	end)
	return rows
end

ns.Pins = Pins
return Pins
