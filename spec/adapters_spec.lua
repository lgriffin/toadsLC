local H = require("spec.helper")
local W = require("spec.wow_mock")

describe("RollParser", function()
  local RP
  before_each(function()
    RP = H.load({ "adapters/RollParser.lua" }).RollParser
  end)

  it("parses roll lines in EN, DE and FR client formats", function()
    for _, case in ipairs({
      { RP.FORMATS.enUS, "Gally rolls 97 (1-100)" },
      { RP.FORMATS.deDE, "Gally würfelt. Ergebnis: 97 (1-100)" },
      { RP.FORMATS.frFR, "Gally obtient un 97 (1-100)." },
    }) do
      local name, roll, min, max = RP.new(case[1])(case[2])
      assert.are.same({ "Gally", 97, 1, 100 }, { name, roll, min, max })
    end
  end)

  it("reads the off-spec range and ignores other system lines", function()
    local p = RP.new(RP.FORMATS.enUS)
    assert.are.same({ "Poohtank", 94, 1, 99 }, { p("Poohtank rolls 94 (1-99)") })
    assert.is_nil(p("Gally has joined the raid group."))
    assert.is_nil(p("Gally rolls a die (1-100)"))
  end)

  it("handles positional format strings", function()
    local p = RP.new("%1$s rolls %2$d (%3$d-%4$d)")
    assert.are.same({ "Hadur", 88, 1, 100 }, { p("Hadur rolls 88 (1-100)") })
  end)
end)

