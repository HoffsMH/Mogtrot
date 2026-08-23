local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = {} end

local MountPreference = ns.MountPreference or require("MountPreference")

-- Chooses what the summon key should do from the current outfit and available mounts.
local MountPick = {}

function MountPick.Sorted(set)
	local ids = {}
	for mountID in pairs(set or {}) do
		table.insert(ids, mountID)
	end
	table.sort(ids)
	return ids
end

function MountPick.Choose(set, usable, random, preference)
	local pool, reason = {}, nil

	for _, mountID in ipairs(MountPick.Sorted(set)) do
		local isUsable, useError = usable(mountID)
		if isUsable then
			table.insert(pool, mountID)
		elseif reason == nil then
			reason = useError
		end
	end

	if #pool == 0 then return nil, reason, nil, pool end
	if preference then
		local mountID, tier, preferredCandidates = MountPreference.Choose(pool, preference.types,
			preference.situation, preference.mountType, random, preference.requirePreferred)
		return mountID, nil, tier, pool, preferredCandidates
	end
	return pool[random(#pool)], nil, nil, pool, pool
end

local function Fallback(request, cause)
	local config = request.fallback or {}
	local mode = config.mode or "random"

	if mode == "off" then
		return { action = "refuse", reason = cause, cause = cause }
	end
	if mode == "litemount" and cause == "nomounts" then
		if request.liteMountAvailable then
			return { action = "litemount", cause = cause }
		end
		return { action = "refuse", reason = "litemountunavailable", cause = cause }
	end
	if mode == "pinned" then
		local mountID, useError = MountPick.Choose(config.set, request.usable,
			request.random, request.preference)
		if mountID then
			return { action = "summon", mountID = mountID, from = "fallback", cause = cause }
		end
		if config.set and next(config.set) ~= nil then
			return { action = "refuse", reason = "unusable", detail = useError, cause = cause }
		end
		return { action = "refuse", reason = "nopins", cause = cause }
	end

	-- Blizzard's random-favourite call can silently choose an unusable mount.
	local favourites = request.favourites()
	if favourites and next(favourites) ~= nil then
		local mountID = MountPick.Choose(favourites, request.usable, request.random,
			request.preference)
		if mountID then
			return { action = "summon", mountID = mountID, from = "favourite",
				cause = cause }
		end
	end

	local collection = request.collection()
	if not collection or next(collection) == nil then
		return { action = "refuse", reason = "nocollection", cause = cause }
	end

	local mountID, refusal = MountPick.Choose(collection, request.usable, request.random,
		request.preference)
	if mountID then
		return { action = "summon", mountID = mountID, from = "collection",
			cause = cause }
	end
	return { action = "refuse", reason = "collectionunusable", detail = refusal,
		cause = cause }
end

function MountPick.Plan(request)
	if request.targetMountID then
		return { action = "summon", mountID = request.targetMountID, from = "target" }
	end
	if not request.hasOutfit then
		return Fallback(request, "nooutfit")
	end

	local set = request.set
	if not set or next(set) == nil then
		return Fallback(request, "nomounts")
	end

	local mountID, refusal, preferenceTier, candidates, viableCandidates =
		MountPick.Choose(set, request.usable, request.random, request.preference)
	if mountID then
		return { action = "summon", mountID = mountID, from = "outfit",
			preferenceTier = preferenceTier, candidates = candidates,
			viableCandidates = viableCandidates }
	end
	if request.preference and request.preference.requirePreferred
		and #candidates > 0 and #viableCandidates == 0 then
		return Fallback(request, "unsuitable")
	end

	return { action = "refuse", reason = "unusable", detail = refusal }
end

ns.MountPick = MountPick
return MountPick
