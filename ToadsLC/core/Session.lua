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
  elseif r.tie then
    opts.tied = r.tied -- the list cannot pick: re-roll, or award by name
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
  s.preAward = { cw = s.computedWinner, cb = s.computedBy }
  if m.cw ~= nil then s.computedWinner, s.computedBy = m.cw, m.cb end
  s.phase = "done"
  return true
end

function Apply.UNAWARD(s, _, sender)
  if not s:isLeader(sender) or s.phase ~= "done" then return false end
  s.awardedTo, s.awardedBy, s.awardedVia, s.override = nil, nil, nil, nil
  if s.preAward then s.computedWinner, s.computedBy, s.preAward = s.preAward.cw, s.preAward.cb, nil end
  s.phase = "voting"
  return true
end

-- apply(msg, sender) -> true when the session changed.
function Session:apply(m, sender)
  local fn = Apply[m.t]
  if not fn then return false end
  -- A leader message is applied once, in order; an officer's vote or proposal is ignored
  -- when it is older than the last one seen from them. A replayed message changes nothing.
  local fromLeader = self:isLeader(sender)
  if fromLeader and m.v and m.v <= (self.version or 0) then return false end
  if m.q then
    self.lastSeq = self.lastSeq or {}
    local k = nameKey(sender)
    if m.q <= (self.lastSeq[k] or 0) then return false end
    self.lastSeq[k] = m.q
  end
  local changed = fn(self, m, sender)
  -- only a change takes a version, so a rejected action never uses one up
  if changed and m.v and fromLeader and m.v > (self.version or 0) then self.version = m.v end
  return changed
end

---------------------------------------------------------------------------
-- leader-side: turning responses and roll lines into RESPONSE messages
---------------------------------------------------------------------------

local function responseMsg(s, k, e)
  return { t = "RESPONSE", s = s.id, k = k, p = e.player, c = e.class, sp = e.spec, r = e.response,
           n = e.note, ro = e.roll, mx = e.max, ig = e.ignored }
end

