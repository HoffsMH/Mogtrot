-- Putting a scene camera at an absolute fraction of the distance its scene
-- shipped with, which is what lets a drag drive it without collapsing it.
--
-- The fake camera is Blizzard's orbit camera in miniature: a zoom is kept as a
-- saturated fraction of the span between the camera's own two limits, so a
-- distance outside that span silently becomes the limit, moving a limit moves
-- the camera, and reading the distance back reports wherever it actually
-- ended up rather than what was asked for.
local ProbeRenderUI = require("ProbeRenderUI")

local function Saturate(value)
	if value < 0 then return 0 end
	if value > 1 then return 1 end
	return value
end

local function Camera(distance, minimum, maximum)
	local camera = { min = minimum, max = maximum }
	function camera:SetZoomDistance(value)
		self.percent = Saturate((value - self.min) / (self.max - self.min))
	end
	function camera:GetZoomDistance()
		return self.min + self.percent * (self.max - self.min)
	end
	-- Both limits keep the fraction and move the camera, exactly as the
	-- client's do.
	function camera:SetMinZoomDistance(value) self.min = value end
	function camera:SetMaxZoomDistance(value) self.max = value end
	camera:SetZoomDistance(distance)
	return camera
end

local function Scene(camera)
	return { GetActiveCamera = function() return camera end }
end

describe("ProbeRenderUI.ZoomTo", function()
	it("puts the camera at a fraction of the distance the scene shipped with", function()
		local camera = Camera(4, 2, 10)
		assert.is_true(ProbeRenderUI.ZoomTo(Scene(camera), 0.5))
		assert.is_near(2, camera:GetZoomDistance(), 1e-6)
	end)

	-- The trap. A camera reports where it was last put, so a factor applied to
	-- what it reads back multiplies itself once a frame and ends inside the
	-- model. Asked for the same factor repeatedly, it must not move again.
	it("does not compound when asked for the same factor again", function()
		local camera = Camera(4, 2, 10)
		local scene = Scene(camera)
		for _ = 1, 5 do ProbeRenderUI.ZoomTo(scene, 0.5) end
		assert.is_near(2, camera:GetZoomDistance(), 1e-6)
	end)

	it("follows a factor up and down from the one distance", function()
		local camera = Camera(4, 2, 10)
		local scene = Scene(camera)
		ProbeRenderUI.ZoomTo(scene, 0.5)
		ProbeRenderUI.ZoomTo(scene, 1)
		assert.is_near(4, camera:GetZoomDistance(), 1e-6)
	end)

	-- Both directions leave the span the scene shipped with, and the camera
	-- would silently stop at the edge of it.
	it("zooms out past the distance the scene was framed at", function()
		local camera = Camera(4, 2, 4)
		assert.is_true(ProbeRenderUI.ZoomTo(Scene(camera), 2))
		assert.is_near(8, camera:GetZoomDistance(), 1e-6)
	end)

	it("zooms in past the closest the scene allowed", function()
		local camera = Camera(4, 2, 10)
		assert.is_true(ProbeRenderUI.ZoomTo(Scene(camera), 0.25))
		assert.is_near(1, camera:GetZoomDistance(), 1e-6)
	end)

	-- A scene that has been transitioned is a different scene with a different
	-- camera, and the old distance describes nothing.
	it("takes a fresh distance once the recorded one is cleared", function()
		local scene = Scene(Camera(4, 2, 10))
		ProbeRenderUI.ZoomTo(scene, 0.5)
		scene.mogtrotBaseDistance = nil
		local camera = Camera(8, 2, 20)
		scene.GetActiveCamera = function() return camera end
		ProbeRenderUI.ZoomTo(scene, 0.5)
		assert.is_near(4, camera:GetZoomDistance(), 1e-6)
	end)

	it("refuses a camera that does not zoom", function()
		assert.is_false(ProbeRenderUI.ZoomTo({}, 0.5))
		assert.is_false(ProbeRenderUI.ZoomTo(Scene({}), 0.5))
	end)

	-- A camera with no limits of its own answers zero, or nothing a number
	-- can be scaled from. Remembering that would leave the scene unzoomable
	-- for as long as it lives.
	it("remembers nothing from a camera that reports no distance", function()
		for _, reported in ipairs({ 0, -1, 0 / 0 }) do
			local scene = Scene({
				GetZoomDistance = function() return reported end,
				SetZoomDistance = function() end,
			})
			assert.is_false(ProbeRenderUI.ZoomTo(scene, 0.5))
			assert.is_nil(scene.mogtrotBaseDistance)
		end
	end)
end)
