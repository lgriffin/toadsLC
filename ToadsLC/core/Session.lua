-- Session: one loot session (or plain /tlc roll) as a pure state machine driven by
-- messages, plus a registry that routes addon messages between clients.
--
-- The session leader's client is the one source of truth for the candidate list: raiders
-- whisper their button response to the leader, /roll lines are parsed on the leader's
-- client, and the leader broadcasts every candidate change as RESPONSE. Votes and
-- proposals come from any council member. Message types:
--   SESSION_OPEN, RSP (raider -> leader), RESPONSE, VOTE, PROPOSE, SESSION_CLOSE,
--   REROLL, AWARD, UNAWARD, STATE_REQUEST, STATE
local _, ns = ...
ns = ns or {}

local Session = {}
Session.__index = Session
ns.Session = Session

local Codec, Priority, Resolver = ns.Codec, ns.Priority, ns.Resolver
local nameKey = Priority.nameKey
local ipairs, pairs, strformat = ipairs, pairs, string.format

Session.REROLL_SECONDS = 15

local function copyList(t)
  local out = {}
  for i, v in ipairs(t or {}) do out[i] = v end
  return out
end

local function contains(list, name)
  local k = nameKey(name)
  for _, n in ipairs(list or {}) do if nameKey(n) == k then return true end end
  return false
end

local function nn(v) if v == nil then return Codec.null end return v end
local function un(v) if v == Codec.null then return nil end return v end

---------------------------------------------------------------------------
-- construction
---------------------------------------------------------------------------

-- new{ id?, itemId, itemName, itemLink?, item?, zone?, boss?, leader, council, rules,
--      mode = "session" | "roll", seconds?, now, priorityVersion? }
function Session.new(o)
  local rules = Resolver.rules(o.rules)
  local s = setmetatable({
    id = o.id or strformat("%s-%s", Codec.isoTime(o.now), tostring(o.itemId or 0)),
    itemId = o.itemId,
    itemName = o.itemName,
    itemLink = o.itemLink or o.itemName,
    item = o.item,
    zone = o.zone or "",
    boss = o.boss or "",
    leader = o.leader,
    council = copyList(o.council),
    rules = rules,
    mode = o.mode or "session",
    priorityVersion = o.priorityVersion,
    openedAt = o.now,
    closesAt = o.now + (o.seconds or rules.sessionSeconds),
    closedAt = nil,
    phase = "open", -- open (taking responses) -> voting -> done
    candidates = {},
    live = {},      -- nameKey -> index of the entry that counts
    passed = {},    -- nameKey -> true
    votes = {},     -- officer -> candidate
    proposal = nil,
    restrict = nil, -- nameKey set during a re-roll of tied names
  }, Session)
  return s
end

function Session:isLeader(name) return nameKey(name) == nameKey(self.leader) end
function Session:isCouncil(name) return self:isLeader(name) or contains(self.council, name) end

function Session:timeLeft(now)
  if self.phase ~= "open" then return 0 end
  return math.max(0, self.closesAt - now)
end

function Session:entryFor(player)
  local k = self.live[nameKey(player)]
  return k and self.candidates[k] or nil
end

function Session:passCount()
  local n = 0
  for _ in pairs(self.passed) do n = n + 1 end
  return n
end

---------------------------------------------------------------------------
-- resolution
---------------------------------------------------------------------------

function Session:result()
  return Resolver.resolve(self.item, self.candidates, self.rules)
end

function Session:tierOf(entry)
  return Priority.tierOf(self.item, entry)
end

-- voteLeader() -> name, count, tied
function Session:voteLeader()
  local counts, best, bestN, tied = {}, nil, 0, false
  for _, cand in pairs(self.votes) do
    local k = nameKey(cand)
    counts[k] = (counts[k] or 0) + 1
  end
  for _, e in ipairs(self.candidates) do
    local k = nameKey(e.player)
    local n = counts[k]
    if n and self.live[k] and not e.ignored then
      if n > bestN then best, bestN, tied = e.player, n, false
      elseif n == bestN and nameKey(best) ~= k then tied = true end
      counts[k] = nil
    end
  end
  return best, bestN, tied
end

