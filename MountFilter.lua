local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Controls which mount cards appear in the mount picker window where users link
-- mounts to an outfit.
local MountFilter = {}

-- Controls above the mount card grid

-- Creates the state shared by the search box and Filter menu above the mount grid.
-- chosenMode is "all", "chosen", or "unchosen" mounts for the current outfit.
function MountFilter.DefaultState(validTypes)
	local state = { validTypes = validTypes or {}, types = {} }
	MountFilter.Reset(state)
	return state
end

function MountFilter.Reset(state)
	state.types = {}
	for _, value in ipairs(state.validTypes or {}) do
		state.types[value] = true
	end
	state.favoritesOnly = false
	state.chosenMode = "all"
	return state
end

function MountFilter.IsDefault(state)
	if not state then return true end
	if state.favoritesOnly then return false end
	if (state.chosenMode or "all") ~= "all" then return false end
	for _, value in ipairs(state.validTypes or {}) do
		if not (state.types and state.types[value]) then return false end
	end
	return true
end

-- Returns whether the Filter menu should say that linked mounts remain visible.
function MountFilter.ShouldShowLinkedMountNotice(state)
	if not state then return false end
	if (state.chosenMode or "all") ~= "all" then return false end
	return not MountFilter.IsDefault(state)
end

function MountFilter.SetAllTypes(state, checked)
	state.types = state.types or {}
	for _, value in ipairs(state.validTypes or {}) do
		state.types[value] = checked or nil
	end
	return state
end

local function TypeAllowed(mount, state)
	local ticked = state.types
	if not ticked then return true end

	local types = mount.types
	if not types or next(types) == nil then return true end

	for value in pairs(types) do
		if ticked[value] then return true end
	end
	return false
end

-- Which mount cards users see

-- Returns whether one mount card should appear for the current controls.
function MountFilter.Matches(mount, state, isChosen)
	state = state or {}

	if state.query and not string.find(mount.search or "", state.query, 1, true) then
		return false
	end

	local mode = state.chosenMode or "all"
	if mode == "chosen" and not isChosen then
		return false
	end
	if mode == "unchosen" and isChosen then
		return false
	end

	-- Keep linked mounts visible through type and favourite filters so users can
	-- unlink them. Search and chosen mode still take precedence.
	if isChosen then return true end

	if state.favoritesOnly and not mount.isFavorite then
		return false
	end
	return TypeAllowed(mount, state)
end

-- Returns the mounts displayed in the grid without changing their existing order.
function MountFilter.Apply(mounts, state, chosen)
	chosen = chosen or {}

	local matches = {}
	for _, mount in ipairs(mounts or {}) do
		if MountFilter.Matches(mount, state, chosen[mount.mountID] == true) then
			table.insert(matches, mount)
		end
	end
	return matches
end

-- Builds the status text that names active Filter menu choices. The search text
-- remains visible in its own box.
function MountFilter.Describe(state, labels)
	if not state then return nil end

	local ticked, total = {}, 0
	for _, value in ipairs(state.validTypes or {}) do
		total = total + 1
		if state.types and state.types[value] then
			table.insert(ticked, (labels and labels[value]) or tostring(value))
		end
	end

	local parts = {}
	local mode = state.chosenMode or "all"
	if mode == "chosen" then
		table.insert(parts, "on this outfit")
	elseif mode == "unchosen" then
		table.insert(parts, "not on this outfit")
	end
	if total > 0 and #ticked < total then
		table.insert(parts, #ticked > 0 and table.concat(ticked, ", ") or "no types")
	end
	if state.favoritesOnly then
		table.insert(parts, "favourites")
	end

	if #parts == 0 then return nil end
	return table.concat(parts, " + ")
end

-- Mount types reported by Blizzard

local NO_OP_BUCKET = 0.95

-- Rejects mount-type results that look like Blizzard returned the unfiltered
-- collection for one type. Unknown mounts remain visible in the picker.
function MountFilter.Verify(types, collectedIDs)
	types = types or {}

	local total, unknown = 0, 0
	for _, mountID in ipairs(collectedIDs or {}) do
		total = total + 1
		local set = types[mountID]
		if not set or next(set) == nil then
			unknown = unknown + 1
		end
	end

	if total == 0 then return true, nil, unknown end
	if unknown == total then
		return false, "no mount landed in any category", unknown
	end

	local counts = {}
	for _, set in pairs(types) do
		for value in pairs(set) do counts[value] = (counts[value] or 0) + 1 end
	end
	for value, count in pairs(counts) do
		if count >= total * NO_OP_BUCKET then
			return false,
				("category %s holds %d of %d mounts"):format(tostring(value), count, total),
				unknown
		end
	end

	return true, nil, unknown
end

-- Adds mount types supplied by a separate Blizzard API, such as its skyriding list.
function MountFilter.InjectType(types, mountIDs, value)
	if not types or not value then return types end
	for _, mountID in ipairs(mountIDs or {}) do
		types[mountID] = types[mountID] or {}
		types[mountID][value] = true
	end
	return types
end

-- Counts how many mounts Blizzard placed in a type before another API adds it.
function MountFilter.OverlapCount(types, mountIDs, value)
	local n = 0
	for _, mountID in ipairs(mountIDs or {}) do
		local set = types and types[mountID]
		if set and set[value] then n = n + 1 end
	end
	return n
end

ns.MountFilter = MountFilter
return MountFilter
