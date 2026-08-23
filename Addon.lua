local _, ns = ...
if type(ns) ~= "table" then ns = {} end

-- The one coordinator shared by the addon's files. Blizzard frames it owns are
-- adapters for events and display, not the addon object itself.
local Addon = {}

ns.Addon = Addon
return Addon