function Session:voteCounts()
  local counts = {}
  for _, cand in pairs(self.votes) do
    local k = nameKey(cand)
    counts[k] = (counts[k] or 0) + 1
  end
  return counts
end

-- awardOptions() -> what the leader's award buttons offer.
function Session:awardOptions()
  local r = self:result()
  local opts = { result = r }
  local vl, vn, vtied = self:voteLeader()
  if vl and not vtied then opts.votes, opts.voteCount = vl, vn end
  if self.proposal then opts.proposal = self.proposal.player end
  if r.allOffspec and self.rules.allOffspecMode == "ask" then
    opts.listPriority = r.ranked[1] and r.ranked[1].player
    opts.listRoll = r.highestRoll and r.highestRoll.player
  else
    opts.list = self.computedWinner or (r.winner and r.winner.player)
  end
  local hr = Resolver.highestRoll(self.candidates, self.rules)
  opts.highest = hr and hr.player
  return opts
end

---------------------------------------------------------------------------
-- applying messages (every client, the leader included)
---------------------------------------------------------------------------

local Apply = {}

function Apply.RESPONSE(s, m, sender)
  if not s:isLeader(sender) then return false end
  local key = nameKey(m.p)
  if m.r == "pass" then
    if s.live[key] then return false end
    s.passed[key] = true
    return true
  end
  local e = {
    player = m.p, class = m.c, spec = m.sp, response = m.r, note = m.n or "",
    roll = m.ro, max = m.mx, ignored = m.ig,
  }
  s.candidates[m.k] = e
  if not e.ignored then
    s.live[key] = m.k
    s.passed[key] = nil
  end
  return true
end

function Apply.VOTE(s, m, sender)
  if not s:isCouncil(sender) or s.phase == "done" then return false end
  local officer = nameKey(sender)
  if m.p == nil or m.p == "" then
    s.votes[officer] = nil
  else
    if not s.live[nameKey(m.p)] then return false end
    s.votes[officer] = m.p
  end
  return true
end

function Apply.PROPOSE(s, m, sender)
  if not s:isCouncil(sender) or s.phase == "done" then return false end
  if m.p == nil or m.p == "" then s.proposal = nil; return true end
  s.proposal = { by = sender, player = m.p, reason = m.re or "" }
  return true
end

function Apply.SESSION_CLOSE(s, m, sender)
  if not s:isLeader(sender) or s.phase ~= "open" then return false end
  s.phase = "voting"
  s.closedAt = m.at
  s.restrict = nil
  if s.computedBy == nil or m.final then -- the first close is what the resolver said
    s.computedWinner, s.computedBy, s.listRoll = m.cw, m.cb, m.hr
  end
  return true
end

function Apply.REROLL(s, m, sender)
  if not s:isLeader(sender) or s.phase ~= "voting" then return false end
  s.restrict = {}
  for _, p in ipairs(m.names) do
    local key = nameKey(p)
    s.restrict[key] = true
    local k = s.live[key]
    if k then
      s.candidates[k].ignored = "rerolled"
      s.live[key] = nil
    end
  end
  s.phase = "open"
  s.closesAt = m.at + (m.sec or Session.REROLL_SECONDS)
  s.computedBy = nil -- the re-roll decides the computed winner again
  return true
end

function Apply.AWARD(s, m, sender)
  if not s:isLeader(sender) or s.phase == "open" then return false end
  s.awardedTo = m.p
  s.awardedBy = sender
  s.awardedVia = m.via
  s.override = m.ov
  if m.cw ~= nil then s.computedWinner, s.computedBy = m.cw, m.cb end
  s.phase = "done"
  return true
end

function Apply.UNAWARD(s, _, sender)
  if not s:isLeader(sender) or s.phase ~= "done" then return false end
  s.awardedTo, s.awardedBy, s.awardedVia, s.override = nil, nil, nil, nil
  s.phase = "voting"
  return true
end

-- apply(msg, sender) -> true when the session changed.
function Session:apply(m, sender)
  local fn = Apply[m.t]
  if not fn then return false end
  return fn(self, m, sender)
end

---------------------------------------------------------------------------
-- leader-side: turning responses and roll lines into RESPONSE messages
---------------------------------------------------------------------------

