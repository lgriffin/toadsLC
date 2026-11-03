-- The Toads LC window (/tlc): a Raider part for everyone, and Loot Council pages behind the
-- raid password, with a button for every slash command.
local H = require("spec.helper")
local W = require("spec.wow_mock")

local PASSWORD = "toads-at-dusk"

describe("main window", function()
  local Main
  before_each(function()
    W.install()
    W.load()
    W.fire("PLAYER_LOGIN")
    W.ns.App.import(H.read("fixtures/priority.sample.json"))
    Main = W.ns.Main
  end)

  local function click(b) b.scripts.OnClick(b, "LeftButton") end
  local function page(key) return Main.page(key) end

  it("opens on /tlc with the raider's rolls and the council pages locked", function()
    W.slash("")
    assert.is_true(_G.ToadsLCMainFrame:IsShown())
    assert.are.equal("rolls", Main.current())
    assert.is_false(Main.unlocked())
    Main.go("loot")
    assert.are.equal("unlock", Main.current()) -- a locked council page asks for the password
    Main.go("trades")
    assert.are.equal("unlock", Main.current())
    W.slash("")
    assert.is_false(_G.ToadsLCMainFrame:IsShown())
  end)

  it("still prints the slash commands on /tlc help", function()
    W.slash("help")
    assert.matches("/tlc begin", table.concat(W.printed, "\n"))
  end)

  it("begins the raid from one button for the raid leader, named, with no lock", function()
    Main.go("loot")
    local p = page("unlock")
    assert.are.equal("Begin raid", p.go:GetText()) -- the raid leader begins; everyone else joins
    p.box:SetText("short")
    click(p.go)
    assert.is_false(Main.unlocked())
    assert.matches("at least 6 characters", p.msg:GetText())
    p.box:SetText(PASSWORD)
    p.nameBox:SetText("Gruul Tuesday")
    click(p.go)
    assert.is_true(Main.unlocked())
    assert.are.equal("raid", Main.current()) -- where the council fills in
    assert.are.equal("Gruul Tuesday", W.ns.App.raidName())
    assert.matches("Gruul Tuesday", page("raid").password:GetText())
    assert.matches("Poohtank %(leads%)", page("raid").council:GetText())
    assert.is_nil(_G.ToadsLCMainFrame.lockBtn)
  end)

  it("shows an officer Join council, and the raid name and leader once confirmed", function()
    W.install({ group = { { name = "Poohtank", class = "PALADIN", leader = true },
                          { name = "Hadur", class = "SHAMAN", assist = true } }, me = "Hadur" })
    W.load()
    W.fire("PLAYER_LOGIN")
    Main = W.ns.Main
    W.slash("")
    Main.go("loot")
    local p = page("unlock")
    assert.are.equal("Join council", p.go:GetText())
    assert.is_true(p.begin:IsShown()) -- an assist can still begin instead
    p.box:SetText(PASSWORD)
    click(p.go)
    assert.is_true(Main.unlocked())
    assert.is_false(W.ns.Store.raid().hosting)
    assert.matches("Checking your password", page("raid").council:GetText())
    -- the leader answers
    local r = W.ns.App.registry
    r:handle({ t = "WELCOME" }, "Poohtank", true, true)
    r:handle({ t = "COUNCIL_IN", names = { "Hadur" }, rn = "Gruul Tuesday" }, "Poohtank", true, true)
    assert.matches("Welcome to Gruul Tuesday!", table.concat(W.printed, "\n"))
    Main.refresh()
    assert.matches("Gruul Tuesday", page("raid").password:GetText())
    assert.matches("Poohtank %(leads%).*Hadur %(in%)", page("raid").council:GetText())
  end)

  it("keeps the raid password per character, so an alt on the same account joins for itself", function()
    W.slash("begin " .. PASSWORD)
    local db = _G.ToadsLCDB
    W.install({ db = db }) -- another character on the same account: its own ToadsLCCharDB
    W.load()
    W.fire("PLAYER_LOGIN")
    assert.is_nil(W.ns.App.secret())
    assert.is_false(W.ns.Main.unlocked())
  end)

  it("unlocks straight away for an officer who already typed /tlc join", function()
    W.slash("join " .. PASSWORD)
    W.slash("")
    assert.are.equal("loot", Main.current())
  end)

  describe("loot page", function()
    before_each(function()
      W.slash("begin " .. PASSWORD)
      W.slash("loot add [Dragonspine Trophy]")
      W.slash("")
    end)

    local function row1() return page("loot").listView.list.rows[1] end

    it("shows each item's status, when it dropped and the two hours it can be traded", function()
      local row = row1()
      assert.is_true(row:IsShown())
      assert.matches("Item 28830", row.cells.item:GetText())
      assert.matches("waiting to open", row.cells.status:GetText())
      assert.matches("2h 00m", row.cells.trade:GetText())
      assert.matches("^%d%d:%d%d$", row.cells.dropped:GetText())
      W.tick(5400)
      Main.refresh()
      assert.matches("|cffe0b04f30m", row.cells.trade:GetText()) -- half an hour left: amber
      W.tick(1800)
      Main.refresh()
      assert.matches("expired", row.cells.trade:GetText())
    end)

    it("opens one item from its row, and all of them with Open all", function()
      W.slash("loot add [Dragonspine Trophy]")
      Main.refresh()
      local p = page("loot").listView
      assert.is_true(p.all:IsShown())
      click(row1().announce)
      assert.matches("Loot: .*Item 28830", W.chatText())
      Main.refresh()
      assert.matches("taking answers: 0 of 4", row1().cells.status:GetText())
      W.ns.App.closeLast()
      W.tick(10) -- the last call runs out
      click(p.all) -- the second copy, still waiting
      Main.refresh()
      assert.matches("taking answers", page("loot").listView.list.rows[2].cells.status:GetText())
    end)

    it("shows the officer who answered, what they picked, and who to call out", function()
      click(row1().announce)
      local s = W.ns.App.registry:latest()
      W.ns.App.respond(s.id, "bis")
      local group = W.ns.Roster.group()
      W.ns.App.registry:handle({ t = "RSP", s = s.id, r = "pass" }, group[2], true, false)
      Main.refresh()
      assert.matches("taking answers: 2 of 4", row1().cells.status:GetText())
      click(row1())
      local d = page("loot").detailView
      local line = d.answers:GetText()
      assert.matches("Answered 2 of 4%.", line)
      assert.matches("Passed: " .. group[2], line)
      assert.matches("Still to answer: " .. group[3] .. ", " .. group[4], line)
      assert.matches("BiS", d.list.rows[1].cells.answer:GetText())
      assert.is_true(d.callout:IsShown())
      click(d.callout)
      assert.matches("Still to answer for .*Item 28830.*s left%): " .. group[3] .. ", " .. group[4], W.chatText())
    end)

    it("opens an item to show its answers as a live poll: click a name to vote, award from the row", function()
      click(row1().announce)
      local s = W.ns.App.registry:latest()
      W.ns.App.respond(s.id, "main")
      W.ns.App.registry:handle({ t = "RSP", s = s.id, r = "bis" }, "Anasazi", true, false)
      W.ns.App.close(s.id)
      W.tick(10)
      Main.refresh()
      assert.matches("council deciding: 0 of 4 voted", row1().cells.status:GetText())

      click(row1()) -- into the item
      local d = page("loot").detailView
      assert.is_true(d:IsShown())
      assert.matches("Still to vote: Poohtank", d.votes:GetText())
      local first, second = d.list.rows[1], d.list.rows[2]
      assert.matches("Anasazi", first.cells.name:GetText()) -- BiS ranks ahead of Main
      assert.matches("Poohtank", second.cells.name:GetText())
      second.scripts.OnClick(second, "LeftButton") -- a click votes
      Main.refresh()
      assert.matches("Poohtank > Poohtank", d.votes:GetText())
      assert.matches("1: Poohtank", second.cells.votes:GetText()) -- the tally names who voted
      first.scripts.OnClick(first, "LeftButton") -- and moves the vote
      Main.refresh()
      assert.matches("1: Poohtank", first.cells.votes:GetText())
      assert.are.equal("", second.cells.votes:GetText())
      assert.is_true(second.award:IsShown()) -- the leader awards from any row
      click(first.award)
      Main.refresh()
      assert.are.equal("Anasazi", s.awardedTo)
      assert.are.equal("votes", s.awardedVia)
      assert.is_true(d.undo:IsShown())
      assert.is_false(first.award:IsShown())
      click(d.back)
      assert.matches("awarded to Anasazi", row1().cells.status:GetText())
    end)

    it("resets an item from its right-click menu", function()
      click(row1().announce)
      local s = W.ns.App.registry:latest()
      W.slash("award Anasazi")
      assert.are.equal("Anasazi", s.awardedTo)
      W.ns.Loot.reset(1)
      local e = W.ns.Loot.list.entries[1]
      assert.are.equal("waiting", e.status)
      assert.is_nil(e.session)
      assert.is_nil(s.awardedTo) -- the award is undone
      Main.refresh()
      assert.matches("waiting to open", row1().cells.status:GetText())
      assert.is_true(row1().announce:IsShown())
    end)
  end)

  it("keeps opacity and the position lock per character", function()
    W.slash("")
    Main.go("settings")
    local p = page("settings")
    p.alpha.scripts.OnValueChanged(p.alpha, 0.62)
    assert.are.equal(0.6, math.floor(W.ns.Frames.alpha() * 100 + 0.5) / 100)
    assert.are.equal(0.6, math.floor(_G.ToadsLCCharDB.alpha * 100 + 0.5) / 100)
    p.locked.GetChecked = function() return true end
    click(p.locked)
    assert.is_true(_G.ToadsLCCharDB.locked)
    click(p.reset)
    assert.are.equal(1, W.ns.Frames.alpha())
  end)

  it("draws every page, with a session awarded and a trade owed", function()
    W.slash("begin " .. PASSWORD)
    W.slash("loot add [Dragonspine Trophy]")
    W.slash("loot 1")
    local s = W.ns.App.registry:latest()
    W.slash("award Anasazi")
    assert.are.equal("Anasazi", s.awardedTo)
    W.slash("")
    for _, key in ipairs({ "rolls", "loot", "trades", "raid", "announce", "data", "history", "practice", "settings" }) do
      Main.go(key)
      assert.are.equal(key, Main.current())
    end
    Main.go("trades")
    assert.are.equal("Anasazi", page("trades").list.rows[1].cells.winner:GetText())
    Main.go("raid")
    assert.matches("fingerprint", page("raid").password:GetText())
    assert.is_true(page("raid").undoLast:IsShown())
    Main.go("announce")
    assert.matches("^e%.g%. ", page("announce").parts.award.sample:GetText())
  end)

  it("shows the mule page and the version check once they're installed, and hides a missing one", function()
    W.slash("begin " .. PASSWORD)
    W.slash("")
    -- the mule (#21) and the version check (#22) are both installed
    assert.is_true(_G.ToadsLCMainFrame.navs.mule:IsShown())
    Main.go("mule")
    assert.are.equal("mule", Main.current())
    Main.go("raid")
    assert.is_true(page("raid").versions:IsShown())
    local check = W.ns.Version
    W.ns.Version = nil
    Main.go("loot")
    Main.go("raid")
    assert.is_false(page("raid").versions:IsShown())
    W.ns.Version = check
  end)
  it("times one item by the officers' setting, and shows the raider's own answer", function()
    W.slash("begin " .. PASSWORD)
    W.slash("")
    Main.go("raid")
    assert.matches("15 s", page("raid").itemSec.value:GetText()) -- the default
    W.slash("timer 25")
    Main.refresh()
    assert.matches("25 s", page("raid").itemSec.value:GetText())
    W.slash("loot add [Dragonspine Trophy]")
    W.slash("loot 1")
    local s = W.ns.App.registry:latest()
    assert.are.equal(25, s.closesAt - s.openedAt)
    Main.go("rolls")
    local row = page("rolls").list.rows[1]
    assert.is_true(row.answers[1]:IsShown()) -- BiS / Main / OS / Pass right on the row
    click(row.answers[1])
    Main.refresh()
    assert.matches("BiS", row.cells.mine:GetText())
    assert.is_false(row.answers[1]:IsShown())
    assert.is_true(row.change:IsShown())
    click(row.change)
    click(row.answers[3]) -- changed to OS
    Main.refresh()
    assert.are.equal("offspec", s:entryFor("Poohtank").response)
    assert.matches("OS", row.cells.mine:GetText())
  end)

  it("keeps the council pages when one page breaks on the live client", function()
    -- a template the client doesn't have: sliders fall back to text and the pages still build
    local create = _G.CreateFrame
    _G.CreateFrame = function(kind, ...)
      if kind == "Slider" then error("Couldn't find inherited node \"OptionsSliderTemplate\"") end
      return create(kind, ...)
    end
    local alpha = W.ns.Frames.alpha
    W.ns.Frames.alpha = function() error("settings broke") end -- and one page that really breaks
    W.slash("")
    local p = page("unlock")
    Main.go("loot")
    p.box:SetText(PASSWORD)
    click(p.go)
    _G.CreateFrame = create
    assert.is_true(Main.unlocked())
    assert.are.equal("raid", Main.current())
    assert.is_nil(page("raid").failText)
    assert.is_true(_G.ToadsLCMainFrame.navs.trades:IsShown())
    Main.go("settings")
    assert.matches("didn't load", page("settings").failText:GetText())
    assert.matches("Settings page failed", table.concat(W.printed, "\n"))
    W.ns.Frames.alpha = alpha
    Main.go("loot")
    assert.are.equal("loot", Main.current())
  end)
end)
