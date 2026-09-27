local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- Controls which mount cards appear in the mount picker window where users link
-- mounts to an outfit.
local MountFilter = {}

-- Controls above the mount card grid

-- Creates the state shared by the search box and Filter menu above the mount grid.
-- chosenMode is "all", "chosen", or "unchosen" mounts for the current outfit.
function MountFilter.DefaultState()
	return MountFilter.Reset({})
end

function MountFilter.Reset(state)
	state.favoritesOnly = false
	state.chosenMode = "all"
	return state
end

function MountFilter.IsDefault(state)
	if not state then return true end
	if state.favoritesOnly then return false end
	return (state.chosenMode or "all") == "all"
end

-- Returns whether the Filter menu should say that linked mounts remain visible.
function MountFilter.ShouldShowLinkedMountNotice(state)
	if not state then return false end
	if (state.chosenMode or "all") ~= "all" then return false end
	return not MountFilter.IsDefault(state)
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

	-- Keep linked mounts visible through the favourites filter so users can
	-- unlink them. Search and chosen mode still take precedence.
	if isChosen then return true end

	return not (state.favoritesOnly and not mount.isFavorite)
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

ns.MountFilter = MountFilter
return MountFilter
