-- Store: ToadsLCDB SavedVariables (priorities, sessions, settings).
-- Session records are kept as JSON text so nulls and empty arrays survive a reload.
local _, ns = ...

local Store = {}
ns.Store = Store

local Codec = ns.Codec

local DEFAULT_SETTINGS = { rollSeconds = 30, announceChannel = "RAID", tooltip = true }

function Store.init()
  ToadsLCDB = ToadsLCDB or {}
  local db = ToadsLCDB
  db.sessions = db.sessions or {}   -- id -> { json, exported, openedAt }
  db.order = db.order or {}         -- session ids, oldest first
  db.settings = db.settings or {}
  for k, v in pairs(DEFAULT_SETTINGS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  return db
end

function Store.settings() return ToadsLCDB.settings end

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
  row.json = Codec.encode(rec)
  row.openedAt = openedAt or row.openedAt
end

function Store.record(id)
  local row = ToadsLCDB.sessions[id]
  return row and Codec.decode(row.json)
end

-- records(all) -> decoded records, oldest first; unexported ones only unless all.
function Store.records(all)
  local out, ids = {}, {}
  for _, id in ipairs(ToadsLCDB.order) do
    local row = ToadsLCDB.sessions[id]
    if row and (all or not row.exported) then
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

-- since(t) -> records opened at or after t (tonight's history)
function Store.since(t)
  local out = {}
  for _, id in ipairs(ToadsLCDB.order) do
    local row = ToadsLCDB.sessions[id]
    if row and (row.openedAt or 0) >= t then out[#out + 1] = Codec.decode(row.json) end
  end
  return out
end
