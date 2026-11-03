-- Store: ToadsLCDB SavedVariables (priorities, sessions, settings).
-- Session records are kept as JSON text so nulls and empty arrays survive a reload.
local _, ns = ...

local Store = {}
ns.Store = Store

local Codec = ns.Codec

-- itemSeconds: how long a single announced item takes answers (the officers' setting); the
-- whole pool at once (Announce all) has no timer
local DEFAULT_SETTINGS = { itemSeconds = 15, announceChannel = "RAID", tooltip = true, lootAuto = true, lootQuality = 4,
                           autoTrade = true, lootParty = false, announceAward = true,
                           announceTrade = true, whisperAward = true }

function Store.init()
  ToadsLCDB = ToadsLCDB or {}
  local db = ToadsLCDB
  db.sessions = db.sessions or {}   -- id -> { json, exported, openedAt }
  db.order = db.order or {}         -- session ids, oldest first
  db.settings = db.settings or {}
  for k, v in pairs(DEFAULT_SETTINGS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  db.settings.raid = nil -- before 0.2.8 the raid password was account-wide: Join or Begin again
  return db
end

function Store.settings() return ToadsLCDB.settings end

-- raid() / setRaid(r): tonight's raid password (its derived key, whether this character
-- leads, when it was set). Per character: an alt on the same account is its own officer and
-- must Join for itself, never inherit "you lead" from the main.
function Store.raid() return Store.layout().raid end
function Store.setRaid(r) Store.layout().raid = r end

-- layout(): this character's window sizes, positions and scale (ToadsLCCharDB, per character,
-- since each character may play on a different screen). Read lazily: frames can be built
-- before PLAYER_LOGIN has run Store.init in tests.
function Store.layout()
  ToadsLCCharDB = ToadsLCCharDB or {}
  local db = ToadsLCCharDB
  db.frames = db.frames or {} -- frame name -> { w, h, point, relPoint, x, y }
  db.scale = db.scale or 1
  -- 0.3: windows got smaller defaults and places that don't overlap; sizes saved before that
  -- (often huge, or a loot window two rows tall) start again from the new defaults once
  if (db.layoutVersion or 0) < Store.LAYOUT_VERSION then
    db.frames, db.layoutVersion = {}, Store.LAYOUT_VERSION
  end
  return db
end
Store.LAYOUT_VERSION = 2

-- answer(id) / setAnswer(id, response, now): what this character answered for an item, kept
-- over a reload (a raider's client has no other copy of it) for a night
Store.ANSWER_MAX_AGE = 12 * 3600
function Store.answer(id)
  local a = id and Store.layout().answers
  local row = a and a[id]
  return row and row.r or nil
end

function Store.setAnswer(id, response, now)
  local db = Store.layout()
  db.answers = db.answers or {}
  for k, row in pairs(db.answers) do
    if now - (row.at or 0) > Store.ANSWER_MAX_AGE then db.answers[k] = nil end
  end
  db.answers[id] = { r = response, at = now }
end

function Store.priorities() return ToadsLCDB.priorities end

-- setPriorities(db): the previous list is kept under priorities.previous for one undo.
function Store.setPriorities(pdb)
  local old = ToadsLCDB.priorities
  if old then old.previous = nil end
  pdb.previous = old
  ToadsLCDB.priorities = pdb
end

function Store.undoImport()
  local cur = ToadsLCDB.priorities
  if not cur or not cur.previous then return false end
  ToadsLCDB.priorities = cur.previous
  return true
end

-- saveSession(rec): written the moment a session closes and patched on every change after.
function Store.saveSession(rec, openedAt)
  local row = ToadsLCDB.sessions[rec.id]
  if not row then
    row = { exported = false }
    ToadsLCDB.sessions[rec.id] = row
    table.insert(ToadsLCDB.order, rec.id)
  end
  local json = Codec.encode(rec)
  if json ~= row.json then row.exported = false end -- changed since it was sent: send it again
  row.json = json
  row.openedAt = openedAt or row.openedAt
end

-- dropSession(id): forget a session that was reset, saved record and live state both
function Store.dropSession(id)
  if ToadsLCDB.sessions[id] then
    ToadsLCDB.sessions[id] = nil
    for i, v in ipairs(ToadsLCDB.order) do
      if v == id then table.remove(ToadsLCDB.order, i); break end
    end
  end
  Store.clearLive(id)
end

function Store.record(id)
  local row = ToadsLCDB.sessions[id]
  return row and Codec.decode(row.json)
end

-- records(all, since) -> decoded records, oldest first; unexported ones only unless all, and
-- only those opened at or after since when it is given (tonight's raid)
function Store.records(all, since)
  local out, ids = {}, {}
  for _, id in ipairs(ToadsLCDB.order) do
    local row = ToadsLCDB.sessions[id]
    if row and (all or not row.exported) and (not since or (row.openedAt or 0) >= since) then
      local rec = Codec.decode(row.json)
      if rec then out[#out + 1] = rec; ids[#ids + 1] = id end
    end
  end
  return out, ids
end

function Store.markExported(ids)
  for _, id in ipairs(ids) do
    local row = ToadsLCDB.sessions[id]
    if row then row.exported = true end
  end
end

-- Sessions a leader is still running, as STATE snapshots, so a reload can pick them up.
function Store.saveLive(id, state, now)
  ToadsLCDB.live = ToadsLCDB.live or {}
  ToadsLCDB.live[id] = { json = Codec.encode(state), at = now }
end

function Store.clearLive(id)
  if ToadsLCDB.live then ToadsLCDB.live[id] = nil end
end

-- live(maxAge, now) -> { { state, at }, ... } newer than maxAge seconds; older ones are dropped
function Store.live(maxAge, now)
  local out = {}
  for id, row in pairs(ToadsLCDB.live or {}) do
    local state = now - (row.at or 0) <= maxAge and Codec.decode(row.json)
    if state then out[#out + 1] = { state = state, at = row.at } else ToadsLCDB.live[id] = nil end
  end
  table.sort(out, function(a, b) return a.at < b.at end)
  return out
end

-- since(t) -> records opened at or after t (tonight's history)
function Store.since(t)
  local out = {}
  for _, id in ipairs(ToadsLCDB.order) do
    local row = ToadsLCDB.sessions[id]
    if row and (row.openedAt or 0) >= t then out[#out + 1] = Codec.decode(row.json) end
  end
  return out
end

-- The night's loot list (adapters/Loot.lua), as wire entries.
function Store.saveLoot(rows, now)
  ToadsLCDB.loot = { json = Codec.encode(Codec.array(rows)), at = now }
end

-- loot(maxAge, now) -> the saved rows, or {} when there are none or they are older than maxAge
function Store.loot(maxAge, now)
  local row = ToadsLCDB.loot
  if not row or now - (row.at or 0) > maxAge then
    ToadsLCDB.loot = nil
    return {}
  end
  return Codec.decode(row.json) or {}
end
