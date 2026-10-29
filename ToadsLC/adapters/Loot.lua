-- Loot: the raid's loot list. When the raid leader or an assist opens a corpse in a raid,
-- its drops (epic and up, or anything on the priority list) are recorded, so the raid can
-- loot and move on. Later the leader picks an entry (/tlc loot, or /tlc loot <n>) and its
-- session or roll opens and is announced in raid chat, as /tlc session or /tlc roll would.
-- Each entry follows its session to the award.
--
-- The list is shared: whoever records an entry sends it to the group, signed with the raid
-- password once one is set, and officers ask for the whole list when they log in or join.
-- Only the raid leader's and assists' lists are taken. /tlc sim's drops go on the list too,
-- marked as simulated, never shared or saved, and dropped by /tlc sim stop.
local _, ns = ...

local Loot = {}
ns.Loot = Loot

local LootList, Codec, Priority = ns.LootList, ns.Codec, ns.Priority

Loot.list = LootList.new()
Loot.MAX_AGE = 12 * 3600 -- a saved list is forgotten after a night, like the raid password

-- currencies and crafting drops that are epic but never go to the council
Loot.IGNORE = {
  [29434] = true, -- Badge of Justice
  [30183] = true, -- Nether Vortex
  [34664] = true, -- Sunmote
}

local frame = CreateFrame("Frame")

local function send(outs) if ns.App then ns.App.send(outs) end end
local function now() return ns.App.now() end

local function save()
  ns.Store.saveLoot(Loot.list:snapshot(), now())
end

local function changed()
  save()
  ns.Frames.lootChanged()
end

local function share(e)
  if e.sim then return end
  send({ { msg = { t = "LOOT", e = LootList.wire(e) }, dist = "RAID" } })
end

-- linkOf(entry): the item link, rebuilt from the item ID for entries that came over the wire
function Loot.linkOf(e)
  if e.link then return e.link end
  local link
  if e.itemId then link = select(2, GetItemInfo(e.itemId)) end
  if link then e.link = link end
  return link or ("[" .. e.name .. "]")
end

---------------------------------------------------------------------------
-- recording
---------------------------------------------------------------------------

-- party(): /tlc loot party on, and in a party rather than a raid: a 5-man practice run
local function party()
  return ns.Store.settings().lootParty == true and not IsInRaid() and IsInGroup()
end

local function wanted(itemId, quality)
  if not itemId or Loot.IGNORE[itemId] then return false end
  if Priority.lookup(ns.Store.priorities(), itemId) then return true end
  local least = party() and 3 or (ns.Store.settings().lootQuality or 4) -- dungeon bosses drop blues
  return (quality or 0) >= least
end

-- record{ key, itemId, name, link, boss, zone, sim } -> entry, or nil when already listed
function Loot.record(o)
  o.at = o.at or now()
  o.zone = o.zone or (GetInstanceInfo()) or ""
  local e = Loot.list:add(o)
  if not e then return nil end
  share(e)
  changed()
  return e
end

-- recording(): only the raid leader and assists record, and only in a raid group (or, with
-- /tlc loot party on, the party leader in a party, rare and up, to practise in a 5-man)
function Loot.recording()
  return ns.Store.settings().lootAuto ~= false and (IsInRaid() or party()) and ns.Roster.canLead()
end

local function sourceOf(slot)
  local guid = GetLootSourceInfo and GetLootSourceInfo(slot)
  if guid then return guid end
  return "target:" .. (UnitGUID("target") or UnitName("target") or "?")
end

local function bossOf(source)
  if UnitGUID("target") == source or source == "target:" .. tostring(UnitGUID("target")) then
    local name = UnitName("target")
    if name then return name end
  end
  return ns.App.boss()
end

