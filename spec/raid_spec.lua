-- A raid night with several clients running the addon side by side: the leader, an
-- officer and raiders, talking over addon messages as they do in game.
local H = require("spec.helper")
local W = require("spec.wow_mock")

local sample = H.read("fixtures/priority.sample.json")
local DST = "|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r"

local function latest(c) return c.ns.App.registry:latest() end

-- the sample list's council is Poohtank, Hadur, Anasazi and Gally; Croaker is only a raider
local GROUP = {
  { name = "Poohtank", class = "PALADIN", leader = true },
  { name = "Anasazi", class = "ROGUE" }, { name = "Gally", class = "WARRIOR" },
  { name = "Hadur", class = "SHAMAN", assist = true }, { name = "Croaker", class = "HUNTER" },
}

-- the sample list without its members[], so specs come from talents and inspects only
local function withoutMembers(c)
  local d = c.ns.Codec.decode(sample)
  d.members = nil
  return c.ns.Codec.encode(d)
end

describe("a raid of clients", function()
  local leader, officer, rogue, warrior, hunter, all

  before_each(function()
    leader = W.client({ me = "Poohtank", group = GROUP })
    officer = W.client({ me = "Hadur", group = GROUP })
    rogue = W.client({ me = "Anasazi", group = GROUP })
    warrior = W.client({ me = "Gally", group = GROUP })
    hunter = W.client({ me = "Croaker", group = GROUP })
    all = { leader, officer, rogue, warrior, hunter }
    for _, c in ipairs(all) do c.ns.App.import(sample) end
    W.deliver(all) -- the login state requests
  end)

  local function rollOnLeader(line) leader:fire("CHAT_MSG_SYSTEM", line) end

  it("gives a 10 second last call when the council closes early, and closes on a second press", function()
    leader:slash("session " .. DST .. " 60")
    W.deliver(all)
    local s = latest(leader)
    leader:slash("close")
    W.deliver(all)
    assert.matches("Last call for .*Dragonspine Trophy.*10 s left", leader:chatText())
    assert.are.equal("open", s.phase)
    assert.are.equal(10, s:timeLeft(leader.time))
    assert.are.equal(10, latest(hunter):timeLeft(hunter.time)) -- raiders' countdowns jump too
    W.tickAll(all, 9)
    W.deliver(all)
    assert.are.equal("open", s.phase)
    W.tickAll(all, 1)
    W.deliver(all)
    assert.are.equal("voting", s.phase)
    assert.are.equal("voting", latest(officer).phase)

    leader:slash("session " .. DST .. " 60")
    W.deliver(all)
    local again = latest(leader)
    leader:slash("close")
    leader:slash("close") -- during the last call: now
    assert.are.equal("voting", again.phase)
  end)

  it("closes an item as soon as everyone in the group has answered", function()
    leader:slash("session " .. DST .. " 60")
    W.deliver(all)
    local s = latest(leader)
    for _, c in ipairs({ leader, officer, warrior, hunter }) do c.ns.App.respond(s.id, "pass") end
    W.deliver(all)
    W.tickAll(all, 0)
    assert.are.equal("open", s.phase) -- the rogue hasn't answered
    rogue.ns.App.respond(s.id, "main")
    W.deliver(all)
    rollOnLeader("Anasazi rolls 42 (1-100)")
    W.deliver(all)
    W.tickAll(all, 0)
    W.deliver(all)
    assert.are.equal("voting", s.phase)
    assert.are.equal("Anasazi", s.computedWinner) -- the list's pick goes to the council
  end)

  it("carries a council session from open to award across every client", function()
    leader:slash("session " .. DST .. " 30")
    W.deliver(all)
    local s = latest(leader)
    for _, c in ipairs({ officer, rogue, warrior, hunter }) do
      local mine = latest(c)
      assert.is_truthy(mine, c.me .. " never saw the session")
      assert.are.equal(s.id, mine.id)
      assert.is_true(c.env.ToadsLCCandidateFrame:IsShown())
    end
    local cand = rogue.env.ToadsLCCandidateFrame
    local row = cand.rows[1]
    assert.are.same({ "BiS", "Main", "OS", "Pass" },
                    { row.bis:GetText(), row.up:GetText(), row.off:GetText(), row.pass:GetText() })

    rogue.ns.App.respond(s.id, "main", "BiS for me")
    warrior.ns.App.respond(s.id, "main")
    assert.are.same({}, rogue.rolls) -- no rolls: the council votes
    W.deliver(all)
    rollOnLeader("Gally rolls 97 (1-100)") -- a /roll counts for nothing
    W.deliver(all)
    W.tickAll(all, 31)
    W.deliver(all)
    assert.are.equal("voting", s.phase)
    assert.are.equal("Anasazi", s.computedWinner) -- tier 1 rogue ranks above the tier 2 warrior

    local seen = latest(officer)
    assert.are.equal("voting", seen.phase)
    local note
    for _, e in ipairs(seen.candidates) do if e.player == "Anasazi" then note = e.note end end
    assert.are.equal("BiS for me", note) -- the officer sees the raider's note
    officer.ns.App.vote(s.id, "Anasazi")
    W.deliver(all)
    assert.are.equal("Anasazi", s.votes.hadur)

    leader:slash("award")
    W.deliver(all)
    for _, c in ipairs(all) do
      assert.are.equal("done", latest(c).phase, c.me)
      assert.are.equal("Anasazi", latest(c).awardedTo, c.me)
    end
    assert.matches("Anasazi", leader.chat[#leader.chat - 1].text)
    assert.are.equal("Anasazi", leader.chat[#leader.chat].target) -- and the winner is whispered
    assert.are.equal(1, #leader.ns.Store.records(false)) -- only the leader keeps the record
    assert.are.equal(0, #officer.ns.Store.records(false))
  end)

  it("lets an officer who joins late catch up from the leader's state", function()
    leader:slash("session " .. DST .. " 30")
    W.deliver({ leader, rogue })
    rogue.ns.App.respond(latest(leader).id, "main")
    W.deliver({ leader, rogue })
    assert.is_nil(latest(officer))
    officer.ns.App.askState()
    for _, fn in ipairs(officer.later) do fn() end
    W.deliver(all)
    local seen = latest(officer)
    assert.is_truthy(seen)
    assert.are.equal(1, #seen.candidates)
    assert.are.equal("Anasazi", seen.candidates[1].player)
  end)

  it("ignores votes from a raider who is not on the council", function()
    leader:slash("session " .. DST .. " 30")
    W.deliver(all)
    local s = latest(leader)
    W.tickAll(all, 31)
    W.deliver(all)
    hunter.ns.App.vote(s.id, "Croaker")
    W.deliver(all)
    assert.is_nil(s.votes.croaker)
  end)

  describe("with a raid password", function()
    it("welcomes an officer with the same password and keeps council traffic sealed", function()
      leader:slash("begin frog pond 42")
      officer:slash("join frog pond 42")
      W.deliver(all)
      assert.matches("matches Poohtank's", officer:printedText())
      assert.are.equal(leader.ns.App.secret().fingerprint, officer.ns.App.secret().fingerprint)

      leader:slash("session " .. DST .. " 30")
      W.deliver(all)
      local s = latest(leader)
      assert.is_truthy(latest(rogue), "a raider without the password still gets the loot frame")
      assert.is_true(rogue.env.ToadsLCCandidateFrame:IsShown())

      -- a raider has no password, so their note goes as a whisper to the leader only
      hunter.ns.App.respond(s.id, "main", "secret note")
      local found = false
      for _, d in ipairs(W.deliver(all)) do
        if d.from == hunter then assert.are.same({ "WHISPER", "Poohtank" }, { d.msg.dist, d.msg.target })
        else -- the leader passes it on to the council sealed
          assert.is_nil(d.msg.text:find("secret note", 1, true), "a note crossed the wire in clear text")
          if d.msg.text:find("T1|e|", 1, true) then found = true end
        end
      end
      W.tickAll(all, 31)
      for _, d in ipairs(W.deliver(all)) do -- the leader passes it on to the council sealed
        assert.is_nil(d.msg.text:find("secret note", 1, true), "a note crossed the wire in clear text")
        if d.msg.text:find("T1|e|", 1, true) then found = true end
      end
      assert.is_true(found, "nothing was sent encrypted")
      assert.are.equal("secret note", latest(officer).candidates[1].note)
      -- the raiders saw sealed traffic all along, and are not told it is someone else's password
      assert.is_nil(hunter:printedText():find("different raid password", 1, true))
      officer.ns.App.vote(s.id, "Croaker")
      W.deliver(all)
      assert.are.equal("Croaker", s.votes.hadur)
    end)

    it("tells both sides when an officer's password is wrong, and ignores their votes", function()
      leader:slash("begin frog pond 42")
      officer:slash("join toad pond 42")
      W.deliver(all)
      assert.matches("doesn't match Poohtank's", officer:printedText())
      assert.matches("Hadur tried to join with a different raid password", leader:printedText())

      leader:slash("session " .. DST .. " 30")
      W.deliver(all)
      local s = latest(leader)
      W.tickAll(all, 31)
      W.deliver(all)
      officer.ns.App.vote(s.id, "Anasazi")
      W.deliver(all)
      assert.is_nil(s.votes.hadur)
    end)
  end)
end)

describe("a raid night run the 0.3 way", function()
  -- Poohtank begins the raid; Hadur and Croaker join with the password (Croaker is not on the
  -- priority list's council[]); Anasazi and Gally are raiders without it
  local GRUUL = "Creature-0-1-565-1-19044-1"
  local leader, officer, joiner, rogue, warrior, all
  local function sessionOn(c, id) return c.ns.App.registry:get(id) end

  before_each(function()
    leader = W.client({ me = "Poohtank", group = GROUP })
    officer = W.client({ me = "Hadur", group = GROUP })
    joiner = W.client({ me = "Croaker", group = GROUP })
    rogue = W.client({ me = "Anasazi", group = GROUP })
    warrior = W.client({ me = "Gally", group = GROUP })
    all = { leader, officer, joiner, rogue, warrior }
    for _, c in ipairs(all) do c.ns.App.import(sample) end
    W.deliver(all)
    leader:slash("begin frog pond 42")
    officer:slash("join frog pond 42")
    W.deliver(all)
  end)

  local function croakerJoins()
    joiner:slash("join frog pond 42")
    W.deliver(all)
  end

  it("opens each drop for answers as it's looted, and every officer who joined sees the answers and votes", function()
    croakerJoins()
    leader:loot({ { 28830, "Dragonspine Trophy", 4, GRUUL } })
    W.deliver(all)
    local s = latest(leader)
    assert.is_truthy(s, "the drop opened for answers")
    assert.is_true(s.untimed)
    assert.matches("Open for answers: .*Dragonspine Trophy", leader:chatText())
    assert.are.equal("open", leader.ns.Loot.list.entries[1].status)
    -- Croaker joined with the password, so they are on this item's council, list or no list
    assert.is_true(sessionOn(joiner, s.id):isCouncil("Croaker"))
    assert.is_true(s:isCouncil("Croaker"))

    rogue.ns.App.respond(s.id, "main")
    warrior.ns.App.respond(s.id, "pass")
    W.deliver(all)
    for _, c in ipairs({ officer, joiner }) do
      local mine = sessionOn(c, s.id)
      assert.are.equal("main", mine:entryFor("Anasazi").response, c.me)
      assert.is_true(mine.passed.gally, c.me) -- a pass reaches every officer: not "still to answer"
    end

    joiner.ns.App.vote(s.id, "Anasazi")
    joiner.ns.App.propose(s.id, "Anasazi", "needs it most")
    W.deliver(all)
    assert.are.equal("Anasazi", s.votes.croaker) -- counted by the leader
    assert.are.equal("Anasazi", sessionOn(officer, s.id).votes.croaker) -- and seen by the other officer
    assert.are.equal("Croaker", sessionOn(officer, s.id).proposal.by)
    assert.are.equal("Anasazi", s.proposal.player)
  end)

  it("lets only the raid leader who began the raid open and award loot", function()
    _G.UnitIsGroupAssistant = _G.UnitIsGroupAssistant -- Hadur is an assist with the password
    officer:slash("loot add [Dragonspine Trophy]")
    assert.matches("Only the raid leader who began the raid", officer:printedText())
    officer:slash("session " .. DST)
    assert.is_nil(latest(officer))
    leader:slash("session " .. DST .. " 30")
    W.deliver(all)
    local s = latest(leader)
    officer.ns.App.award(s.id, "Hadur")
    W.deliver(all)
    assert.is_nil(s.awardedTo)
    assert.matches("Only the raid leader who opened this item", officer:printedText())
  end)

  it("brings an officer who joins after an item opened onto its council", function()
    leader:slash("session " .. DST .. " 60")
    W.deliver(all)
    local s = latest(leader)
    rogue.ns.App.respond(s.id, "bis")
    W.deliver(all)
    assert.is_false(sessionOn(joiner, s.id):isCouncil("Croaker")) -- only a viewer so far
    croakerJoins()
    local mine = sessionOn(joiner, s.id)
    assert.is_true(mine:isCouncil("Croaker"))
    assert.are.equal("bis", mine:entryFor("Anasazi").response)
    joiner.ns.App.vote(s.id, "Anasazi")
    W.deliver(all)
    assert.are.equal("Anasazi", s.votes.croaker)
  end)

  it("gives a raider who reloads the items still open, and remembers what they answered", function()
    leader:loot({ { 28830, "Dragonspine Trophy", 4, GRUUL } })
    W.deliver(all)
    local s = latest(leader)
    rogue.ns.App.respond(s.id, "bis")
    W.deliver(all)
    -- Anasazi reloads: a fresh client with the same saved variables
    local again = W.client({ me = "Anasazi", group = GROUP, db = rogue.env.ToadsLCDB, charDb = rogue.env.ToadsLCCharDB })
    local clients = { leader, officer, joiner, again, warrior }
    again.ns.App.askState()
    for _, fn in ipairs(again.later) do fn() end
    W.deliver(clients)
    local mine = sessionOn(again, s.id)
    assert.is_truthy(mine, "the open item came back after the reload")
    assert.are.equal("bis", mine.myResponse) -- not asked again
    again.ns.Frames.showCandidate()
    assert.is_false(again.env.ToadsLCCandidateFrame:IsShown()) -- nothing waits for an answer
  end)

  it("waits for the end of the pull before the answer window pops up", function()
    rogue.env.InCombatLockdown = function() return true end
    leader:loot({ { 28830, "Dragonspine Trophy", 4, GRUUL } })
    W.deliver(all)
    local cand = rogue.env.ToadsLCCandidateFrame
    assert.is_falsy(cand and cand:IsShown())
    rogue.env.InCombatLockdown = function() return false end
    rogue:fire("PLAYER_REGEN_ENABLED")
    assert.is_true(rogue.env.ToadsLCCandidateFrame:IsShown())
  end)

  it("shows who an item was awarded to on its tooltip, and the council's votes while it's open", function()
    croakerJoins()
    leader:slash("session " .. DST .. " 30")
    W.deliver(all)
    local s = latest(leader)
    rogue.ns.App.respond(s.id, "main")
    W.deliver(all)
    officer.ns.App.vote(s.id, "Anasazi")
    W.deliver(all)
    local lines = table.concat(joiner.ns.Tooltip.tonight(28830), "\n")
    assert.matches("votes: Anasazi 1 %(Hadur%)", lines)
    assert.are.same({}, warrior.ns.Tooltip.tonight(28830)) -- raiders don't see the council's votes
    leader:slash("award Anasazi")
    W.deliver(all)
    for _, c in ipairs({ leader, officer, rogue, warrior }) do
      assert.matches("Awarded tonight to Anasazi", table.concat(c.ns.Tooltip.tonight(28830), "\n"), c.me)
    end
  end)
end)

describe("Roster", function()
  it("reads the player's own spec from talents", function()
    local c = W.client({ me = "Gally", group = {
      { name = "Poohtank", class = "PALADIN", leader = true },
      { name = "Gally", class = "WARRIOR", talents = { 17, 44, 0 } },
    } })
    assert.are.same({ class = "Warrior", spec = "Warrior:Fury" }, c.ns.Roster.who("Gally"))
  end)

  it("leaves a feral druid's spec open rather than guessing bear or cat", function()
    local c = W.client({ me = "Moonfrog", group = {
      { name = "Poohtank", class = "PALADIN", leader = true },
      { name = "Moonfrog", class = "DRUID", talents = { 0, 41, 20 } },
    } })
    assert.is_nil(c.ns.Roster.who("Moonfrog").spec)
    assert.are.equal("Druid", c.ns.Roster.who("Moonfrog").class)
  end)

  it("inspects a raider who rolled without the addon, one at a time, and keeps the spec", function()
    local c = W.client({ me = "Poohtank", canInspect = true, group = {
      { name = "Poohtank", class = "PALADIN", leader = true },
      { name = "Anasazi", class = "ROGUE", talents = { 15, 41, 5 } },
      { name = "Gally", class = "WARRIOR", talents = { 0, 0, 0 } },
    } })
    c.ns.App.import(withoutMembers(c))
    c:slash("roll " .. DST)
    c:fire("CHAT_MSG_SYSTEM", "Anasazi rolls 41 (1-100)")
    c:fire("CHAT_MSG_SYSTEM", "Gally rolls 97 (1-100)")
    local function update(dt) for f in pairs(c.eventFrames) do
      if f.events.INSPECT_READY and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
    end end
    update(2)
    assert.are.same({ "raid2" }, c.inspects)
    update(2)
    assert.are.equal(1, #c.inspects, "waits for the answer before the next inspect")
    c:fire("INSPECT_READY", "Player-Someone") -- someone else's inspect: not ours
    assert.is_nil(c.ns.Roster.who("Anasazi").spec)
    c:fire("INSPECT_READY", "Player-Anasazi")
    assert.are.equal("Rogue:Combat", c.ns.Roster.who("Anasazi").spec)
    update(2)
    assert.are.same({ "raid2", "raid3" }, c.inspects)
    c:fire("INSPECT_READY", "Player-Gally")
    assert.is_nil(c.ns.Roster.who("Gally").spec) -- no talents spent: still unknown
  end)

  it("takes the spec from the imported members[] when talents cannot tell", function()
    local c = W.client({ me = "Poohtank" })
    c.ns.App.import(withoutMembers(c))
    assert.is_nil(c.ns.Roster.who("Anasazi").spec)
    c.ns.App.import(sample)
    assert.are.equal("Rogue:Combat", c.ns.Roster.who("Anasazi").spec)
  end)
end)
