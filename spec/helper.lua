-- Loads the core modules the way the WoW client does: each file gets (addonName, ns).
local root = (debug.getinfo(1, "S").source:match("^@(.*)spec/helper%.lua$") or "./")

local H = { root = root }

function H.load(files, ns)
  ns = ns or {}
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(root .. "ToadsLC/" .. f))
    chunk("ToadsLC", ns)
  end
  return ns
end

function H.core()
  return H.load({ "core/Codec.lua", "core/Priority.lua", "core/Resolver.lua", "core/Session.lua" })
end

function H.read(path)
  local f = assert(io.open(root .. path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

return H