function Loot.onLootOpened()
  if not Loot.recording() then return end
  local counts, added = {}, {}
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    local itemId = link and tonumber(link:match("item:(%d+)"))
    local _, name, _, _, quality = GetLootSlotInfo(slot)
    if itemId and wanted(itemId, quality) then
      local source = sourceOf(slot)
      local base = source .. ":" .. itemId
      counts[base] = (counts[base] or 0) + 1
      local e = Loot.record({ key = base .. ":" .. counts[base], itemId = itemId, link = link,
                              name = name or link:match("%[(.-)%]") or tostring(itemId), boss = bossOf(source) })
      if e then added[#added + 1] = e end
    end
  end
  if #added > 0 then
    local names = {}
    for i, e in ipairs(added) do names[i] = Loot.linkOf(e) end
    ns.Chat.print(string.format("Added to the loot list: %s. /tlc loot to start them.", table.concat(names, ", ")))
  end
end

-- add(itemText): an item put on the list by hand
function Loot.add(itemText)
  if not ns.Roster.canLead() then ns.Chat.print("You need raid lead or assist to add loot."); return end
  local itemId, name, link = ns.App.parseItem(itemText)
  if not name then ns.Chat.print("Usage: /tlc loot add <item link>"); return end
  local e = Loot.record({ key = string.format("hand:%s:%d:%d", ns.Roster.me(), now(), #Loot.list.entries + 1),
                          itemId = itemId, name = name, link = link, boss = ns.App.boss() })
  if e then ns.Chat.print(string.format("Added %s as %d.", Loot.linkOf(e), Loot.list:numberOf(e))) end
end

---------------------------------------------------------------------------
-- starting an entry
---------------------------------------------------------------------------

-- opened(session, entry): a session opened for this entry (or, typed by hand, for the first
-- waiting entry of the same item) now marks it
function Loot.opened(s, e)
  local sim = ns.Sim.isSim(s)
  if not e then
    e = Loot.list:forItem(s.itemId)
    if e and (e.sim or false) ~= sim then e = nil end
  end
  if e and LootList.follow(e, s) then
    share(e)
    changed()
  end
end

-- start(n, mode, seconds): open the entry's session ("session") or roll ("roll")
function Loot.start(n, mode, seconds)
  local Chat = ns.Chat
  if not ns.Roster.canLead() then Chat.print("You need raid lead or assist to start loot."); return end
  local e = Loot.list:get(n)
  if not e then Chat.print("There is no " .. tostring(n) .. " on the loot list. /tlc loot shows it."); return end
  if not LootList.startable(e) then
    Chat.print(string.format("%s is %s already.", e.name, LootList.label(e)))
    return
  end
  local busy = ns.App.registry:rolling()
  if busy then
    Chat.print(busy.itemName .. " is still taking rolls; let it close (or /tlc close) first.")
    return
  end
  if e.sim then return ns.Sim.openEntry(e, seconds) end
  return ns.App.open(nil, seconds, mode, e)
end

-- startNext(mode, seconds): the first entry still waiting
function Loot.startNext(mode, seconds)
  local e = Loot.list:waiting()[1]
  if not e then ns.Chat.print("Nothing on the loot list is waiting."); return end
  return Loot.start(Loot.list:numberOf(e), mode, seconds)
end

local function lines(parts)
  local out, cur = {}, nil
  for _, p in ipairs(parts) do
    if cur and #cur + 1 + #p > 250 then out[#out + 1] = cur; cur = nil end
    cur = cur and (cur .. " " .. p) or p
  end
  out[#out + 1] = cur
  return out
end

Loot.ALL_MAX = 20 -- items opened at once by /tlc loot all

-- allSeconds(n): how long the window stays open for n items at once
function Loot.allSeconds(n) return math.min(600, 60 + 15 * n) end

-- startAll(seconds): open a council session for every item still to hand out, all at once,
-- announced in one go. Raiders answer each item in one window; their button rolls are matched
-- to the items they pressed, so a bare /roll does not count while several are open.
function Loot.startAll(seconds)
  local Chat = ns.Chat
  if not ns.Roster.canLead() then Chat.print("You need raid lead or assist to start loot."); return end
  local todo = {}
  for _, e in ipairs(Loot.list.entries) do
    if LootList.startable(e) and #todo < Loot.ALL_MAX then todo[#todo + 1] = e end
  end
  if #todo == 0 then Chat.print("Nothing on the loot list is waiting."); return end
  if #todo == 1 then return Loot.start(Loot.list:numberOf(todo[1]), "session", seconds) end
  local busy = ns.App.registry:rolling()
  if busy then
    Chat.print(busy.itemName .. " is still taking rolls; let it close (or /tlc close) first.")
    return
  end
  seconds = seconds or Loot.allSeconds(#todo)
  local parts, sim = {}, true
  for _, e in ipairs(todo) do
    parts[#parts + 1] = string.format("%d. %s", Loot.list:numberOf(e), Loot.linkOf(e))
    if not e.sim then sim = false end
  end
  local head = string.format("[ToadsLC] Loot council: %d items open for %d s. Answer each in the Toads LC window"
    .. " (MS / OS / Pass); while several are open a bare /roll doesn't count.", #todo, seconds)
  if sim then
    Chat.print("[sim] " .. head:gsub("^%[ToadsLC%] ", "") .. " " .. table.concat(parts, " "))
  else
    Chat.say(head, true)
    for _, line in ipairs(lines(parts)) do Chat.say(line) end
  end
  for _, e in ipairs(todo) do
    if e.sim then ns.Sim.openEntry(e, seconds, true) else ns.App.open(nil, seconds, "session", e, true) end
  end
end

function Loot.onSession(s)
  local e = Loot.list:forSession(s.id)
  if not e or not LootList.follow(e, s) then return end
  if s:isLeader(ns.Roster.me()) then share(e) end
  changed()
end

---------------------------------------------------------------------------
-- list commands
---------------------------------------------------------------------------

-- announce(): the entries still waiting, in raid chat
function Loot.announce()
  if not ns.Roster.canLead() then ns.Chat.print("You need raid lead or assist to announce loot."); return end
  local live, sim = { "[ToadsLC] Loot to hand out:" }, {}
  for _, e in ipairs(Loot.list:waiting()) do
    local part = string.format("%d. %s", Loot.list:numberOf(e), Loot.linkOf(e))
    if e.sim then sim[#sim + 1] = part else live[#live + 1] = part end
  end
  if #live == 1 and #sim == 0 then ns.Chat.print("Nothing on the loot list is waiting."); return end
  if #live > 1 then
    for _, line in ipairs(lines(live)) do ns.Chat.say(line) end
  end
  if #sim > 0 then ns.Chat.print("[sim] Loot to hand out: " .. table.concat(sim, " ")) end
end

function Loot.print()
  local entries = Loot.list.entries
  if #entries == 0 then ns.Chat.print("The loot list is empty."); return end
  for i, e in ipairs(entries) do
    ns.Chat.print(string.format("%d. %s (%s): %s%s", i, Loot.linkOf(e), e.boss ~= "" and e.boss or "?",
      LootList.label(e), e.sim and " [sim]" or ""))
  end
end

function Loot.remove(n)
  if not ns.Roster.canLead() then ns.Chat.print("You need raid lead or assist to change the loot list."); return end
  local e = Loot.list:get(n)
  if not e then ns.Chat.print("There is no " .. tostring(n) .. " on the loot list."); return end
  Loot.list:remove(e)
  if not e.sim then send({ { msg = { t = "LOOT", e = LootList.wire(e), rm = true }, dist = "RAID" } }) end
  ns.Chat.print("Removed " .. Loot.linkOf(e) .. " from the loot list.")
  changed()
end

function Loot.clear()
  if not ns.Roster.canLead() then ns.Chat.print("You need raid lead or assist to clear the loot list."); return end
  local n = #Loot.list.entries
  Loot.list:clear()
  send({ { msg = { t = "LOOT_CLEAR" }, dist = "RAID" } })
  ns.Chat.print(string.format("Cleared the loot list (%d item%s).", n, n == 1 and "" or "s"))
  changed()
end

-- dropSim(): /tlc sim stop takes its drops off the list
function Loot.dropSim()
  Loot.list:clear(function(e) return not e.sim end)
  ns.Frames.lootChanged()
end

---------------------------------------------------------------------------
-- sharing
---------------------------------------------------------------------------

function Loot.request()
  return { { msg = { t = "LOOT_REQUEST" }, dist = "RAID" } }
end

local function leads(name)
  local unit = ns.Roster.unitOf(name)
  return unit ~= nil and (UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)) and true or false
end

-- follow the session too, when this client has it: it may be newer than the message
local function merged(e)
  local s = e.session and ns.App.registry:get(e.session)
  if s then LootList.follow(e, s) end
end

function Loot.handles(t) return t == "LOOT" or t == "LOOT_LIST" or t == "LOOT_CLEAR" or t == "LOOT_REQUEST" end

-- handle(msg, sender, trusted, signed): trusted and signed as Comms reports them
function Loot.handle(m, sender, trusted, signed)
  if ns.App.secret() == nil then trusted = not signed end
  if not trusted then return end
  if m.t == "LOOT_REQUEST" then
    local rows = Loot.list:snapshot()
    if #rows > 0 and ns.Roster.canLead() then
      for i = 1, #rows, 10 do -- in parts, so one lost chunk loses ten entries, not the night
        local part = {}
        for j = i, math.min(#rows, i + 9) do part[#part + 1] = rows[j] end
        send({ { msg = { t = "LOOT_LIST", es = Codec.array(part) }, dist = "WHISPER", target = sender } })
      end
    end
    return
  end
  if not leads(sender) then return end
  local dirty = false
  if m.t == "LOOT" then
    if not LootList.validEntry(m.e, Codec.null) then return end
    if m.rm == true then
      local e = Loot.list:byKeyOf(m.e.k)
      dirty = e ~= nil and Loot.list:remove(e)
    else
      local e = Loot.list:merge(m.e)
      if e then merged(e); dirty = true end
    end
  elseif m.t == "LOOT_LIST" then
    if type(m.es) ~= "table" or #m.es > LootList.MAX then return end
    for _, row in ipairs(m.es) do
      local e = LootList.validEntry(row, Codec.null) and Loot.list:merge(row)
      if e then merged(e); dirty = true end
    end
  elseif m.t == "LOOT_CLEAR" then
    dirty = #Loot.list.entries > 0
    Loot.list:clear(function(e) return e.sim end)
  end
  if dirty then changed() end
end

function Loot.init()
  Loot.list = LootList.new()
  Loot.list:restore(ns.Store.loot(Loot.MAX_AGE, now()))
  frame:RegisterEvent("LOOT_OPENED")
  frame:SetScript("OnEvent", function() Loot.onLootOpened() end)
end

return Loot
