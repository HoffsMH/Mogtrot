local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

local Pins = ns.Pins or require("Pins")

-- Records acquisition events before the collection journal has to know the
-- ID. One bound caller-owned pin domain; OnAcquired translates straight into
-- Pins.RecordAcquired and notifies only for newly recorded acquisitions.
local PinController = {}

function PinController.New(domain, deps)
	local controller = { domain = domain, deps = deps }

	function controller:BindDomain(newDomain)
		self.domain = newDomain
	end

	function controller:OnAcquired(id)
		if not self.domain then return false end
		local recorded = Pins.RecordAcquired(self.domain, id, self.deps.now())
		if recorded and self.deps.changed then self.deps.changed() end
		return recorded
	end

	return controller
end

ns.PinController = PinController
return PinController
