local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Battle-pet model adapter. Decides whether an owned copy's displayID can be
-- rendered on a caller-provided model, using injected display hooks. Any
-- unsuitable input or model-scene failure returns false so the card's static
-- icon fallback takes over; the row's metadata is never touched.
local BattlePetModel = {}

-- Returns true when the display was applied and the model shown.
function BattlePetModel.Apply(model, row, deps)
	if not model or type(deps) ~= "table" then
		return false
	end

	local displayID = row and row.displayID
	if type(displayID) ~= "number" or displayID <= 0 or displayID ~= math.floor(displayID) then
		return false
	end

	local setDisplay = deps.setDisplay
	local show = deps.show
	if type(setDisplay) ~= "function" or type(show) ~= "function" then
		return false
	end

	local ok = pcall(setDisplay, model, displayID)
	if not ok then return false end

	ok = pcall(show, model)
	if not ok then return false end

	return true
end

ns.BattlePetModel = BattlePetModel
return BattlePetModel
