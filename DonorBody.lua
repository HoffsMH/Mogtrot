local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Picking a living body to borrow when a stored look is the other sex.
--
-- SetModelByUnit builds its model from a unit and takes a race override, but
-- no sex override. Measured in game: the race comes from the override and the
-- sex comes from the unit. So a record of a woman renders correctly on any
-- woman standing nearby, wearing the record's race and the record's whole
-- outfit, composited armour included. Rendering from your own unit is the same
-- call with the same result whenever the sexes already agree.
--
-- Pure: tokens in, no frames, no C_ calls. The caller injects how to read a
-- unit, which is what makes the choosing testable without a client.
local DonorBody = {}

-- Ordered by how likely a token is to be someone standing in front of you and
-- to stay there. Your own body first, because when the sexes agree there is
-- nothing to borrow and nothing that can walk away. Party and raid come before
-- the crowd because those are the only units whose identity is never
-- restricted, so they are the only donors that keep working on an instanced
-- map.
--
-- The target-of-target chains are worth their cost: they reach people you
-- never pointed at, and the client builds them by appending to any token it
-- already knows. The soft and "any" tokens cost nothing to ask about and may
-- resolve with no input at all.
local TOKENS = {
	"player",
	"target", "focus", "mouseover",
	"softfriend", "softinteract", "anyfriend", "anyinteract", "anytarget",
	"targettarget", "focustarget", "mouseovertarget",
}

for index = 1, 4 do TOKENS[#TOKENS + 1] = "party" .. index end
for index = 1, 4 do TOKENS[#TOKENS + 1] = "party" .. index .. "target" end
for index = 1, 40 do TOKENS[#TOKENS + 1] = "raid" .. index end
for index = 1, 5 do TOKENS[#TOKENS + 1] = "arena" .. index end
-- Nameplates run to 150, not 40.
for index = 1, 150 do TOKENS[#TOKENS + 1] = "nameplate" .. index end

function DonorBody.Tokens()
	local copy = {}
	for index, token in ipairs(TOKENS) do copy[index] = token end
	return copy
end

-- Returns the first token whose unit is a player of the wanted sex, or nil.
--
-- read(token) answers exists, isPlayer, sex, raceID. A unit the client will
-- not answer for is skipped rather than guessed at: borrowing the wrong body
-- is worse than falling back to your own.
--
-- wantedRace is a preference, not a requirement. The race override replaces
-- the race but the skin, hair and face still come from the donor, and those
-- are chosen from that race's own palette. Borrowed across races they land on
-- whatever the new race has at the same index, which is how a Blood Elf's tan
-- ends up on a Void Elf. So a donor of the right race is looked for first, and
-- anybody of the right sex is the fallback: a plausible skin beats no body.
function DonorBody.Find(wantedSex, read, wantedRace)
	if type(read) ~= "function" then return nil end
	if wantedSex ~= 2 and wantedSex ~= 3 then return nil end

	local fallback
	for _, token in ipairs(TOKENS) do
		local exists, isPlayer, sex, raceID = read(token)
		if exists and isPlayer and sex == wantedSex then
			if wantedRace == nil or raceID == wantedRace then
				return token, raceID == wantedRace
			end
			fallback = fallback or token
		end
	end
	return fallback, false
end

ns.DonorBody = DonorBody
return DonorBody
