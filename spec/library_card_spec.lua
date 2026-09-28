-- Library cards and the detail pane are frame code with no pure layer, so the
-- rules that matter are checked by reading the library's source: the window
-- (LibraryUI.lua), its cards (LibraryCards.lua), its bodies (LibraryBodies.lua)
-- and the snap pop-up (SnapConfirmUI.lua).
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local FILES = { "LibraryUI.lua", "LibraryCards.lua", "LibraryBodies.lua",
	"SnapConfirmUI.lua" }

-- Every library file at once, for what none of them may contain.
local SOURCE
do
	local parts = {}
	for _, path in ipairs(FILES) do parts[#parts + 1] = Read(path) end
	SOURCE = table.concat(parts, "\n")
end

-- The text of one top-level function in path, from its header to the next
-- "end" at column one.
local function Body(path, header)
	local text = Read(path)
	local start = assert(text:find(header, 1, true), "no " .. header .. " in " .. path)
	local stop = assert(text:find("\nend\n", start, true), "no end for " .. header)
	return text:sub(start, stop)
end

describe("library cards", function()
	-- The render note, the per-slot readback and the record dump are
	-- debugging aids that do not ship.
	it("carries no render note or render readback", function()
		assert.is_nil(SOURCE:find("card.Status", 1, true))
		assert.is_nil(SOURCE:find("lastApply", 1, true))
		assert.is_nil(SOURCE:find("lastVisible", 1, true))
		assert.is_nil(SOURCE:find("lastNote", 1, true))
		assert.is_nil(SOURCE:find("MogtrotDB.debug", 1, true))
		assert.is_nil(SOURCE:find("ShowDetails", 1, true))
		assert.is_nil(SOURCE:find('"More info"', 1, true))
		assert.is_nil(SOURCE:find("CopyBox", 1, true))
	end)

	-- The library itself listens to no unit: passive donors come through
	-- DonorWatchUI, which asks DonorWatch.Accepts before taking the donor's
	-- facts, and builds staged bodies step by step.
	it("leaves passive donors to DonorWatchUI, gated by DonorWatch.Accepts", function()
		for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
			"NAME_PLATE_UNIT_ADDED", "GROUP_ROSTER_UPDATE" }) do
			assert.is_nil(SOURCE:find(event, 1, true), event .. " registered in the library")
		end
		local set = Body("LibraryBodies.lua",
			"local function SetBody(actor, record, body, preferredDonor)")
		assert.is_nil(set:find(".Find(", 1, true), "SetBody searches the live units")
		local warm = Body("LibraryBodies.lua",
			"function LibraryBodies.WarmBody(record, donorUnit, want, staging)")
		assert.is_nil(warm:find(".Find(", 1, true), "WarmBody searches the live units")
		local snap = Read("SnapCapture.lua")
		assert.is_nil(snap:find("WarmAll", 1, true), "a snap still borrows bodies")
		assert.is_nil(snap:find("WarmBody", 1, true), "a snap still borrows a body")
		local watch = Read("DonorWatchUI.lua")
		local accepts = assert(watch:find("Watch.Accepts(", 1, true), "no Accepts gate")
		local ingest = assert(watch:find("DonorFacts(unit)", 1, true), "no ingest")
		assert.is_true(accepts < ingest)
		assert.is_nil(watch:find("IngestDonor(", 1, true), "a passive donor built in one frame")
		assert.is_truthy(watch:find("WarmBody(step.record, token, step.want, build.guid)", 1, true),
			"passive card bodies are not staged")
	end)

	-- Original race is offered from the first borrowed body of the other sex,
	-- and nothing waits on a background check.
	it("offers original race as soon as one body of the other sex is held", function()
		local refresh = Body("LibraryUI.lua", "function LibraryUI.Refresh()")
		assert.is_truthy(refresh:find("Bodies.HoldsBorrowed()", 1, true))
		assert.is_nil(refresh:find("Offered()", 1, true))
		assert.is_truthy(refresh:find("window.Body:SetShown(fullFidelity)", 1, true))
		local rank = Body("LibraryBodies.lua", "local function RankFor(record)")
		assert.is_nil(rank:find("Covering", 1, true))
		assert.is_nil(SOURCE:find("Wake()", 1, true), "the library wakes a background check")
		assert.is_nil(Read("SnapCapture.lua"):find("DonorWatchUI", 1, true),
			"a snap wakes a background check")
	end)

	it("says in plain words why looks are on your body before any body is held", function()
		local status = Body("LibraryUI.lua", "function LibraryUI.PaintStatus()")
		assert.is_truthy(status:find("Looks are shown on your own body until you've"
			.. " seen players of the other sex", 1, true))
	end)

	it("reads donor facts gated by DonorWatch.Refusal", function()
		local facts = Body("LibraryBodies.lua", "function LibraryBodies.DonorFacts(unit)")
		assert.is_truthy(facts:find("DonorWatch.Refusal(", 1, true))
	end)

	-- Donors come only in passing; the manual ingest and its macro are in the
	-- private specs tree as a debug tool.
	it("has no manual donor ingest, Donor macro handle or donor windows", function()
		for _, name in ipairs({ "IngestDonor", "WarmAll", "Macro.DONOR", "DonorDrag",
			"DonorLabUI", "DonorLab.", "DonorSupply", "/mogtrot donor" }) do
			assert.is_nil(SOURCE:find(name, 1, true), name .. " still in the library")
		end
		local watch = Read("DonorWatchUI.lua")
		for _, name in ipairs({ "DonorLabUI", "DonorLab.", "GridState", "/mogtrot donor" }) do
			assert.is_nil(watch:find(name, 1, true), name .. " still in DonorWatchUI")
		end
		for _, path in ipairs({ "DonorCoverage.lua", "DonorCoverageUI.lua" }) do
			assert.is_nil(io.open(path, "r"), path .. " is back in the addon")
		end
		for _, toc in ipairs({ "Mogtrot.toc", "MogtrotDev.toc" }) do
			assert.is_nil(Read(toc):find("DonorCoverage", 1, true), "DonorCoverage in " .. toc)
		end
	end)

	-- Cards always stand. Mounted cards are in the private specs tree as a
	-- tool; a record keeps its mount, which is not drawn.
	it("has no Mounted switch and draws no mount behind the body", function()
		for _, name in ipairs({ '"Mounted"', "MOUNTED_SWITCH", "showMounts", "anyMounts",
			"mountActor", "StageMount", "ShowMount", "HideMount" }) do
			assert.is_nil(SOURCE:find(name, 1, true), name .. " still in the library")
		end
		local render = Read("LookRender.lua")
		for _, name in ipairs({ "MountStage", "StageMount", "ShowMount", "HideMount",
			"mogtrot-mount" }) do
			assert.is_nil(render:find(name, 1, true), name .. " still in LookRender")
		end
		for _, toc in ipairs({ "Mogtrot.toc", "MogtrotDev.toc" }) do
			assert.is_nil(Read(toc):find("MountStage.lua", 1, true), toc .. " loads MountStage.lua")
		end
	end)

	-- Without the live body the pop-up never draws the look on the wrong sex.
	it("chooses the snap pop-up's body through PopupBody and retries live", function()
		local snap = Body("SnapConfirmUI.lua",
			"function SnapConfirmUI.ConfirmSnap(record, isNew, token, liveUnit, recheck)")
		assert.is_truthy(snap:find("DrawConfirmBody(", 1, true))
		assert.is_nil(snap:find("BodyIsDeterministic", 1, true))
		local draw = Body("SnapConfirmUI.lua",
			"local function DrawConfirmBody(frame, record, liveUnit)")
		assert.is_truthy(draw:find("PopupBody", 1, true))
		local ensure = Body("SnapConfirmUI.lua", "local function EnsureConfirm()")
		assert.is_truthy(ensure:find("LiveRetry(", 1, true))
	end)
end)
