local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Pure read layer over an injected adapter and the curated
-- HearthstoneDefinitions registry. The adapter stands in for C_ToyBox/C_Item;
-- the registry is the only enumeration source, so the player's Toy Box
-- filters are never touched. Every read is fresh and event-independent; the
-- caller decides when to read again.
local HearthstoneCollection = {}
local function ItemOwnership(adapter, itemID)
	if adapter.totalItemCount then
		local total = adapter.totalItemCount(itemID)
		if total ~= nil then return total end
	end
	if adapter.itemCount then
		return adapter.itemCount(itemID)
	end
	return nil
end

local function ToyOwnership(adapter, itemID, probe)
	probe = probe or adapter.hasToy
	if not probe then return nil end
	return probe(itemID) and true or false
end

-- One fresh row per reviewed registry ID. Toy rows get ownership from
-- hasToy and metadata from getToyInfo; item rows count carried copies with
-- itemCount and, when the adapter exposes it, total owned copies. Metadata
-- that has not loaded yet stays nil - nothing is invented.
function HearthstoneCollection.Rows(adapter, registry)
	local rows = {}
	for itemID, entry in pairs(registry.entries) do
		local row = {
			itemID = itemID,
			kind = entry.kind,
			spellID = entry.spellID,
		}
		if entry.kind == "toy" then
			row.owned = ToyOwnership(adapter, itemID)
			local name, icon, favorite = adapter.getToyInfo(itemID)
			row.name = name
			row.icon = icon
			row.favorite = favorite and true or false
		else
			row.count = adapter.itemCount and adapter.itemCount(itemID) or nil
			row.owned = type(row.count) == "number" and row.count > 0 or nil
			if adapter.totalItemCount then
				row.total = adapter.totalItemCount(itemID)
			end
			row.name = adapter.getItemName(itemID)
			row.icon = adapter.getItemIcon(itemID)
		end
		rows[#rows + 1] = row
	end
	return rows
end

-- Action-time checks, straight from the adapter's answer per exact item ID.
function HearthstoneCollection.UsableInfo(adapter, itemID)
	return adapter.isUsable(itemID)
end

function HearthstoneCollection.Cooldown(adapter, itemID)
	return adapter.getCooldown(itemID)
end

local function PickerName(row)
	return type(row.name) == "string" and row.name or ("item " .. tostring(row.itemID))
end

-- What the pairing window lists for hearthstones: the rows matching the
-- search, collected first and then by name, each marked with whether its
-- cooldown is running, plus the footer note. options.cooldown(itemID) answers
-- start and duration on the clock options.now reads, which in the client is
-- GetTime, not time.
function HearthstoneCollection.PickerList(rows, options)
	options = options or {}
	local query = type(options.query) == "string" and options.query ~= ""
		and string.lower(options.query) or nil
	local matches, collected = {}, 0
	for _, row in ipairs(rows or {}) do
		if row.owned == true then collected = collected + 1 end
		if not query or string.find(string.lower(PickerName(row)), query, 1, true) then
			local start, duration
			if row.owned == true and options.cooldown then
				start, duration = options.cooldown(row.itemID)
			end
			row.onCooldown = type(start) == "number" and type(duration) == "number"
				and duration > 0 and start + duration > (options.now or 0)
			matches[#matches + 1] = row
		end
	end
	table.sort(matches, function(a, b)
		local ao, bo = a.owned == true, b.owned == true
		if ao ~= bo then return ao end
		local an, bn = string.lower(PickerName(a)), string.lower(PickerName(b))
		if an ~= bn then return an < bn end
		return a.itemID < b.itemID
	end)
	local note = #matches == 0 and "No reviewed hearthstones match."
		or ("%d of %d collected."):format(collected, #(rows or {}))
	return { rows = matches, note = note }
end

-- Initial ownership snapshot: totals for items, ownership booleans for toys.
-- Nothing is emitted - what the character already owns is baseline, not
-- acquisition.

function HearthstoneCollection.Baseline(adapter, registry)
	local baseline = {}
	for itemID, entry in pairs(registry.entries) do
		if entry.kind == "toy" then
			baseline[itemID] = ToyOwnership(adapter, itemID)
		else
			baseline[itemID] = ItemOwnership(adapter, itemID)
		end
	end
	return baseline
end

-- Compares current ownership against the caller's baseline map and reports
-- acquisitions: any item ownership increase over the recorded baseline
-- (including 1 -> 2 for a new copy) and toys going false -> true. A nil
-- means initial, never an acquisition. The baseline is updated in place so
-- repeated calls diff successive states. onAcquired receives the exact itemID.
function HearthstoneCollection.Acquisitions(adapter, registry, baseline, onAcquired, toyOwned)
	for itemID, entry in pairs(registry.entries) do
		local was, now
		if entry.kind == "toy" then
			was = baseline[itemID]
			now = ToyOwnership(adapter, itemID, toyOwned)
		else
			was = baseline[itemID]
			now = ItemOwnership(adapter, itemID)
		end

		local acquired
		if entry.kind == "toy" then
			-- false -> true; an unknown baseline (nil) is not an acquisition.
			acquired = was == false and now == true
		else
			-- A later increase over the recorded total; an unknown baseline
			-- (nil) counts as initial, not acquisition.
			acquired = type(was) == "number" and type(now) == "number" and now > was
		end

		if acquired then onAcquired(itemID) end
		if now ~= nil then baseline[itemID] = now end
	end
end

ns.HearthstoneCollection = HearthstoneCollection
return HearthstoneCollection
