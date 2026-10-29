-- The shipped folder as the client sees it: the .toc, its load order, and only the
-- globals the WoW sandbox actually has.
local H = require("spec.helper")
local W = require("spec.wow_mock")

local function tocFiles()
  local meta, files = {}, {}
  for line in H.read("ToadsLC/ToadsLC.toc"):gmatch("[^\r\n]+") do
    local k, v = line:match("^##%s*([^:]+):%s*(.-)%s*$")
    if k then meta[k] = v elseif line:match("%S") and not line:match("^#") then
      files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
    end
  end
  return meta, files
end

-- what plain Lua has and the WoW client does not: reading one gives nil, as in the client
local NOT_IN_CLIENT = { io = true, os = true, require = true, loadfile = true, dofile = true, debug = true,
                        package = true, module = true, utf8 = true }

describe("ToadsLC.toc", function()
  it("names a TBC Classic interface, a title, a version and the SavedVariables", function()
    local meta = tocFiles()
    for n in meta.Interface:gmatch("[^,%s]+") do assert.matches("^205%d%d$", n) end
    assert.are.equal("Toads LC", meta.Title)
    assert.matches("^%d+%.%d+%.%d+$", meta.Version)
    assert.are.equal("ToadsLCDB", meta.SavedVariables)
    assert.are.equal("ToadsLCCharDB", meta.SavedVariablesPerCharacter) -- window sizes, per screen
  end)

  it("lists files that exist, each once", function()
    local _, files = tocFiles()
    local seen = {}
    for _, f in ipairs(files) do
      assert.is_nil(seen[f], f .. " listed twice")
      seen[f] = true
      assert.truthy(io.open(H.root .. "ToadsLC/" .. f), f .. " is missing")
    end
  end)

  it("lists every Lua file in the folder", function()
    local _, files = tocFiles()
    local listed = {}
    for _, f in ipairs(files) do listed[f] = true end
    local p = io.popen('cd "' .. H.root .. 'ToadsLC" && find . -name "*.lua"')
    for f in p:lines() do
      f = f:gsub("^%./", "")
      assert.is_true(listed[f] == true, f .. " is not in the .toc, so the client never loads it")
    end
    p:close()
  end)

  it("loads each module after the modules it reads at load time", function()
    W.install()
    local _, files = tocFiles()
    local current
    local ns = setmetatable({}, { __index = function(_, k)
      if type(k) == "string" and k:match("^%u") then
        error(current .. " reads ns." .. k .. " before any earlier file defines it", 2)
      end
    end })
    for _, f in ipairs(files) do
      current = f
      assert(loadfile(H.root .. "ToadsLC/" .. f))("ToadsLC", ns)
    end
    assert.truthy(rawget(ns, "App"))
  end)

  it("runs with only the client's globals", function()
    W.install()
    local env = setmetatable({ bit = require("bit") }, {
      __index = function(_, k)
        if not NOT_IN_CLIENT[k] then return _G[k] end
      end,
      __newindex = function(_, k, v) _G[k] = v end,
    })
    local _, files = tocFiles()
    local ns = {}
    for _, f in ipairs(files) do
      local chunk = assert(loadfile(H.root .. "ToadsLC/" .. f))
      setfenv(chunk, env)
      chunk("ToadsLC", ns)
    end
    W.ns = ns
    W.fire("PLAYER_LOGIN")
    W.slash("help")
    W.slash("begin swordfish")
    W.slash("status")
    assert.matches("ingerprint", table.concat(W.printed, "\n"))
    assert.is_true(ns.App.import(H.read("fixtures/priority.sample.json")))
    W.slash("session |cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r 30")
    W.flushComms()
    assert.truthy(#W.addon > 0)
    for _, m in ipairs(W.addon) do -- the first chunk of each message carries the signature
      local first = m.text:match("^[^:]*:1/%d+:(.*)$")
      if first then assert.matches("^T1|", first) end
    end
  end)
end)
