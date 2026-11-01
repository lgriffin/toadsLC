-- Version: who in the group runs Toads LC, and which version. /tlc version sends a
-- VERSION_PING to the group; every client with this addon whispers back a VERSION with its
-- own version. After a few seconds the asker lists the group: on the newest version seen,
-- on an older one, no answer (no addon, or a build from before this check existed) and
-- offline. Either message also tells a client with an older version that a newer one exists.
--
-- Neither message is council traffic: they are never encrypted and are answered whatever
-- raid password either side holds, so a raider without the password still shows up.
local _, ns = ...

local Version = {}
ns.Version = Version

local Priority = ns.Priority

Version.WAIT = 5          -- seconds to wait for answers before listing the group
Version.REPLY_GAP = 5     -- answer one asker at most once in this many seconds
Version.MAX_LENGTH = 24   -- longest version string taken from another client

local pending   -- the check waiting for answers: { id, at, members, replies, callbacks }
local answered = {} -- nameKey -> when we last answered their ping
local toldNewer -- the newest version we have already told the player about
Version.last = nil -- the last finished report, for a window that wants to show it

local function send(outs) if ns.App then ns.App.send(outs) end end
local function now() return ns.App.now() end
local function mine() return ns.App and ns.App.VERSION or "dev" end

---------------------------------------------------------------------------
-- comparing versions
---------------------------------------------------------------------------

-- parse("0.2.1") -> { 0, 2, 1 }; nil for anything without a number ("dev")
function Version.parse(v)
  if type(v) ~= "string" then return nil end
  local parts = {}
  for n in v:gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
  return #parts > 0 and parts or nil
end

-- compare(a, b) -> -1, 0 or 1. A version with no numbers sorts below every numbered one.
function Version.compare(a, b)
  local pa, pb = Version.parse(a), Version.parse(b)
  if not pa or not pb then
    if pa then return 1 elseif pb then return -1 end
    return 0
  end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end

local function valid(v)
  return type(v) == "string" and #v > 0 and #v <= Version.MAX_LENGTH and not v:find("|", 1, true)
end

---------------------------------------------------------------------------
-- the report
---------------------------------------------------------------------------

