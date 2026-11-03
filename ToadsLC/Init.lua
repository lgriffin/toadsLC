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

-- whisperWinner(s, text): tell the winner privately; nobody needs a whisper from themselves,
-- and /tlc sim winners are made up, so the player only sees what would have been sent
function App.whisperWinner(s, text)
  if not text or Priority.nameKey(s.awardedTo) == Priority.nameKey(Roster.me()) then return end
  if ns.Sim.isSim(s) then
    if not ns.Sim.quiet then Chat.print("[sim] to " .. s.awardedTo .. ": " .. text:gsub("^%[ToadsLC%] ", "")) end
  else
    Chat.whisper(text, s.awardedTo)
  end
end

local function onChange(s, what)
  local me = Roster.me()
  if what == "SESSION_OPEN" or what == "STATE" then
    -- what this character answered before a reload (raiders get no snapshot of their own entry)
    if not s.myResponse then s.myResponse = Store.answer(s.id) end
  end
  if what == "SESSION_OPEN" then
    if s.mode == "session" then
      -- the council works from the Loot page (/tlc); the answer window waits for the end of a
      -- pull, so items opened as they drop never pop up mid-fight
      App.showCandidateSoon()
    end
  elseif what == "SESSION_CLOSE" then
    Frames.hideCandidate(s)
    if s:isLeader(me) and s.mode == "roll" then App.announce(s, s:resultLine()) end
  elseif what == "FINAL_CALL" then
    if s:isLeader(me) then
      App.announce(s, string.format("[ToadsLC] Last call for %s: %d s left to answer.", s.itemLink or s.itemName,
        s:timeLeft(App.now())), true)
    end
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
    if s:isLeader(me) and set.announceAward ~= false and not s.quietAward then App.announce(s, s:awardLine(set.awardMessage), true) end
    if s:isLeader(me) and set.whisperAward ~= false then App.whisperWinner(s, s:whisperLine(set.whisperMessage)) end
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

-- open(itemText, seconds, mode [, entry [, quiet [, untimed]]]) -> session: entry is a loot list
-- entry, whose item, zone and boss are used; quiet leaves the raid chat line to the caller
-- (/tlc loot all); untimed keeps it open until the council's last call (the whole pool at once).
-- A single item takes answers for the officers' setting (itemSeconds, 15 s by default).
-- canStart(): who hands out loot. With a raid begun (a password set), only the character who
-- began it; with none, the raid leader (or an assist when the leader has no addon running it).
-- Outside a group anyone may, to try things out. /tlc sim practice is always allowed.
function App.canStart()
  if ns.Sim.active then return true end
  if not IsInGroup() then return true end
  local raid = App.secret() and Store.raid()
  if raid then return raid.hosting == true and Roster.canLead() end
  return Roster.canLead()
end

function App.cantStartWhy()
  local raid = App.secret() and Store.raid()
  if raid and not raid.hosting then return "Only the raid leader who began the raid hands out loot." end
  if not Roster.canLead() then return "Only the raid leader (or the assist who began the raid) hands out loot." end
  return nil
end

-- councilNames() -> the council for a new item: the priority list's council[] (or the raid's
-- leader and assists), plus every officer who has joined with tonight's password
function App.councilNames()
  local out, seen = {}, {}
  local function add(n)
    local k = n and Priority.nameKey(n)
    if k and k ~= "" and not seen[k] and #out < 40 then seen[k] = true; out[#out + 1] = n end
  end
  for _, n in ipairs(Roster.council()) do add(n) end
  if App.secret() and App.registry then
    local raid = Store.raid()
    local list = App.registry:councilList(raid and raid.hosting)
    if list.leader then add(list.leader) end
    for _, n in ipairs(list.names) do if list.state[Priority.nameKey(n)] ~= "bad" then add(n) end end
  end
  return out
end

function App.open(itemText, seconds, mode, entry, quiet, untimed)
  if not App.canStart() then
    Chat.print(App.cantStartWhy() or ("You can't start a " .. mode .. " here."))
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
    council = mode == "session" and App.councilNames() or {},
    rules = rules, mode = mode,
    seconds = seconds or Store.settings().itemSeconds or rules.sessionSeconds, untimed = untimed,
    priorityVersion = pdb.version,
  })
  send(outs)
  if not quiet then Chat.say(s:openLine(), true) end
  ns.Loot.opened(s, entry)
  return s
