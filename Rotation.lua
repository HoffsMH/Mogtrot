local ADDON_NAME, ns = ...
-- Loaded two ways: by the client, where ... is (name, shared table), and by
-- require in the test runner, where ... is the module name and ns is nil.
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Pure non-repeating rotation over a list of candidate IDs. The caller owns
-- the state table (plain persisted data: signature, remaining, last); the
-- module never touches globals, the WoW API, or the clock, and the only
-- randomness source is the injected `random(n) -> 1..n` (math.random when
-- omitted). Choosing is separate from committing, so an abandoned choice
-- leaves no trace.
local Rotation = {}

-- Canonical form of a candidate set: the IDs sorted, so reordering the same
-- set keeps the cycle while a changed set restarts it.
local function Signature(candidates)
	local keys = {}
	for i, id in ipairs(candidates) do keys[i] = id end
	table.sort(keys, function(a, b)
		if type(a) == "number" and type(b) == "number" then return a < b end
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function SameSignature(a, b)
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

-- Build a fresh full cycle. The just-committed candidate stays out of the
-- next pick through Alternatives, not by being dropped here.
local function Refill(state, candidates)
	local remaining = {}
	for _, id in ipairs(candidates) do
		remaining[#remaining + 1] = id
	end

	state.remaining = remaining
	state.signature = Signature(candidates)
	return remaining
end

local function Pick(remaining, random)
	local pool = remaining
	if #pool == 0 then return nil end
	return pool[random(#pool)]
end

-- Members of remaining that are none of the excluded IDs (nils ignored).
local function Alternatives(remaining, ...)
	local pool = {}
	for _, id in ipairs(remaining) do
		local skip = false
		for _, excluded in ipairs({ ... }) do
			if id == excluded then skip = true break end
		end
		if not skip then pool[#pool + 1] = id end
	end
	return pool
end

-- Pick a candidate without consuming anything. currentID (optional) is
-- excluded while an alternative exists; when it is the sole candidate it is
-- returned. Empty candidates return nil and leave the state untouched.
function Rotation.Choose(state, candidates, random, currentID)
	if #candidates == 0 then return nil end
	if random == nil then random = math.random end

	local remaining = state.remaining
	if remaining == nil or #remaining == 0 or state.signature == nil
		or not SameSignature(state.signature, Signature(candidates)) then
		remaining = Refill(state, candidates)
	end

	local pool = Alternatives(remaining, currentID, state.last)
	if #pool == 0 and currentID ~= nil and #candidates >= 2 then
		-- Only the current ID (or the just-committed one) is left in this
		-- cycle; refill so an alternative is served while one exists.
		pool = Alternatives(Refill(state, candidates), currentID, state.last)
	end
	if #pool == 0 then pool = remaining end
	return Pick(pool, random)
end

-- Consume the chosen ID: record it as last and remove it from the cycle.
function Rotation.Commit(state, id)
	state.last = id
	local remaining = state.remaining
	if remaining == nil then return end
	for i, candidate in ipairs(remaining) do
		if candidate == id then
			table.remove(remaining, i)
			return
		end
	end
end

ns.Rotation = Rotation
return Rotation