-- responseFromMax(max, pressed): what a roll counts as. A 1-100 roll is Upgrade unless the
-- player pressed BiS; BiS and Upgrade roll the same, only the button tells them apart.
function Session:responseFromMax(max, pressed)
  if max == self.rules.offspecRollMax then return "offspec" end
  return pressed == "bis" and "bis" or "main"
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
                response = self:responseFromMax(max, cur.response), note = cur.note, roll = roll, max = max }
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
-- rsp = { r = "bis" | "main" | "offspec" | "pass", n = note, c = class, sp = spec }; "main" is Upgrade
function Session:ingestResponse(player, rsp, who)
  if self.phase ~= "open" then return nil end
  local key = nameKey(player)
  if self.restrict and not self.restrict[key] then return nil end
  who = who or {}
  -- The leader's roster (class from the client, spec from inspect or members[]) wins over
  -- what the raider's addon claims; a claimed spec is only taken when it fits the class.
  local class = who.class or rsp.c
  local spec = who.spec
  if not spec and rsp.sp and Priority.isSpec(rsp.sp) and rsp.sp:match("^(%a+):") == class then spec = rsp.sp end
  if rsp.r == "pass" then
    if self.live[key] then return nil end
    return { t = "RESPONSE", s = self.id, p = player, r = "pass" }
  end
  if rsp.r ~= "bis" and rsp.r ~= "main" and rsp.r ~= "offspec" then return nil end
  local k = self.live[key]
  local cur = k and self.candidates[k]
  if cur then
    -- the roll line got here first; keep the roll, add the note and spec, and BiS if pressed
    local e = { player = cur.player, class = class or cur.class, spec = spec or cur.spec,
                response = cur.roll and self:responseFromMax(cur.max, rsp.r) or cur.response, note = rsp.n or "", roll = cur.roll, max = cur.max }
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
  elseif not r.tie then
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
  local seqs = {}
  for o, q in pairs(self.lastSeq or {}) do seqs[#seqs + 1] = { o, q } end
  table.sort(seqs, function(a, b) return a[1] < b[1] end)
  local cands = {}
  for i, e in ipairs(self.candidates) do
    cands[i] = { p = e.player, c = e.class, sp = e.spec, r = e.response, n = e.note,
                 ro = e.roll, mx = e.max, ig = e.ignored }
  end
  return {
    t = "STATE", s = self.id, v = self.version or 0,
    o = { itemId = self.itemId, itemName = self.itemName, itemLink = self.itemLink, zone = self.zone,
          boss = self.boss, leader = self.leader, council = self.council, rules = self.rules,
          mode = self.mode, priorityVersion = self.priorityVersion },
    oa = self.openedAt, left = self:timeLeft(now), ca = self.closedAt, ph = self.phase,
    cands = cands, passed = passed, votes = votes, sq = seqs, prop = self.proposal, restrict = restrict,
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
  s.version = m.v or 0
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
  s.lastSeq = {}
  for _, v in ipairs(m.sq or {}) do s.lastSeq[v[1]] = v[2] end
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

-- How an entry reads in chat: the label of the tier cell it matched ("Fury"), or OffSpec.
function Session:describe(e)
  if e.max == self.rules.offspecRollMax then return "OffSpec" end
  local t, c = Priority.match(self.item, e)
  if t then
    local cell = Priority.tiers(self.item)[t][c]
    local label = cell.cand.player and (e.spec and Priority.label(e.spec) or e.class) or cell.label
    return label, t
  end
  if e.spec and Priority.isSpec(e.spec) then return Priority.label(e.spec) end
  return e.class or "?"
end

-- BiS is flagged in front so the council sees it; Upgrade is the plain case.
local function who(s, e, withTier)
  local label, tier = s:describe(e)
  if tier and withTier then label = strformat("%s, tier %d", label, tier) end
  if e.response == "bis" and e.max ~= s.rules.offspecRollMax then label = "BiS, " .. label end
  return label
end

function Session:openLine()
  local list = self.item and Priority.text(self.item)
  local how = "/roll Upgrade, /roll " .. self.rules.offspecRollMax .. " OffSpec."
  local head
  if self.mode == "session" then
    head = strformat("[ToadsLC] Loot session: %s (%d s). Answer in the frame, or %s",
                     self.itemLink, self.closesAt - self.openedAt, how)
  else
    head = strformat("[ToadsLC] Roll: %s (%d s). %s", self.itemLink, self.closesAt - self.openedAt, how)
  end
  return head .. (list and (" Priority: " .. list .. ".") or " Not on the priority list: BiS first, then highest roll.")
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
    return strformat("[ToadsLC] %s: only OffSpec rolls. %s by priority, %s by highest roll; the council picks.",
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
  if s:isLeader(self.ctx.me) then msg.v = (s.version or 0) + 1 end
  -- an action this client rejects is not sent: it would only use up a version elsewhere
  if not s:apply(msg, self.ctx.me) then return {} end
  self:changed(s, what or msg.t)
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

Registry.UNCLAIMED_SECONDS = 15 -- how long a roll waits for the button press it belongs to

-- With several items open at once (/tlc loot all), a /roll line names no item. Each MS or OS
-- button press both whispers the leader and rolls, so a player's rolls are matched to their
-- button presses in order: a roll goes to the oldest press still missing its roll, and a roll
-- that gets here before its press waits for it. A /roll with no press behind it only counts
-- while a single item is open.

local function openLed(self)
  local me, n = self.ctx.me, 0
  for _, id in ipairs(self.order) do
    local s = self.sessions[id]
    if s.phase == "open" and s:isLeader(me) then n = n + 1 end
  end
  return n
end

-- awaiting(key) -> the oldest open session whose button press from this player has no roll yet
function Registry:awaitingRoll(key)
  local q = self.awaiting and self.awaiting[key]
  while q and #q > 0 do
    local s = self.sessions[table.remove(q, 1)]
    local k = s and s.phase == "open" and s.live[key]
    if k and s.candidates[k].roll == nil then return s end
  end
end

-- roll(player, roll, min, max): a parsed /roll line seen by this client.
function Registry:roll(player, roll, min, max)
  local key = nameKey(player)
  local s = self:awaitingRoll(key)
  if not s then
    local open = openLed(self)
    if open == 0 then return {} end
    if open > 1 then -- several items open: hold it for the button press it belongs to
      self.unclaimed = self.unclaimed or {}
      local q = self.unclaimed[key] or {}
      self.unclaimed[key] = q
      q[#q + 1] = { roll = roll, min = min, max = max, at = self:now() }
      return {}
    end
    s = self:rolling()
  end
  return self:act(s, s:ingestRoll(player, roll, min, max, self.ctx.who(player)), "RESPONSE")
end

-- pressed(s, player): a button press reached the leader; pair it with a waiting roll, or
-- wait for one
function Registry:pressed(s, player)
  local key = nameKey(player)
  local k = s.live[key]
  if not k or s.candidates[k].roll ~= nil or s.candidates[k].response == "pass" then return {} end
  local q = self.unclaimed and self.unclaimed[key]
  while q and #q > 0 do
    local r = table.remove(q, 1)
    if self:now() - r.at <= Registry.UNCLAIMED_SECONDS then
      return self:act(s, s:ingestRoll(player, r.roll, r.min, r.max, self.ctx.who(player)), "RESPONSE")
    end
  end
  self.awaiting = self.awaiting or {}
  self.awaiting[key] = self.awaiting[key] or {}
  table.insert(self.awaiting[key], s.id)
  return {}
end

-- seq(): increasing per client, across reloads (time-based), for votes and proposals
function Registry:seq()
  local q = self:now() * 100
  if self.lastQ and q <= self.lastQ then q = self.lastQ + 1 end
  self.lastQ = q
  return q
end

function Registry:vote(id, player)
  local s = self.sessions[id]
  if not s then return {} end
  return self:act(s, { t = "VOTE", s = id, p = player, q = self:seq() })
end

function Registry:propose(id, player, reason)
  local s = self.sessions[id]
  if not s then return {} end
  return self:act(s, { t = "PROPOSE", s = id, p = player, re = reason, q = self:seq() })
end

-- hello(): an officer checking their council password against the raid's
function Registry:hello()
  self.helloAt = self:now()
  return out({}, { t = "HELLO" })
end

Registry.NOTICE_EVERY = 60 -- seconds between repeats of the same notice about the same player
Registry.HELLO_WAIT = 10   -- seconds /tlc join waits for the raid leader's answer

-- notice(kind, name) -> true when this player was told (once a minute at most per kind and name)
function Registry:notice(kind, name)
  self.noticedAt = self.noticedAt or {}
  local k, now = kind .. "|" .. nameKey(name or ""), self:now()
  if self.noticedAt[k] and now - self.noticedAt[k] < Registry.NOTICE_EVERY then return false end
  self.noticedAt[k] = now
  if self.ctx.notify then self.ctx.notify(kind, name) end
  return true
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
  if self.helloAt and now - self.helloAt >= Registry.HELLO_WAIT then
    self.helloAt = nil
    self:notice("noanswer")
  end
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

---------------------------------------------------------------------------
-- incoming message checks: anything from another client is untrusted, so every field a
-- handler reads is type-checked first and a malformed message is dropped, never thrown on.
---------------------------------------------------------------------------

local MAX_TEXT = 255

local function isInt(v) return type(v) == "number" and v == math.floor(v) and v > -1e12 and v < 1e12 end

local KINDS = {
  str = function(v) return type(v) == "string" and #v <= MAX_TEXT end,
  int = isInt,
  num = function(v) return type(v) == "number" and v == v and v > -1e12 and v < 1e12 end,
  bool = function(v) return type(v) == "boolean" end,
  names = function(v)
    if type(v) ~= "table" or #v > 40 then return false end
    for _, n in ipairs(v) do if type(n) ~= "string" or #n > MAX_TEXT then return false end end
    return true
  end,
  tbl = function(v) return type(v) == "table" end,
}

-- field -> kind; a trailing "?" makes it optional (absent or null)
local FIELDS = {
  SESSION_OPEN = { s = "str", it = "int?", nm = "str", lk = "str?", z = "str?", b = "str?", co = "names",
                   sec = "int", oa = "int?", md = "str?", pv = "str?", ru = "tbl?", v = "int?" },
  RSP = { s = "str", r = "str", n = "str?", c = "str?", sp = "str?" },
  RESPONSE = { s = "str", k = "int?", p = "str", c = "str?", sp = "str?", r = "str", n = "str?", ro = "int?",
               mx = "int?", ig = "str?", v = "int?" },
  VOTE = { s = "str", p = "str?", v = "int?", q = "int?" },
  PROPOSE = { s = "str", p = "str?", re = "str?", v = "int?", q = "int?" },
  SESSION_CLOSE = { s = "str", at = "int", cw = "str?", cb = "str", hr = "str?", final = "bool?", v = "int?" },
  REROLL = { s = "str", at = "int", names = "names", sec = "int?", v = "int?" },
  AWARD = { s = "str", p = "str?", via = "str?", ov = "tbl?", cw = "str?", cb = "str?", v = "int?" },
  UNAWARD = { s = "str", v = "int?" },
  STATE_REQUEST = {},
  HELLO = {},
  WELCOME = {},
  MISMATCH = {},
  STATE = { s = "str", v = "int?", o = "tbl", oa = "int", left = "num?", ca = "int?", ph = "str",
            cands = "tbl?", passed = "names?", votes = "tbl?", sq = "tbl?", prop = "tbl?", restrict = "names?",
            cw = "str?", cb = "str?", hr = "str?", aw = "tbl?" },
}

local ONE_OF = {
  r = { bis = true, main = true, offspec = true, pass = true },
  ph = { open = true, voting = true, done = true },
  cb = { priority = true, ["highest-roll"] = true, none = true },
  via = { votes = true, proposal = true, list = true, ["highest-roll"] = true, manual = true },
  md = { session = true, roll = true },
}

local function checkFields(m, fields)
  for k in pairs(m) do
    if k ~= "t" and not fields[k] then return false end
    if m[k] == Codec.null then m[k] = nil end
  end
  for k, kind in pairs(fields) do
    local v = m[k]
    local opt = kind:sub(-1) == "?"
    if opt then kind = kind:sub(1, -2) end
    if v == nil then
      if not opt then return false end
    elseif not KINDS[kind](v) or (ONE_OF[k] and not ONE_OF[k][v]) then
      return false
    end
  end
  return true
end

local function checkState(m)
  local o = m.o
  if not checkFields(o, { itemId = "int?", itemName = "str", itemLink = "str?", zone = "str?", boss = "str?",
                          leader = "str", council = "names", rules = "tbl?", mode = "str?",
                          priorityVersion = "str?" }) then return false end
  if #(m.cands or {}) > 200 then return false end
  for _, c in ipairs(m.cands or {}) do
    if type(c) ~= "table" or not checkFields(c, { p = "str", c = "str?", sp = "str?", r = "str", n = "str?",
                                                  ro = "int?", mx = "int?", ig = "str?" }) then
      return false
    end
  end
  for _, v in ipairs(m.votes or {}) do
    if type(v) ~= "table" or type(v[1]) ~= "string" or type(v[2]) ~= "string" then return false end
  end
  for _, v in ipairs(m.sq or {}) do
    if type(v) ~= "table" or type(v[1]) ~= "string" or type(v[2]) ~= "number" then return false end
  end
  if m.prop and not checkFields(m.prop, { by = "str", player = "str", reason = "str?" }) then return false end
  if m.aw and not checkFields(m.aw, { p = "str?", by = "str?", via = "str?", ov = "tbl?" }) then return false end
  return true
end

local function checkRules(r)
  if r == nil then return true end
  return checkFields(r, { offspecRollMax = "int?", allOffspecMode = "str?", sessionSeconds = "int?",
                          votesVisibleTo = "str?" })
end

local function checkOverride(ov)
  return ov == nil or checkFields(ov, { by = "str", reason = "str?" })
end

-- valid(m) -> true when the message is well-formed for its type.
function Session.valid(m)
  if type(m) ~= "table" or type(m.t) ~= "string" then return false end
  local fields = FIELDS[m.t]
  if not fields or not checkFields(m, fields) then return false end
  if m.t == "SESSION_OPEN" then
    return m.sec > 0 and m.sec <= 600 and checkRules(m.ru)
  elseif m.t == "RESPONSE" then
    return m.k == nil or m.k >= 1
  elseif m.t == "AWARD" then
    return checkOverride(m.ov)
  elseif m.t == "STATE" then
    return checkState(m) and checkRules(m.o.rules) and (m.aw == nil or checkOverride(m.aw.ov))
  end
  return true
end

Registry.STATE_RETRY = 10 -- seconds between snapshot requests for a session we have not seen

-- handle(msg, sender, trusted, signed): an addon message from another client.
-- trusted: the message carried a valid signature for this client's council password.
-- signed: it carried a signature at all. With no password set here, unsigned traffic is
-- trusted and signed traffic is not (it belongs to a protected council we have not joined).
-- With a password set, council traffic must be trusted; raiders without the password
-- still follow the public open, close and award.
function Registry:handle(m, sender, trusted, signed)
  local me = self.ctx.me
  if not Session.valid(m) then return {} end
  local secured = self.ctx.secured and self.ctx.secured() or false
  if not secured then trusted = not signed end

  if m.t == "HELLO" then
    if not (self.ctx.hosting and self.ctx.hosting()) then return {} end
    if trusted then return out({}, { t = "WELCOME" }, "WHISPER", sender) end
    -- tell the joiner (and ourselves), but not more than once a minute per name
    if not self:notice("mismatch", sender) then return {} end
    return out({}, { t = "MISMATCH" }, "WHISPER", sender)
  end

  -- answers to our own /tlc join only
  if m.t == "WELCOME" or m.t == "MISMATCH" then
    if not secured or not self.helloAt then return {} end
    if m.t == "MISMATCH" then
      self.helloAt = nil
      self:notice("mismatch_self", sender)
      return {}
    end
    if not trusted then return {} end
    self.helloAt = nil
    self:notice("welcome", sender)
    -- sessions we only saw as a viewer before the password was right
    return out({}, { t = "STATE_REQUEST" }, "WHISPER", sender)
  end

  if m.t == "SESSION_OPEN" then
    if self.sessions[m.s] then return {} end
    if not secured and signed and contains(m.co, me) then self:notice("needjoin", sender) end
    -- an open we cannot verify makes us a viewer, never council
    local s = Session.new({ id = m.s, itemId = m.it, itemName = m.nm, itemLink = m.lk, zone = m.z, boss = m.b,
                            leader = sender, council = trusted and m.co or {}, rules = m.ru, mode = m.md, seconds = m.sec,
                            priorityVersion = m.pv, now = self:now(),
                            item = self.ctx.item(m.it, m.nm) })
    s.openedAt = m.oa or s.openedAt
    s.version = m.v or 0
    self:add(s)
    self:changed(s, "SESSION_OPEN")
    return {}
  end

  if m.t == "STATE_REQUEST" then
    local msgs = {}
    for _, id in ipairs(self.order) do
      local s = self.sessions[id]
      if trusted and s:isLeader(me) and s:isCouncil(sender) and s.phase ~= "done" then
        out(msgs, s:stateMsg(self:now()), "WHISPER", sender)
      end
    end
    return msgs
  end

  if m.t == "STATE" then
    local o = m.o
    if not trusted or nameKey(o.leader) ~= nameKey(sender) or not contains(o.council, me) then return {} end
    local known = self.sessions[m.s]
    -- A snapshot may only come from the session's own leader, and never replaces newer state.
    if known and (not known:isLeader(sender) or (m.v or 0) < (known.version or 0)) then return {} end
    local s = Session.fromState(m, self.ctx.item(o.itemId, o.itemName), self:now())
    self:add(s)
    self:changed(s, "STATE")
    return {}
  end

  local s = self.sessions[m.s]
  if not s then
    -- An update for a session we never saw open (we joined late): ask its sender once in a while.
    local now = self:now()
    if m.t ~= "RSP" and (not self.askedAt or now - self.askedAt >= Registry.STATE_RETRY) then
      self.askedAt = now
      return out({}, { t = "STATE_REQUEST" }, "WHISPER", sender)
    end
    return {}
  end

  if m.t == "RSP" then
    if not s:isLeader(me) then return {} end
    local msgs = self:act(s, s:ingestResponse(sender, m, self.ctx.who(sender)), "RESPONSE")
    for _, o in ipairs(self:pressed(s, sender)) do msgs[#msgs + 1] = o end
    return msgs
  end

  -- Raiders outside the council only follow the session's open, close and award.
  local public = m.t == "SESSION_CLOSE" or m.t == "AWARD" or m.t == "UNAWARD" or m.t == "REROLL"
  if not public and not s:isCouncil(me) then return {} end
  if s:isCouncil(me) and not trusted then
    if s:isLeader(me) and s:isCouncil(sender) and (m.t == "VOTE" or m.t == "PROPOSE") then
      self:notice("untrusted", sender)
    end
    return {}
  end
  if m.t == "RESPONSE" and m.k and m.k > #s.candidates + 1 then return {} end
  if s:apply(m, sender) then self:changed(s, m.t) end
  return {}
end

-- restore(state, savedAt): bring back a session this client was leading before a reload.
function Registry:restore(m, savedAt)
  if not Session.valid(m) or nameKey(m.o.leader) ~= nameKey(self.ctx.me) or self.sessions[m.s] then return nil end
  local now = self:now()
  m.left = math.max(0, (m.left or 0) - (now - (savedAt or now)))
  local s = Session.fromState(m, self.ctx.item(m.o.itemId, m.o.itemName), now)
  self:add(s)
  self:changed(s, "STATE")
  return s
end

return Session
