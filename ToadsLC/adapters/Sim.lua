-- Sim: /tlc sim fakes a boss kill outside a raid. It opens a council session for each of
-- the boss's drops (from data/RaidLoot.lua), one after the other, and a fake raid answers
-- them: button responses, /roll lines, passes, the odd duplicate roll, and a fake officer's
-- vote once responses close. The player answers in the candidate frame like any raider.
--
-- Simulated sessions go through the same registry as real ones. Their ids start with
-- "sim-"; they are never saved, exported or posted to group chat, and /tlc sim stop drops them.
-- It runs solo or in a party, never in a raid group, and never alongside a live session.
--
-- The drops also go on the loot list (adapters/Loot.lua), marked as simulated. /tlc sim
-- opens them one after the other; /tlc sim drop only records them, for trying the list:
-- start each one from /tlc loot, and the fake raid answers it.
local _, ns = ...

local Sim = {}
ns.Sim = Sim

local Codec, Priority = ns.Codec, ns.Priority

Sim.OFFICER = "Toadmaster"
Sim.RAIDERS = {
  { name = "Croaksworth", class = "Warrior", spec = "Warrior:Protection" },
  { name = "Ribbita", class = "Rogue", spec = "Rogue:Combat" },
  { name = "Hoppington", class = "Hunter", spec = "Hunter:BeastMastery" },
  { name = "Bogwort", class = "Mage", spec = "Mage:Fire" },
  { name = "Lilypadd", class = "Warlock", spec = "Warlock:Destruction" },
  { name = "Tadpolly", class = "Priest", spec = "Priest:Holy" },
  { name = "Wartimus", class = "Druid", spec = "Druid:Restoration" },
  { name = "Puddlefoot", class = "Shaman", spec = "Shaman:Enhancement" },
  { name = "Swampella", class = "Paladin", spec = "Paladin:Retribution" },
  { name = "Murkgill", class = "Warrior", spec = "Warrior:Fury" },
  { name = "Toadstool", class = "Priest", spec = "Priest:Shadow" },
  { name = "Fenhopper", class = "Paladin", spec = "Paladin:Holy" },
}
Sim.SECONDS = 30

