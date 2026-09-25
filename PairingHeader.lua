local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- The header of a window that shows a collection, as a sentence whose
-- changeable words are its controls. There is no window title separate from
-- this: "Choosing mounts for brick chillin" says what you are looking at, and
-- the words "mounts" and "brick chillin" are the things you click to change
-- it. The library reads "Showing my characters - 50 of 247 looks   switch to
-- snapshots", and has no title and no tabs either.
--
-- Pure. Returns segments rather than a string so the caller can make the
-- clickable ones clickable without parsing prose back apart.
--
--   segment = { text = string, boxed = true | nil,
--               action = "domain" | "outfit" | "mode" | "libraryMode"
--                        | "body" | nil,
--               icon = "mounts" | "hearthstones" | "outfit" | "pins"
--                      | "characters" | "snapshots" | nil }
--
-- The icon is a name, never a texture: which file a name resolves to is the
-- window's business, and this module stays testable without a client.
--
-- Two domains is what lets the domain word be a plain toggle. A third would
-- make it a dropdown and the sentence would stop reading as one.
local PairingHeader = {}

PairingHeader.DOMAINS = { "mounts", "hearthstones" }
PairingHeader.MODES = { "outfit", "pins" }
PairingHeader.LIBRARY_MODES = { "mine", "snapshots" }
PairingHeader.BODIES = { "original", "mine" }

local DOMAIN_LABEL = { mounts = "mounts", hearthstones = "hearthstones" }
local LIBRARY_MODE_LABEL = { mine = "my characters", snapshots = "snapshots" }
local LIBRARY_MODE_ICON = { mine = "characters", snapshots = "snapshots" }
local BODY_LABEL = { original = "original race", mine = "my race" }

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

-- Where the domain menu takes the window: the same outfit in the other
-- domain, or the other domain's pins from pins. Nil when nothing would change.
function PairingHeader.SwitchDomain(state, domain)
	state = type(state) == "table" and state or {}
	if not DOMAIN_LABEL[domain] or domain == PairingHeader.Domain(state.domain) then
		return nil
	end
	local mode = PairingHeader.Mode(state.mode)
	return { domain = domain, mode = mode,
		outfitID = mode == "outfit" and state.outfitID or nil }
end

-- Anything that is not "mine" is the snapshot wall, the same default the
-- library's own filter takes, so the sentence can never disagree with the
-- cards under it.
function PairingHeader.LibraryMode(mode)
	return mode == "mine" and "mine" or "snapshots"
end

function PairingHeader.OtherLibraryMode(mode)
	return PairingHeader.LibraryMode(mode) == "mine" and "snapshots" or "mine"
end

-- Whose body a stored look is shown on. Original race is the default because
-- it is the point of the library; whether it can be granted is the window's
-- question, not this module's.
function PairingHeader.Body(body)
	return body == "mine" and "mine" or "original"
end

-- The choices behind a word that stands for one of a fixed set, in the order
-- they are offered. A choice reads the way the sentence reads it and wears the
-- same icon, so the word and the menu it opens come from one vocabulary.
--
-- Only the words with a set answer have choices; "outfit" is a name out of the
-- user's own library and belongs to whoever owns that list.
function PairingHeader.Choices(action)
	local choices = {}
	if action == "domain" then
		for _, domain in ipairs(PairingHeader.DOMAINS) do
			choices[#choices + 1] =
				{ value = domain, text = DOMAIN_LABEL[domain], icon = domain }
		end
	elseif action == "libraryMode" then
		for _, mode in ipairs(PairingHeader.LIBRARY_MODES) do
			choices[#choices + 1] = { value = mode, text = LIBRARY_MODE_LABEL[mode],
				icon = LIBRARY_MODE_ICON[mode] }
		end
	elseif action == "body" then
		-- No icon. There is no stock glyph that tells whose body a look is
		-- standing on, and an atlas that does not exist draws nothing without
		-- saying so, so the words carry this one on their own.
		for _, body in ipairs(PairingHeader.BODIES) do
			choices[#choices + 1] = { value = body, text = BODY_LABEL[body] }
		end
	end
	return choices
end

-- One of those choices by name, for a control that shows a single word rather
-- than a whole sentence. A value with no choice behind it answers nothing
-- rather than a row made up on the spot.
function PairingHeader.Choice(action, value)
	for _, choice in ipairs(PairingHeader.Choices(action)) do
		if choice.value == value then return choice end
	end
	return nil
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

-- "50 of 247 looks", and "247 looks" when nothing was filtered out: a
-- comparison where there is no filter would invent one. An empty library says
-- so rather than counting to zero.
local function Looks(shown, total)
	if total <= 0 then return "no looks" end
	if shown >= total then
		return ("%d look%s"):format(total, total == 1 and "" or "s")
	end
	return ("%d of %d looks"):format(shown, total)
end

-- The library's header. The wall comes first because the count is only ever
-- true of the wall you are on. The count lives in the sentence, the way the pairing window's
-- "3 chosen" does; the row below it says which filters are on and how the
-- bodies are being drawn, which is why this reads 50 rather than 247.
function PairingHeader.LibrarySegments(state)
	state = type(state) == "table" and state or {}
	local mode = PairingHeader.LibraryMode(state.mode)
	local total = math.max(tonumber(state.total) or 0, 0)
	local shown = math.max(tonumber(state.shown) or 0, 0)

	local other = PairingHeader.OtherLibraryMode(mode)

	-- The wall is boxed like a word you can change but is not one; the switch
	-- after the count is the control, as "switch to pins" is while pairing.
	return {
		{ text = "Showing " },
		{ text = LIBRARY_MODE_LABEL[mode], boxed = true,
			icon = LIBRARY_MODE_ICON[mode] },
		{ text = (" - %s   "):format(Looks(shown, total)) },
		{ text = ("switch to %s"):format(LIBRARY_MODE_LABEL[other]),
			action = "libraryMode", icon = LIBRARY_MODE_ICON[other] },
	}
end

ns.PairingHeader = PairingHeader
return PairingHeader
