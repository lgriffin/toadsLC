local H = require("spec.helper")

-- A fake raid: each client has its own registry; RAID messages reach everyone except the
-- sender (who applied them already), WHISPER reaches one client. Messages go through the
-- wire format so the chunking is exercised too.
local function newRaid(ns, names, priorities, secrets)
  local Priority, Session, Wire = ns.Priority, ns.Session, ns.Wire
  local raid = { clients = {}, clock = 1792614670, queue = {}, chat = {} }
  local db = Priority.index(priorities, "Poohtank", 0)
  for _, name in ipairs(names) do
    local c = { name = name, changes = {}, secret = secrets and secrets[name] }
    c.wire = Wire.new({ secret = function() return c.secret end, clock = function() return raid.clock end })
    c.reg = Session.newRegistry({
      me = name,
      secured = function() return c.secret ~= nil end,
      now = function() return raid.clock end,
      item = function(id, n) return Priority.lookup(db, id, n) end,
      who = function(n) local m = db.members[Priority.nameKey(n)]; return m and { class = m.class, spec = m.spec } end,
      onChange = function(_, what) c.changes[#c.changes + 1] = what end,
    })
    raid.clients[name] = c
  end
  function raid.send(from, outs)
    for _, o in ipairs(outs) do
      for _, chunk in ipairs(raid.clients[from] and raid.clients[from].wire.pack(o.msg, from)
                             or Wire.new({ secret = function() end }).pack(o.msg, from)) do
        raid.queue[#raid.queue + 1] = { from = from, dist = o.dist, target = o.target, chunk = chunk }
      end
    end
  end
  function raid.flush()
    while #raid.queue > 0 do
      local m = table.remove(raid.queue, 1)
      for name, c in pairs(raid.clients) do
        local deliver = (m.dist == "RAID" and name ~= m.from) or (m.dist == "WHISPER" and Priority.nameKey(m.target) == Priority.nameKey(name))
        if deliver then
          local msg, trusted, signed = c.wire.unpack(m.from, m.chunk)
          if msg then raid.send(name, c.reg:handle(msg, m.from, trusted, signed)) end
        end
      end
    end
  end
  function raid.act(name, fn, ...)
    local c = raid.clients[name]
    local outs = c.reg[fn](c.reg, ...)
    raid.send(name, outs)
    raid.flush()
    return outs
  end
  -- a /roll line every client sees in system chat
  function raid.roll(player, roll, min, max)
    for name, c in pairs(raid.clients) do raid.send(name, c.reg:roll(player, roll, min or 1, max or 100)) end
    raid.flush()
  end
  return raid
end

describe("Session", function()
  local ns, Codec, priorities, council
  before_each(function()
    ns = H.core()
    Codec = ns.Codec
    priorities = assert(Codec.decode(H.read("fixtures/priority.sample.json")))
    council = { "Poohtank", "Hadur", "Anasazi", "Gally" }
  end)

  local function setup(extra)
    local names = { "Poohtank", "Hadur", "Anasazi", "Gally", "Raider" }
    for _, n in ipairs(extra or {}) do names[#names + 1] = n end
    local raid = newRaid(ns, names, priorities)
    local outs, s = raid.clients.Poohtank.reg:open({
      itemId = 28830, itemName = "Dragonspine Trophy", itemLink = "[Dragonspine Trophy]",
      zone = "Gruul's Lair", boss = "Gruul the Dragonkiller", council = council, rules = priorities.rules,
      priorityVersion = priorities.exportedAt,
    })
    raid.send("Poohtank", outs)
    raid.flush()
    return raid, s.id
  end

  local function sessionOf(raid, name, id) return raid.clients[name].reg:get(id) end

  it("plays the Dragonspine Trophy night end to end and every officer ends with the same record", function()
    local raid, id = setup()
    -- button responses: whispered to the leader, each followed by the client's RandomRoll
    raid.act("Anasazi", "respond", id, "main", "")
    raid.roll("Anasazi", 41)
    raid.act("Gally", "respond", id, "main", "Hyjal DPS check")
    raid.roll("Gally", 97)
    raid.roll("Hadur", 88)                               -- no addon button: plain /roll
    raid.act("Poohtank", "respond", id, "offspec", "ret set")
    raid.roll("Poohtank", 94, 1, 99)
    raid.roll("Anasazi", 99)                             -- second roll: ignored as duplicate
    raid.act("Raider", "respond", id, "pass")

    local lead = sessionOf(raid, "Poohtank", id)
    local r = lead:result()
    assert.are.equal("Anasazi", r.winner.player)
    assert.are.same({ "Anasazi", "Gally", "Hadur", "Poohtank" },
      { r.ranked[1].player, r.ranked[2].player, r.ranked[3].player, r.ranked[4].player })

    raid.clock = raid.clock + 30
    raid.send("Poohtank", raid.clients.Poohtank.reg:tick())
    raid.flush()

    raid.act("Poohtank", "vote", id, "Gally")
    raid.act("Hadur", "vote", id, "Anasazi")
    raid.act("Anasazi", "vote", id, "Hadur")
    raid.act("Anasazi", "vote", id, "Anasazi") -- changes their vote
    raid.act("Gally", "vote", id, "Anasazi")
    raid.act("Raider", "vote", id, "Raider")   -- not council: ignored everywhere
    raid.act("Poohtank", "propose", id, "Gally", "Hyjal DPS check")

    local opts = lead:awardOptions()
    assert.are.equal("Anasazi", opts.votes)
    assert.are.equal(3, opts.voteCount)
    assert.are.equal("Gally", opts.proposal)
    assert.are.equal("Anasazi", opts.list)
    assert.are.equal("Gally", opts.highest)

    raid.act("Poohtank", "award", id, "Anasazi", "votes")
    assert.are.equal("[ToadsLC] [Dragonspine Trophy] awarded to Anasazi (Rogue, tier 1, rolled 41).", lead:awardLine())

    local rec = lead:serialize()
    assert.are.equal("Anasazi", rec.awardedTo)
    assert.are.equal("votes", rec.awardedVia)
    assert.are.equal(Codec.null, rec.override)
    assert.are.equal("priority", rec.computedBy)
    assert.are.equal(1, rec.passes)
    assert.are.equal("duplicate", rec.candidates[5].ignored)
    assert.are.equal("Gally", rec.votes.Poohtank)
    assert.are.equal("Anasazi", rec.votes.Anasazi)
    assert.is_nil(rec.votes.Raider)
    assert.are.same({ by = "Poohtank", player = "Gally", reason = "Hyjal DPS check" }, rec.proposal)

    -- same as the sample document's session, field for field, apart from the timestamps
    local sample = assert(Codec.decode(H.read("fixtures/session.sample.json"))).sessions[1]
    for _, f in ipairs({ "id", "openedAt", "closedAt" }) do rec[f], sample[f] = nil, nil end
    sample.passes = 1
    sample.candidates[5].note = "" -- the addon writes an empty note on every row
    assert.are.equal(Codec.encode(sample, " "), Codec.encode(rec, " "))

    for _, officer in ipairs(council) do
      assert.are.equal(Codec.encode(lead:serialize()), Codec.encode(sessionOf(raid, officer, id):serialize()))
    end
    -- the raider follows the award but never sees responses, notes or votes
    local seen = sessionOf(raid, "Raider", id)
    assert.are.equal("Anasazi", seen.awardedTo)
    assert.are.equal(0, #seen.candidates)
    assert.is_nil(next(seen.votes))
    assert.is_nil(seen.proposal)
  end)

  it("If the session leader awards someone other than the computed winner, then the addon shall record it as an override with the reason given", function()
    local raid, id = setup()
    raid.roll("Anasazi", 41)
    raid.act("Gally", "respond", id, "main", "Hyjal DPS check")
    raid.roll("Gally", 97)
    raid.act("Poohtank", "propose", id, "Gally", "Hyjal DPS check")
    raid.act("Poohtank", "award", id, "Gally", "proposal", "Hyjal DPS check")
    local rec = sessionOf(raid, "Hadur", id):serialize()
    assert.are.equal("Anasazi", rec.computedWinner)
    assert.are.equal("Gally", rec.awardedTo)
    assert.are.equal("proposal", rec.awardedVia)
    assert.are.same({ by = "Poohtank", reason = "Hyjal DPS check" }, rec.override)
  end)

  it("When every response is off-spec, waits for the council and records highest-roll when the LC picks by roll", function()
    local raid, id = setup()
    raid.roll("Gally", 12, 1, 99)
    raid.roll("Poohtank", 94, 1, 99)
    raid.act("Poohtank", "close", id)
    local lead = sessionOf(raid, "Poohtank", id)
    local opts = lead:awardOptions()
    assert.are.equal("Gally", opts.listPriority)
    assert.are.equal("Poohtank", opts.listRoll)
    assert.is_nil(opts.list)
    assert.matches("only off%-spec rolls", lead:resultLine())
    raid.act("Poohtank", "award", id, "Poohtank", "highest-roll")
    local rec = lead:serialize()
    assert.are.equal("highest-roll", rec.computedBy)
    assert.are.equal("Poohtank", rec.computedWinner)
    assert.are.equal(Codec.null, rec.override)
  end)

  it("ignores rolls outside 1-100/1-99 and keeps them grey in the record", function()
    local raid, id = setup()
    raid.roll("Gally", 400, 1, 1000)
    raid.roll("Gally", 97)
    local rec = sessionOf(raid, "Poohtank", id):serialize()
    assert.are.equal("out-of-range", rec.candidates[1].ignored)
    assert.is_nil(rec.candidates[2].ignored)
  end)

  it("re-rolls a tie on tier and roll among the tied names only", function()
    local raid, id = setup()
    raid.roll("Anasazi", 50)
    raid.roll("Hunt", 50) -- not in members[]: class unknown, so not tier 1
    raid.act("Poohtank", "setSpec", id, "Hunt", "Hunter:BeastMastery")
    raid.act("Poohtank", "close", id)
    local lead = sessionOf(raid, "Poohtank", id)
    assert.is_true(lead:result().tie)
    raid.act("Poohtank", "reroll", id)
    raid.roll("Gally", 100)   -- not tied: ignored
    raid.roll("Hunt", 7)
    raid.roll("Anasazi", 62)
    raid.clock = raid.clock + 15
    raid.send("Poohtank", raid.clients.Poohtank.reg:tick())
    raid.flush()
    assert.are.equal("Anasazi", lead.computedWinner)
    local rec = sessionOf(raid, "Gally", id):serialize()
    assert.are.equal("rerolled", rec.candidates[1].ignored)
    assert.are.equal(4, #rec.candidates)
  end)

  it("records nobody rolling as awardedTo null with computedBy none", function()
    local raid, id = setup()
    raid.act("Poohtank", "close", id)
    local lead = sessionOf(raid, "Poohtank", id)
    assert.are.equal("[ToadsLC] Dragonspine Trophy: No rolls.", lead:resultLine())
    raid.act("Poohtank", "award", id, nil, nil)
    local rec = lead:serialize()
    assert.are.equal(Codec.null, rec.awardedTo)
    assert.are.equal("none", rec.computedBy)
    local doc = { format = "toads-loot-session", version = 1, exportedAt = "x", exportedBy = "Poohtank",
                  addonVersion = "0.1.0", priorityVersion = Codec.null, sessions = { rec } }
    assert.is_true(Codec.validateSession(doc))
  end)

  it("The addon shall let a council member join a session late and receive the current state on request", function()
    local raid, id = setup()
    raid.act("Gally", "respond", id, "main", "Hyjal DPS check")
    raid.roll("Gally", 97)
    raid.roll("Anasazi", 41)
    raid.act("Hadur", "vote", id, "Anasazi")
    raid.act("Poohtank", "propose", id, "Gally", "Hyjal DPS check")
    -- Hadur reloads: their registry starts empty
    local c = raid.clients.Hadur
    c.reg.sessions, c.reg.order = {}, {}
    raid.act("Hadur", "requestState")
    local lead, late = sessionOf(raid, "Poohtank", id), sessionOf(raid, "Hadur", id)
    assert.is_not_nil(late)
    assert.are.equal(Codec.encode(lead:serialize()), Codec.encode(late:serialize()))
    assert.are.equal(lead:timeLeft(raid.clock), late:timeLeft(raid.clock))
    -- and keeps following
    raid.act("Gally", "vote", id, "Gally")
    assert.are.equal(Codec.encode(lead:serialize()), Codec.encode(late:serialize()))
  end)

  it("undoes an award and lets the leader award again", function()
    local raid, id = setup()
    raid.roll("Anasazi", 41)
    raid.act("Poohtank", "award", id, "Anasazi", "list")
    raid.act("Poohtank", "unaward", id)
    local s = sessionOf(raid, "Gally", id)
    assert.are.equal("voting", s.phase)
    assert.is_nil(s.awardedTo)
    raid.act("Poohtank", "award", id, nil, "list")
    assert.are.equal("Anasazi", s.awardedTo)
  end)

  it("announces a plain /tlc roll result in one line", function()
    local raid = newRaid(ns, { "Poohtank" }, priorities)
    local reg = raid.clients.Poohtank.reg
    local _, s = reg:open({ itemId = 28830, itemName = "Dragonspine Trophy", itemLink = "[Dragonspine Trophy]",
                            mode = "roll", council = {}, rules = priorities.rules })
    assert.are.equal("[ToadsLC] Roll: [Dragonspine Trophy] (30 s). /roll MS, /roll 99 OS. Priority: BM Hunter = Rogue > Fury > Arms > Enhance = Ret > Surv Hunter > Kitty.", s:openLine())
    reg:roll("Anasazi", 41, 1, 100)
    reg:roll("Gally", 97, 1, 100)
    reg:roll("Hadur", 88, 1, 100)
    reg:roll("Poohtank", 94, 1, 99)
    reg:close(s.id)
    assert.are.equal("[ToadsLC] Dragonspine Trophy: Anasazi wins (Rogue, tier 1, rolled 41). Gally 97 (Fury, tier 2), Hadur 88 (Enhance, tier 4), Poohtank 94 (off-spec).", s:resultLine())
  end)
end)

describe("Session hardening", function()
  local ns, Codec, priorities
  before_each(function()
    ns = H.core()
    Codec = ns.Codec
    priorities = assert(Codec.decode(H.read("fixtures/priority.sample.json")))
  end)

  local function setup()
    local raid = newRaid(ns, { "Poohtank", "Hadur", "Anasazi", "Gally", "Raider" }, priorities)
    local outs, s = raid.clients.Poohtank.reg:open({
      itemId = 28830, itemName = "Dragonspine Trophy", council = { "Poohtank", "Hadur", "Anasazi", "Gally" },
      rules = priorities.rules,
    })
    raid.send("Poohtank", outs)
    raid.flush()
    return raid, s.id
  end

  it("ignores a STATE from anyone but the session's own leader", function()
    local raid, id = setup()
    local forged = raid.clients.Poohtank.reg:get(id):stateMsg(raid.clock)
    forged.o.leader = "Raider"
    raid.send("Raider", { { msg = forged, dist = "RAID" } })
    raid.flush()
    assert.are.equal("Poohtank", raid.clients.Hadur.reg:get(id).leader)
  end)

  it("ignores a STATE older than what the officer already has", function()
    local raid, id = setup()
    raid.roll("Anasazi", 41)
    local old = raid.clients.Poohtank.reg:get(id):stateMsg(raid.clock)
    raid.act("Poohtank", "award", id, "Anasazi", "list")
    raid.send("Poohtank", { { msg = old, dist = "WHISPER", target = "Hadur" } })
    raid.flush()
    assert.are.equal("Anasazi", raid.clients.Hadur.reg:get(id).awardedTo)
  end)

  it("asks the leader for a snapshot when an update arrives for a session it never saw", function()
    local raid, id = setup()
    local c = raid.clients.Gally
    c.reg.sessions, c.reg.order = {}, {}
    raid.roll("Anasazi", 41) -- the leader's RESPONSE broadcast reaches Gally, who asks for STATE
    assert.is_not_nil(c.reg:get(id))
    assert.are.equal(1, #c.reg:get(id).candidates)
  end)

  it("takes class and spec from the leader's roster, not the raider's claim", function()
    local raid, id = setup()
    raid.send("Gally", { { msg = { t = "RSP", s = id, r = "main", n = "", c = "Rogue", sp = "Rogue:Combat" },
                           dist = "WHISPER", target = "Poohtank" } })
    raid.flush()
    local e = raid.clients.Poohtank.reg:get(id):entryFor("Gally")
    assert.are.equal("Warrior", e.class)
    assert.are.equal("Warrior:Fury", e.spec)
    -- unknown to the roster: a claimed spec is only taken when it fits the class
    raid.send("Hunt", { { msg = { t = "RSP", s = id, r = "main", c = "Hunter", sp = "Rogue:Combat" },
                          dist = "WHISPER", target = "Poohtank" } })
    raid.flush()
    assert.is_nil(raid.clients.Poohtank.reg:get(id):entryFor("Hunt").spec)
  end)

  it("drops malformed messages without throwing", function()
    local raid = setup()
    local reg = raid.clients.Hadur.reg
    for _, m in ipairs({
      { t = "SESSION_OPEN", s = "x", nm = "Item", co = {}, sec = "30" },
      { t = "SESSION_OPEN", s = "x", nm = "Item", co = {}, sec = 30, ru = { offspecRollMax = "99" } },
      { t = "RESPONSE", s = "x", p = 5, r = "main" },
      { t = "VOTE", s = {}, p = "Gally" },
      { t = "STATE", s = "x", o = { leader = "Poohtank" }, oa = 1, ph = "open" },
      { t = "NOPE" }, "string", 42,
    }) do
      assert.has_no.errors(function() reg:handle(m, "Poohtank") end)
    end
    assert.is_nil(reg:get("x"))
    assert.is_nil((Codec.decode("[1e999]")))
  end)

  it("does not let the list pick a tied winner by name", function()
    local raid, id = setup()
    raid.roll("Anasazi", 50)
    raid.roll("Gally", 50)
    raid.act("Poohtank", "setSpec", id, "Gally", "Warrior:Fury")
    local s = raid.clients.Poohtank.reg:get(id)
    s.item = { priority = { { { spec = "Rogue:*" }, { spec = "Warrior:*" } } } }
    raid.act("Poohtank", "close", id)
    assert.is_nil(s.computedWinner)
    local opts = s:awardOptions()
    assert.is_nil(opts.list)
    assert.are.same({ "Anasazi", "Gally" }, opts.tied)
  end)

  it("restores the computed winner when an all-off-spec highest-roll award is undone", function()
    local raid, id = setup()
    raid.roll("Gally", 12, 1, 99)
    raid.roll("Poohtank", 94, 1, 99)
    raid.act("Poohtank", "award", id, "Poohtank", "highest-roll")
    raid.act("Poohtank", "unaward", id)
    raid.act("Poohtank", "award", id, "Gally", "list")
    local rec = raid.clients.Hadur.reg:get(id):serialize()
    assert.are.equal("Gally", rec.computedWinner)
    assert.are.equal("priority", rec.computedBy)
    assert.are.equal(Codec.null, rec.override)
  end)

  it("lets a leader pick a session back up after a reload", function()
    local raid, id = setup()
    raid.roll("Anasazi", 41)
    local c = raid.clients.Poohtank
    local saved = c.reg:get(id):stateMsg(raid.clock)
    saved = assert(Codec.decode(Codec.encode(saved))) -- through SavedVariables as JSON
    c.reg.sessions, c.reg.order = {}, {}
    raid.clock = raid.clock + 40
    local s = c.reg:restore(saved, raid.clock - 40)
    assert.are.equal(1, #s.candidates)
    raid.send("Poohtank", c.reg:tick())
    raid.flush()
    assert.are.equal("Anasazi", s.computedWinner)
    assert.are.equal("Anasazi", raid.clients.Hadur.reg:get(id).computedWinner)
  end)
end)

describe("Resolver ties in highest-roll mode", function()
  it("flags a top-roll tie across tiers and not a priority tie below the top roll", function()
    local ns = H.core()
    local item = { priority = { { { spec = "Rogue:*" } }, { { spec = "Warrior:*" } } } }
    local rules = { allOffspecMode = "highest" }
    local function e(p, c, roll) return { player = p, class = c, roll = roll, max = 99 } end
    local r = ns.Resolver.resolve(item, { e("A", "Rogue", 80), e("B", "Warrior", 80), e("C", "Mage", 10) }, rules)
    assert.is_true(r.tie)
    assert.are.same({ "A", "B" }, r.tied)
    r = ns.Resolver.resolve(item, { e("A", "Rogue", 20), e("B", "Rogue", 20), e("C", "Mage", 90) }, rules)
    assert.is_false(r.tie)
    assert.are.equal("C", r.winner.player)
  end)
end)

describe("Session with a raid password", function()
  local ns, Codec, priorities, council
  before_each(function()
    ns = H.core()
    Codec = ns.Codec
    priorities = assert(Codec.decode(H.read("fixtures/priority.sample.json")))
    council = { "Poohtank", "Hadur", "Anasazi", "Gally" }
  end)

  local function setup(secrets)
    local raid = newRaid(ns, { "Poohtank", "Hadur", "Anasazi", "Gally", "Raider" }, priorities, secrets)
    local outs, s = raid.clients.Poohtank.reg:open({
      itemId = 28830, itemName = "Dragonspine Trophy", council = council, rules = priorities.rules,
    })
    raid.send("Poohtank", outs)
    raid.flush()
    return raid, s.id
  end

  local function keyed(names, password)
    local secret = ns.Wire.secret(ns.Wire.keyFromPassword(password, 10))
    local out = {}
    for _, n in ipairs(names) do out[n] = secret end
    return out
  end

  it("runs the whole session when every officer joined with the same password", function()
    local raid, id = setup(keyed(council, "frog-pond-42"))
    raid.act("Gally", "respond", id, "main", "Hyjal DPS check")
    raid.roll("Gally", 97)
    raid.roll("Anasazi", 41)
    raid.act("Hadur", "vote", id, "Anasazi")
    raid.act("Poohtank", "propose", id, "Gally", "Hyjal DPS check")
    raid.act("Poohtank", "award", id, "Anasazi", "votes")
    local lead = raid.clients.Poohtank.reg:get(id)
    for _, officer in ipairs(council) do
      assert.are.equal(Codec.encode(lead:serialize()), Codec.encode(raid.clients[officer].reg:get(id):serialize()))
    end
    assert.are.equal("Gally", lead:entryFor("Gally").player)
    assert.are.equal("Hyjal DPS check", lead:entryFor("Gally").note)
    assert.are.equal("Anasazi", raid.clients.Raider.reg:get(id).awardedTo) -- raiders still see the award
  end)

  it("ignores votes and proposals from anyone without the password", function()
    local secrets = keyed(council, "frog-pond-42")
    secrets.Gally = nil -- Gally typed nothing
    local raid, id = setup(secrets)
    raid.roll("Anasazi", 41)
    raid.act("Gally", "vote", id, "Anasazi")
    raid.send("Raider", { { msg = { t = "VOTE", s = id, p = "Raider" }, dist = "RAID" } })
    raid.send("Raider", { { msg = { t = "PROPOSE", s = id, p = "Raider", re = "trust me" }, dist = "RAID" } })
    raid.flush()
    local s = raid.clients.Hadur.reg:get(id)
    assert.is_nil(next(s.votes))
    assert.is_nil(s.proposal)
  end)

  it("keeps an officer with the wrong password out of council traffic", function()
    local secrets = keyed(council, "frog-pond-42")
    secrets.Gally = ns.Wire.secret(ns.Wire.keyFromPassword("typo", 10))
    local raid, id = setup(secrets)
    raid.act("Anasazi", "respond", id, "main", "secret note")
    raid.roll("Anasazi", 41)
    local s = raid.clients.Gally.reg:get(id)
    assert.are.equal(0, #s.council) -- a viewer, like a raider
    assert.are.equal(0, #s.candidates)
  end)

  local function listen(raid)
    local heard = {}
    for name, c in pairs(raid.clients) do
      c.reg.ctx.hosting = function() return name == "Poohtank" end
      c.reg.ctx.notify = function(kind, who) heard[#heard + 1] = name .. ":" .. kind .. ":" .. (who or "") end
    end
    return heard
  end

  it("answers HELLO with WELCOME for the same password and tells both sides about a mismatch", function()
    local secrets = keyed({ "Poohtank", "Hadur" }, "frog-pond-42")
    secrets.Gally = ns.Wire.secret(ns.Wire.keyFromPassword("typo", 10))
    local raid = newRaid(ns, { "Poohtank", "Hadur", "Gally" }, priorities, secrets)
    local heard = listen(raid)
    raid.act("Hadur", "hello")
    raid.act("Gally", "hello")
    raid.act("Gally", "hello") -- told once a minute at most
    table.sort(heard)
    assert.are.same({ "Gally:mismatch_self:Poohtank", "Hadur:welcome:Poohtank", "Poohtank:mismatch:Gally" }, heard)
  end)

  it("says so when no raid leader answers /tlc join", function()
    local raid = newRaid(ns, { "Poohtank", "Gally" }, priorities, keyed({ "Gally" }, "frog-pond-42"))
    local heard = listen(raid)
    raid.clients.Poohtank.reg.ctx.hosting = function() return false end
    raid.act("Gally", "hello")
    raid.clock = raid.clock + 10
    raid.act("Gally", "tick")
    assert.are.same({ "Gally:noanswer:" }, heard)
  end)

  it("ignores a WELCOME it did not ask for", function()
    local raid = newRaid(ns, { "Poohtank", "Gally" }, priorities, keyed({ "Poohtank" }, "frog-pond-42"))
    local heard = listen(raid)
    raid.send("Poohtank", { { msg = { t = "WELCOME" }, dist = "WHISPER", target = "Gally" } })
    raid.send("Raider", { { msg = { t = "WELCOME" }, dist = "WHISPER", target = "Poohtank" } })
    raid.flush()
    assert.are.same({}, heard)
  end)

  it("lets an officer who joins late with the right password into a session they saw as a viewer", function()
    local secrets = keyed(council, "frog-pond-42")
    local key = secrets.Gally
    secrets.Gally = nil
    local raid, id = setup(secrets)
    local heard = listen(raid)
    raid.act("Anasazi", "respond", id, "main", "secret note")
    raid.act("Hadur", "vote", id, "Anasazi")
    assert.are.equal(0, #raid.clients.Gally.reg:get(id).council)
    raid.clients.Gally.secret = key
    raid.act("Gally", "hello")
    local s = raid.clients.Gally.reg:get(id)
    assert.is_true(s:isCouncil("Gally"))
    assert.are.equal("secret note", s:entryFor("Anasazi").note)
    assert.are.equal("Anasazi", s.votes.hadur)
    assert.are.same({ "Gally:welcome:Poohtank" }, heard)
  end)

  it("tells an officer without the password to /tlc join when a protected session opens", function()
    local secrets = keyed(council, "frog-pond-42")
    secrets.Gally = nil
    local raid = newRaid(ns, { "Poohtank", "Gally", "Raider" }, priorities, secrets)
    local heard = listen(raid)
    raid.act("Poohtank", "open", { itemId = 28830, itemName = "Dragonspine Trophy", council = council })
    assert.are.same({ "Gally:needjoin:Poohtank" }, heard) -- not the raider, who is not on the council
  end)

  it("tells the leader when a council member votes without the password", function()
    local secrets = keyed(council, "frog-pond-42")
    secrets.Gally = nil
    local raid, id = setup(secrets)
    local heard = listen(raid)
    raid.roll("Anasazi", 41)
    raid.send("Gally", { { msg = { t = "VOTE", s = id, p = "Anasazi", q = 1 }, dist = "RAID" } })
    raid.flush()
    table.sort(heard)
    assert.are.same({ "Poohtank:untrusted:Gally" }, heard)
  end)

  it("does not let an old vote replace the one a snapshot carried", function()
    local raid, id = setup(keyed(council, "frog-pond-42"))
    raid.roll("Anasazi", 41)
    raid.roll("Gally", 97)
    local first = raid.act("Hadur", "vote", id, "Anasazi")
    raid.act("Hadur", "vote", id, "Gally")
    local c = raid.clients.Anasazi
    c.reg.sessions, c.reg.order = {}, {}
    raid.act("Anasazi", "requestState")
    raid.send("Hadur", first) -- the older vote arrives late
    raid.flush()
    assert.are.equal("Gally", c.reg:get(id).votes.hadur)
  end)

  it("does not send a leader action it rejects, so no version is used up", function()
    local raid, id = setup(keyed(council, "frog-pond-42"))
    local lead = raid.clients.Poohtank.reg:get(id)
    local v = lead.version or 0
    assert.are.same({}, raid.act("Poohtank", "vote", id, "Nobody"))
    assert.are.equal(v, lead.version or 0)
    raid.roll("Anasazi", 41)
    raid.act("Poohtank", "close", id)
    assert.are.equal("voting", raid.clients.Hadur.reg:get(id).phase)
  end)

  it("ignores a replayed leader message", function()
    local raid, id = setup(keyed(council, "frog-pond-42"))
    raid.roll("Anasazi", 41)
    raid.roll("Gally", 97)
    local outs = raid.act("Poohtank", "award", id, "Anasazi", "list")
    raid.act("Poohtank", "unaward", id)
    raid.send("Poohtank", { outs[#outs] }) -- the same signed AWARD again
    raid.flush()
    assert.is_nil(raid.clients.Hadur.reg:get(id).awardedTo)
  end)
end)