local function responseMsg(s, k, e)
  return { t = "RESPONSE", s = s.id, k = k, p = e.player, c = e.class, sp = e.spec, r = e.response,
           n = e.note, ro = e.roll, mx = e.max, ig = e.ignored }
end

function Session:responseFromMax(max)
  return max == self.rules.offspecRollMax and "offspec" or "main"
end

-- ingestRoll(player, roll, min, max, who) -> RESPONSE msg | nil
-- who = { class, spec } from the roster. Only while responses are open.
function Session:ingestRoll(player, roll, min, max, who)
  if self.phase ~= "open" then return nil end
  local key = nameKey(player)
  if self.restrict and not self.restrict[key] then return nil end
  local valid = min == 1 and (max == 100 or max == self.rules.offspecRollMax)
  local k = self.live[key]
  local cur = k and self.candidates[k]
  who = who or {}
  if cur and cur.roll == nil and valid then
    -- the button response arrived first; its roll completes it
    local e = { player = cur.player, class = cur.class or who.class, spec = cur.spec or who.spec,
                response = self:responseFromMax(max), note = cur.note, roll = roll, max = max }
    return responseMsg(self, k, e)
  end
  local e = { player = player, class = cur and cur.class or who.class, spec = cur and cur.spec or who.spec,
              response = self:responseFromMax(max), note = "", roll = roll, max = max }
  if not valid then
    e.ignored = "out-of-range"
  elseif cur then
    e.ignored = "duplicate"
  end
  return responseMsg(self, #self.candidates + 1, e)
end

-- ingestResponse(player, rsp) -> RESPONSE msg | nil, for a raider's button press.
-- rsp = { r = "main" | "offspec" | "pass", n = note, c = class, sp = spec }
function Session:ingestResponse(player, rsp, who)
  if self.phase ~= "open" then return nil end
  local key = nameKey(player)
  if self.restrict and not self.restrict[key] then return nil end
  who = who or {}
  local class, spec = rsp.c or who.class, rsp.sp or who.spec
  if rsp.r == "pass" then
    if self.live[key] then return nil end
    return { t = "RESPONSE", s = self.id, p = player, r = "pass" }
  end
  if rsp.r ~= "main" and rsp.r ~= "offspec" then return nil end
  local k = self.live[key]
  local cur = k and self.candidates[k]
  if cur then
    -- the roll line got here first; keep the roll, add the note and spec
    local e = { player = cur.player, class = class or cur.class, spec = spec or cur.spec,
                response = cur.response, note = rsp.n or "", roll = cur.roll, max = cur.max }
    return responseMsg(self, k, e)
  end
  local e = { player = player, class = class, spec = spec, response = rsp.r, note = rsp.n or "" }
  return responseMsg(self, #self.candidates + 1, e)
end

-- setSpecMsg(player, spec) -> RESPONSE msg: the LC fixing an unknown spec.
function Session:setSpecMsg(player, spec)
  local k = self.live[nameKey(player)]
  if not k then return nil end
  local cur = self.candidates[k]
  local e = {}
  for f, v in pairs(cur) do e[f] = v end
  e.spec = spec
  return responseMsg(self, k, e)
end

function Session:closeMsg(now)
  local r = self:result()
  local m = { t = "SESSION_CLOSE", s = self.id, at = now, cb = r.by }
  if r.allOffspec and self.rules.allOffspecMode == "ask" then
    m.cw = r.ranked[1] and r.ranked[1].player
    m.hr = r.highestRoll and r.highestRoll.player
  else
    m.cw = r.winner and r.winner.player
  end
  if self.restrict then m.final = true end
  return m
end

function Session:rerollMsg(now, names)
  if not names then
    local r = self:result()
    names = r.tied
  end
  if not names or #names < 2 then return nil end
  return { t = "REROLL", s = self.id, at = now, names = names, sec = Session.REROLL_SECONDS }
end

-- awardMsg(by, player, via, reason) -> AWARD msg. player nil = no award.
-- via: votes | proposal | list | highest-roll | manual
function Session:awardMsg(by, player, via, reason)
  local cw = self.computedWinner
  if via == "list" and player == nil then player = cw end
  local m = { t = "AWARD", s = self.id, p = player, via = player and via or nil }
  -- with only off-spec rolls the LC chooses which list row counts as the computed winner
  if self.listRoll and player and nameKey(player) == nameKey(self.listRoll) and via == "highest-roll" then
    cw = self.listRoll
    m.cw, m.cb = self.listRoll, "highest-roll"
  end
  if player and nameKey(player) ~= nameKey(cw) then
    m.ov = { by = by, reason = reason or "" }
  end
  return m
end

---------------------------------------------------------------------------
-- record and state
---------------------------------------------------------------------------

-- serialize() -> the session record of the toads-loot-session document.
function Session:serialize()
  local cands = Codec.array()
  for i, e in ipairs(self.candidates) do
    local tier = (e.response ~= "offspec") and Priority.tierOf(self.item, e) or nil
    if e.max and e.max == self.rules.offspecRollMax then tier = nil end
    local c = {
      player = e.player, class = nn(e.class), spec = nn(e.spec), response = e.response,
      roll = nn(e.roll), max = nn(e.max), tier = nn(tier), note = e.note or "",
    }
    if e.ignored then c.ignored = e.ignored end
    cands[i] = c
  end
  local votes = Codec.object()
  for officer, cand in pairs(self.votes) do votes[officer] = cand end
  -- officer keys are stored lower-case; restore the council's spelling
  local spelled = Codec.object()
  for _, name in ipairs(self.council) do
    local v = votes[nameKey(name)]
    if v then spelled[name] = v; votes[nameKey(name)] = nil end
  end
  if votes[nameKey(self.leader)] then
    spelled[self.leader] = votes[nameKey(self.leader)]
    votes[nameKey(self.leader)] = nil
  end
  for k, v in pairs(votes) do spelled[k] = v end
  return {
    id = self.id,
    itemId = nn(self.itemId),
    itemName = self.itemName,
    zone = self.zone or "",
    boss = self.boss or "",
    openedAt = Codec.isoTime(self.openedAt),
    closedAt = self.closedAt and Codec.isoTime(self.closedAt) or Codec.null,
    leader = self.leader,
    council = Codec.array(copyList(self.council)),
    candidates = cands,
    passes = self:passCount(),
    votes = spelled,
    proposal = self.proposal and { by = self.proposal.by, player = self.proposal.player,
                                   reason = self.proposal.reason } or Codec.null,
    computedWinner = nn(self.computedWinner),
    computedBy = self.computedBy or "none",
    awardedTo = nn(self.awardedTo),
    awardedBy = nn(self.awardedBy),
    awardedVia = nn(self.awardedVia),
    override = self.override and { by = self.override.by, reason = self.override.reason } or Codec.null,
  }
end

-- stateMsg() -> STATE: everything a late-joining council member needs.
function Session:stateMsg(now)
  local passed = {}
  for k in pairs(self.passed) do passed[#passed + 1] = k end
  table.sort(passed)
  local restrict
  if self.restrict then
    restrict = {}
    for k in pairs(self.restrict) do restrict[#restrict + 1] = k end
    table.sort(restrict)
  end
  local votes = {}
  for o, c in pairs(self.votes) do votes[#votes + 1] = { o, c } end
  table.sort(votes, function(a, b) return a[1] < b[1] end)
  local cands = {}
  for i, e in ipairs(self.candidates) do
    cands[i] = { p = e.player, c = e.class, sp = e.spec, r = e.response, n = e.note,
                 ro = e.roll, mx = e.max, ig = e.ignored }
  end
  return {
    t = "STATE", s = self.id,
    o = { itemId = self.itemId, itemName = self.itemName, itemLink = self.itemLink, zone = self.zone,
          boss = self.boss, leader = self.leader, council = self.council, rules = self.rules,
          mode = self.mode, priorityVersion = self.priorityVersion },
    oa = self.openedAt, left = self:timeLeft(now), ca = self.closedAt, ph = self.phase,
    cands = cands, passed = passed, votes = votes, prop = self.proposal, restrict = restrict,
    cw = self.computedWinner, cb = self.computedBy, hr = self.listRoll,
    aw = self.phase == "done" and { p = self.awardedTo, by = self.awardedBy, via = self.awardedVia,
                                    ov = self.override } or nil,
  }
end

function Session.fromState(m, item, now)
  local o = m.o
  local s = Session.new({ id = m.s, itemId = un(o.itemId), itemName = o.itemName, itemLink = o.itemLink,
                          item = item, zone = o.zone, boss = o.boss, leader = o.leader,
                          council = o.council, rules = o.rules, mode = o.mode,
                          priorityVersion = un(o.priorityVersion), now = m.oa, seconds = 0 })
  s.closesAt = now + (m.left or 0)
  s.closedAt = un(m.ca)
  s.phase = m.ph
  for i, c in ipairs(m.cands or {}) do
    local e = { player = c.p, class = un(c.c), spec = un(c.sp), response = c.r, note = c.n or "",
                roll = un(c.ro), max = un(c.mx), ignored = un(c.ig) }
    s.candidates[i] = e
    if not e.ignored then s.live[nameKey(e.player)] = i end
  end
  for _, k in ipairs(m.passed or {}) do s.passed[k] = true end
  for _, v in ipairs(m.votes or {}) do s.votes[v[1]] = v[2] end
  if m.prop and m.prop ~= Codec.null then s.proposal = m.prop end
  if m.restrict and m.restrict ~= Codec.null then
    s.restrict = {}
    for _, k in ipairs(m.restrict) do s.restrict[k] = true end
  end
  s.computedWinner, s.computedBy, s.listRoll = un(m.cw), un(m.cb), un(m.hr)
  if m.aw and m.aw ~= Codec.null then
    s.awardedTo, s.awardedBy, s.awardedVia, s.override = un(m.aw.p), un(m.aw.by), un(m.aw.via), un(m.aw.ov)
  end
  return s
end

---------------------------------------------------------------------------
-- announcements
---------------------------------------------------------------------------

-- How an entry reads in chat: the label of the tier cell it matched ("Fury"), or off-spec.
function Session:describe(e)
  if e.max == self.rules.offspecRollMax then return "off-spec" end
  local t, c = Priority.match(self.item, e)
  if t then
    local cell = Priority.tiers(self.item)[t][c]
    local label = cell.cand.player and (e.spec and Priority.label(e.spec) or e.class) or cell.label
    return label, t
  end
  if e.spec and Priority.isSpec(e.spec) then return Priority.label(e.spec) end
  return e.class or "?"
end

local function who(s, e, withTier)
  local label, tier = s:describe(e)
  if tier and withTier then return strformat("%s, tier %d", label, tier) end
  return label
end

function Session:openLine()
  local list = self.item and Priority.text(self.item)
  local how = "/roll main spec, /roll " .. self.rules.offspecRollMax .. " off-spec."
  local head
  if self.mode == "session" then
    head = strformat("[ToadsLC] Loot session: %s (%d s). Answer in the frame, or %s",
                     self.itemLink, self.closesAt - self.openedAt, how)
  else
    head = strformat("[ToadsLC] Roll: %s (%d s). %s", self.itemLink, self.closesAt - self.openedAt, how)
  end
  return head .. (list and (" Priority: " .. list .. ".") or " Not on the priority list: highest roll wins.")
end

-- resultLine(): one line for raid chat when the roll closes.
function Session:resultLine()
  local r = self:result()
  local name = self.itemName
  if r.by == "none" then return strformat("[ToadsLC] %s: No rolls.", name) end
  local rest = {}
  local first = r.winner or r.ranked[1]
  for _, e in ipairs(r.ranked) do
    if e ~= first then
      rest[#rest + 1] = strformat("%s %d (%s)", e.player, e.roll, who(self, e, true))
    end
  end
  local tail = #rest > 0 and (" " .. table.concat(rest, ", ") .. ".") or ""
  if r.tie then
    return strformat("[ToadsLC] %s: tie on %d between %s, re-roll.", name, first.roll, table.concat(r.tied, " and "))
  end
  if not r.winner then
    return strformat("[ToadsLC] %s: only off-spec rolls. %s by priority, %s by highest roll; the council picks.",
                     name, r.ranked[1].player, r.highestRoll.player)
  end
  return strformat("[ToadsLC] %s: %s wins (%s, rolled %d).%s", name, first.player, who(self, first, true),
                   first.roll, tail)
end

function Session:awardLine()
  if not self.awardedTo then return strformat("[ToadsLC] %s: not awarded.", self.itemName) end
  local e = self:entryFor(self.awardedTo)
  if not e or not e.roll then return strformat("[ToadsLC] %s: %s.", self.itemName, self.awardedTo) end
  return strformat("[ToadsLC] %s: %s (%s, rolled %d)", self.itemName, self.awardedTo, who(self, e, true), e.roll)
end

---------------------------------------------------------------------------
-- registry: one per client; routes messages and turns local actions into messages
---------------------------------------------------------------------------
-- ctx = {
--   me = "Poohtank",
--   now = function() -> epoch seconds,
--   item = function(itemId, name) -> priority item | nil,
--   who = function(name) -> { class, spec } | nil,
--   onChange = function(session, what) (optional),
-- }
-- Every action and handler returns a list of outgoing { msg, dist = "RAID" | "WHISPER", target }.

local Registry = {}
Registry.__index = Registry

function Session.newRegistry(ctx)
  return setmetatable({ ctx = ctx, sessions = {}, order = {} }, Registry)
end

function Registry:now() return self.ctx.now() end

function Registry:changed(s, what)
  if self.ctx.onChange then self.ctx.onChange(s, what) end
end

function Registry:add(s)
  if not self.sessions[s.id] then self.order[#self.order + 1] = s.id end
  self.sessions[s.id] = s
end

function Registry:get(id) return self.sessions[id] end

-- latest(filter) -> newest session passing filter(s)
function Registry:latest(filter)
  for i = #self.order, 1, -1 do
    local s = self.sessions[self.order[i]]
    if s and (not filter or filter(s)) then return s end
  end
end

-- The session that /roll lines go to: the newest one I lead that is taking responses.
function Registry:rolling()
  local me = self.ctx.me
  return self:latest(function(s) return s.phase == "open" and s:isLeader(me) end)
end

local function out(list, msg, dist, target)
  list[#list + 1] = { msg = msg, dist = dist or "RAID", target = target }
  return list
end

-- Apply locally (as me) and broadcast.
function Registry:act(s, msg, what)
  if not msg then return {} end
  if s:apply(msg, self.ctx.me) then self:changed(s, what or msg.t) end
  return out({}, msg)
end

-- open{ itemId, itemName, itemLink, zone, boss, council, rules, mode, seconds, priorityVersion }
function Registry:open(o)
  local now = self:now()
  o.now, o.leader = now, self.ctx.me
  o.item = o.item or self.ctx.item(o.itemId, o.itemName)
  local s = Session.new(o)
  if self.sessions[s.id] then s.id = s.id .. "-" .. (#self.order + 1) end
  self:add(s)
  self:changed(s, "SESSION_OPEN")
  local msg = { t = "SESSION_OPEN", s = s.id, it = s.itemId, nm = s.itemName, lk = s.itemLink, z = s.zone,
                b = s.boss, co = s.council, sec = s.closesAt - s.openedAt, oa = s.openedAt, md = s.mode,
                pv = s.priorityVersion, ru = s.rules }
  return out({}, msg), s
end

-- respond(id, response, note) as a raider pressing a button.
function Registry:respond(id, response, note, me)
  local s = self.sessions[id]
  if not s or s.phase ~= "open" then return {} end
  me = me or self.ctx.who(self.ctx.me) or {}
  local rsp = { t = "RSP", s = id, r = response, n = note, c = me.class, sp = me.spec }
  s.myResponse = response
  if s:isLeader(self.ctx.me) then return self:handle(rsp, self.ctx.me) end
  return out({}, rsp, "WHISPER", s.leader)
end

-- roll(player, roll, min, max): a parsed /roll line seen by this client.
function Registry:roll(player, roll, min, max)
  local s = self:rolling()
  if not s then return {} end
  return self:act(s, s:ingestRoll(player, roll, min, max, self.ctx.who(player)), "RESPONSE")
end

function Registry:vote(id, player)
  local s = self.sessions[id]
  if not s then return {} end
  return self:act(s, { t = "VOTE", s = id, p = player })
end

function Registry:propose(id, player, reason)
  local s = self.sessions[id]
  if not s then return {} end
  return self:act(s, { t = "PROPOSE", s = id, p = player, re = reason })
end

function Registry:setSpec(id, player, spec)
  local s = self.sessions[id]
  if not s or not s:isLeader(self.ctx.me) then return {} end
  return self:act(s, s:setSpecMsg(player, spec), "RESPONSE")
end

function Registry:close(id)
  local s = self.sessions[id]
  if not s or not s:isLeader(self.ctx.me) or s.phase ~= "open" then return {} end
  return self:act(s, s:closeMsg(self:now()))
end

function Registry:reroll(id, names)
  local s = self.sessions[id]
  if not s or not s:isLeader(self.ctx.me) then return {} end
  return self:act(s, s:rerollMsg(self:now(), names))
end

function Registry:award(id, player, via, reason)
  local s = self.sessions[id]
  if not s or not s:isLeader(self.ctx.me) then return {} end
  local msgs = {}
  if s.phase == "open" then msgs = self:close(id) end
  for _, o in ipairs(self:act(s, s:awardMsg(self.ctx.me, player, via, reason))) do msgs[#msgs + 1] = o end
  return msgs
end

function Registry:unaward(id)
  local s = self.sessions[id]
  if not s or not s:isLeader(self.ctx.me) then return {} end
  return self:act(s, { t = "UNAWARD", s = id })
end

-- tick(): close the response window on sessions I lead whose timer ran out.
function Registry:tick()
  local now, msgs = self:now(), {}
  for _, id in ipairs(self.order) do
    local s = self.sessions[id]
    if s.phase == "open" and s:isLeader(self.ctx.me) and now >= s.closesAt then
      for _, o in ipairs(self:close(id)) do msgs[#msgs + 1] = o end
    end
  end
  return msgs
end

function Registry:requestState()
  return out({}, { t = "STATE_REQUEST" })
end

-- handle(msg, sender): an addon message from another client.
function Registry:handle(m, sender)
  local me = self.ctx.me
  if type(m) ~= "table" or type(m.t) ~= "string" then return {} end

  if m.t == "SESSION_OPEN" then
    if self.sessions[m.s] then return {} end
    local s = Session.new({ id = m.s, itemId = un(m.it), itemName = m.nm, itemLink = m.lk, zone = m.z, boss = m.b,
                            leader = sender, council = m.co, rules = m.ru, mode = m.md, seconds = m.sec,
                            priorityVersion = un(m.pv), now = self:now(),
                            item = self.ctx.item(un(m.it), m.nm) })
    s.openedAt = m.oa or s.openedAt
    self:add(s)
    self:changed(s, "SESSION_OPEN")
    return {}
  end

  if m.t == "STATE_REQUEST" then
    local msgs = {}
    for _, id in ipairs(self.order) do
      local s = self.sessions[id]
      if s:isLeader(me) and s:isCouncil(sender) and s.phase ~= "done" then
        out(msgs, s:stateMsg(self:now()), "WHISPER", sender)
      end
    end
    return msgs
  end

  if m.t == "STATE" then
    local o = m.o or {}
    if nameKey(o.leader) ~= nameKey(sender) or not contains(o.council, me) then return {} end
    local s = Session.fromState(m, self.ctx.item(un(o.itemId), o.itemName), self:now())
    self:add(s)
    self:changed(s, "STATE")
    return {}
  end

  local s = self.sessions[m.s]
  if not s then return {} end

  if m.t == "RSP" then
    if not s:isLeader(me) then return {} end
    return self:act(s, s:ingestResponse(sender, m, self.ctx.who(sender)), "RESPONSE")
  end

  -- Raiders outside the council only follow the session's open, close and award.
  local public = m.t == "SESSION_CLOSE" or m.t == "AWARD" or m.t == "UNAWARD" or m.t == "REROLL"
  if not public and not s:isCouncil(me) then return {} end
  if s:apply(m, sender) then self:changed(s, m.t) end
  return {}
end

return Session
