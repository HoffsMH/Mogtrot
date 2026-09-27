-- The release carries no debug output and no diagnostic modules. The tools
-- are kept outside the repository; this catches one pasted back and left in.
local function Read(path)
	local file = assert(io.open(path, "r"))
	local body = file:read("*a")
	file:close()
	return body
end

local function SourceFiles()
	local names = {}
	local pipe = assert(io.popen("ls *.lua"))
	for name in pipe:lines() do names[#names + 1] = name end
	pipe:close()
	return names
end

local FORBIDDEN = {
	":Debug(", "MogtrotDB.debug", "MogtrotDB.cardNudge", "ns.DevCommands",
	"ns.Diagnostics", "BodyAudit", "LayerProbe", "ReportMountTypes",
	"MogtrotProbeRender", "WearReport", "ShowState",
}

-- Helpers only the private tools call. The tools' reinstall patches put them
-- back.
local TOOL_ONLY = {
	"SummonBindingText", "OutfitLookCapture.GetModel", "InspectLook.Format",
	"DonorBody.Find", "OverlapCount", "SlotVisibility",
}

describe("release code", function()
	it("has no debug output or diagnostic hooks", function()
		for _, path in ipairs(SourceFiles()) do
			local body = Read(path)
			for _, needle in ipairs(FORBIDDEN) do
				assert.is_nil(body:find(needle, 1, true), path .. " contains " .. needle)
			end
		end
	end)

	it("has no helpers that only the private tools call", function()
		for _, path in ipairs(SourceFiles()) do
			local body = Read(path)
			for _, needle in ipairs(TOOL_ONLY) do
				assert.is_nil(body:find(needle, 1, true), path .. " contains " .. needle)
			end
		end
	end)
end)
