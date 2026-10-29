-- Init: wires the core to the client. Everything that decides who wins is in core/;
-- this file only connects events, frames and chat to the session registry.
local addonName, ns = ...

local App = {}
ns.App = App

local Codec, Priority, Session = ns.Codec, ns.Priority, ns.Session
local Store, Roster, Chat, Comms, Frames = ns.Store, ns.Roster, ns.Chat, ns.Comms, ns.Frames

local lastBoss = ""

App.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(addonName, "Version") or "dev"

-- v1 runs on the TBC Classic client only; the WoW Forever port replaces the adapters.
local function supportedClient()
  return WOW_PROJECT_ID ~= nil and WOW_PROJECT_BURNING_CRUSADE_CLASSIC ~= nil
     and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
end

function App.now() return GetServerTime and GetServerTime() or time() end

-- boss(): the last boss killed (ENCOUNTER_END), for loot recorded off a corpse
function App.boss() return lastBoss end

local wasGrouped = false
local loginTime = 0

---------------------------------------------------------------------------
-- session events
---------------------------------------------------------------------------

local LIVE_MAX_AGE = 2 * 3600 -- a leader's unfinished session survives a reload this long

local function persist(s)
  if not s:isLeader(Roster.me()) or ns.Sim.isSim(s) then return end
  if s.phase ~= "open" then Store.saveSession(s:serialize(), s.openedAt) end
  if s.phase == "done" then Store.clearLive(s.id) else Store.saveLive(s.id, s:stateMsg(App.now()), App.now()) end
end

-- announce(s, text, warn): raid chat, except for /tlc sim sessions, which only the player sees
function App.announce(s, text, warn)
  if ns.Sim.isSim(s) then
    if not ns.Sim.quiet then Chat.print("[sim] " .. text:gsub("^%[ToadsLC%] ", "")) end
  else
    Chat.say(text, warn)
  end
end

