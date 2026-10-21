-- Sim: /tlc sim fakes a boss kill outside a raid. It opens a council session for each of
-- the boss's drops (from data/RaidLoot.lua), one after the other, and a fake raid answers
-- them: button responses, /roll lines, passes, the odd duplicate roll, and a fake officer's
-- vote once responses close. The player answers in the candidate frame like any raider.
--
-- Simulated sessions go through the same registry as real ones. Their ids start with
-- "sim-"; they are never saved, exported or posted to group chat, and /tlc sim stop drops them.
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

local tasks, generation, queue = {}, 0, {}

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

-- who(name) -> { class, spec } for a fake raider, so the leader's roster knows them
function Sim.who(name)
  local r = byName[Priority.nameKey(name)]
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

local function roll(s, r, max)
  if s.phase ~= "open" then return end
  local n = Sim.random(max)
  ns.Chat.print(string.format("|cffffff00%s rolls %d (1-%d)|r", r.name, n, max))
  ns.App.send(ns.App.registry:roll(r.name, n, 1, max))
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

local function openNext()
  local job = table.remove(queue, 1)
  if not job then return end
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
  App.announce(s, s:openLine())
  if not item then ns.Chat.print("[sim] " .. it[2] .. " is not on your list; using a made-up priority.") end
  local window = math.max(2, math.floor(job.seconds * 0.6))
  for _, r in ipairs(Sim.RAIDERS) do answer(s, r, window) end
end

-- onChange(s, what): the next item opens once this one stops taking responses
function Sim.onChange(s, what)
  if not Sim.isSim(s) or not s:isLeader(ns.Roster.me()) then return end
  if what == "SESSION_CLOSE" then
    after(2, function() officerVote(s) end)
    after(3, openNext)
  end
end

---------------------------------------------------------------------------
-- commands
---------------------------------------------------------------------------

function Sim.start(query, seconds)
  local Chat = ns.Chat
  local _, instanceType = (IsInInstance or function() end)()
  if instanceType == "raid" then
    Chat.print("Not inside a raid instance: a simulation would show fake loot to the whole raid.")
    return
  end
  if IsInGroup() and not ns.Roster.canLead() then
    Chat.print("You need group lead or assist to run a simulation in a group.")
    return
  end
  local zone, boss, items = Sim.choose(query)
  if not zone then Chat.print(boss); return end
  generation = generation + 1
  queue = {}
  for _, it in ipairs(items) do
    queue[#queue + 1] = { item = it, zone = zone, boss = boss, seconds = seconds or Sim.SECONDS }
  end
  local names = {}
  for i, it in ipairs(items) do names[i] = it[2] end
  Chat.print(string.format("[sim] %s killed (%s): %s. %d fake raiders and %s are answering; use the frames as normal.",
    boss, zone, table.concat(names, ", "), #Sim.RAIDERS, Sim.OFFICER))
  openNext()
end

function Sim.stop()
  generation = generation + 1
  queue = {}
  local reg, kept, dropped = ns.App.registry, {}, 0
  for _, id in ipairs(reg.order) do
    if Sim.isSim(reg.sessions[id]) then
      reg.sessions[id] = nil
      dropped = dropped + 1
    else
      kept[#kept + 1] = id
    end
  end
  reg.order = kept
  ns.Frames.hideCandidate()
  ns.Frames.sessionsChanged()
  ns.Chat.print(string.format("[sim] Stopped; cleared %d simulated session%s.", dropped, dropped == 1 and "" or "s"))
end

return Sim
