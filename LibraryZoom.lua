local ADDON_NAME, ns = ...
-- Loaded two ways: by the client, where ... is (name, shared table), and by
-- require in the test runner, where ... is the module name and ns is nil.
if type(ns) ~= "table" then ns = {} end -- luacheck: ignore 331/ns

-- How far the library wall is zoomed, and what a drag does to it.
--
-- A zoom here is a factor of whatever distance a scene shipped with, never a
-- distance in world units: one number then frames every card, whatever camera
-- its own scene came with. Smaller is closer.
--
-- Every answer is computed from where the drag started, so asking twice during
-- one drag answers where the cursor is, not where it went. A factor stepped
-- per frame instead compounds sixty times a second and buries the camera in
-- the model. The module touches no globals, no WoW API and no clock.
local LibraryZoom = {}

-- The bounds sit inside what the saved value is read back at, so a wall left
-- at either end still looks the same after a reload.
LibraryZoom.MIN = 0.1
LibraryZoom.MAX = 3

-- Pixels of drag per halving or doubling, and clicks of the button per the
-- same. Both slow enough to stop where you meant to.
LibraryZoom.PIXELS_PER_DOUBLING = 200
LibraryZoom.STEPS_PER_DOUBLING = 8

-- Refuses anything a factor cannot be made of, nan included: it compares equal
-- to nothing, so it would slip through both bounds and reach the camera.
local function Number(value)
	if type(value) ~= "number" or value ~= value then return nil end
	return value
end

function LibraryZoom.Clamp(factor)
	local value = Number(factor)
	if not value then return nil end
	if value < LibraryZoom.MIN then return LibraryZoom.MIN end
	if value > LibraryZoom.MAX then return LibraryZoom.MAX end
	return value
end

-- Where a drag that began at startY with the wall at startFactor has reached
-- now that the cursor is at y. Cursor y grows upward, and up is in.
--
-- Multiplying rather than adding is what makes the same drag mean the same
-- thing at both ends of the range: a fixed amount of distance per pixel
-- crawls while the camera is far out and crosses the whole range in a flick
-- once it is close.
function LibraryZoom.Drag(startFactor, startY, y)
	local start, from, to = Number(startFactor), Number(startY), Number(y)
	if not (start and from and to) then return nil end
	return LibraryZoom.Clamp(start * 2 ^ ((from - to) / LibraryZoom.PIXELS_PER_DOUBLING))
end

-- One press of a zoom button. Positive steps zoom in, the way dragging up
-- does, so both controls agree on which way is closer.
function LibraryZoom.Step(factor, steps)
	local value, count = Number(factor), Number(steps)
	if not (value and count) then return nil end
	return LibraryZoom.Clamp(value * 2 ^ (-count / LibraryZoom.STEPS_PER_DOUBLING))
end

-- The factor as the readout says it: a percentage that grows as the model
-- does. A factor shrinks as the camera closes in, which is the right number
-- and the wrong direction for anybody reading it off a button.
function LibraryZoom.Magnification(factor)
	local value = Number(factor)
	if not value or value <= 0 then return nil end
	return math.floor(100 / value + 0.5)
end

ns.LibraryZoom = LibraryZoom
return LibraryZoom