end

-- the answer window, now or once this pull is over
local candidateAfterCombat = false
function App.showCandidateSoon()
  if InCombatLockdown and InCombatLockdown() then candidateAfterCombat = true; return end
  Frames.showCandidate()
end

App.ANSWERS = { bis = "BiS", main = "Main", offspec = "OS", pass = "Pass" }

-- respond(id, response, note): BiS / Main / OS / Pass. Council sessions take no roll: the
-- council votes on who gets it. An answer can be changed while the item is open.
function App.respond(id, response, note)
  local s = App.registry:get(id)
  if not s then return end
  if s.phase ~= "open" then Chat.print(s.itemName .. " isn't taking answers any more."); return end
  send(App.registry:respond(id, response, note, Roster.specOf("player")))
  Store.setAnswer(id, response, App.now())
  Chat.print(string.format("Answered %s for %s%s.", App.ANSWERS[response] or response, s.itemLink or s.itemName,
    response ~= "pass" and " The council votes once answers are in" or ""))
  if Frames.refreshCandidate then Frames.refreshCandidate() end
  if ns.Main.refresh then ns.Main.refresh() end
end

function App.vote(id, player) send(App.registry:vote(id, player)) end
function App.propose(id, player, reason) send(App.registry:propose(id, player, reason)) end
function App.setSpec(id, player, spec) send(App.registry:setSpec(id, player, spec)) end
-- close(id): the council ends answers early, with a last call of Session.FINAL_SECONDS
-- (a second press during the last call closes straight away)
function App.close(id) send(App.registry:finalCall(id)) end
function App.reroll(id) send(App.registry:reroll(id)) end

function App.award(id, player, via, reason)
  local s = App.registry:get(id)
  if not s or not s:isLeader(Roster.me()) then
    Chat.print("Only the raid leader who opened this item can award it.")
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
    if s.phase == "open" then send(App.registry:close(s.id)) end
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

function App.unaward(id) send(App.registry:unaward(id)) end

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

-- raidStart() -> when tonight's raid began on this character (Begin raid or Join), or nil
function App.raidStart()
  local r = App.secret() and Store.raid()
  return r and r.at or nil
end

-- export(all): Export new is tonight's raid only (sessions opened since Begin raid), named after
-- it, so practice items from before the raid stay out; Export all is every saved session
function App.export(all)
  local since = not all and App.raidStart() or nil
  local records = Store.records(all, since)
  local pdb = Store.priorities()
  local realm = (GetRealmName() or ""):gsub("%s", "")
  local raidName = App.raidName()
  local doc = {
    format = Codec.SESSION_FORMAT, version = Codec.VERSION,
    exportedAt = Codec.isoTime(App.now()),
    exportedBy = Roster.me() .. "-" .. realm,
    addonVersion = App.VERSION,
    priorityVersion = pdb and pdb.version or Codec.null,
    sessions = Codec.array(records),
  }
  if raidName and not all then doc.raidName = raidName end
  local older = 0
  if since then older = #Store.records(false) - #records end
  local what = raidName and not all and (raidName .. ": ") or ""
  Frames.showExport(Codec.encode(doc, "  "),
    string.format("%s%d session%s.%s After the site accepts it: Mark as sent", what, #records, #records == 1 and "" or "s",
      older > 0 and string.format(" %d older one%s left out (Export all has them).", older, older == 1 and "" or "s") or ""))
end

function App.exportClear()
  local _, ids = Store.records(false, App.raidStart())
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
  local secret, raid = App.secret(), Store.raid()
  if secret then
    Chat.print(string.format("Raid password: set (%s, fingerprint %s). Every officer should see the same fingerprint.",
      raid.hosting and "leading" or "joined", secret.fingerprint))
    Chat.print("Council: " .. ns.Main.councilText())
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

-- tonight() -> the session records saved tonight (the history page, /tlc history)
function App.tonight() return Store.since(loginTime - 6 * 3600) end

