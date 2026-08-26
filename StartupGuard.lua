local ADDON_NAME, ns = ...

local StartupGuard = {}

function StartupGuard.OtherName(addonName)
	if addonName == "Mogtrot" then return "MogtrotDev" end
	if addonName == "MogtrotDev" then return "Mogtrot" end
end

function StartupGuard.DatabaseNames(addonName)
	if addonName == "MogtrotDev" then return "MogtrotDevDB", "MogtrotDevCharDB" end
	return "MogtrotDB", "MogtrotCharDB"
end

function StartupGuard.IsConflict(addonName, deps)
	local other = StartupGuard.OtherName(addonName)
	if not other or not deps.getInfo(other) then return false end
	return deps.getEnableState(other, deps.character and deps.character()) ~= 0
end

function StartupGuard.Resolve(keep, character, disable, reload)
	disable(StartupGuard.OtherName(keep), character)
	reload()
end

local function ShowConflict()
	if _G.MogtrotAddonConflictShown then return end
	_G.MogtrotAddonConflictShown = true

	StaticPopupDialogs.MOGTROT_ADDON_CONFLICT = {
		text = "Both Mogtrot and MogtrotDev are enabled, so Mogtrot did not start. "
			.. "Choose one; the other will be disabled before the UI reloads.",
		button1 = "Use MogtrotDev",
		button2 = "Use Mogtrot",
		OnAccept = function()
			StartupGuard.Resolve("MogtrotDev", UnitGUID("player"), C_AddOns.DisableAddOn, ReloadUI)
		end,
		OnCancel = function()
			StartupGuard.Resolve("Mogtrot", UnitGUID("player"), C_AddOns.DisableAddOn, ReloadUI)
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = false,
		preferredIndex = 3,
	}
	StaticPopup_Show("MOGTROT_ADDON_CONFLICT")
end

if type(ns) == "table" then
	ns.StartupGuard = StartupGuard
	ns.Disabled = StartupGuard.IsConflict(ADDON_NAME, {
		getInfo = C_AddOns.GetAddOnInfo,
		getEnableState = C_AddOns.GetAddOnEnableState,
		character = function() return UnitGUID("player") end,
	})
	if ns.Disabled then ShowConflict() end
end

return StartupGuard
