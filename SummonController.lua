local _, ns = ...

-- Coordinates mount selection, fallback behavior, and summon feedback.
local SummonController = {}

local function Format(fmt, ...)
	if select("#", ...) == 0 then return fmt end
	return fmt:format(...)
end

function SummonController.Attach(Addon, deps)
	local MountTravelSnapshot = deps.mountTravelSnapshot

local SUMMON_BINDING = "CLICK MogtrotSummon:LeftButton"

local SUMMON_COMPLAINT_GAP = 10

local function SummonBindingKey()
	return GetBindingKey(SUMMON_BINDING)
end

function Addon:SummonMaySpeak()
	local now = GetTime()
	if self.lastSummonComplaint and now - self.lastSummonComplaint < SUMMON_COMPLAINT_GAP then
		return false
	end
	self.lastSummonComplaint = now
	return true
end

function Addon:RefuseSummon(alsoChat, fmt, ...)
	local text = Format(fmt, ...)
	UIErrorsFrame:AddMessage("Mogtrot: " .. text, 1, 0.3, 0.3)
	if not alsoChat then return end
	if not self:SummonMaySpeak() then return end
	self:Say(text)
end

function Addon:SaySummon(lines)
	if #lines == 0 or not self:SummonMaySpeak() then return end
	for _, line in ipairs(lines) do
		self:Say(line)
	end
end

local FALLBACK_MODES = { random = true, pinned = true, litemount = true, off = true }

function Addon:FallbackMode()
	local mode = MogtrotDB.fallbackMode
	return (mode and FALLBACK_MODES[mode]) and mode or "random"
end

local function LiteMountFallbackAvailable()
	return _G.LiteMount ~= nil
end

local function LiteMountFallbackReady()
	return _G.LM_B1 ~= nil
end

local targetMountNameIndex, targetMountIndexCount