describe("addon in a fake client", function()
  local sample
  before_each(function()
    W.install()
    W.load()
    W.fire("PLAYER_LOGIN")
    sample = H.read("fixtures/priority.sample.json")
  end)

  it("refuses to load on any other client", function()
    W.install({ project = 1 })
    W.load()
    W.fire("PLAYER_LOGIN")
    assert.is_nil(_G.SlashCmdList.TOADSLC)
    assert.matches("TBC Classic client only", W.printed[1])
  end)

  it("imports the priorities document and reports it", function()
    local ok, msg = W.ns.App.import(sample)
    assert.is_true(ok)
    assert.are.equal("Imported 1 items, dated 21 Oct 2026.", msg)
    assert.are.equal(1, _G.ToadsLCDB.priorities.count)
    local bad = sample:gsub('"Warrior:Fury"', '"Shamans"', 1)
    ok, msg = W.ns.App.import(bad)
    assert.is_false(ok)
    assert.are.equal('import failed: items[0].priority[1][0].spec "Shamans" is not a known token', msg)
    assert.are.equal(1, _G.ToadsLCDB.priorities.count) -- the good list is kept
  end)

  it("runs /tlc roll from open to award and writes the record", function()
    W.ns.App.import(sample)
    W.slash("roll |cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r 30")
    assert.matches("^RAID: %[ToadsLC%] Roll: .*Dragonspine Trophy.*%(30 s%)%. /roll main spec, /roll 99 off%-spec%. Priority: BM Hunter = Rogue > Fury", W.chatText())
    W.fire("CHAT_MSG_SYSTEM", "Anasazi rolls 41 (1-100)")
    W.fire("CHAT_MSG_SYSTEM", "Gally rolls 97 (1-100)")
    W.fire("CHAT_MSG_SYSTEM", "Hadur rolls 88 (1-100)")
    W.fire("CHAT_MSG_SYSTEM", "Poohtank rolls 94 (1-99)")
    W.fire("CHAT_MSG_SYSTEM", "Gally rolls 12 (1-100)")
    W.tick(31)
    local last = W.chat[#W.chat].text
    assert.are.equal("[ToadsLC] Dragonspine Trophy: Anasazi wins (Rogue, tier 1, rolled 41). Gally 97 (Fury, tier 2), Hadur 88 (Enhance, tier 4), Poohtank 94 (off-spec).", last)
    W.slash("award")
    assert.are.equal("RAID_WARNING", W.chat[#W.chat].channel)
    local recs = W.ns.Store.records(false)
    assert.are.equal(1, #recs)
    assert.are.equal("Anasazi", recs[1].awardedTo)
    assert.are.equal("Gruul's Lair", recs[1].zone)
    assert.are.equal("duplicate", recs[1].candidates[5].ignored)
  end)

  it("exports unexported sessions as one valid document and clears them", function()
    W.ns.App.import(sample)
    W.slash("roll [Dragonspine Trophy]")
    W.fire("CHAT_MSG_SYSTEM", "Anasazi rolls 41 (1-100)")
    W.tick(31)
    W.slash("award Gally out of the list")
    W.slash("export")
    local text = _G.ToadsLCIOFrame.box:GetText()
    local doc = assert(W.ns.Codec.decode(text))
    assert.is_true(W.ns.Codec.validateSession(doc))
    assert.are.equal("Poohtank-Spineshatter", doc.exportedBy)
    assert.are.equal("Gally", doc.sessions[1].awardedTo)
    assert.are.equal("out of the list", doc.sessions[1].override.reason)
    W.slash("export clear")
    assert.are.equal(0, #W.ns.Store.records(false))
    assert.are.equal(1, #W.ns.Store.records(true))
  end)

  it("re-exports a session whose record changed after it was cleared", function()
    W.ns.App.import(sample)
    W.slash("roll [Dragonspine Trophy]")
    W.fire("CHAT_MSG_SYSTEM", "Anasazi rolls 41 (1-100)")
    W.tick(31)
    W.slash("export clear")
    assert.are.equal(0, #W.ns.Store.records(false))
    W.slash("award")
    local recs = W.ns.Store.records(false)
    assert.are.equal(1, #recs)
    assert.are.equal("Anasazi", recs[1].awardedTo)
  end)

  it("records the priority pick named in /tlc award as a list award when only off-spec rolls came in", function()
    W.ns.App.import(sample)
    W.slash("roll [Dragonspine Trophy]")
    W.fire("CHAT_MSG_SYSTEM", "Gally rolls 12 (1-99)")
    W.fire("CHAT_MSG_SYSTEM", "Poohtank rolls 94 (1-99)")
    W.tick(31)
    W.slash("award Gally")
    local rec = W.ns.Store.records(false)[1]
    assert.are.equal("list", rec.awardedVia)
    assert.are.equal(W.ns.Codec.null, rec.override)
  end)

  it("picks up the leader's unfinished session after a reload", function()
    W.ns.App.import(sample)
    W.slash("roll [Dragonspine Trophy]")
    W.fire("CHAT_MSG_SYSTEM", "Anasazi rolls 41 (1-100)")
    local db = _G.ToadsLCDB
    W.install({ db = db })
    W.load()
    W.fire("PLAYER_LOGIN")
    assert.matches("Picked up your unfinished session", table.concat(W.printed, "\n"))
    W.fire("CHAT_MSG_SYSTEM", "Gally rolls 97 (1-100)")
    W.tick(31)
    assert.matches("Anasazi wins", W.chat[#W.chat].text)
    assert.matches("Gally 97", W.chat[#W.chat].text)
  end)

  it("asks for open sessions on joining a group", function()
    local grouped = false
    _G.IsInGroup = function() return grouped end
    _G.IsInRaid = function() return grouped end
    W.fire("GROUP_ROSTER_UPDATE") -- left the group
    W.later, W.addon = {}, {}
    grouped = true
    W.fire("GROUP_ROSTER_UPDATE") -- joined one
    assert.are.equal(2, #W.later)
    for _, fn in ipairs(W.later) do fn() end
    W.flushComms()
    local asm = W.ns.Codec.newAssembler()
    local found = false
    for _, a in ipairs(W.addon) do
      local m = asm.feed("me", a.text)
      m = m and W.ns.Codec.decode(m)
      if m and m.t == "STATE_REQUEST" then found = true end
    end
    assert.is_true(found)
  end)

  it("begins a protected raid, signs council traffic and forgets the password on /tlc end", function()
    W.slash("begin short")
    assert.matches("at least 6 characters", W.printed[#W.printed])
    W.slash("begin frog pond 42")
    assert.matches("Raid begun%. Council traffic is now signed and encrypted %(fingerprint %x+%)", W.printed[#W.printed])
    assert.is_nil(_G.ToadsLCDB.settings.raid.password) -- only the derived key is stored
    W.slash("status")
    assert.matches("Raid password: set %(leading, fingerprint", table.concat(W.printed, "\n"))
    W.ns.App.import(sample)
    W.slash("session [Dragonspine Trophy]")
    W.flushComms()
    assert.matches("^1:1/%d+:T1|p|", W.addon[1].text)
    W.slash("end")
    assert.is_nil(W.ns.App.secret())
  end)

  it("forgets the raid password after 12 hours without a reload", function()
    W.slash("begin frog pond 42")
    assert.is_not_nil(W.ns.App.secret())
    _G.ToadsLCDB.settings.raid.at = W.ns.App.now() - 12 * 3600 - 1
    assert.is_nil(W.ns.App.secret())
    assert.is_nil(_G.ToadsLCDB.settings.raid)
  end)

  it("sends HELLO on /tlc join", function()
    W.slash("join frog pond 42")
    W.flushComms()
    assert.matches("checking it with the raid leader", W.printed[#W.printed])
    assert.matches("T1|p|", W.addon[#W.addon].text)
  end)

  it("opens a council session and broadcasts it to the raid by addon message", function()
    W.ns.App.import(sample)
    W.slash("session [Dragonspine Trophy]")
    W.flushComms()
    assert.is_true(#W.addon > 0)
    assert.are.equal("ToadsLC", W.addon[1].prefix)
    assert.are.equal("RAID", W.addon[1].dist)
    local asm = W.ns.Codec.newAssembler()
    local msg
    for _, a in ipairs(W.addon) do msg = asm.feed("Poohtank", a.text) or msg end
    msg = W.ns.Codec.decode(msg)
    assert.are.equal("SESSION_OPEN", msg.t)
    assert.are.same({ "Poohtank", "Hadur", "Anasazi", "Gally" }, msg.co)
    assert.is_true(_G.ToadsLCCouncilFrame:IsShown())
    assert.is_true(_G.ToadsLCCandidateFrame:IsShown())
  end)

  it("shows the Priority block once on a listed item and nothing on others", function()
    W.ns.App.import(sample)
    local tt = _G.GameTooltip
    tt.GetItem = function() return "Dragonspine Trophy", "|Hitem:28830::|h[Dragonspine Trophy]|h" end
    tt.hooks.OnTooltipSetItem(tt)
    assert.are.equal(8, #tt.lines) -- spacer, header, six tiers
    assert.matches("Priority %(Toads LC%)", tt.lines[2])
    assert.matches("BM Hunter", tt.lines[3])
    tt.lines = nil
    tt.GetItem = function() return "Hearthstone", "|Hitem:6948::|h[Hearthstone]|h" end
    tt.hooks.OnTooltipSetItem(tt)
    assert.is_nil(tt.lines)
  end)

  it("hooks OnTooltipSetItem even when the client also has TooltipDataProcessor (TBC Classic)", function()
    W.install({ tooltipData = true })
    W.load()
    W.fire("PLAYER_LOGIN")
    W.ns.App.import(sample)
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
      local tt = _G[name]
      assert.is_function(tt.hooks and tt.hooks.OnTooltipSetItem, name)
      tt.GetItem = function() return "Dragonspine Trophy", "|Hitem:28830::|h[Dragonspine Trophy]|h" end
      tt.hooks.OnTooltipSetItem(tt)
      assert.are.equal(8, #tt.lines, name)
      -- the data processor's post call skips tooltips the hook already covers
      W.tooltipPostCalls[1].fn(tt, { id = 28830 })
      assert.are.equal(8, #tt.lines, name)
    end
  end)

  it("falls back to TooltipDataProcessor on tooltips without OnTooltipSetItem", function()
    W.install({ tooltipData = true, noSetItem = true })
    W.load()
    W.fire("PLAYER_LOGIN")
    W.ns.App.import(sample)
    local tt = _G.GameTooltip
    assert.is_nil(tt.hooks and tt.hooks.OnTooltipSetItem)
    tt.GetItem = function() return "Dragonspine Trophy", nil end
    W.tooltipPostCalls[1].fn(tt, { id = 28830 })
    assert.are.equal(8, #tt.lines)
  end)

  it("/tlc debug says which hooks are in and why the last tooltip had no block", function()
    local tt = _G.GameTooltip
    tt.GetItem = function() return "Dragonspine Trophy", "|Hitem:28830::|h[Dragonspine Trophy]|h" end
    tt.hooks.OnTooltipSetItem(tt)
    W.slash("debug")
    local out = table.concat(W.printed, "\n")
    assert.matches("interface 20505", out)
    assert.matches("Tooltip hooks: GameTooltip, ItemRefTooltip", out)
    assert.matches("Dragonspine Trophy %(28830%) on GameTooltip: not shown, no list imported", out)
    W.ns.App.import(sample)
    tt.lines = nil
    tt.hooks.OnTooltipSetItem(tt)
    W.slash("debug [Dragonspine Trophy]")
    out = table.concat(W.printed, "\n")
    assert.matches("Priority block shown", out)
    assert.matches("Dragonspine Trophy %(28830%): on the list: BM Hunter", out)
  end)

  it("marks the viewer's own tier on the tooltip", function()
    W.install({ me = "Gally" })
    W.load()
    W.fire("PLAYER_LOGIN")
    W.ns.App.import(sample)
    local item = W.ns.Priority.lookup(W.ns.Store.priorities(), 28830)
    local lines = W.ns.Tooltip.lines(item, { player = "Gally", class = "Warrior", spec = "Warrior:Fury" })
    assert.matches("^> ", lines[3])
    assert.matches("^  ", lines[2])
  end)
end)

describe("/tlc sim", function()
  local reg
  before_each(function()
    W.install()
    W.load()
    W.fire("PLAYER_LOGIN")
    reg = W.ns.App.registry
    _G.IsInRaid = function() return false end -- solo
    _G.IsInGroup = function() return false end
    local seed = 42 -- a fixed sequence, so every run fakes the same raid
    W.ns.Sim.random = function(n)
      seed = (seed * 16807) % 2147483647
      local x = seed / 2147483647
      return n and (math.floor(x * n) + 1) or x
    end
  end)

  local function sims()
    local out = {}
    for _, id in ipairs(reg.order) do out[#out + 1] = reg.sessions[id] end
    return out
  end

  it("chooses a boss's drops, or one item, from the loot tables", function()
    local zone, boss, items = W.ns.Sim.choose("gruul the dragonkiller")
    assert.are.equal("Gruul's Lair", zone)
    assert.are.equal("Gruul the Dragonkiller", boss)
    assert.are.equal(3, #items)
    local itemZone, _, one = W.ns.Sim.choose("|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r")
    assert.are.equal("Gruul's Lair", itemZone)
    assert.are.same({ 28830 }, { one[1][1] })
    zone, boss, items = W.ns.Sim.choose("karazhan")
    assert.are.equal("Karazhan", zone)
    assert.are.equal(2, #items)
    assert.is_not.equal("Trash", boss)
    local none, err = W.ns.Sim.choose("Onyxia")
    assert.is_nil(none)
    assert.matches("No boss, raid or item", err)
  end)

  it("runs a fake kill through responses, rolls, the officer's vote and the next item", function()
    W.slash("sim Gruul the Dragonkiller 20")
    assert.matches("%[sim%] Gruul the Dragonkiller killed", table.concat(W.printed, "\n"))
    local first = sims()[1]
    assert.are.equal(1, #sims())
    assert.matches("^sim%-", first.id)
    assert.are.equal("Gruul the Dragonkiller", first.boss)
    assert.is_truthy(first.item and first.item.priority) -- no list imported: a made-up priority
    assert.is_true(first:isCouncil("Toadmaster"))
    assert.is_true(_G.ToadsLCCandidateFrame:IsShown())
    for _ = 1, 20 do W.tick(1) end
    assert.are.equal("voting", first.phase)
    assert.is_true(#first.candidates > 0)
    local rolled = false
    for _, e in ipairs(first.candidates) do
      assert.is_truthy(W.ns.Sim.who(e.player)) -- every candidate is a fake raider with a class and spec
      assert.is_truthy(e.class)
      if e.roll then rolled = true end
    end
    assert.is_true(rolled)
    for _ = 1, 3 do W.tick(1) end
    assert.is_truthy(first.votes.toadmaster)
    assert.are.equal(2, #sims()) -- the second drop opened once the first closed
    W.slash("award Croaksworth testing")
    assert.are.equal(0, #W.chat) -- nothing reaches group chat
    assert.are.same({}, _G.ToadsLCDB.sessions) -- nor the export
    W.slash("sim stop")
    assert.are.equal(0, #sims())
    for _ = 1, 60 do W.tick(1) end
    assert.are.equal(0, #sims()) -- the stopped simulation opens nothing more
  end)

  it("ranks the fake raid by the imported list when the item is on it", function()
    W.ns.App.import(H.read("fixtures/priority.sample.json"))
    W.slash("sim Dragonspine Trophy 20")
    local s = sims()[1]
    assert.are.equal(28830, s.itemId)
    assert.is_nil(s.item.sim)
    assert.is_truthy(s.priorityVersion)
  end)

  it("stays out of raid groups, live sessions and timers other clients reject", function()
    _G.IsInRaid = function() return true end
    _G.IsInGroup = function() return true end
    W.slash("sim")
    assert.are.equal(0, #sims())
    assert.matches("Not in a raid group", W.printed[#W.printed])
    _G.IsInRaid = function() return false end
    _G.IsInGroup = function() return false end
    W.slash("sim gruul 601")
    assert.matches("Use 5 to 600 seconds", W.printed[#W.printed])
    W.slash("session [Dragonspine Trophy]")
    W.slash("sim gruul")
    assert.matches("real loot session is still taking rolls", W.printed[#W.printed])
    assert.are.equal(1, #sims())
  end)

  it("hands over to a live session, and fakes no one outside a run", function()
    assert.is_nil(W.ns.Sim.who("Croaksworth"))
    W.slash("sim gruul 30")
    assert.is_truthy(W.ns.Sim.who("Croaksworth"))
    W.tick(2)
    W.slash("session [Dragonspine Trophy] 30")
    assert.is_false(W.ns.Sim.active)
    assert.is_nil(W.ns.Sim.who("Croaksworth"))
    for _ = 1, 40 do W.tick(1) end
    local live = sims()
    assert.are.equal(1, #live)
    for _, e in ipairs(live[1].candidates) do error("fake answer reached the live session: " .. e.player) end
  end)

  it("ends the simulated sessions for the party when stopped", function()
    _G.IsInGroup = function() return true end -- a party: the mock's player leads
    W.slash("sim gruul 30")
    W.flushComms()
    W.addon = {}
    W.slash("sim stop")
    W.flushComms()
    local asm, types = W.ns.Codec.newAssembler(), {}
    for _, a in ipairs(W.addon) do
      local m = asm.feed("Poohtank", a.text)
      if type(m) == "string" then m = W.ns.Codec.decode(m) end -- the signed wire format hands back text
      if m then types[#types + 1] = m.t end
    end
    assert.are.same({ "SESSION_CLOSE", "AWARD" }, types)
    assert.are.equal(0, #W.chat)
  end)
end)

describe("Chat", function()
  it("splits long announcements under the chat limit on spaces", function()
    W.install()
    local ns = W.load()
    local lines = ns.Chat.split(string.rep("word ", 120))
    assert.is_true(#lines > 1)
    for _, l in ipairs(lines) do assert.is_true(#l <= 250) end
    local long = string.rep("x", 600)
    assert.are.equal(long, table.concat(ns.Chat.split(long)))
  end)
end)
