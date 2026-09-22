local _, ns = ...
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- Deferred authoritative outfit-transition guard. Synchronous
-- TRANSMOG_DISPLAYED_OUTFIT_CHANGED events only mark that a read is due; the
-- authoritative active outfit ID is read on the next scheduled frame and
-- compared against the guard. The first successful read initializes the guard
-- without dispatching, so login never looks like a change. Reader, scheduler
-- and onChanged are injected; nothing here touches the clock or WoW.
local OutfitTransition = {}

function OutfitTransition.New(reader, schedule, onChanged)
	local controller = {
		guard = nil,
		known = false, -- a successful read has set the guard
		reading = false,
		cycle = 0,
	}

	local function Read(cycle)
		if cycle ~= controller.cycle then return end
		local id = reader()

		if id == nil then
			-- The client may not answer yet (loading screen). One retry, then
			-- the cycle ends and the guard is left alone.
			if not controller.retryDone then
				controller.retryDone = true
				schedule(function() Read(cycle) end)
			end
			return
		end

		controller.retryDone = nil
		if not controller.known then
			-- First authoritative answer: initialize silently.
			controller.guard = id
			controller.known = true
		elseif id ~= controller.guard then
			controller.guard = id
			onChanged(id)
		end
	end

	local function BeginCycle(self)
		self.cycle = self.cycle + 1
		self.retryDone = nil
		local cycle = self.cycle
		self.reading = true
		schedule(function()
			if cycle ~= self.cycle then return end
			self.reading = false
			Read(cycle)
		end)
	end

	function controller:Initialize()
		BeginCycle(self)
	end


	-- Coalesce synchronous events before the frame runs into one read.
	function controller:OutfitChanged()
		if self.reading then return end
		BeginCycle(self)
	end

	return controller
end

ns.OutfitTransition = OutfitTransition
return OutfitTransition
