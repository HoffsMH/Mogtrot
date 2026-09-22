local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Curated, versioned registry of the auras that change how a player is drawn:
-- spellID -> { name, kind }. Adding or removing an entry raises VERSION.
--
-- Inclusion rule: the aura must change the body a transmog is seen on, so it
-- is part of how somebody looked and belongs in the record. A buff that only
-- adds a glow is not here.
--
-- kind says what the change does to the outfit underneath:
--   silhouette - the same body, recoloured or dimmed, transmog still readable
--   replaced   - a different creature entirely, transmog not visible at all
--
-- transient marks a form that is a cooldown rather than a stance. Seeing one
-- says what that player was doing for a few seconds, not how they choose to
-- look, so a reader can rank it below a form somebody stands in all day.
--
-- Nothing here can be rendered yet. An actor takes a spell visual kit ID, but
-- no Lua call maps an aura to its kit, so reproducing these needs the kit IDs
-- read out of the client database first. Recording the fact costs nothing and
-- is the half that cannot be recovered later.
local FormDefinitions = {}

FormDefinitions.VERSION = 2

FormDefinitions.entries = {
	-- Priest. Shadowform darkens the body to a shadow of itself; the mog still
	-- reads, which is the whole reason a shadow priest's silhouette matters.
	[232698] = { name = "Shadowform", kind = "silhouette" },
	[228260] = { name = "Voidform", kind = "silhouette", transient = true },

	-- Druid. Moonkin replaces the body outright. Glyph of Stars converts that
	-- into Astral Form, which is the player's own body lit from within, so the
	-- transmog comes back.
	[24858] = { name = "Moonkin Form", kind = "replaced" },
	[197625] = { name = "Moonkin Form", kind = "replaced" },
	[102560] = { name = "Incarnation: Chosen of Elune", kind = "replaced", transient = true },
	[390414] = { name = "Incarnation: Chosen of Elune", kind = "replaced", transient = true },
	[114301] = { name = "Glyph of Stars", kind = "silhouette" },
	[114302] = { name = "Astral Form", kind = "silhouette" },
}

-- Exact lookup by numeric spell ID: no coercion, no mutation, nil for unknown.
function FormDefinitions.Lookup(spellID)
	return FormDefinitions.entries[spellID]
end

-- Whether a form is a cooldown rather than a stance.
function FormDefinitions.IsTransient(spellID)
	local entry = FormDefinitions.entries[spellID]
	return entry ~= nil and entry.transient == true
end

-- The first entry among the auras a unit carries, as spellID, name, kind.
-- Order is the client's aura order, which is not meaningful, so a unit
-- carrying two of these gets whichever came first; none of them stack in
-- practice.
function FormDefinitions.FromSpellIDs(spellIDs)
	if type(spellIDs) ~= "table" then return nil end
	for _, spellID in ipairs(spellIDs) do
		local entry = FormDefinitions.entries[spellID]
		if entry then return spellID, entry.name, entry.kind end
	end
	return nil
end

ns.FormDefinitions = FormDefinitions
return FormDefinitions
