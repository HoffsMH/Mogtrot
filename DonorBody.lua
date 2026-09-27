local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- The unit tokens a living body may be borrowed from, when a stored look is
-- the other sex. SetModelByUnit takes a race override but no sex override, so
-- the sex comes from the unit.
--
-- Pure: a list, no frames, no C_ calls.
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

-- The first token whose GUID is wantGUID, or nil. readGUID(token) answers a
-- token's GUID or nil. A secret GUID is skipped: comparing one is an error.
function DonorBody.TokenFor(wantGUID, readGUID)
	for _, token in ipairs(TOKENS) do
		local guid = readGUID(token)
		if guid ~= nil and not (issecretvalue and issecretvalue(guid))
			and guid == wantGUID then
			return token
		end
	end
	return nil
end

ns.DonorBody = DonorBody
return DonorBody
