local _, ns = ...
if type(ns) ~= "table" then ns = {} end

local MountPins = ns.MountPins or require("MountPins")

-- Records mount acquisition events before the journal has to know the mount.
local MountPinController = {}

function MountPinController.New(account, deps)
	local controller = { account = account, deps = deps }

	function controller:BindStore(store)
		self.account = store
	end

	function controller:OnNewMount(mountID)
		if not self.account then return false end
		local recorded = MountPins.RecordAcquired(self.account, mountID, self.deps.now())
		if recorded and self.deps.changed then self.deps.changed() end
		return recorded
	end

	return controller
end

ns.MountPinController = MountPinController
return MountPinController
