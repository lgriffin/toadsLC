-- The raid's loot list: drops recorded as the raid loots and moves on, started later by the
-- leader, followed to the award, and shared with the officers.
local H = require("spec.helper")
local W = require("spec.wow_mock")

local sample = H.read("fixtures/priority.sample.json")
local GRUUL = "Creature-0-1-565-1-19044-1"
local MAG = "Creature-0-1-544-1-17257-1"

-- a Gruul corpse: Dragonspine Trophy, two of the same token, a blue and a Badge of Justice
local CORPSE = {
  { 28830, "Dragonspine Trophy", 4, GRUUL },
  { 29765, "Leggings of the Fallen Hero", 4, GRUUL },
  { 29765, "Leggings of the Fallen Hero", 4, GRUUL },
  { 28795, "Bladespire Warbands", 3, GRUUL },
  { 29434, "Badge of Justice", 4, GRUUL },
}

describe("LootList", function()
  local LootList
  before_each(function()
    LootList = H.load({ "core/Codec.lua", "core/Priority.lua", "core/Resolver.lua", "core/Session.lua",
                        "core/LootList.lua" }).LootList
  end)

  it("records each drop once, in order", function()
    local l = LootList.new()
    assert.is_truthy(l:add({ key = "a", itemId = 1, name = "One", at = 10 }))
    assert.is_truthy(l:add({ key = "b", itemId = 2, name = "Two", at = 11 }))
    assert.is_nil(l:add({ key = "a", itemId = 1, name = "One", at = 12 }))
    assert.are.equal(2, #l.entries)
    assert.are.equal("Two", l:get(2).name)
    assert.are.equal(2, l:numberOf(l:get(2)))
    assert.are.equal(2, #l:waiting())
  end)

  it("follows its session through to the award", function()
    local l = LootList.new()
    local e = l:add({ key = "a", itemId = 1, name = "One" })
    local s = { id = "s1", phase = "open" }
    assert.is_true(LootList.follow(e, s))
    assert.are.equal("rolling", LootList.label(e))
    assert.are.equal(e, l:forSession("s1"))
    assert.is_false(LootList.follow(e, s))
    s.phase = "voting"
    LootList.follow(e, s)
    assert.are.equal("council deciding", LootList.label(e))
    assert.is_false(LootList.startable(e))
    s.phase, s.awardedTo = "done", "Gally"
    LootList.follow(e, s)
    assert.are.equal("to Gally", LootList.label(e))
    s.awardedTo = nil
    LootList.follow(e, s)
    assert.are.equal("not awarded", LootList.label(e))
    assert.is_true(LootList.startable(e)) -- nobody took it: it can be offered again
  end)

  it("merges entries from another client and keeps simulated ones to itself", function()
    local l = LootList.new()
    l:add({ key = "sim:1", itemId = 3, name = "Fake", sim = true })
    local e = l:add({ key = "a", itemId = 1, name = "One", boss = "Gruul" })
    local snap = l:snapshot()
    assert.are.equal(1, #snap)
    assert.are.same({ k = "a", it = 1, nm = "One", b = "Gruul", z = "", at = 0, st = "waiting" }, snap[1])
    local other = LootList.new()
    other:restore(snap)
    assert.are.equal("One", other:get(1).name)
    assert.is_nil(other:merge(snap[1])) -- nothing new
    e.status, e.session = "open", "s1"
    local changed = other:merge(LootList.wire(e))
    assert.are.equal("open", changed.status)
    assert.are.equal("s1", changed.session)
  end)

  it("rejects malformed wire entries", function()
    assert.is_true(LootList.validEntry({ k = "a", nm = "One", it = 5, st = "awarded", w = "Gally" }))
    assert.is_false(LootList.validEntry({ nm = "One" }))
    assert.is_false(LootList.validEntry({ k = "a", nm = "One", st = "stolen" }))
    assert.is_false(LootList.validEntry({ k = "a", nm = "One", it = "5" }))
    assert.is_false(LootList.validEntry("a"))
  end)
end)

describe("/tlc loot in a fake client", function()
  local function entries() return W.ns.Loot.list.entries end
  local function printed() return table.concat(W.printed, "\n") end

  before_each(function()
    W.install()
    W.load()
    W.fire("PLAYER_LOGIN")
    W.ns.App.import(sample)
  end)

  it("records a corpse's epics as the leader loots it, once, and leaves badges and blues out", function()
    W.fire("ENCOUNTER_END", 649, "Gruul the Dragonkiller", 14, 25, 1)
    W.loot(CORPSE)
    assert.are.equal(3, #entries())
    assert.are.same({ "Dragonspine Trophy", "Leggings of the Fallen Hero", "Leggings of the Fallen Hero" },
      { entries()[1].name, entries()[2].name, entries()[3].name })
    assert.are.equal("Gruul the Dragonkiller", entries()[1].boss)
    assert.are.equal("Gruul's Lair", entries()[1].zone)
    assert.matches("Added to the loot list: .*Dragonspine Trophy", printed())
    W.loot(CORPSE) -- opened again: nothing new
    W.loot({ CORPSE[2] }) -- one token handed out, the other still there
    assert.are.equal(3, #entries())
    assert.are.equal(0, #W.chat) -- recording is quiet; the raid hears about it when it starts
  end)

  it("records nothing for raiders, outside raids, or with recording off", function()
    W.group[1].leader = false
    W.loot(CORPSE)
    assert.are.equal(0, #entries())
    W.group[1].leader = true
    _G.IsInRaid = function() return false end
    W.loot(CORPSE)
    assert.are.equal(0, #entries())
    _G.IsInRaid = function() return true end
    W.slash("loot auto off")
    W.loot(CORPSE)
    assert.are.equal(0, #entries())
    W.slash("loot auto on")
    W.loot(CORPSE)
    assert.are.equal(3, #entries())
  end)

  it("records a party leader's drops, rare and up, only with /tlc loot party on", function()
    _G.IsInRaid = function() return false end
    W.loot(CORPSE)
    assert.are.equal(0, #entries())
    W.slash("loot party on")
    W.loot(CORPSE)
    assert.are.equal(4, #entries()) -- the blue Bladespire Warbands too, never the badge
    assert.are.equal("Bladespire Warbands", entries()[4].name)
    W.group[1].leader = false
    W.loot({ { 28796, "Malefic Mask of the Shadows", 4, GRUUL } })
    assert.are.equal(4, #entries()) -- not the party leader
    W.group[1].leader = true
    _G.IsInRaid = function() return true end
    W.loot({ { 28797, "Brute Cloak of the Ogre-Magi", 3, GRUUL } })
    assert.are.equal(4, #entries()) -- in a raid, blues stay out as before
    W.slash("loot auto off")
    W.slash("loot party on")
    assert.matches("Recording corpses is off", printed())
    W.slash("loot auto on")
    W.slash("loot party off")
    _G.IsInRaid = function() return false end
    W.loot({ { 28796, "Malefic Mask of the Shadows", 4, GRUUL } })
    assert.are.equal(4, #entries())
  end)

  it("starts an item from the list, announces it, and marks it through to the award", function()
    W.loot(CORPSE)
    W.slash("loot roll 1 30")
    assert.matches("^RAID: %[ToadsLC%] Roll: .*Dragonspine Trophy.*%(30 s%)", W.chatText())
    local s = W.ns.App.registry:latest()
    assert.are.equal(28830, s.itemId)
    assert.are.equal("open", entries()[1].status)
    assert.are.equal(s.id, entries()[1].session)
    W.slash("loot 2")
    assert.matches("Dragonspine Trophy is still taking rolls", W.printed[#W.printed])
    assert.are.equal(1, #W.ns.App.registry.order)
    W.fire("CHAT_MSG_SYSTEM", "Anasazi rolls 41 (1-100)")
    W.tick(31)
    assert.are.equal("voting", entries()[1].status)
    W.slash("award")
    assert.are.equal("awarded", entries()[1].status)
    assert.are.equal("Anasazi", entries()[1].winner)
    W.slash("loot roll 1")
    assert.matches("Dragonspine Trophy is to Anasazi already", W.printed[#W.printed])
    W.slash("undo")
    assert.are.equal("voting", entries()[1].status) -- reopened with the session
  end)

  it("opens a council session for the next waiting item", function()
    W.loot(CORPSE)
    entries()[1].status = "awarded"
    W.slash("loot next")
    local s = W.ns.App.registry:latest()
    assert.are.equal("session", s.mode)
    assert.are.equal(29765, s.itemId)
    assert.are.equal("Gruul's Lair", s.zone)
    assert.matches("Loot session: .*Leggings of the Fallen Hero", W.chatText())
    assert.are.equal(s.id, entries()[2].session)
    assert.are.equal("waiting", entries()[3].status) -- the second token waits its turn
  end)

  it("marks the list when the leader types /tlc session for an item on it", function()
    W.loot(CORPSE)
    W.slash("session [Dragonspine Trophy]")
    assert.are.equal("open", entries()[1].status)
  end)

  it("announces what is still waiting, adds and removes items by hand, and clears", function()
    W.fire("ENCOUNTER_END", 649, "Gruul the Dragonkiller", 14, 25, 1)
    W.loot(CORPSE)
    entries()[1].status = "awarded"
    W.slash("loot announce")
    assert.are.equal("RAID", W.chat[1].channel)
    assert.matches("^%[ToadsLC%] Loot to hand out: 2%. .*Leggings of the Fallen Hero.* 3%. ", W.chat[1].text)
    assert.is_nil(W.chat[1].text:find("Dragonspine", 1, true))
    W.slash("loot add |cffa335ee|Hitem:28825::::::::70:::::|h[Aldori Legacy Defender]|h|r")
    assert.are.equal(4, #entries())
    assert.are.equal(28825, entries()[4].itemId)
    assert.matches("Added .* as 4%.", W.printed[#W.printed])
    W.slash("loot remove 4")
    assert.are.equal(3, #entries())
    W.slash("loot list")
    assert.matches("3%. .*Leggings of the Fallen Hero.*%(Gruul the Dragonkiller%): waiting", W.printed[#W.printed])
    W.slash("loot clear")
    assert.are.equal(0, #entries())
  end)

  it("shows the list in a frame, with start buttons for the leader", function()
    W.loot(CORPSE)
    W.slash("loot")
    local f = _G.ToadsLCLootFrame
    assert.is_true(f:IsShown())
    local row = f.rows[1]
    assert.matches("Dragonspine Trophy", row.item:GetText())
    assert.is_true(row.session:IsShown())
    row.session.scripts.OnClick(row.session)
    assert.are.equal("open", entries()[1].status)
    assert.matches("rolling", f.rows[1].status:GetText())
    assert.is_false(f.rows[1].session:IsShown())
    row.hover.scripts.OnEnter(row.hover)
    assert.matches("^item:28830", _G.GameTooltip.link)
  end)

  it("keeps the list over a reload, and forgets it after the night", function()
    W.loot(CORPSE)
    local db = _G.ToadsLCDB
    W.install({ db = db })
    W.load()
    W.fire("PLAYER_LOGIN")
    assert.are.equal(3, #entries())
    db.loot.at = W.time - 12 * 3600 - 1
    W.install({ db = db })
    W.load()
    W.fire("PLAYER_LOGIN")
    assert.are.equal(0, #entries())
  end)

  it("puts /tlc sim drops on the list, starts them with the fake raid, and drops them on stop", function()
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return false end
    W.slash("sim drop gruul the dragonkiller")
    assert.are.equal(3, #entries())
    assert.is_true(entries()[1].sim)
    assert.matches("on the loot list", W.printed[#W.printed])
    W.slash("sim drop gruul the dragonkiller") -- another kill adds up
    assert.are.equal(6, #entries())
    assert.are.equal(0, #W.ns.App.registry.order) -- nothing opens by itself
    W.slash("loot 2 20")
    local s = W.ns.App.registry:latest()
    assert.matches("^sim%-", s.id)
    assert.are.equal(entries()[2].itemId, s.itemId)
    assert.are.equal("open", entries()[2].status)
    for _ = 1, 25 do W.tick(1) end
    assert.are.equal("voting", entries()[2].status)
    assert.is_true(#s.candidates > 0) -- the fake raid answered
    assert.are.equal(1, #W.ns.App.registry.order) -- and the next one waits for the leader
    assert.are.equal(0, #W.chat)
    assert.is_nil(_G.ToadsLCDB.loot and _G.ToadsLCDB.loot.json:find("sim", 1, true))
    W.slash("sim stop")
    assert.are.equal(0, #entries())
  end)

  it("marks /tlc sim's drops as they open one after the other", function()
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return false end
    W.slash("sim gruul the dragonkiller 20")
    assert.are.equal(3, #entries())
    assert.are.equal("open", entries()[1].status)
    assert.are.equal("waiting", entries()[2].status)
  end)
end)

describe("the loot list across a raid of clients", function()
  local GROUP = {
    { name = "Poohtank", class = "PALADIN", leader = true },
    { name = "Anasazi", class = "ROGUE" }, { name = "Gally", class = "WARRIOR" },
    { name = "Hadur", class = "SHAMAN", assist = true },
  }
  local leader, officer, rogue, all

  local function list(c) return c.ns.Loot.list.entries end

  before_each(function()
    leader = W.client({ me = "Poohtank", group = GROUP })
    officer = W.client({ me = "Hadur", group = GROUP })
    rogue = W.client({ me = "Anasazi", group = GROUP })
    all = { leader, officer, rogue }
    for _, c in ipairs(all) do c.ns.App.import(sample) end
    W.deliver(all)
  end)

  it("shows the officers what dropped and how each item was handed out", function()
    leader:loot(CORPSE)
    W.deliver(all)
    assert.are.equal(3, #list(officer))
    assert.are.equal("Dragonspine Trophy", list(officer)[1].name)
    assert.are.equal("waiting", list(officer)[1].status)
    leader:slash("loot 1 30")
    W.deliver(all)
    assert.are.equal("open", list(officer)[1].status)
    rogue.ns.App.respond(list(leader)[1].session, "main")
    W.deliver(all)
    leader:fire("CHAT_MSG_SYSTEM", "Anasazi rolls 41 (1-100)")
    W.tickAll(all, 31)
    W.deliver(all)
    leader:slash("award")
    W.deliver(all)
    for _, c in ipairs(all) do
      assert.are.equal("awarded", list(c)[1].status, c.me)
      assert.are.equal("Anasazi", list(c)[1].winner, c.me)
    end
  end)

  it("hands the list to an officer who logs in late, and takes drops an assist loots", function()
    leader:loot(CORPSE)
    W.deliver(all)
    local late = W.client({ me = "Gally", group = GROUP })
    late.ns.App.import(sample)
    for _, fn in ipairs(late.later) do fn() end -- the login requests
    W.deliver({ leader, officer, rogue, late })
    assert.are.equal(3, #list(late))
    officer:loot({ { 28800, "Hammer of the Naaru", 4, MAG } })
    W.deliver({ leader, officer, rogue, late })
    assert.are.equal(4, #list(leader))
    assert.are.equal("Hammer of the Naaru", list(late)[4].name)
  end)

  it("takes no list from a raider", function()
    rogue.ns.Loot.record({ key = "forged", itemId = 28830, name = "Dragonspine Trophy" }) -- what a forger could send
    W.deliver(all)
    assert.are.equal(0, #list(leader))
    assert.are.equal(0, #list(officer))
  end)

  it("ignores list changes not signed with the raid password", function()
    leader:slash("begin frog pond 42")
    officer:slash("join frog pond 42")
    W.deliver(all)
    leader:loot(CORPSE)
    W.deliver(all)
    assert.are.equal(3, #list(officer))
    leader:slash("end") -- the leader's messages go out unsigned now
    leader:slash("loot clear")
    W.deliver(all)
    assert.are.equal(3, #list(officer))
  end)
end)

describe("several items open at once", function()
  local Session, reg, clock
  local function open(id) return select(2, reg:open({ id = id, itemId = 1, itemName = id, council = {}, rules = {},
                                                      mode = "session", seconds = 60 })) end
  local function press(s, who, r) reg:handle({ t = "RSP", s = s.id, r = r or "main" }, who, true, false) end
  local function rollOf(s, who) local e = s:entryFor(who); return e and e.roll end

  before_each(function()
    Session = H.core().Session
    clock = 1000
    reg = Session.newRegistry({ me = "Poohtank", now = function() return clock end, item = function() end,
                                who = function() return {} end })
  end)

  it("gives each button roll to the item it was pressed for, in order", function()
    local a, b = open("A"), open("B")
    press(b, "Gally")
    press(a, "Gally", "offspec")
    reg:roll("Gally", 77, 1, 100)
    reg:roll("Gally", 12, 1, 99)
    assert.are.equal(77, rollOf(b, "Gally"))
    assert.are.equal(12, rollOf(a, "Gally"))
    assert.are.equal("offspec", a:entryFor("Gally").response)
  end)

  it("holds a roll that gets here before its button press", function()
    local a, b = open("A"), open("B")
    reg:roll("Gally", 77, 1, 100)
    assert.is_nil(rollOf(a, "Gally"))
    assert.is_nil(rollOf(b, "Gally"))
    press(a, "Gally")
    assert.are.equal(77, rollOf(a, "Gally"))
    reg:roll("Gally", 50, 1, 100)
    clock = clock + 20 -- its press never came in time
    press(b, "Gally")
    assert.is_nil(rollOf(b, "Gally"))
  end)

  it("counts a bare /roll only while one item is open", function()
    local a = open("A")
    reg:roll("Anasazi", 41, 1, 100)
    assert.are.equal(41, rollOf(a, "Anasazi"))
    local b = open("B")
    reg:roll("Gally", 90, 1, 100)
    assert.is_nil(rollOf(a, "Gally"))
    assert.is_nil(rollOf(b, "Gally"))
  end)

  it("leaves a single item as it was: press then roll, or roll then press", function()
    local a = open("A")
    press(a, "Gally")
    reg:roll("Gally", 33, 1, 100)
    reg:roll("Anasazi", 44, 1, 100)
    press(a, "Anasazi")
    assert.are.equal(33, rollOf(a, "Gally"))
    assert.are.equal(44, rollOf(a, "Anasazi"))
  end)
end)

describe("/tlc loot all", function()
  before_each(function()
    W.install()
    W.load()
    W.fire("PLAYER_LOGIN")
    W.ns.App.import(sample)
  end)

  local function open()
    local out = {}
    for _, id in ipairs(W.ns.App.registry.order) do
      local s = W.ns.App.registry.sessions[id]
      if s.phase == "open" then out[#out + 1] = s end
    end
    return out
  end

  it("opens every waiting item at once, announced in one go, answered in one window", function()
    W.loot(CORPSE)
    W.slash("loot all")
    local sessions = open()
    assert.are.equal(3, #sessions)
    assert.are.equal(105, sessions[1].closesAt - sessions[1].openedAt) -- 60 s + 15 s an item
    assert.matches("^%[ToadsLC%] Loot council: 3 items open for 105 s", W.chat[1].text)
    assert.are.equal("RAID_WARNING", W.chat[2].channel)
    assert.matches("1%. .*Dragonspine Trophy.* 2%. .* 3%. ", W.chat[3].text)
    assert.is_nil(W.chatText():find("Loot session:", 1, true)) -- no line per item
    local cand = _G.ToadsLCCandidateFrame
    assert.matches("3 items", cand.title:GetText())
    assert.is_true(cand.rows[3]:IsShown())
    -- the leader answers the second item, then the first; each roll lands on its own item
    cand.rows[2].main.scripts.OnClick(cand.rows[2].main)
    assert.is_false(cand.rows[3]:IsShown()) -- answered items leave the window
    cand.rows[1].off.scripts.OnClick(cand.rows[1].off)
    W.fire("CHAT_MSG_SYSTEM", "Poohtank rolls 81 (1-100)")
    W.fire("CHAT_MSG_SYSTEM", "Poohtank rolls 22 (1-99)")
    assert.are.equal(81, sessions[2]:entryFor("Poohtank").roll)
    assert.are.equal(22, sessions[1]:entryFor("Poohtank").roll)
    W.fire("CHAT_MSG_SYSTEM", "Gally rolls 90 (1-100)") -- no button behind it: ignored
    for _, s in ipairs(sessions) do assert.is_nil(s:entryFor("Gally")) end
    for _, e in ipairs(W.ns.Loot.list.entries) do assert.are.equal("open", e.status) end
    W.tick(106)
    assert.are.equal(0, #open())
  end)

  it("resizes its windows by the corner grip, shows as many rows as fit, and keeps the size per character", function()
    W.loot(CORPSE)
    W.slash("loot all") -- three items, one row each
    local cand = _G.ToadsLCCandidateFrame
    local function shownRows()
      local n = 0
      for _, row in ipairs(cand.rows) do if row.shown then n = n + 1 end end
      return n
    end
    assert.are.equal(3, shownRows())
    cand.scripts.OnSizeChanged(cand, 470, 96 + 2 * 44) -- dragged shorter: two rows and a scroll hint
    assert.are.equal(2, shownRows())
    assert.matches("1%-2 of 3", cand.more.text)
    cand.GetPoint = function() return "TOPLEFT", nil, "BOTTOMLEFT", 120, 700 end
    cand.GetWidth, cand.GetHeight = function() return 2000 end, function() return 96 + 2 * 44 end
    cand.grip.scripts.OnMouseUp(cand.grip)
    assert.are.same({ w = 900, h = 184, point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 120, y = 700 },
      _G.ToadsLCCharDB.frames.ToadsLCCandidateFrame) -- held to the largest size it allows

    W.slash("scale 1.25")
    assert.are.equal(1.25, _G.ToadsLCCharDB.scale)
    W.slash("scale 7")
    assert.are.equal(1.25, _G.ToadsLCCharDB.scale)
    W.slash("scale reset")
    assert.are.equal(1, _G.ToadsLCCharDB.scale)
    assert.are.same({}, _G.ToadsLCCharDB.frames)
  end)

  it("refuses while an item is still taking rolls, and takes a time", function()
    W.loot(CORPSE)
    W.slash("loot 1")
    W.slash("loot all")
    assert.matches("still taking rolls", W.printed[#W.printed])
    assert.are.equal(1, #open())
    W.slash("close")
    W.slash("loot all 200")
    assert.are.equal(2, #open())
    assert.are.equal(200, open()[1].closesAt - open()[1].openedAt)
  end)

  it("runs a simulated loot pool through the fake raid", function()
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return false end
    W.slash("sim drop gruul the dragonkiller")
    W.slash("sim drop gruul the dragonkiller")
    W.slash("loot all 30")
    assert.are.equal(6, #open())
    assert.are.equal(0, #W.chat)
    assert.matches("%[sim%] Loot council: 6 items open for 30 s", table.concat(W.printed, "\n"))
    for _ = 1, 35 do W.tick(1) end
    assert.are.equal(0, #open())
    for _, e in ipairs(W.ns.Loot.list.entries) do assert.are.equal("voting", e.status) end
  end)
end)

describe("/tlc loot all across a raid of clients", function()
  local GROUP = {
    { name = "Poohtank", class = "PALADIN", leader = true },
    { name = "Anasazi", class = "ROGUE" }, { name = "Hadur", class = "SHAMAN", assist = true },
  }

  it("matches a raider's button rolls to the items they answered", function()
    local leader = W.client({ me = "Poohtank", group = GROUP })
    local rogue = W.client({ me = "Anasazi", group = GROUP })
    local all = { leader, rogue }
    for _, c in ipairs(all) do c.ns.App.import(sample) end
    W.deliver(all)
    leader:loot(CORPSE)
    leader:slash("loot all")
    W.deliver(all)
    local cand = rogue.env.ToadsLCCandidateFrame
    assert.is_true(cand.rows[3]:IsShown())
    local third, first = cand.rows[3].session.id, cand.rows[1].session.id
    cand.rows[3].main.scripts.OnClick(cand.rows[3].main)
    cand.rows[1].main.scripts.OnClick(cand.rows[1].main)
    assert.are.same({ { 1, 100 }, { 1, 100 } }, rogue.rolls)
    -- the roll lines reach the leader before the whispers do
    leader:fire("CHAT_MSG_SYSTEM", "Anasazi rolls 64 (1-100)")
    leader:fire("CHAT_MSG_SYSTEM", "Anasazi rolls 5 (1-100)")
    W.deliver(all)
    local reg = leader.ns.App.registry
    assert.are.equal(64, reg:get(third):entryFor("Anasazi").roll)
    assert.are.equal(5, reg:get(first):entryFor("Anasazi").roll)
  end)
end)
