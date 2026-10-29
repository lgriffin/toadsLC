-- LootList: the night's drops, in the order they were looted, waiting for the council.
-- The raid loots and moves on; the leader (or an assist doing master loot) records what
-- dropped, and later picks an entry to open its session or roll. Each entry follows its
-- session through to the award, so the list shows what is still to hand out.
--
-- Entries are keyed by where they came from (corpse GUID, item, how many of that item the
-- corpse held), so looting the same corpse twice, or two assists looting it, records it
-- once. Numbers are positions in this client's list, for /tlc loot <n>.
--
-- Message types (public, but only accepted from the raid leader or an assist):
--   LOOT (one entry added or changed), LOOT_LIST (a snapshot), LOOT_CLEAR, LOOT_REQUEST
local _, ns = ...
ns = ns or {}

local LootList = {}
LootList.__index = LootList
ns.LootList = LootList

local ipairs, pairs = ipairs, pairs

LootList.MAX = 200 -- entries kept per night

-- status: waiting -> open (taking responses) -> voting -> awarded | none (no award)
LootList.STATUS = { waiting = true, open = true, voting = true, awarded = true, none = true }

function LootList.new()
  return setmetatable({ entries = {}, byKey = {} }, LootList)
end

-- add{ key, itemId, name, link?, boss?, zone?, at, sim? } -> entry, or nil when already listed
function LootList:add(o)
  if not o.key or not o.name or self.byKey[o.key] or #self.entries >= LootList.MAX then return nil end
  local e = {
    key = o.key, itemId = o.itemId, name = o.name, link = o.link, boss = o.boss or "", zone = o.zone or "",
    at = o.at or 0, status = o.status or "waiting", session = o.session, winner = o.winner, sim = o.sim,
  }
  self.entries[#self.entries + 1] = e
  self.byKey[e.key] = e
  return e
end

function LootList:get(n) return self.entries[tonumber(n) or 0] end
function LootList:byKeyOf(key) return self.byKey[key] end

function LootList:numberOf(entry)
  for i, e in ipairs(self.entries) do if e == entry then return i end end
end

-- remove(entry) -> true when it was listed
function LootList:remove(entry)
  for i, e in ipairs(self.entries) do
    if e == entry then
      table.remove(self.entries, i)
      self.byKey[e.key] = nil
      return true
    end
  end
  return false
end

-- clear(keep): drop every entry, or only those keep(entry) says no to
function LootList:clear(keep)
  local kept = {}
  self.byKey = {}
  for _, e in ipairs(self.entries) do
    if keep and keep(e) then
      kept[#kept + 1] = e
      self.byKey[e.key] = e
    end
  end
  self.entries = kept
end

-- waiting() -> entries nobody has started yet
function LootList:waiting()
  local out = {}
  for _, e in ipairs(self.entries) do if e.status == "waiting" then out[#out + 1] = e end end
  return out
end

-- startable(entry): waiting, or closed with no award (it can be offered again)
function LootList.startable(e) return e.status == "waiting" or e.status == "none" end

-- forItem(itemId) -> the first startable entry for that item (a /tlc session typed by hand)
function LootList:forItem(itemId)
  if not itemId then return nil end
  for _, e in ipairs(self.entries) do
    if e.itemId == itemId and LootList.startable(e) then return e end
  end
end

-- forSession(id) -> the entry that session was opened for
function LootList:forSession(id)
  for _, e in ipairs(self.entries) do if e.session == id then return e end end
end

-- follow(entry, session) -> true when the entry's status changed
function LootList.follow(e, s)
  local status, winner = s.phase, nil
  if s.phase == "done" then
    winner = s.awardedTo
    status = winner and "awarded" or "none"
  end
  if e.session == s.id and e.status == status and e.winner == winner then return false end
  e.session, e.status, e.winner = s.id, status, winner
  return true
end

-- label(entry) -> how the status reads in the list
function LootList.label(e)
  if e.status == "waiting" then return "waiting" end
  if e.status == "open" then return "rolling" end
  if e.status == "voting" then return "council deciding" end
  if e.status == "awarded" then return "to " .. (e.winner or "?") end
  return "not awarded"
end

---------------------------------------------------------------------------
-- wire form and saved form
---------------------------------------------------------------------------

-- wire(entry): links are left out (the receiver rebuilds them from the item ID)
function LootList.wire(e)
  return { k = e.key, it = e.itemId, nm = e.name, b = e.boss, z = e.zone, at = e.at, st = e.status,
           s = e.session, w = e.winner }
end

local function str(v, max) return type(v) == "string" and #v <= (max or 255) end
local function opt(v, check) return v == nil or check(v) end
local function int(v) return type(v) == "number" and v == math.floor(v) and v >= 0 and v < 1e12 end

-- validEntry(m) -> true when a wire entry is well-formed
function LootList.validEntry(m, null)
  if type(m) ~= "table" then return false end
  for k, v in pairs(m) do if v == null then m[k] = nil end end
  return str(m.k, 120) and str(m.nm) and opt(m.it, int) and opt(m.b, str) and opt(m.z, str) and opt(m.at, int)
    and opt(m.st, function(v) return LootList.STATUS[v] == true end) and opt(m.s, str) and opt(m.w, str)
end

-- merge(m) -> entry when the list changed: adds it, or brings a known entry up to date
function LootList:merge(m)
  local e = self.byKey[m.k]
  if not e then
    return self:add({ key = m.k, itemId = m.it, name = m.nm, boss = m.b, zone = m.z, at = m.at,
                      status = m.st, session = m.s, winner = m.w })
  end
  local status = m.st or e.status
  if e.status == status and e.session == m.s and e.winner == m.w then return nil end
  e.status, e.session, e.winner = status, m.s, m.w
  return e
end

-- snapshot() -> wire entries, sim ones left out
function LootList:snapshot()
  local out = {}
  for _, e in ipairs(self.entries) do if not e.sim then out[#out + 1] = LootList.wire(e) end end
  return out
end

-- restore(rows): entries saved with snapshot()
function LootList:restore(rows)
  for _, m in ipairs(rows or {}) do
    if LootList.validEntry(m) then self:merge(m) end
  end
end

return LootList