-- awardsTonight() -> { { id, itemId, itemName, awardedTo, reason, traded, at }, ... }, oldest first:
-- every item handed out (or not) tonight that this client knows of, whoever ran it: the
-- sessions it saw, the loot list, and the records it saved, once each by session id
function App.awardsTonight()
  local out, seen = {}, {}
  local since = loginTime - 6 * 3600
  local function add(id, itemId, name, to, reason, at)
    if not id or seen[id] or ns.Sim.isSim({ id = id }) then return end
    seen[id] = true
    if at and at < since then return end
    out[#out + 1] = { id = id, itemId = itemId, itemName = name, awardedTo = to, reason = reason,
                      traded = ns.Trade.traded(id), at = at or 0 }
  end
  local reg = App.registry
  for _, id in ipairs(reg and reg.order or {}) do
    local s = reg.sessions[id]
    if s.phase == "done" then add(s.id, s.itemId, s.itemName, s.awardedTo, s.override and s.override.reason, s.openedAt) end
  end
  for _, e in ipairs(ns.Loot.list.entries) do
    if e.session and (e.status == "awarded" or e.status == "none") then
      add(e.session, e.itemId, e.name, e.winner, nil, e.at)
    end
  end
  for _, r in ipairs(App.tonight()) do
    if r and r.id and r.closedAt ~= Codec.null then
      local ov = r.override ~= Codec.null and r.override or nil
      add(r.id, r.itemId ~= Codec.null and r.itemId or nil, r.itemName,
        r.awardedTo ~= Codec.null and r.awardedTo or nil, ov and ov.reason, nil)
    end
  end
  table.sort(out, function(a, b) return a.at < b.at end)
  return out
end

function App.history()
  local recs = App.awardsTonight()
  if #recs == 0 then Chat.print("No awards tonight."); return end
  for _, r in ipairs(recs) do
    local to = r.awardedTo or "not awarded"
    local ov = r.reason and r.reason ~= "" and (" (override: " .. r.reason .. ")") or ""
    local tr = r.awardedTo and (r.traded and ", traded" or ", still to trade") or ""
    Chat.print(string.format("%s: %s%s%s", r.itemName, to, tr, ov))
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
  C_Timer.After(5, function()
    send(App.registry:requestState()); send(ns.Loot.request())
    -- after a reload: check the password again, so the council list is right on both sides
    local raid = Store.raid()
    if App.secret() and raid and IsInGroup() then send(raid.hosting and App.registry:rollcall() or App.registry:hello()) end
  end)
  C_Timer.After(20, function() if IsInGroup() then send(App.registry:requestState()); send(ns.Loot.request()) end end)
end

---------------------------------------------------------------------------
-- raid password: /tlc begin <password> (raid leader), /tlc join <password> (officers)
---------------------------------------------------------------------------

local RAID_MAX_AGE = 12 * 3600 -- a raid password is forgotten after a night
local secretCache

-- secret() -> the raid password's keys, or nil (none set, or set more than 12 hours ago)
function App.secret()
  local r = Store.raid()
  if r and App.now() - (r.at or 0) > RAID_MAX_AGE then
    r, secretCache = nil, nil; Store.setRaid(nil)
  end
  if not r then return nil end
  if not secretCache or secretCache.hex ~= r.key then
    local s = ns.Wire.secret(ns.Crypto.unhex(r.key))
    s.hex = r.key
    secretCache = s
  end
  return secretCache
end

-- raidName() -> what the leader called tonight's raid (shown to every officer who joins)
function App.raidName()
  local r = App.secret() and Store.raid()
  if not r then return nil end
  if r.hosting then return r.name or (Roster.me() .. "'s raid") end
  local c = App.registry and App.registry.councilIn
  return c and c.raidName
end

-- nameRaid(name): the leader names (or renames) tonight's raid; officers see it at once
function App.nameRaid(name)
  local r = App.secret() and Store.raid()
  name = name and name:match("^%s*(.-)%s*$") or ""
  if not r or not r.hosting then Chat.print("Only the raid leader who began the raid can name it."); return end
  if name == "" then Chat.print("Tonight's raid: " .. App.raidName() .. ". /tlc name <raid name> to rename it."); return end
  r.name = name:sub(1, 60)
  Chat.print("Tonight's raid is now called " .. r.name .. ".")
  send({ { msg = App.registry:councilInMsg(), dist = "RAID" } })