-- report(members, replies, me, myVersion) -> { newest, current, outdated, missing, offline, total }
-- members: { { name, online } } for the whole group; replies: nameKey -> version.
-- current, missing and offline are lists of names; outdated is a list of { name, version }.
function Version.report(members, replies, me, myVersion)
  local got = {}
  for k, v in pairs(replies) do got[k] = v end
  got[Priority.nameKey(me)] = myVersion
  local newest = myVersion
  for _, v in pairs(got) do
    if Version.compare(v, newest) > 0 then newest = v end
  end
  local r = { newest = newest, current = {}, outdated = {}, missing = {}, offline = {}, total = #members }
  for _, m in ipairs(members) do
    local v = got[Priority.nameKey(m.name)]
    if v then
      if Version.compare(v, newest) >= 0 then r.current[#r.current + 1] = m.name
      else r.outdated[#r.outdated + 1] = { name = m.name, version = v } end
    elseif m.online == false then
      r.offline[#r.offline + 1] = m.name
    else
      r.missing[#r.missing + 1] = m.name
    end
  end
  table.sort(r.current)
  table.sort(r.missing)
  table.sort(r.offline)
  table.sort(r.outdated, function(a, b) return a.name < b.name end)
  return r
end

-- lines(r, myVersion) -> chat lines describing a report
function Version.lines(r, myVersion)
  local out = {}
  out[1] = string.format("Version check: %d of %d in the group have Toads LC, %d on the newest (%s).",
    #r.current + #r.outdated, r.total, #r.current, r.newest)
  if #r.outdated > 0 then
    local names = {}
    for _, o in ipairs(r.outdated) do names[#names + 1] = o.name .. " " .. o.version end
    out[#out + 1] = string.format("Older version (%d): %s", #r.outdated, table.concat(names, ", "))
  end
  if #r.missing > 0 then
    out[#out + 1] = string.format("No answer, so no Toads LC or one too old to answer (%d): %s", #r.missing,
      table.concat(r.missing, ", "))
  end
  if #r.offline > 0 then
    out[#out + 1] = string.format("Offline (%d): %s", #r.offline, table.concat(r.offline, ", "))
  end
  if Version.compare(myVersion, r.newest) < 0 then
    out[#out + 1] = string.format("You have %s yourself: update to %s.", myVersion, r.newest)
  end
  return out
end

---------------------------------------------------------------------------
-- asking and answering
---------------------------------------------------------------------------

local function members()
  local list = {}
  for unit in ns.Roster.units() do
    local name = UnitName(unit)
    if name then
      local online = true
      if UnitIsConnected then online = UnitIsConnected(unit) and true or false end
      list[#list + 1] = { name = ns.Roster.normalize(name), online = online }
    end
  end
  return list
end

-- the player hears once per newer version that one exists
local function noteNewer(v, sender)
  if not valid(v) or Version.compare(v, mine()) <= 0 then return end
  if toldNewer and Version.compare(v, toldNewer) <= 0 then return end
  toldNewer = v
  ns.Chat.print(string.format("A newer Toads LC is out: %s has %s, you have %s.", sender, v, mine()))
end

local function finish()
  local p = pending
  if not p then return end
  pending = nil
  local r = Version.report(p.members, p.replies, ns.Roster.me(), mine())
  r.at = p.at
  Version.last = r
  for _, line in ipairs(Version.lines(r, mine())) do ns.Chat.print(line) end
  for _, fn in ipairs(p.callbacks) do
    local ok, err = pcall(fn, r)
    if not ok then ns.Chat.debug("version check callback failed: " .. tostring(err)) end
  end
end

-- check([onDone(report)]) -> true when a check started (or one already running takes onDone).
-- The report is printed to the player's chat frame either way; onDone is for a window.
function Version.check(onDone)
  if pending then
    if onDone then pending.callbacks[#pending.callbacks + 1] = onDone end
    ns.Chat.print("Already checking versions; the list follows in a few seconds.")
    return true
  end
  if not IsInGroup() then
    ns.Chat.print("Toads LC " .. mine() .. ". Join a party or raid to check everyone else's version.")
    return false
  end
  local id = string.format("%x%x", now(), math.random(0, 0xFFFF))
  pending = { id = id, at = now(), members = members(), replies = {}, callbacks = { onDone } }
  send({ { msg = { t = "VERSION_PING", id = id, v = mine() }, dist = "RAID" } })
  ns.Chat.print(string.format("Asking the group for their Toads LC version (%d s)…", Version.WAIT))
  C_Timer.After(Version.WAIT, finish)
  return true
end

function Version.handles(t) return t == "VERSION_PING" or t == "VERSION" end

-- handle(msg, sender): trust does not matter here, a version is not a secret, but only
-- group members are answered or believed about a newer version
function Version.handle(m, sender)
  if type(m.id) ~= "string" or #m.id > 32 then return end
  if not ns.Roster.unitOf(sender) then return end
  if m.t == "VERSION_PING" then
    noteNewer(m.v, sender)
    local key, t = Priority.nameKey(sender), now()
    if answered[key] and t - answered[key] < Version.REPLY_GAP then return end
    answered[key] = t
    send({ { msg = { t = "VERSION", id = m.id, v = mine() }, dist = "WHISPER", target = sender } })
  elseif m.t == "VERSION" then
    if not valid(m.v) or not pending or m.id ~= pending.id then return end
    noteNewer(m.v, sender)
    pending.replies[Priority.nameKey(sender)] = m.v
  end
end

-- for tests: forget the running check and what has been answered
function Version.reset() pending, answered, toldNewer, Version.last = nil, {}, nil, nil end

return Version
