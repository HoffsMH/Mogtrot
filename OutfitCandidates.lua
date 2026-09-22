local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Pure links-plus-pins precedence for one outfit. Resolve combines the
-- caller-provided local sets into a fresh candidate set; it never reads
-- globals, mutates its inputs, or orders its output (Rotation owns sorting).
--
-- input = {
--     links = { [id] = true },  explicit links for the active outfit; absent
--                               means empty
--     pins = { [id] = true },   active account pins for the domain; absent
--                               means empty
--     isEligible = function,    id -> boolean, applied to links and pins
--     hasActiveOutfit = bool,
--     pinsOptOut = bool,        the outfit excluded pins for this domain
--     allowPinsWithoutOutfit = bool,  hearth-only: pins alone with no outfit
-- }
local OutfitCandidates = {}

function OutfitCandidates.Resolve(input)
	local candidates = {}

	local function Offer(id)
		if id ~= nil and input.isEligible(id) then candidates[id] = true end
	end

	-- With no active outfit, pins are the whole story and only when allowed.
	if not input.hasActiveOutfit then
		if input.allowPinsWithoutOutfit then
			for id in pairs(input.pins or {}) do Offer(id) end
		end
		return candidates
	end

	-- Eligible links first; an ID already offered here is not re-checked as a
	-- pin. The candidates table itself tracks what has been seen. Opt-out
	-- excludes pins entirely from the union.
	for id in pairs(input.links or {}) do
		Offer(id)
	end

	if not input.pinsOptOut then
		for id in pairs(input.pins or {}) do
			if not candidates[id] then Offer(id) end
		end
	end

	return candidates
end

ns.OutfitCandidates = OutfitCandidates
return OutfitCandidates
