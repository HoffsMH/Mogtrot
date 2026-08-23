local ADDON_NAME, ns = ...
if type(ns) ~= "table" then ns = {} end

local MountType = {}

-- Derived from Mount, MountTypeXCapability, MountCapability and SpellName in
-- Blizzard build 12.1.0.69273. Values omitted here are internal, test, racing,
-- or otherwise not ordinary journal mounts.
local CAPABILITIES = {
	[230] = { ground = true },
	[231] = { ground = true, aquatic = true },
	[232] = { aquatic = true },
	[241] = { ground = true },
	[242] = { flying = true },
	[247] = { flying = true },
	[254] = { aquatic = true },
	[284] = { ground = true },
	[291] = { ground = true },
	[402] = { flying = true, dragonriding = true },
	[407] = { flying = true, aquatic = true },
	[408] = { ground = true },
	[412] = { ground = true, aquatic = true },
	[424] = { flying = true, dragonriding = true },
	[436] = { flying = true, aquatic = true, dragonriding = true },
	[437] = { flying = true, dragonriding = true },
	[444] = { flying = true, dragonriding = true },
	[445] = { flying = true, dragonriding = true },
}

function MountType.Classify(mountTypeID, enum)
	local capabilities = CAPABILITIES[mountTypeID]
	if not capabilities or not enum then return nil end

	local types = {}
	if capabilities.ground then types[enum.Ground] = true end
	if capabilities.flying then types[enum.Flying] = true end
	if capabilities.aquatic then types[enum.Aquatic] = true end
	if capabilities.dragonriding then types[enum.Dragonriding] = true end
	return next(types) and types or nil
end

ns.MountType = MountType
return MountType