local function TargetMountNames()
	local mountIDs = C_MountJournal.GetMountIDs()
	if targetMountNameIndex and targetMountIndexCount == #mountIDs then
		return targetMountNameIndex
	end

	local names = {}
	for _, mountID in ipairs(mountIDs) do
		local name, spellID, _icon, _isActive, _isUsable, _sourceType, _isFavorite,
			_isFactionSpecific, _faction, shouldHideOnChar, isCollected =
			C_MountJournal.GetMountInfoByID(mountID)
		if name and isCollected and not shouldHideOnChar then
			local spellName = C_Spell.GetSpellName(spellID)
			for _, candidate in ipairs({ name, spellName }) do
				if candidate then
					names[candidate] = names[candidate] or {}
					if names[candidate][#names[candidate]] ~= mountID then
						table.insert(names[candidate], mountID)
					end
				end
			end
		end
	end
	targetMountNameIndex = names
	targetMountIndexCount = #mountIDs
	return names
end

local function InspectTargetMount(mountID)
	local name, _spellID, _icon, _isActive, _isUsable, _sourceType, _isFavorite,
		_isFactionSpecific, _faction, shouldHideOnChar, isCollected =
		C_MountJournal.GetMountInfoByID(mountID)
	if not name then return { exists = false } end
	local usable, useError = C_MountJournal.GetMountUsabilityByID(mountID, true)
	return {
		exists = true,
		name = name,
		collected = isCollected and true or false,
		hidden = shouldHideOnChar and true or false,
		usable = usable and true or false,
		error = useError,
	}
end

local function ReadTargetMount()
	if not MogtrotDB.matchTargetMount then return { enabled = false } end
	if not UnitExists("target") then return { enabled = true, reason = "no-target" } end
	if not UnitIsPlayer("target") then return { enabled = true, reason = "not-player" } end
	if C_Secrets.ShouldAurasBeSecret() then
		return { enabled = true, reason = "secret" }
	end

	local nameIndex
	for index = 1, 255 do
		local aura = C_UnitAuras.GetAuraDataByIndex("target", index, "HELPFUL")
		if issecretvalue(aura) then return { enabled = true, reason = "secret" } end
		if aura == nil then break end

		local auraName = aura.name
		if issecretvalue(auraName) then return { enabled = true, reason = "secret" } end
		local matches
		if auraName then
			nameIndex = nameIndex or TargetMountNames()
			matches = nameIndex[auraName]
		end

		local spellID = aura.spellId
		if issecretvalue(spellID) then return { enabled = true, reason = "secret" } end
		if spellID then
			local mountID = C_MountJournal.GetMountFromSpell(spellID)
			if issecretvalue(mountID) then return { enabled = true, reason = "secret" } end
			if mountID then
				return { enabled = true, exactMountID = mountID, nameMatches = matches }
			end
		end

		if matches then return { enabled = true, nameMatches = matches } end
	end
	return { enabled = true, reason = "unidentified" }
end

local function FallbackDid(plan)
	if plan.from == "favourite" then return "a random favourite" end
	if plan.from == "collection" then
		return "a random mount from your collection"
	end
	return "a pinned mount"
end

local function SummonRefusalText(plan, outfitName)
	if plan.reason == "nomounts" then
		return ("no mounts linked to '%s' - open Mogtrot and pick some."):format(outfitName)
	elseif plan.reason == "litemountunavailable" then
		return "LiteMount fallback is selected, but its compatibility button is not ready."
	elseif plan.reason == "nocollection" then
		return "no mounts on this character to fall back on yet."
	elseif plan.reason == "collectionunusable" then
		return plan.detail or "no mount you own can be used here."
	elseif plan.reason == "unusable" then
		return plan.detail or "no mount linked to this outfit can be used here."
	elseif plan.reason == "unsuitable" then
		return "no mount linked to this outfit can fly here."
	end
	return "no outfit is active, so there is no mount set to draw from."
end

local function SummonCauseText(plan, outfitName)
	if plan.cause == "nomounts" then
		return ("no mounts linked to '%s', so this is %s. /mogtrot fallback changes that.")
			:format(outfitName, FallbackDid(plan))
	end
	if plan.cause == "unsuitable" then
		return ("no mount linked to '%s' can fly here, so this is %s. "
			.. "/mogtrot fallback changes that."):format(outfitName, FallbackDid(plan))
	end
	return ("no outfit is active, so this is %s. /mogtrot fallback changes that.")
		:format(FallbackDid(plan))
end

local function MountIDsText(ids)
	local text = {}
	for _, mountID in ipairs(ids or {}) do
		table.insert(text, tostring(mountID))
	end
	return #text > 0 and table.concat(text, ",") or "none"
end

local summonShuffleState = {}

local function SummonCollectionSnapshot()
	local collection = {}
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local name, _spellID, _icon, _isActive, _isUsable, _sourceType, isFavorite,
			_isFactionSpecific, _faction, shouldHideOnChar, isCollected =
			C_MountJournal.GetMountInfoByID(mountID)
		if name then
			local usable, useError = C_MountJournal.GetMountUsabilityByID(mountID, true)
			collection[mountID] = {
				name = name,
				collected = isCollected and true or false,
				hidden = shouldHideOnChar and true or false,
				favorite = isFavorite and true or false,
				usable = usable and true or false,
				error = useError,
			}
		end
	end
	return collection
end

function Addon:SummonForActiveOutfit(canDelegateLiteMount)
	local outfitID = C_TransmogOutfitInfo.GetActiveOutfitID()
	local hasOutfit = outfitID ~= nil and outfitID ~= 0
	local info = hasOutfit and self.outfitsByID and self.outfitsByID[outfitID]
	local outfitName = info and info.name or tostring(outfitID)
	local set = hasOutfit and self:GetOutfitMounts(outfitID) or nil
	local preference = MountTravelSnapshot()
	local pinnedMountIDs = ns.MountPins.ActiveSet(MogtrotDB, time())
	local target, targetReason, targetDetail = ns.TargetMount.Resolve(
		ReadTargetMount(), InspectTargetMount)
	local result = ns.SummonDecision.Decide({
		collection = SummonCollectionSnapshot(),
		situation = {
			mounted = IsMounted(),
			combat = InCombatLockdown(),
			targetMountID = target and target.mountID or nil,
			swimming = preference and preference.situation.swimming,
			submerged = preference and preference.situation.submerged,
			advancedFlyable = preference and preference.situation.advancedFlyable,
			flyable = preference and preference.situation.flyable,
			drivable = preference and preference.situation.drivable,
		},
		outfit = hasOutfit and { id = outfitID, name = outfitName, linkedMountIDs = set }
			or nil,
		pinnedMountIDs = pinnedMountIDs,
		preferences = {
			fallbackMode = self:FallbackMode(),
			shufflePinned = not (MogtrotCharDB.noPinnedShuffle
				and MogtrotCharDB.noPinnedShuffle[outfitID]),
			matchTarget = MogtrotDB.matchTargetMount and true or false,
		},
		integrations = { liteMountReady = LiteMountFallbackReady() and true or false },
		mountTypes = preference and preference.types,
		mountType = preference and preference.mountType,
		requirePreferred = preference and preference.requirePreferred,
		shuffle = summonShuffleState,
		random = math.random,
		now = GetTime(),
	})
	local plan = result.intent
	summonShuffleState = result.shuffle
	if plan.action == "dismiss" then
		C_MountJournal.Dismiss()
		return
	end
	if plan.reason == "combat" then
		self:RefuseSummon(false, "can't summon in combat.")
		return
	end
	self:Debug("target match: %s source=%s mount=%s detail=%s",
		tostring(target and target.reason or targetReason),
		tostring(target and target.source), tostring(target and target.mountID),
		tostring(targetDetail))
	self:Debug("summon plan: action=%s reason=%s cause=%s mode=%s LiteMount=%s ready=%s",
		tostring(plan.action), tostring(plan.reason), tostring(plan.cause),
		tostring(self:FallbackMode()), tostring(LiteMountFallbackAvailable()),
		tostring(LiteMountFallbackReady()))
	if preference then
		local situation = preference.situation
		self:Debug("summon preference: swimming=%s submerged=%s flyable=%s advanced=%s "
			.. "drivable=%s tier=%s candidates=%s choice=%s",
			tostring(situation.swimming), tostring(situation.submerged),
			tostring(situation.flyable), tostring(situation.advancedFlyable),
			tostring(situation.drivable), tostring(plan.preferenceTier),
			MountIDsText(plan.candidates), tostring(plan.mountID))
	end

	local lines = {}
	if plan.action == "litemount" then
		if canDelegateLiteMount then return true end
		self:RefuseSummon(true, "LiteMount fallback needs the Mogtrot keybinding or "
			.. "action-bar macro.")
		return
	end

	if plan.action == "refuse" then
		local text = SummonRefusalText(plan, outfitName)
		UIErrorsFrame:AddMessage("Mogtrot: " .. text, 1, 0.3, 0.3)
		local situational = plan.reason == "unusable" or plan.reason == "collectionunusable"
		if not situational then table.insert(lines, text) end
		self:SaySummon(lines)
		return
	end

	if plan.cause then table.insert(lines, SummonCauseText(plan, outfitName)) end
	self:SaySummon(lines)

	if plan.from == "outfit" then
		local spellID = select(2, C_MountJournal.GetMountInfoByID(plan.mountID))
		summonShuffleState = ns.SummonDecision.Transition(summonShuffleState, {
			type = "stage", outfitID = outfitID, mountID = plan.mountID,
			spellID = spellID, now = GetTime(),
		})
		C_Timer.After(10, function()
			summonShuffleState = ns.SummonDecision.Transition(summonShuffleState,
				{ type = "expire", now = GetTime() })
		end)
	end
	C_MountJournal.SummonByID(plan.mountID)
end

function Addon:SummonBindingText()
	local key = SummonBindingKey()
	if key then
		return ("summon keybinding: %s."):format(key)
	end
	return "summon keybinding: not bound - it is 'Summon a mount for this outfit' "
		.. "under Key Bindings, Mogtrot."
end

function Addon:SummonFallbackText()
	local mode = self:FallbackMode()
	if mode == "off" then
		return "summon fallback: off - with no outfit or no linked mounts the key "
			.. "explains itself instead."
	end
	if mode == "pinned" then
		local count = 0
		for _ in pairs(ns.MountPins.ActiveSet(MogtrotDB, time())) do count = count + 1 end
		return ("summon fallback: a pinned mount (%d active)."):format(count)
	end
	if mode == "litemount" then
		if LiteMountFallbackAvailable() then
			return "summon fallback: LiteMount when the active outfit has no linked mounts."
		end
		return "summon fallback: LiteMount selected, but its compatibility button is unavailable."
	end
	return "summon fallback: a random mount - a favourite if you have any, "
		.. "otherwise anything you own."
end

function Addon:NoticeSummonBindingOnce()
	if MogtrotDB.summonNoticed then return end
	if self:LiteMountInstalled() or SummonBindingKey() then return end

	MogtrotDB.summonNoticed = true
	self:Warn("linked mounts need a key of their own without LiteMount. Bind 'Summon a "
		.. "mount for this outfit' under Key Bindings, Mogtrot - or /mogtrot summon.")
	self:Warn("with no outfit on, or no mounts linked to it, that key summons a random "
		.. "mount - a favourite if you have any. Mogtrot's settings panel, or "
		.. "/mogtrot fallback, changes that.")
end

function Addon:OpenFallbackPicker()
	local mode = self:FallbackMode()

	local items = {
		{ name = "Random mount", note = "default - a favourite if you have one",
			noteDim = true, mode = "random",
			preselected = (mode == "random") or nil },
		{ name = "Pinned mount", mode = "pinned",
			note = "choose among active pins", noteDim = true,
			preselected = (mode == "pinned") or nil },
	}
	if LiteMountFallbackAvailable() then
		table.insert(items, { name = "LiteMount", mode = "litemount",
			note = "when the active outfit has no linked mounts", noteDim = true,
			preselected = (mode == "litemount") or nil })
	end
	table.insert(items, { name = "Nothing, just say why", mode = "off", divider = true,
		preselected = (mode == "off") or nil })

	ns.OpenSearchPicker({
		title = "Mount when the outfit has none",
		searchHint = "Search your mounts",
		emptyText = "No mounts match.",
		items = items,
		buttons = {
			{
				text = "Use this", width = 90,
				tipTitle = "Summon fallback",
				tipBody = "What the summon key does when no outfit is on, or the outfit "
					.. "you are wearing has no mounts linked to it.",
				onClick = function(chosen) Addon:SetSummonFallback(chosen[1]) end,
			},
		},
	})
end

function Addon:SetSummonFallback(choice)
	MogtrotDB.fallbackMode = choice.mode
	self:Say(self:SummonFallbackText())
	self:RepaintMountCards()
end

function Addon:IsMountPinned(mountID)
	return ns.MountPins.IsPinned(MogtrotDB, mountID, time())
end

function Addon:ToggleMountPin(mountID)
	if self:IsMountPinned(mountID) then
		ns.MountPins.Unpin(MogtrotDB, mountID)
	else
		ns.MountPins.Pin(MogtrotDB, mountID, time())
	end
	self:RepaintMountCards()
end

function Addon:SetMountPinDays(mountID, days)
	return ns.MountPins.SetDaysRemaining(MogtrotDB, mountID, days, time())
end

function Addon:KeepMountPinned(mountID)
	ns.MountPins.Keep(MogtrotDB, mountID)
	self:RepaintMountCards()
end

	local controller = {}
	function controller:Transition(event)
		summonShuffleState = ns.SummonDecision.Transition(summonShuffleState, event)
	end
	return {
		controller = controller,
		fallbackModes = FALLBACK_MODES,
		liteMountFallbackAvailable = LiteMountFallbackAvailable,
	}
end

ns.SummonController = SummonController
return SummonController
