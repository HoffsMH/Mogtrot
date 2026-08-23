local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = {} end

local MountPick = ns.MountPick or require("MountPick")
local LinkedMountShuffle = ns.LinkedMountShuffle or require("LinkedMountShuffle")

local SummonDecision = {}

local function MountSet(collection, predicate)
	local mountIDs = {}
	for mountID, mount in pairs(collection or {}) do
		if predicate(mount) then mountIDs[mountID] = true end
	end
	return mountIDs
end

local function Usability(collection)
	return function(mountID)
		local mount = collection and collection[mountID]
		return mount and mount.usable == true, mount and mount.error
	end
end

local function MountInfo(collection)
	return function(mountID)
		local mount = collection and collection[mountID]
		return mount and mount.collected and not mount.hidden or false,
			mount and mount.name
	end
end

function SummonDecision.Decide(snapshot)
	snapshot = snapshot or {}
	local situation = snapshot.situation or {}
	local shuffleState = snapshot.shuffle or {}
	if situation.mounted then
		return { intent = { action = "dismiss" }, shuffle = shuffleState }
	end
	if situation.combat then
		return { intent = { action = "refuse", reason = "combat" }, shuffle = shuffleState }
	end

	local collection = snapshot.collection or {}
	local outfit = snapshot.outfit
	local preferences = snapshot.preferences or {}
	local preference
	if snapshot.mountTypes then
		preference = {
			types = snapshot.mountTypes,
			situation = situation,
			mountType = snapshot.mountType,
			requirePreferred = snapshot.requirePreferred,
		}
	end
	local linkedMountIDs = outfit and outfit.linkedMountIDs or nil
	if outfit and linkedMountIDs and next(linkedMountIDs) ~= nil
		and preferences.shufflePinned then
		local mixed = {}
		for mountID in pairs(linkedMountIDs) do mixed[mountID] = true end
		for mountID in pairs(snapshot.pinnedMountIDs or {}) do mixed[mountID] = true end
		linkedMountIDs = mixed
	end
	local plan = MountPick.Plan({
		targetMountID = preferences.matchTarget and situation.targetMountID or nil,
		hasOutfit = outfit ~= nil,
		set = linkedMountIDs,
		fallback = { mode = preferences.fallbackMode, mountID = preferences.pinnedMountID,
			set = snapshot.pinnedMountIDs },
		liteMountAvailable = snapshot.integrations and snapshot.integrations.liteMountReady,
		usable = Usability(collection),
		random = snapshot.random,
		preference = preference,
		mountInfo = MountInfo(collection),
		favourites = function()
			return MountSet(collection, function(mount)
				return mount.collected and not mount.hidden and mount.favorite
			end)
		end,
		collection = function()
			return MountSet(collection, function(mount)
				return mount.collected and not mount.hidden
			end)
		end,
	})

	local shuffle = LinkedMountShuffle.FromState(shuffleState, snapshot.random)
	shuffle:Select(outfit and outfit.id, plan, snapshot.now or 0)
	return { intent = plan, shuffle = shuffle:State() }
end

function SummonDecision.Transition(state, event)
	event = event or {}
	local shuffle = LinkedMountShuffle.FromState(state, function() return 1 end)
	if event.type == "stage" then
		shuffle:Stage(event.outfitID, event.mountID, event.spellID, event.now)
	elseif event.type == "cast-sent" then
		shuffle:Sent(event.spellID, event.castGUID)
	elseif event.type == "cast-start" or event.type == "cast-succeeded" then
		shuffle:Confirm(event.spellID, event.castGUID, event.now)
	elseif event.type == "cast-failed" then
		shuffle:Cancel(event.spellID, event.castGUID)
	elseif event.type == "clear" then
		shuffle:ClearPending()
	elseif event.type == "expire" then
		shuffle:Expire(event.now)
	end
	return shuffle:State()
end

ns.SummonDecision = SummonDecision
return SummonDecision
