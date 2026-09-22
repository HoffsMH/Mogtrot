-- The arithmetic behind dragging a library card up and down.
--
-- The contract: a zoom is a factor of whatever distance a scene shipped with,
-- so the module is scale free and knows nothing about cameras. A drag is
-- computed from where it started, never from the last frame, which is the
-- whole reason this is a module: a factor accumulated per frame collapses the
-- camera into the model. The spec requires only LibraryZoom, which is also the
-- proof that it touches no globals and no WoW API.
local LibraryZoom = require("LibraryZoom")

-- Pixels of drag per halving or doubling, as the module defines it. Read back
-- rather than hardcoded so a change of feel is a change of one number.
local SPAN = LibraryZoom.PIXELS_PER_DOUBLING

describe("LibraryZoom.Clamp", function()
	it("passes a factor inside the bounds through untouched", function()
		assert.equal(0.85, LibraryZoom.Clamp(0.85))
	end)

	it("holds at the bounds", function()
		assert.equal(LibraryZoom.MIN, LibraryZoom.Clamp(LibraryZoom.MIN / 10))
		assert.equal(LibraryZoom.MAX, LibraryZoom.Clamp(LibraryZoom.MAX * 10))
	end)

	-- Whatever it hands back has to survive being written to the saved
	-- variables and read again, and the reader refuses anything at or below
	-- 0.05 or above 6.
	it("stays inside what the saved value is read back at", function()
		assert.is_true(LibraryZoom.MIN > 0.05)
		assert.is_true(LibraryZoom.MAX <= 6)
	end)

	it("answers nothing for what is not a number", function()
		assert.is_nil(LibraryZoom.Clamp(nil))
		assert.is_nil(LibraryZoom.Clamp("0.5"))
		assert.is_nil(LibraryZoom.Clamp({}))
		assert.is_nil(LibraryZoom.Clamp(0 / 0))
	end)
end)

describe("LibraryZoom.Drag", function()
	it("leaves the factor alone while the cursor has not moved", function()
		assert.equal(0.85, LibraryZoom.Drag(0.85, 400, 400))
	end)

	-- Cursor y grows upward in this client, and up is in: the model gets
	-- closer, which is a smaller fraction of the distance it shipped at.
	it("halves the factor over a span dragged up", function()
		assert.is_near(0.4, LibraryZoom.Drag(0.8, 400, 400 + SPAN), 1e-9)
	end)

	it("doubles the factor over a span dragged down", function()
		assert.is_near(1.6, LibraryZoom.Drag(0.8, 400, 400 - SPAN), 1e-9)
	end)

	-- The same drag has to mean the same thing whatever the wall was already
	-- at, which is what multiplying rather than adding buys.
	it("moves by a ratio, not by a fixed amount of distance", function()
		local half = LibraryZoom.Drag(0.4, 0, SPAN) / 0.4
		assert.is_near(half, LibraryZoom.Drag(1.6, 0, SPAN) / 1.6, 1e-9)
	end)

	-- The trap this module exists for. Asked twice during one drag, the
	-- second answer is where the cursor is now, not that answer moved again.
	it("reads from the start of the drag rather than accumulating", function()
		local partway = LibraryZoom.Drag(0.8, 400, 400 + SPAN / 2)
		assert.is_true(partway > 0.4)
		assert.is_near(LibraryZoom.Drag(0.8, 400, 400 + SPAN),
			LibraryZoom.Drag(0.8, 400, 400 + SPAN), 1e-9)
		assert.is_near(0.4, LibraryZoom.Drag(0.8, 400, 400 + SPAN), 1e-9)
	end)

	it("holds at the bounds however far the drag goes", function()
		assert.equal(LibraryZoom.MIN, LibraryZoom.Drag(0.85, 0, 100000))
		assert.equal(LibraryZoom.MAX, LibraryZoom.Drag(0.85, 0, -100000))
	end)

	-- Held at a bound and dragged back, the wall follows the cursor again
	-- rather than starting from the bound it was stuck on.
	it("comes back off a bound on the way home", function()
		local out = LibraryZoom.Drag(0.85, 0, -100000)
		assert.equal(LibraryZoom.MAX, out)
		assert.is_near(0.85, LibraryZoom.Drag(0.85, 0, 0), 1e-9)
	end)

	it("answers nothing for what is not a number", function()
		assert.is_nil(LibraryZoom.Drag(nil, 0, 10))
		assert.is_nil(LibraryZoom.Drag(0.85, nil, 10))
		assert.is_nil(LibraryZoom.Drag(0.85, 0, nil))
	end)
end)

describe("LibraryZoom.Step", function()
	it("zooms in on a positive step and out on a negative one", function()
		assert.is_true(LibraryZoom.Step(0.85, 1) < 0.85)
		assert.is_true(LibraryZoom.Step(0.85, -1) > 0.85)
	end)

	it("takes a whole doubling in the steps it says it does", function()
		assert.is_near(0.4, LibraryZoom.Step(0.8, LibraryZoom.STEPS_PER_DOUBLING), 1e-9)
	end)

	it("holds at the bounds", function()
		assert.equal(LibraryZoom.MIN, LibraryZoom.Step(LibraryZoom.MIN, 1))
		assert.equal(LibraryZoom.MAX, LibraryZoom.Step(LibraryZoom.MAX, -1))
	end)

	it("answers nothing for what is not a number", function()
		assert.is_nil(LibraryZoom.Step(nil, 1))
		assert.is_nil(LibraryZoom.Step(0.85, nil))
	end)
end)

describe("LibraryZoom.Magnification", function()
	-- What the readout says. A factor is a distance, so it reads backwards to
	-- anyone looking at a model: the number shown grows as the model does.
	it("reads the shipped framing as a hundred percent", function()
		assert.equal(100, LibraryZoom.Magnification(1))
	end)

	it("grows as the camera comes closer", function()
		assert.equal(200, LibraryZoom.Magnification(0.5))
		assert.equal(50, LibraryZoom.Magnification(2))
	end)

	it("rounds to a whole percent", function()
		assert.equal(118, LibraryZoom.Magnification(0.85))
		assert.equal(33, LibraryZoom.Magnification(3))
	end)

	-- What the readout rests on with the wall dragged all the way out.
	it("reads the far end of the range as seventeen percent", function()
		assert.equal(17, LibraryZoom.Magnification(LibraryZoom.MAX))
	end)

	it("answers nothing for what is not a usable factor", function()
		assert.is_nil(LibraryZoom.Magnification(nil))
		assert.is_nil(LibraryZoom.Magnification(0))
	end)
end)