local function onChange(s, what)
  local me = Roster.me()
  if what == "SESSION_OPEN" then
    if s.mode == "session" then
      if s:isCouncil(me) then Frames.showCouncil(s.id) end
      Frames.showCandidate(s)
    end
  elseif what == "SESSION_CLOSE" then
    Frames.hideCandidate(s)
    if s:isLeader(me) and s.mode == "roll" then App.announce(s, s:resultLine()) end
  elseif what == "REROLL" then
    if s:isLeader(me) then
      local names = {}
      for _, e in ipairs(s.candidates) do
        if e.ignored == "rerolled" and s.restrict[Priority.nameKey(e.player)] then names[#names + 1] = e.player end
      end
      App.announce(s, string.format("[ToadsLC] %s: tie, re-roll %s (%d s).", s.itemName, table.concat(names, " and "),
        Session.REROLL_SECONDS), true)
    end
  elseif what == "AWARD" then
    local set = Store.settings()
    if s:isLeader(me) and set.announceAward ~= false then App.announce(s, s:awardLine(set.awardMessage), true) end
    ns.Trade.onAward(s)
  elseif what == "STATE" then
    Frames.sessionsChanged()
  end
  persist(s)
  ns.Loot.onSession(s)
  if what ~= "SESSION_OPEN" then Frames.refresh() end
  ns.Sim.onChange(s, what)
end

App.registry = nil

local function send(outs) Comms.send(outs) end
App.send = send

function App.openSessionFor(itemId)
  if not App.registry then return nil end
  return App.registry:latest(function(s) return s.phase == "open" and s.itemId == itemId end)
end

---------------------------------------------------------------------------
-- actions
---------------------------------------------------------------------------

function App.parseItem(text)
  text = text and text:match("^%s*(.-)%s*$") or ""
  if text == "" then return nil end
  local itemId = tonumber(text:match("item:(%d+)"))
  local name = text:match("%[(.-)%]") or text
  local pdb = Store.priorities()
  if not itemId then
    local item = Priority.lookup(pdb, nil, name)
    itemId = item and item.itemId
  end
  local link = text:find("|H") and text or nil
  if itemId and not link then
    local _, l = GetItemInfo(itemId)
    link = l
  end
  return itemId, name, link or ("[" .. name .. "]")
end

-- open(itemText, seconds, mode [, entry [, quiet]]) -> session: entry is a loot list entry, whose
-- item, zone and boss are used; quiet leaves the raid chat line to the caller (/tlc loot all)
function App.open(itemText, seconds, mode, entry, quiet)
  if not Roster.canLead() then
    Chat.print("You need raid lead or assist to start a " .. mode .. ".")
    return
  end
  local itemId, name, link
  if entry then
    itemId, name, link = entry.itemId, entry.name, ns.Loot.linkOf(entry)
  else
    itemId, name, link = App.parseItem(itemText)
  end
  if not name then
    Chat.print("Usage: /tlc " .. mode .. " <item link> [seconds]")
    return
  end
  if ns.Sim.active then -- real loot wins: no fake raid answering it
    ns.Sim.stop()
  end
  local pdb = Store.priorities() or {}
  local rules = pdb.rules or {}
  local outs, s = App.registry:open({
    itemId = itemId, itemName = name, itemLink = link,
    zone = entry and entry.zone ~= "" and entry.zone or (GetInstanceInfo()) or "",
    boss = entry and entry.boss ~= "" and entry.boss or lastBoss,
    council = mode == "session" and Roster.council() or {},
    rules = rules, mode = mode,
    seconds = seconds or (mode == "roll" and Store.settings().rollSeconds) or rules.sessionSeconds,
    priorityVersion = pdb.version,
  })
  send(outs)
  if not quiet then Chat.say(s:openLine(), true) end
  ns.Loot.opened(s, entry)
  return s
end

function App.respond(id, response, note)
  local s = App.registry:get(id)
  if not s then return end
  send(App.registry:respond(id, response, note, Roster.specOf("player")))
  if response == "bis" or response == "main" then RandomRoll(1, 100)
  elseif response == "offspec" then RandomRoll(1, s.rules.offspecRollMax) end
end

function App.vote(id, player) send(App.registry:vote(id, player)) end
function App.propose(id, player, reason) send(App.registry:propose(id, player, reason)) end
function App.setSpec(id, player, spec) send(App.registry:setSpec(id, player, spec)) end
function App.close(id) send(App.registry:close(id)) end
function App.reroll(id) send(App.registry:reroll(id)) end

function App.award(id, player, via, reason)
  local s = App.registry:get(id)
  if not s or not s:isLeader(Roster.me()) then
    Chat.print("Only the session leader can award.")
    return
  end
  send(App.registry:award(id, player, via, reason))
end

local function lastLed(filter)
  local me = Roster.me()
  return App.registry:latest(function(s) return s:isLeader(me) and (not filter or filter(s)) end)
end

function App.awardLast(name, reason)
  local s = lastLed(function(x) return x.phase ~= "done" end)
  if not s then Chat.print("Nothing to award."); return end
  if name then
    local opts = s:awardOptions()
    local via = "manual"
    local listPick = opts.list or opts.listPriority
    if listPick and Priority.nameKey(listPick) == Priority.nameKey(name) then via = "list"
    elseif opts.highest and Priority.nameKey(opts.highest) == Priority.nameKey(name) then via = "highest-roll" end
    App.award(s.id, name, via, reason)
  else
    if s.phase == "open" then App.close(s.id) end
    local tied = s:awardOptions().tied
    if tied then
      Chat.print("Tied: " .. table.concat(tied, " and ") .. ". /tlc reroll, or /tlc award <name> [reason].")
      return
    end
    if not s.computedWinner or s.listRoll then
      Chat.print("The list does not name a single winner: /tlc award <name> [reason].")
      return
    end
    App.award(s.id, s.computedWinner, "list")
  end
end

function App.closeLast()
  local s = lastLed(function(x) return x.phase == "open" end)
  if s then App.close(s.id) else Chat.print("No open session.") end
end

function App.rerollLast()
  local s = lastLed(function(x) return x.phase == "voting" end)
  if s then App.reroll(s.id) else Chat.print("Nothing to re-roll.") end
end

function App.undoLast()
  local s = lastLed(function(x) return x.phase == "done" end)
  if not s then Chat.print("No award to undo."); return end
  send(App.registry:unaward(s.id))
  Chat.print("Reopened " .. s.itemName .. "; award again from the council frame or /tlc award.")
end

---------------------------------------------------------------------------
-- import / export
---------------------------------------------------------------------------

local function dateOf(iso)
  local y, m, d = (iso or ""):match("^(%d+)-(%d+)-(%d+)")
  if not y then return iso or "?" end
  local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
  return string.format("%d %s %s", tonumber(d), months[tonumber(m)] or m, y)
end

function App.import(text)
  local doc, err = Codec.decode(text or "")
  if not doc then
    local msg = "import failed: " .. err
    Chat.print(msg)
    return false, msg
  end
  local ok, verr = Codec.validatePriority(doc)
  if not ok then
    local msg = "import failed: " .. verr
    Chat.print(msg)
    return false, msg
  end
  local previous = Store.priorities()
  local pdb = Priority.index(Codec.stripNulls(doc), Roster.me(), App.now())
  Store.setPriorities(pdb)
  local msg = string.format("Imported %d items, dated %s%s.", pdb.count, dateOf(pdb.exportedAt),
    previous and (", replacing the list dated " .. dateOf(previous.exportedAt)) or "")
  Chat.print(msg)
  return true, msg
end

function App.undoImport()
  if Store.undoImport() then
    local p = Store.priorities()
    Chat.print(string.format("Restored the list dated %s (%d items).", dateOf(p.exportedAt), p.count))
  else
    Chat.print("Nothing to undo.")
  end
end

function App.export(all)
  local records = Store.records(all)
  local pdb = Store.priorities()
  local realm = (GetRealmName() or ""):gsub("%s", "")
  local doc = {
    format = Codec.SESSION_FORMAT, version = Codec.VERSION,
    exportedAt = Codec.isoTime(App.now()),
    exportedBy = Roster.me() .. "-" .. realm,
    addonVersion = App.VERSION,
    priorityVersion = pdb and pdb.version or Codec.null,
    sessions = Codec.array(records),
  }
  Frames.showExport(Codec.encode(doc, "  "),
    string.format("%d session%s. After the site accepts it: /tlc export clear", #records, #records == 1 and "" or "s"))
end

function App.exportClear()
  local _, ids = Store.records(false)
  Store.markExported(ids)
  Chat.print(string.format("Marked %d session%s as sent.", #ids, #ids == 1 and "" or "s"))
end

function App.status()
  local p = Store.priorities()
  if not p then
    Chat.print("Priorities: none imported. /tlc import")
  else
    Chat.print(string.format("Priorities: %d items, dated %s, imported by %s", p.count, dateOf(p.exportedAt),
      p.importedBy or "?"))
  end
  local _, ids = Store.records(false)
  Chat.print(string.format("Sessions waiting for export: %d", #ids))
  local secret, raid = App.secret(), Store.settings().raid
  if secret then
    Chat.print(string.format("Raid password: set (%s, fingerprint %s). Every officer should see the same fingerprint.",
      raid.hosting and "leading" or "joined", secret.fingerprint))
  else
    Chat.print("Raid password: none. Council traffic is unsigned; /tlc begin <password> to protect it.")
  end
end

-- debug(itemText): what the tooltip needs, for "the tooltip shows no priorities"
function App.debug(itemText)
  local version, build, _, interface = GetBuildInfo()
  Chat.print(string.format("Client %s (%s), interface %s, project %s; ToadsLC %s", tostring(version), tostring(build),
    tostring(interface), tostring(WOW_PROJECT_ID), App.VERSION))
  local T = ns.Tooltip
  Chat.print(string.format("Tooltip hooks: %s%s; priorities %s", #T.hooks > 0 and table.concat(T.hooks, ", ") or "none",
    T.dataProcessor and " + TooltipDataProcessor" or "", Store.settings().tooltip and "on" or "off (/tlc tooltip on)"))
  local p = Store.priorities()
  Chat.print(p and string.format("List: %d items, dated %s", p.count, dateOf(p.exportedAt))
    or "List: none imported. /tlc import")
  local last = T.last
  if last then
    Chat.print(string.format("Last item hovered (%d so far): %s (%d) on %s: %s", T.seen, last.name or "?", last.itemId,
      last.tooltip, last.shown and "Priority block shown" or ("not shown, " .. (last.why or "?"))))
  else
    Chat.print("No item tooltip seen since login. Hover an item, then /tlc debug again.")
  end
  if itemText and itemText ~= "" then
    local itemId, name = App.parseItem(itemText)
    local item = Priority.lookup(p, itemId, name)
    Chat.print(string.format("%s (%s): %s", name or "?", tostring(itemId),
      item and ("on the list: " .. (Priority.text(item) or "")) or "not on the list"))
  end
end

function App.history()
  local since = loginTime - 6 * 3600
  local recs = Store.since(since)
  if #recs == 0 then Chat.print("No awards tonight."); return end
  for _, r in ipairs(recs) do
    local to = r.awardedTo ~= Codec.null and r.awardedTo or "not awarded"
    local ov = (r.override ~= Codec.null and r.override) and (" (override: " .. (r.override.reason or "") .. ")") or ""
    Chat.print(string.format("%s: %s%s", r.itemName, to, ov))
  end
end

---------------------------------------------------------------------------
-- events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")

local function onRoll(text)
  local name, roll, min, max = ns.RollParser.parse(text)
  if not name then return end
  name = Roster.normalize(name)
  local outs = App.registry:roll(name, roll, min, max)
  send(outs)
  local who = Roster.who(name)
  if who and not who.spec then Roster.queueInspect({ name }) end
end

-- Ask the leaders for any open session: at login, and on joining a group. The second ask
-- covers a leader whose client was still loading.
function App.askState()
  C_Timer.After(5, function() send(App.registry:requestState()); send(ns.Loot.request()) end)
  C_Timer.After(20, function() if IsInGroup() then send(App.registry:requestState()); send(ns.Loot.request()) end end)
end

---------------------------------------------------------------------------
-- raid password: /tlc begin <password> (raid leader), /tlc join <password> (officers)
---------------------------------------------------------------------------

local RAID_MAX_AGE = 12 * 3600 -- a raid password is forgotten after a night
local secretCache

-- secret() -> the raid password's keys, or nil (none set, or set more than 12 hours ago)
function App.secret()
  local r = Store.settings().raid
  if r and App.now() - (r.at or 0) > RAID_MAX_AGE then
    Store.settings().raid, r, secretCache = nil, nil, nil
  end
  if not r then return nil end
  if not secretCache or secretCache.hex ~= r.key then
    local s = ns.Wire.secret(ns.Crypto.unhex(r.key))
    s.hex = r.key
    secretCache = s
  end
  return secretCache
end

local function setPassword(password, hosting)
  if not password or #password < 6 then
    Chat.print("Use a password of at least 6 characters, shared with the council only (not raid chat).")
    return false
  end
  local key = ns.Wire.keyFromPassword(password)
  Store.settings().raid = { key = ns.Crypto.hex(key), hosting = hosting, at = App.now() }
  return true
end

function App.beginRaid(password)
  if not setPassword(password, true) then return end
  Chat.print("Raid begun. Council traffic is now signed and encrypted (fingerprint " .. App.secret().fingerprint
    .. "). Officers: /tlc join <the same password>.")
end

function App.joinRaid(password)
  if not setPassword(password, false) then return end
  Chat.print("Joined with fingerprint " .. App.secret().fingerprint .. "; checking it with the raid leader…")
  send(App.registry:hello())
end

function App.endRaid()
  Store.settings().raid = nil
  secretCache = nil
  Chat.print("Raid password cleared. Council traffic is unsigned again.")
end

local NOTICES = {
  welcome = "Raid password matches NAME's. You're in the council traffic.",
  mismatch = "NAME tried to join with a different raid password.",
  mismatch_self = "Your raid password doesn't match NAME's. Check it with them, then /tlc join <password> again.",
  noanswer = "No raid leader answered. Check they typed /tlc begin, then /tlc join <password> again.",
  needjoin = "NAME's loot council uses a raid password. Type /tlc join <password> to see and vote in it.",
  untrusted = "NAME is on the council but hasn't joined with the raid password, so their votes are ignored.",
  sealed = "NAME sent council traffic under a different raid password. Compare /tlc status fingerprints.",
}

local function start()
  Store.init()
  App.secret() -- forgets a password from an earlier night
  loginTime = App.now()
  App.registry = Session.newRegistry({
    me = Roster.me(),
    now = App.now,
    item = function(id, name) return Priority.lookup(Store.priorities(), id, name) end,
    who = Roster.who,
    onChange = onChange,
    secured = function() return App.secret() ~= nil end,
    hosting = function() return App.secret() ~= nil and Store.settings().raid.hosting end,
    notify = function(kind, name)
      local line = NOTICES[kind]
      if line then Chat.print((line:gsub("NAME", name or ""))) end
      if kind == "welcome" then send(ns.Loot.request()) end -- the list we could not check before
    end,
  })
  Comms.init(function(msg, sender, trusted, signed)
    if ns.Loot.handles(msg.t) then ns.Loot.handle(msg, sender, trusted, signed); return end
    send(App.registry:handle(msg, sender, trusted, signed))
  end,
    function(sender) App.registry:notice("sealed", sender) end)
  ns.Tooltip.init()
  ns.Commands.init()
  ns.Loot.init()
  ns.Trade.init()
  for _, row in ipairs(Store.live(LIVE_MAX_AGE, App.now())) do
    local s = App.registry:restore(row.state, row.at)
    if s then Chat.print("Picked up your unfinished session for " .. s.itemName .. ".") end
  end
  C_Timer.NewTicker(0.5, function() send(App.registry:tick()) end)
  ns.Sim.init()
  wasGrouped = IsInGroup()
  if wasGrouped then App.askState() end
  frame:RegisterEvent("CHAT_MSG_SYSTEM")
  frame:RegisterEvent("GROUP_ROSTER_UPDATE")
  frame:RegisterEvent("ENCOUNTER_END")
  frame:RegisterEvent("BOSS_KILL")
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    if not supportedClient() then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33cc66[ToadsLC]|r This version runs on the TBC Classic client only; it is disabled here.")
      return
    end
    start()
  elseif event == "CHAT_MSG_SYSTEM" then
    onRoll(...)
  elseif event == "GROUP_ROSTER_UPDATE" then
    local grouped = IsInGroup()
    if grouped and not wasGrouped then App.askState() end
    wasGrouped = grouped
  elseif event == "ENCOUNTER_END" then
    local _, encounterName, _, _, success = ...
    if success == 1 then lastBoss = encounterName or "" end
  elseif event == "BOSS_KILL" then
    local _, encounterName = ...
    lastBoss = encounterName or lastBoss
  end
end)
