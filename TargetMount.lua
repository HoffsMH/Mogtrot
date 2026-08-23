local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = {} end

local TargetMount = {}

local function Validate(mountID, inspect, source)
	if not mountID then return nil, "unidentified" end
	local mount = inspect(mountID)
	if not mount or not mount.exists then return nil, "unidentified" end
	if not mount.collected then return nil, "unowned" end
	if mount.hidden then return nil, "hidden" end
	if not mount.usable then return nil, "unusable", mount.error end
	return {
		mountID = mountID,
		name = mount.name,
		reason = "accepted",
		source = source,
	}
end

-- Resolve an already non-secret target observation against the player's
-- collection. Exact spell identity wins; names are accepted only when unique.
function TargetMount.Resolve(observation, inspect)
	if not observation or not observation.enabled then return nil, "disabled" end
	if observation.reason then return nil, observation.reason end

	local exactReason, exactDetail
	if observation.exactMountID then
		local match, reason, detail = Validate(observation.exactMountID, inspect, "exact")
		if match then return match end
		if reason ~= "unowned" and reason ~= "hidden" and reason ~= "unidentified" then
			return nil, reason, detail
		end
		exactReason, exactDetail = reason, detail
	end

	local matches = observation.nameMatches or {}
	if #matches == 0 then return nil, exactReason or "unidentified", exactDetail end
	if #matches > 1 then return nil, "ambiguous" end
	return Validate(matches[1], inspect, "equivalent")
end

ns.TargetMount = TargetMount
return TargetMount
