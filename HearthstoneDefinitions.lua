local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Curated, versioned hearthstone registry: itemID -> { kind = "toy" | "item" }.
-- Adding or removing an entry raises VERSION.
--
-- Inclusion rule: the entry must be a hearthstone replacement, meaning it
-- returns you to the home you set at an innkeeper and shares the hearth
-- cooldown. Fixed-destination teleports are deliberately absent even when
-- their name says Hearthstone: Garrison Hearthstone, Dalaran Hearthstone and
-- Zuldazar Hearthstone all go somewhere specific on their own cooldown.
--
-- kind drives the secure dispatch attribute, not ownership: a toy is used via
-- type="toy" and answers PlayerHasToy, a plain item via type="item" and a bag
-- count. The two pairs of slippers are worn rather than carried, so a bag
-- count of zero is all this addon can see of them and the key leaves them
-- alone.
--
-- No localized names, icons or animation data here. The collection adapter
-- resolves display metadata live, and the client exposes no mapping from an
-- item to its cast animation or visual kit.
local HearthstoneDefinitions = {}

HearthstoneDefinitions.VERSION = 3

HearthstoneDefinitions.entries = {
	[6948] = { kind = "item" },                       -- Hearthstone
	[28585] = { kind = "item" },                      -- Ruby Slippers
	[54452] = { kind = "toy" },                       -- Ethereal Portal
	[64488] = { kind = "toy" },                       -- The Innkeeper's Daughter
	[93672] = { kind = "toy" },                       -- Dark Portal
	[142298] = { kind = "item" },                     -- Astonishingly Scarlet Slippers
	[142542] = { kind = "toy" },                      -- Tome of Town Portal
	[162973] = { kind = "toy" },                      -- Greatfather Winter's Hearthstone
	[163045] = { kind = "toy" },                      -- Headless Horseman's Hearthstone
	[165669] = { kind = "toy" },                      -- Lunar Elder's Hearthstone
	[165670] = { kind = "toy" },                      -- Peddlefeet's Lovely Hearthstone
	[165802] = { kind = "toy" },                      -- Noble Gardener's Hearthstone
	[166746] = { kind = "toy" },                      -- Fire Eater's Hearthstone
	[166747] = { kind = "toy" },                      -- Brewfest Reveler's Hearthstone
	[168907] = { kind = "toy" },                      -- Holographic Digitalization Hearthstone
	[172179] = { kind = "toy" },                      -- Eternal Traveler's Hearthstone
	[180290] = { kind = "toy" },                      -- Night Fae Hearthstone
	[182773] = { kind = "toy" },                      -- Necrolord Hearthstone
	[183716] = { kind = "toy" },                      -- Venthyr Sinstone
	[184353] = { kind = "toy" },                      -- Kyrian Hearthstone
	[188952] = { kind = "toy" },                      -- Dominated Hearthstone
	[190196] = { kind = "toy" },                      -- Enlightened Hearthstone
	[190237] = { kind = "toy" },                      -- Broker Translocation Matrix
	[193588] = { kind = "toy" },                      -- Timewalker's Hearthstone
	[200630] = { kind = "toy" },                      -- Ohn'ir Windsage's Hearthstone
	[206195] = { kind = "toy" },                      -- Path of the Naaru
	[208704] = { kind = "toy" },                      -- Deepdweller's Earthen Hearthstone
	[209035] = { kind = "toy" },                      -- Hearthstone of the Flame
	[210455] = { kind = "toy" },                      -- Draenic Hologem
	[212337] = { kind = "toy" },                      -- Stone of the Hearth
	[228940] = { kind = "toy" },                      -- Notorious Thread's Hearthstone
	[235016] = { kind = "toy" },                      -- Redeployment Module
	[236687] = { kind = "toy" },                      -- Explosive Hearthstone
	[245970] = { kind = "toy" },                      -- P.O.S.T. Master's Express Hearthstone
	[246565] = { kind = "toy", spellID = 1242509 },   -- Cosmic Hearthstone
	[250411] = { kind = "item" },                     -- Timerunner's Hearthstone
	[257736] = { kind = "toy" },                      -- Lightcalled Hearthstone
	[263489] = { kind = "toy" },                      -- Naaru's Enfold
	[263933] = { kind = "toy" },                      -- Preyseeker's Hearthstone
	[264367] = { kind = "toy" },                      -- Mycomancer's Hearthspore
	[265100] = { kind = "toy" },                      -- Corewarden's Hearthstone
}

-- Exact lookup by numeric item ID: no coercion, no mutation, nil for unknown.
function HearthstoneDefinitions.Lookup(itemID)
	return HearthstoneDefinitions.entries[itemID]
end

ns.HearthstoneDefinitions = HearthstoneDefinitions
return HearthstoneDefinitions
