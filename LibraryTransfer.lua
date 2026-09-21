local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local LibraryTransfer = {}

function LibraryTransfer.PreferredSource(sourceID, deps)
	if type(sourceID) ~= "number" or type(deps) ~= "table"
		or type(deps.getSourceInfo) ~= "function" then return nil, false end
	local info = deps.getSourceInfo(sourceID)
	if type(info) ~= "table" then return nil, false end
	local function Usable(candidate)
		if candidate.useError then return false end
		return candidate.useErrorType == nil or candidate.useErrorType == deps.noError
	end
	if info.isCollected and Usable(info) then return sourceID, true end
	if type(deps.getAllSources) ~= "function" or not info.visualID then return nil, false end
	for _, siblingID in ipairs(deps.getAllSources(info.visualID) or {}) do
		if siblingID ~= sourceID then
			local sibling = deps.getSourceInfo(siblingID)
			if type(sibling) == "table" and sibling.isCollected and Usable(sibling) then
				return siblingID, true
			end
		end
	end
	return nil, false
end

local function Add(plan, createLocation, inventorySlot, transmogType, secondary,
	transmogID, resolve, options)
	if type(transmogID) ~= "number" or transmogID <= 0 then return end
	local location = createLocation(inventorySlot, transmogType, secondary)
	if not location then return end
	if resolve then
		transmogID = resolve(transmogID, location)
		if not transmogID then
			if options and options.hideUnavailable then
				plan[#plan + 1] = {
					slot = location:GetSlot(), type = location:GetType(),
					transmogID = options.noTransmogID,
					displayType = options.hiddenDisplayType,
				}
				return "hidden"
			end
			plan.unavailable = (plan.unavailable or 0) + 1
			return false
		end
	end
	plan[#plan + 1] = {
		slot = location:GetSlot(),
		type = location:GetType(),
		transmogID = transmogID,
	}
	return true
end

function LibraryTransfer.Plan(look, createLocation, appearanceType, illusionType,
	resolveAppearance, options)
	local plan = {}
	if type(look) ~= "table" or type(createLocation) ~= "function" then return plan end
	local slots = {}
	for inventorySlot in pairs(look) do slots[#slots + 1] = inventorySlot end
	table.sort(slots)
	for _, inventorySlot in ipairs(slots) do
		local entry = look[inventorySlot]
		if type(entry) == "table" then
			local primary = Add(plan, createLocation, inventorySlot, appearanceType,
				false, entry[1],
				resolveAppearance, options)
			Add(plan, createLocation, inventorySlot, appearanceType, true, entry[2],
				resolveAppearance, options)
			if type(entry[3]) == "number" and entry[3] > 0 and entry[1]
				and entry[1] > 0 and primary == "hidden" then
				-- A hidden weapon has nowhere to display its illusion.
			elseif type(entry[3]) == "number" and entry[3] > 0 and entry[1]
				and entry[1] > 0 and not primary then
				plan.unavailable = (plan.unavailable or 0) + 1
			else
				Add(plan, createLocation, inventorySlot, illusionType, false, entry[3])
			end
		end
	end
	if type(options) == "table" and type(options.emptySlots) == "table" then
		for _, inventorySlot in ipairs(options.emptySlots) do
			local entry = look[inventorySlot]
			if type(entry) ~= "table" or type(entry[1]) ~= "number" or entry[1] <= 0 then
				local location = createLocation(inventorySlot, appearanceType, false)
				if location then
					plan[#plan + 1] = {
						slot = location:GetSlot(), type = location:GetType(),
						transmogID = options.noTransmogID,
						displayType = options.hiddenDisplayType,
					}
				end
			end
		end
	end
	return plan
end

function LibraryTransfer.Apply(plan, deps)
	local attempted, verified = 0, 0
	for _, entry in ipairs(plan or {}) do
		local option = deps.option(entry.slot, entry.type)
		if option ~= nil then
			attempted = attempted + 1
			local displayType = entry.displayType or deps.assignedDisplayType
			local ok = pcall(deps.setPending, entry.slot, entry.type, option,
				entry.transmogID, displayType)
			local viewed = ok and deps.getViewed(entry.slot, entry.type, option)
			if viewed and viewed.transmogID == entry.transmogID
				and (not entry.displayType or viewed.displayType == displayType) then
				verified = verified + 1
			end
		end
	end
	return attempted, verified, plan and plan.unavailable or 0
end

ns.LibraryTransfer = LibraryTransfer
return LibraryTransfer
