local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- The pairing window's header, as a sentence whose changeable words are its
-- controls. There is no window title separate from this: "Choosing mounts for
-- brick chillin" says what you are looking at, and the words "mounts" and
-- "brick chillin" are the things you click to change it.
--
-- Pure. Returns segments rather than a string so the caller can make the
-- clickable ones clickable without parsing prose back apart.
--
--   segment = { text = string, action = "domain" | "outfit" | "mode" | nil,
--               icon = "mounts" | "hearthstones" | "outfit" | "pins" | nil }
--
-- The icon is a name, never a texture: which file a name resolves to is the
-- window's business, and this module stays testable without a client.
--
-- Two domains is what lets the domain word be a plain toggle. A third would
-- make it a dropdown and the sentence would stop reading as one.
local PairingHeader = {}

PairingHeader.DOMAINS = { "mounts", "hearthstones" }
PairingHeader.MODES = { "outfit", "pins" }

local DOMAIN_LABEL = { mounts = "mounts", hearthstones = "hearthstones" }

function PairingHeader.Domain(domain)
	return DOMAIN_LABEL[domain] and domain or "mounts"
end

function PairingHeader.Mode(mode)
	return mode == "pins" and "pins" or "outfit"
end

function PairingHeader.OtherDomain(domain)
	return PairingHeader.Domain(domain) == "mounts" and "hearthstones" or "mounts"
end

function PairingHeader.OtherMode(mode)
	return PairingHeader.Mode(mode) == "outfit" and "pins" or "outfit"
end

-- Reads "switch to pins" while pairing, because a control names where it
-- takes you rather than where you already are.
local function SwitchLabel(mode)
	return ("switch to %s"):format(PairingHeader.OtherMode(mode))
end

function PairingHeader.Segments(state)
	state = type(state) == "table" and state or {}
	local domain = PairingHeader.Domain(state.domain)
	local mode = PairingHeader.Mode(state.mode)
	local chosen = tonumber(state.chosen) or 0

	local segments = {}
	local function Say(text, action, icon)
		segments[#segments + 1] = { text = text, action = action, icon = icon }
	end

	-- Pins belong to the account, so naming an outfit beside them would be a
	-- lie. The clause is absent rather than emptied.
	Say(mode == "pins" and "Choosing pinned " or "Choosing ")
	Say(DOMAIN_LABEL[domain], "domain", domain)
	if mode ~= "pins" then
		Say(" for ")
		local name = state.outfitName
		Say((type(name) == "string" and name ~= "") and name or "Outfit", "outfit",
			"outfit")
	end
	Say(("   %d chosen   "):format(chosen))
	-- The mode word names where it takes you, so it wears that mode's icon.
	Say(SwitchLabel(mode), "mode", PairingHeader.OtherMode(mode))
	return segments
end

ns.PairingHeader = PairingHeader
return PairingHeader
