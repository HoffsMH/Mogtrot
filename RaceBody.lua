local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Race and sex to a creature display ID that renders a plain, textured body.
--
-- Needed because a stored outfit has to be shown on some body once its wearer
-- is gone, and a live player's own display ID renders as an untextured
-- silhouette: a player has no static display row to composite from. A static
-- creature row does, so a record can be replayed on a body of the right race.
--
-- Every entry is a gearless base body, not a named NPC. The obvious-looking
-- source is wrong twice over: ChrRaces lost its display columns after 8.0, and
-- the ChrModel rows that replaced them carry no baked skin, so they render
-- blank. These come from CreatureDisplayInfoExtra rows that do carry one.
--
-- Sex follows UnitSex, which is 2 for male and 3 for female. That is not the
-- Enum.UnitSex convention, which is 0 and 1; both are live in the client.
local RaceBody = {}

RaceBody.VERSION = 1

RaceBody.MALE, RaceBody.FEMALE = 2, 3

RaceBody.bodies = {
	[1]  = { male = 55239,  female = 55238  }, -- Human
	[2]  = { male = 55257,  female = 55256  }, -- Orc
	[3]  = { male = 55241,  female = 55240  }, -- Dwarf
	[4]  = { male = 55243,  female = 55242  }, -- Night Elf
	[5]  = { male = 55259,  female = 55258  }, -- Undead
	[6]  = { male = 55261,  female = 55260  }, -- Tauren
	[7]  = { male = 55245,  female = 55244  }, -- Gnome
	[8]  = { male = 55263,  female = 55262  }, -- Troll
	[9]  = { male = 55267,  female = 55266  }, -- Goblin
	[10] = { male = 55265,  female = 55264  }, -- Blood Elf
	[11] = { male = 55247,  female = 55246  }, -- Draenei
	-- UnitRace answers 22 in both worgen and human form, so the form has to be
	-- recorded separately; this is the worgen body.
	[22] = { male = 55255,  female = 55254  }, -- Worgen
	[24] = { male = 55251,  female = 55250  }, -- Pandaren, neutral
	[25] = { male = 55249,  female = 55248  }, -- Pandaren, Alliance
	-- Horde Pandaren have no gearless row of their own and share the model.
	[26] = { male = 55251,  female = 55250  }, -- Pandaren, Horde
	[27] = { male = 117534, female = 117535 }, -- Nightborne
	[28] = { male = 117536, female = 117537 }, -- Highmountain Tauren
	[29] = { male = 117528, female = 117529 }, -- Void Elf
	[30] = { male = 117530, female = 117531 }, -- Lightforged Draenei
	[31] = { male = 96149,  female = 96150  }, -- Zandalari Troll
	[32] = { male = 96145,  female = 96146  }, -- Kul Tiran
	[34] = { male = 117532, female = 117533 }, -- Dark Iron Dwarf
	[35] = { male = 96147,  female = 96148  }, -- Vulpera
	[36] = { male = 88420,  female = 88410  }, -- Mag'har Orc
	[37] = { male = 96151,  female = 96152  }, -- Mechagnome
	-- Dracthyr render as their visage here. The dragon body is one sexless
	-- mesh and is deliberately absent until one is verified in game.
	[52] = { male = 112798, female = 112797 }, -- Dracthyr, Alliance
	[70] = { male = 112798, female = 112797 }, -- Dracthyr, Horde
	[75] = { male = 112798, female = 112797 }, -- Visage, Alliance
	[76] = { male = 112798, female = 112797 }, -- Visage, Horde
	[84] = { male = 118657, female = 118658 }, -- Earthen, Horde
	[85] = { male = 118111, female = 118112 }, -- Earthen, Alliance
	[86] = { male = 140493, female = 140492 }, -- Haranir, Alliance
	[91] = { male = 140503, female = 140502 }, -- Haranir, Horde
}

-- Returns displayID, or nil plus a reason. A miss is expected the patch a new
-- playable race ships, so the caller must degrade rather than guess: never
-- substitute a base model ID or a live player's ID, because both render as an
-- untextured body that reads as a broken addon.
function RaceBody.Lookup(raceID, sex)
	if type(raceID) ~= "number" then return nil, "no race ID" end
	local entry = RaceBody.bodies[raceID]
	if not entry then return nil, ("no body for race %d"):format(raceID) end

	if sex == RaceBody.FEMALE then return entry.female end
	if sex == RaceBody.MALE then return entry.male end
	return nil, ("unexpected sex %s"):format(tostring(sex))
end

ns.RaceBody = RaceBody
return RaceBody
