require("spec.helpers")

local MountSort = require("MountSort")

local function mount(id, name, fields)
  local m = { mountID = id, name = name }
  for k, v in pairs(fields or {}) do m[k] = v end
  return m
end

local function order(list, ctx)
  MountSort.Apply(list, ctx)
  local names = {}
  for _, m in ipairs(list) do table.insert(names, m.name) end
  return names
end

describe("MountSort", function()
  it("falls back to name, case-insensitively", function()
    -- Byte order would put every capitalised name above every lowercase one.
    local list = { mount(1, "wacky"), mount(2, "Alpha"), mount(3, "beta") }
    assert.same({ "Alpha", "beta", "wacky" }, order(list))
  end)

  it("puts the outfit's own mounts first", function()
    local list = { mount(1, "Aaa"), mount(2, "Zzz") }
    assert.same({ "Zzz", "Aaa" }, order(list, { chosen = { [2] = true } }))
  end)

  it("ranks chosen mounts, other outfit pairings, then pins", function()
    local list = {
      mount(1, "Z pin", { isPinned = true }),
      mount(2, "Z pair", { pairings = 1 }),
      mount(3, "Z chosen"),
      mount(4, "A plain"),
    }
    assert.same({ "Z chosen", "Z pair", "Z pin", "A plain" },
      order(list, { chosen = { [3] = true } }))
  end)

  it("is a total order, so equal mounts never reshuffle", function()
    local a, b = mount(7, "Same"), mount(3, "Same")
    assert.is_true(MountSort.Compare(b, a, { chosen = {} }))
    assert.is_false(MountSort.Compare(a, b, { chosen = {} }))
  end)

  it("copes with no context at all", function()
    local list = { mount(2, "Bbb"), mount(1, "Aaa") }
    assert.same({ "Aaa", "Bbb" }, order(list))
  end)
end)
