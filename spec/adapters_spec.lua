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

describe("Chat", function()
  it("splits long announcements under the chat limit on spaces", function()
    W.install()
    local ns = W.load()
    local lines = ns.Chat.split(string.rep("word ", 120))
    assert.is_true(#lines > 1)
    for _, l in ipairs(lines) do assert.is_true(#l <= 250) end
  end)
end)