local NOTES = { "", "", "", "BiS", "upgrade", "small upgrade", "for my off-spec set", "please :)" }
local QUALITY_COLOR = { [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000" }

local byName = {}
for _, r in ipairs(Sim.RAIDERS) do byName[Priority.nameKey(r.name)] = r end

Sim.random = math.random -- the tests swap in a fixed sequence

local tasks, generation, queue, advanced, drops = {}, 0, {}, {}, 0

Sim.active = false -- between /tlc sim and /tlc sim stop (or a live session opening)
Sim.MIN_SECONDS, Sim.MAX_SECONDS = 5, 600 -- what other clients accept in a SESSION_OPEN

local function chance(p) return Sim.random() < p end
local function pick(list) return list[Sim.random(#list)] end

local function shuffled(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  for i = #out, 2, -1 do
    local j = Sim.random(i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end

-- after(seconds, fn): run fn on the ticker once that much server time has passed,
-- unless /tlc sim stop (or a new /tlc sim) came first
local function after(seconds, fn)
  tasks[#tasks + 1] = { at = ns.App.now() + seconds, gen = generation, fn = fn }
end

local function runDue()
  local now, due, keep = ns.App.now(), {}, {}
  for _, t in ipairs(tasks) do
    if t.gen == generation then -- older ones belong to a stopped simulation
      if t.at <= now then due[#due + 1] = t else keep[#keep + 1] = t end
    end
  end
  tasks = keep
  for _, t in ipairs(due) do t.fn() end
end

function Sim.init()
  C_Timer.NewTicker(0.5, runDue)
end

function Sim.isSim(s) return s ~= nil and type(s.id) == "string" and s.id:find("^sim%-") ~= nil end

-- who(name) -> { class, spec } for a fake raider, so the leader's roster knows them. Only while
-- a simulation runs, and never for someone of that name actually in the group.
function Sim.who(name)
  if not Sim.active then return nil end
  local r = byName[Priority.nameKey(name)]
  if r and ns.Roster.unitOf(name) then return nil end
  if r then return { class = r.class, spec = r.spec } end
end

---------------------------------------------------------------------------
-- choosing the loot
---------------------------------------------------------------------------

local function lower(s) return (s or ""):lower() end

local function dropsWhere(test)
  local out = {}
  for _, d in ipairs(ns.RaidLoot) do if test(d) then out[#out + 1] = d end end
  return out
end

-- How many items a kill drops: 10-man raids two, 25-man raids three, trash one.
local function dropCount(d)
  if d.boss == "Trash" then return 1 end
  if d.zone == "Karazhan" or d.zone == "Zul'Aman" then return 2 end
  return 3
end

-- choose(query) -> zone, boss, { item, ... } | nil, error
-- query: empty (a random boss, in the current zone when it is a raid), a boss, a zone,
-- or one item (link, ID or name).
function Sim.choose(query)
  query = query and query:match("^%s*(.-)%s*$") or ""
  local q = lower(query)
  local bosses
  if q == "" then
    local here = lower((GetInstanceInfo()))
    bosses = dropsWhere(function(d) return lower(d.zone) == here and d.boss ~= "Trash" end)
    if #bosses == 0 then bosses = dropsWhere(function(d) return d.boss ~= "Trash" end) end
  else
    bosses = dropsWhere(function(d) return lower(d.boss) == q end)
    if #bosses == 0 then bosses = dropsWhere(function(d) return lower(d.boss):find(q, 1, true) ~= nil end) end
    if #bosses == 0 then
      bosses = dropsWhere(function(d) return lower(d.zone):find(q, 1, true) ~= nil and d.boss ~= "Trash" end)
    end
  end
  if #bosses > 0 then
    local d = pick(bosses)
    local items = {}
    for i, it in ipairs(shuffled(d.items)) do
      if i > dropCount(d) then break end
      items[i] = it
    end
    return d.zone, d.boss, items
  end
  -- one item, by link, ID or name
  local id = tonumber(query:match("item:(%d+)") or query:match("^(%d+)$"))
  local name = lower(query:match("%[(.-)%]") or query)
  for _, d in ipairs(ns.RaidLoot) do
    for _, it in ipairs(d.items) do
      if (id and it[1] == id) or (not id and lower(it[2]) == name) then return d.zone, d.boss, { it } end
    end
  end
  for _, d in ipairs(ns.RaidLoot) do
    for _, it in ipairs(d.items) do
      if not id and lower(it[2]):find(name, 1, true) then return d.zone, d.boss, { it } end
    end
  end
  return nil, "No boss, raid or item matches \"" .. query .. "\"."
end

---------------------------------------------------------------------------
-- the fake raid
---------------------------------------------------------------------------

local function linkFor(it)
  local _, link = GetItemInfo(it[1]) -- also asks the server for the item, for the icon and tooltip
  return link or string.format("|c%s|Hitem:%d::::::::70:::::|h[%s]|h|r", QUALITY_COLOR[it[3]] or "ffffffff", it[1], it[2])
end

-- An item the imported list does not cover gets a made-up priority over the fake raid's
-- specs, so tiers, ranking and overrides can still be tried.
local function fakeItem(it)
  local specs = {}
  for i, r in ipairs(shuffled(Sim.RAIDERS)) do
    if i > 4 then break end
    specs[i] = { spec = r.spec }
  end
  local priority = { { specs[1] }, { specs[2], specs[3] }, { specs[4] }, { { spec = "ANY" } } }
  if chance(0.5) then table.insert(priority[1], table.remove(priority[2])) end
  return { itemId = it[1], name = it[2], priority = priority, sim = true }
end

-- listed(item, raider): true when the raider's spec has a tier of its own (not just "everyone else")
local function listed(item, r)
  local t, c = Priority.match(item, { player = r.name, class = r.class, spec = r.spec })
  return t ~= nil and item.priority[t][c].spec ~= "ANY"
end

local function rsp(s, r, response)
  local m = { t = "RSP", s = s.id, r = response, c = r.class, sp = r.spec }
  if response ~= "pass" then m.n = pick(NOTES) end
  -- trusted, unsigned: what a raider's whisper looks like to the leader
  ns.App.send(ns.App.registry:handle(m, r.name, true, false))
end

-- roll(s, r, max): straight into this session, never the registry's newest open one
local function roll(s, r, max)
  if s.phase ~= "open" then return end
  local n = Sim.random(max)
  ns.Chat.print(string.format("|cffffff00%s rolls %d (1-%d)|r", r.name, n, max))
  local reg = ns.App.registry
  ns.App.send(reg:act(s, s:ingestRoll(r.name, n, 1, max, Sim.who(r.name)), "RESPONSE"))
end

-- How one fake raider answers: listed specs mostly want it for main spec; the rest
-- pass, stay quiet, or take it for off-spec.
local function answer(s, r, window)
  local wants
  if s.item and listed(s.item, r) then
    wants = chance(0.85) and "main" or (chance(0.5) and "offspec" or "pass")
  else
    local x = Sim.random()
    wants = x < 0.2 and "main" or x < 0.5 and "offspec" or x < 0.75 and "pass" or nil
  end
  if not wants then return end
  local max = wants == "offspec" and s.rules.offspecRollMax or 100
  after(Sim.random(window), function()
    if s.phase ~= "open" then return end
    if wants == "pass" then rsp(s, r, "pass"); return end
    local how = Sim.random()
    if how < 0.7 then -- button, then the roll a second or two later
      rsp(s, r, wants)
      after(Sim.random(2), function() roll(s, r, max) end)
    elseif how < 0.9 then -- just /roll
      roll(s, r, max)
    else -- button only: never rolls
      rsp(s, r, wants)
    end
    if chance(0.08) then after(2, function() roll(s, r, max) end) end -- rolls twice: ignored as a duplicate
  end)
end

local function officerVote(s)
  if s.phase ~= "voting" then return end
  local r = s:result()
  local target = r.winner or (r.ranked and r.ranked[1])
  local live = {}
  for _, e in ipairs(s.candidates) do if not e.ignored then live[#live + 1] = e end end
  if #live == 0 then return end
  if not target or chance(0.25) then target = pick(live) end
  ns.App.send(ns.App.registry:handle({ t = "VOTE", s = s.id, p = target.player }, Sim.OFFICER, true, false))
  ns.Chat.print(string.format("[sim] %s voted for %s.", Sim.OFFICER, target.player))
end

local function open(job)
  local App, Store = ns.App, ns.Store
  local pdb = Store.priorities() or {}
  local it = job.item
  local item = Priority.lookup(pdb, it[1], it[2])
  local council = { Sim.OFFICER }
  for _, n in ipairs(ns.Roster.council()) do council[#council + 1] = n end
  local outs, s = App.registry:open({
    id = string.format("sim-%s-%d", Codec.isoTime(App.now()), it[1]),
    itemId = it[1], itemName = it[2], itemLink = linkFor(it),
    item = item or fakeItem(it),
    zone = job.zone, boss = job.boss, council = council,
    rules = pdb.rules or {}, mode = "session", seconds = job.seconds,
    priorityVersion = item and pdb.version or nil,
  })
  App.send(outs)
  if not job.quiet then App.announce(s, s:openLine()) end
  ns.Loot.opened(s, job.entry)
  if not item then ns.Chat.print("[sim] " .. it[2] .. " is not on your list; using a made-up priority.") end
  local window = math.max(2, math.floor(job.seconds * 0.6))
  for _, r in ipairs(Sim.RAIDERS) do answer(s, r, window) end
end

local function openNext()
  local job = table.remove(queue, 1)
  if job then open(job) end
end

-- The next item opens once this one stops taking responses: once per session, and not
-- while it is reopened for a re-roll (its next close tries again).
local function advance(s)
  if s.phase == "open" or advanced[s.id] then return end
  advanced[s.id] = true
  openNext()
end

function Sim.onChange(s, what)
  if not Sim.active or not Sim.isSim(s) or not s:isLeader(ns.Roster.me()) then return end
  if what == "SESSION_CLOSE" then
    after(2, function() officerVote(s) end)
    after(3, function() advance(s) end)
  elseif what == "REROLL" then
    -- the tied fake raiders roll again, inside the re-roll window
    for _, r in ipairs(Sim.RAIDERS) do
      local key = Priority.nameKey(r.name)
      if s.restrict and s.restrict[key] then
        local max = 100
        for _, c in ipairs(s.candidates) do if Priority.nameKey(c.player) == key and c.max then max = c.max end end
        after(Sim.random(math.max(1, ns.Session.REROLL_SECONDS - 5)), function() roll(s, r, max) end)
      end
    end
  end
end

---------------------------------------------------------------------------
-- commands
---------------------------------------------------------------------------

-- clear(): cancel what is scheduled, end the simulated sessions for the party too, and
-- drop them. Returns how many there were.
local function clear()
  Sim.active = false
  generation = generation + 1
  queue, advanced = {}, {}
  local App, reg = ns.App, ns.App.registry
  local kept, dropped = {}, 0
  Sim.quiet = true -- no "not awarded" line for each one
  for _, id in ipairs(reg.order) do
    local s = reg.sessions[id]
    if Sim.isSim(s) then
      if s.phase ~= "done" and s:isLeader(ns.Roster.me()) then App.send(reg:award(id, nil, nil)) end
      reg.sessions[id] = nil
      dropped = dropped + 1
    else
      kept[#kept + 1] = id
    end
  end
  Sim.quiet = false
  reg.order = kept
  ns.Loot.dropSim()
  ns.Frames.hideCandidate()
  ns.Frames.sessionsChanged()
  return dropped
end

local function liveOpen()
  local me = ns.Roster.me()
  return ns.App.registry:latest(function(s) return not Sim.isSim(s) and s.phase == "open" and s:isLeader(me) end)
end

-- checks(seconds) -> true when a simulation may start here
local function checks(seconds)
  local Chat = ns.Chat
  if IsInRaid() then
    Chat.print("Not in a raid group: a simulation would show fake loot to the whole raid. Solo or a party only.")
    return
  end
  if IsInGroup() and not ns.Roster.canLead() then
    Chat.print("You need party lead to run a simulation in a party.")
    return
  end
  if liveOpen() then
    Chat.print("A real loot session is still taking rolls; close or award it first.")
    return
  end
  if seconds and (seconds < Sim.MIN_SECONDS or seconds > Sim.MAX_SECONDS) then
    Chat.print(string.format("Use %d to %d seconds.", Sim.MIN_SECONDS, Sim.MAX_SECONDS))
    return false
  end
  return true
end

-- record(zone, boss, items) -> loot list entries for the fake kill's drops
local function record(zone, boss, items)
  local entries = {}
  for i, it in ipairs(items) do
    drops = drops + 1
    entries[i] = ns.Loot.record({ key = string.format("sim:%d:%d", drops, it[1]), itemId = it[1], name = it[2],
                                  link = linkFor(it), zone = zone, boss = boss, sim = true })
  end
  return entries
end

function Sim.start(query, seconds)
  local Chat = ns.Chat
  if not checks(seconds) then return end
  local zone, boss, items = Sim.choose(query)
  if not zone then Chat.print(boss); return end
  clear() -- a new run replaces the last one
  Sim.active = true
  local entries = record(zone, boss, items)
  for i, it in ipairs(items) do
    queue[#queue + 1] = { item = it, zone = zone, boss = boss, seconds = seconds or Sim.SECONDS, entry = entries[i] }
  end
  local names = {}
  for i, it in ipairs(items) do names[i] = it[2] end
  Chat.print(string.format("[sim] %s killed (%s): %s. %d fake raiders and %s are answering; use the frames as normal.",
    boss, zone, table.concat(names, ", "), #Sim.RAIDERS, Sim.OFFICER))
  openNext()
end

-- drop(query): a fake kill whose drops only go on the loot list. Kills add up, as in a raid,
-- until /tlc sim stop or a /tlc sim run.
function Sim.drop(query)
  local Chat = ns.Chat
  if not checks(nil) then return end
  local zone, boss, items = Sim.choose(query)
  if not zone then Chat.print(boss); return end
  if not Sim.active then clear() end
  Sim.active = true
  record(zone, boss, items)
  local names = {}
  for i, it in ipairs(items) do names[i] = it[2] end
  Chat.print(string.format("[sim] %s killed (%s): %s, on the loot list. /tlc loot to start them; %d fake raiders and %s answer.",
    boss, zone, table.concat(names, ", "), #Sim.RAIDERS, Sim.OFFICER))
end

-- openEntry(entry, seconds, quiet): a simulated loot list entry, started from /tlc loot;
-- quiet when /tlc loot all announces the lot in one go
function Sim.openEntry(e, seconds, quiet)
  if not Sim.active then ns.Chat.print("[sim] The simulation was stopped; /tlc sim drop again."); return end
  if not checks(seconds) then return end
  local it = { e.itemId, e.name, 4 }
  for _, d in ipairs(ns.RaidLoot) do
    for _, x in ipairs(d.items) do if x[1] == e.itemId then it = x end end
  end
  open({ item = it, zone = e.zone, boss = e.boss, seconds = seconds or Sim.SECONDS, entry = e, quiet = quiet })
end

function Sim.stop()
  local dropped = clear()
  ns.Chat.print(string.format("[sim] Stopped; cleared %d simulated session%s.", dropped, dropped == 1 and "" or "s"))
end

return Sim