end

local function setPassword(password, hosting)
  if not password or #password < 6 then
    Chat.print("Use a password of at least 6 characters, shared with the council only (not raid chat).")
    return false
  end
  local key = ns.Wire.keyFromPassword(password)
  Store.setRaid({ key = ns.Crypto.hex(key), hosting = hosting, at = App.now() })
  return true
end

function App.beginRaid(password, name)
  if not setPassword(password, true) then return end
  name = name and name:match("^%s*(.-)%s*$") or ""
  if name ~= "" then Store.raid().name = name:sub(1, 60) end
  App.registry:forgetCouncil()
  Chat.print("Raid begun: " .. App.raidName() .. ". Council traffic is now signed and encrypted (fingerprint "
    .. App.secret().fingerprint .. "). Officers: Join council with the same password; you'll see each one join here.")
  -- officers who typed the password before we began get confirmed now
  send(App.registry:rollcall())
end

-- checkCouncil(): the leader asks who is in again; an officer checks with the leader again
function App.checkCouncil()
  local raid = Store.raid()
  if not App.secret() or not raid then Chat.print("No raid password is set: Begin raid or Join first."); return end
  if raid.hosting then
    Chat.print("Asking the council who's in…")
    send(App.registry:rollcall())
  else
    Chat.print("Checking your password with the raid leader…")
    send(App.registry:hello())
  end
end

function App.joinRaid(password)
  if not setPassword(password, false) then return end
  App.registry:forgetCouncil()
  Chat.print("Joined with fingerprint " .. App.secret().fingerprint .. "; checking it with the raid leader…")
  send(App.registry:hello())
end

function App.endRaid()
  Store.setRaid(nil)
  secretCache = nil
  App.registry:forgetCouncil()
  Chat.print("Raid password cleared. Council traffic is unsigned again.")
end

local NOTICES = {
  welcome = "Raid password matches NAME's. You're in the council traffic.",
  joined = "NAME joined the council (same raid password).",
  welcome_raid = "Welcome to RAID! You're on the loot council; NAME leads.",
  mismatch = "NAME tried to join with a different raid password.",
  mismatch_self = "Your raid password doesn't match NAME's. Check it with them, End raid, then Join council again.",
  noanswer = "No raid leader answered yet. Once they press Begin raid you'll be confirmed by yourself.",
  needjoin = "NAME's loot council uses a raid password. Join council (/tlc) with it to see and vote.",
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
    group = Roster.group,
    onChange = onChange,
    secured = function() return App.secret() ~= nil end,
    hosting = function() return App.secret() ~= nil and Store.raid().hosting end,
    raidName = function() return App.raidName() end,
    notify = function(kind, name, raid)
      local line = NOTICES[kind]
      if line then
        line = line:gsub("NAME", function() return name or "" end):gsub("RAID", function() return raid or "" end)
        Chat.print(line)
      end
      if kind == "welcome" then send(ns.Loot.request()) end -- the list we could not check before
      if ns.Main.refresh then ns.Main.refresh() end -- the Raid & council page's who's-in line
    end,
  })
  Comms.init(function(msg, sender, trusted, signed)
    if ns.Loot.handles(msg.t) then ns.Loot.handle(msg, sender, trusted, signed); return end
    if ns.Version.handles(msg.t) then ns.Version.handle(msg, sender); return end
    send(App.registry:handle(msg, sender, trusted, signed))
  end,
    function(sender) App.registry:notice("sealed", sender) end)
  ns.Tooltip.init()
  ns.Commands.init()
  ns.Main.init()
  ns.Loot.init()
  ns.Mule.init()
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
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
  elseif event == "PLAYER_REGEN_ENABLED" then
    if candidateAfterCombat then candidateAfterCombat = false; Frames.showCandidate() end
  elseif event == "BOSS_KILL" then
    local _, encounterName = ...
    lastBoss = encounterName or lastBoss
  end
end)
