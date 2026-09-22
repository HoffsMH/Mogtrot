-- Pure candidate precedence contract: eligible explicit links plus allowed
-- active account pins for one outfit, resolved by OutfitCandidates. Broader
-- domain fallback behavior stays with SummonDecision; this module only
-- combines the caller-provided local sets.
local OutfitCandidates = require("OutfitCandidates")

describe("OutfitCandidates", function()
	local Links = { [1] = true, [2] = true }
	local Pins = { [2] = true, [3] = true }

	-- Everything is eligible unless listed here.
	local function Eligibility(eligible)
		return function(id) return eligible[id] ~= false end
	end

	local function Candidates(overrides)
		local input = {
			links = overrides.links or Links,
			pins = overrides.pins or Pins,
			isEligible = overrides.isEligible or Eligibility({}),
			hasActiveOutfit = overrides.hasActiveOutfit ~= false,
			pinsOptOut = overrides.pinsOptOut == true,
			allowPinsWithoutOutfit = overrides.allowPinsWithoutOutfit == true,
		}
		return input
	end

	it("returns eligible links only when no pins apply", function()
		local candidates = OutfitCandidates.Resolve(Candidates({
			pinsOptOut = true,
		}))
		assert.same({ [1] = true, [2] = true }, candidates)
	end)

	it("unions active pins into links by default", function()
		assert.same({ [1] = true, [2] = true, [3] = true },
			OutfitCandidates.Resolve(Candidates({})))
	end)

	it("dedupes IDs that appear in both links and pins", function()
		local candidates = OutfitCandidates.Resolve(Candidates({
			links = { [5] = true },
			pins = { [5] = true },
		}))
		assert.same({ [5] = true }, candidates)
	end)

	it("removes ineligible links and pins", function()
		local candidates = OutfitCandidates.Resolve(Candidates({
			isEligible = Eligibility({ [2] = false, [3] = false }),
		}))
		assert.same({ [1] = true }, candidates)
	end)

	it("uses pins as the first local pool when no link survives", function()
		local candidates = OutfitCandidates.Resolve(Candidates({
			links = { [1] = true },
			isEligible = Eligibility({ [1] = false }),
		}))
		assert.same({ [2] = true, [3] = true }, candidates)
	end)

	it("excludes opted-out pins from the union and the local fallback", function()
		assert.same({ [1] = true, [2] = true }, OutfitCandidates.Resolve(Candidates({
			pinsOptOut = true,
		})))
		assert.same({}, OutfitCandidates.Resolve(Candidates({
			pinsOptOut = true,
			links = { [1] = true },
			isEligible = Eligibility({ [1] = false }),
		})))
	end)

	it("returns empty with no active outfit unless pins are allowed", function()
		assert.same({}, OutfitCandidates.Resolve(Candidates({
			hasActiveOutfit = false,
		})))
		assert.same({ [2] = true, [3] = true }, OutfitCandidates.Resolve(Candidates({
			hasActiveOutfit = false,
			links = {},
			allowPinsWithoutOutfit = true,
		})))
	end)

	it("filters eligibility from the allowed pins too, not just links", function()
		local candidates = OutfitCandidates.Resolve(Candidates({
			hasActiveOutfit = false,
			links = {},
			allowPinsWithoutOutfit = true,
			isEligible = Eligibility({ [3] = false }),
		}))
		assert.same({ [2] = true }, candidates)
	end)

	it("treats absent link and pin sets as empty", function()
		assert.same({}, OutfitCandidates.Resolve({
			isEligible = Eligibility({}),
			hasActiveOutfit = true,
			pinsOptOut = true,
		}))
		assert.same({}, OutfitCandidates.Resolve({
			links = {},
			pins = {},
			isEligible = Eligibility({}),
			hasActiveOutfit = true,
		}))
		assert.same({ [2] = true, [3] = true }, OutfitCandidates.Resolve({
			pins = Pins,
			isEligible = Eligibility({}),
			hasActiveOutfit = false,
			allowPinsWithoutOutfit = true,
		}))
	end)

	it("does not mutate or alias the input sets", function()
		local links = { [1] = true }
		local pins = { [3] = true }
		local candidates = OutfitCandidates.Resolve(Candidates({
			links = links,
			pins = pins,
		}))
		assert.same({ [1] = true }, links)
		assert.same({ [3] = true }, pins)
		assert.not_equal(links, candidates)
		assert.not_equal(pins, candidates)
	end)

	it("preserves exact numeric and string GUID IDs", function()
		local guid = "Pet-0xC0FFEE-0002"
		local candidates = OutfitCandidates.Resolve(Candidates({
			links = { [42] = true, [guid] = true },
			pins = {},
		}))
		assert.is_true(candidates[42])
		assert.is_true(candidates[guid])
		assert.is_nil(candidates[string.lower(guid)])
	end)
end)
