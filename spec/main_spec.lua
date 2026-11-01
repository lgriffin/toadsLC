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

  it("unlocks with Begin raid, locks again, and only reopens on the same password", function()
    Main.go("loot")
    local p = page("unlock")
    p.box:SetText("short")
    click(p.begin)
    assert.is_false(Main.unlocked())
    assert.matches("at least 6 characters", p.msg:GetText())
    p.box:SetText(PASSWORD)
    click(p.begin)
    assert.is_true(Main.unlocked())
    assert.are.equal("loot", Main.current())
    assert.is_not_nil(W.ns.App.secret()) -- the same password /tlc begin sets

    click(_G.ToadsLCMainFrame.lockBtn)
    assert.is_false(Main.unlocked())
    assert.are.equal("rolls", Main.current())
    assert.is_not_nil(W.ns.App.secret()) -- council traffic keeps working while the window is locked
    Main.go("loot")
    p.box:SetText("wrong-password")
    click(p.unlock)
    assert.is_false(Main.unlocked())
    assert.matches("isn't the password", p.msg:GetText())
    p.box:SetText(PASSWORD)
    click(p.unlock)
    assert.is_true(Main.unlocked())
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
      assert.matches("waiting to announce", row.cells.status:GetText())
      assert.matches("2h 00m", row.cells.trade:GetText())
      assert.matches("^%d%d:%d%d$", row.cells.dropped:GetText())
      W.tick(5400)
      Main.refresh()
      assert.matches("|cffe0b04f30m", row.cells.trade:GetText()) -- half an hour left: amber
      W.tick(1800)
      Main.refresh()
      assert.matches("expired", row.cells.trade:GetText())
    end)

    it("announces one item from its row, and all of them with Announce all", function()
      W.slash("loot add [Dragonspine Trophy]")
      Main.refresh()
      local p = page("loot").listView
      assert.is_true(p.all:IsShown())
      click(row1().announce)
      assert.matches("Loot session: .*Item 28830", W.chatText())
      Main.refresh()
      assert.matches("awaiting rolls: 0 in", row1().cells.status:GetText())
      W.ns.App.closeLast()
      click(p.all) -- the second copy, still waiting
      Main.refresh()
      assert.matches("awaiting rolls", page("loot").listView.list.rows[2].cells.status:GetText())
    end)

    it("opens an item to show its answers, who voted and who is still to vote", function()
      click(row1().announce)
      local s = W.ns.App.registry:latest()
      W.ns.App.respond(s.id, "main")
      W.fire("CHAT_MSG_SYSTEM", "Poohtank rolls 80 (1-100)")
      W.ns.App.close(s.id)
      Main.refresh()
      assert.matches("missing votes", row1().cells.status:GetText())

      click(row1()) -- into the item
      local d = page("loot").detailView
      assert.is_true(d:IsShown())
      assert.matches("Still to vote: Poohtank", d.votes:GetText())
      local cand = d.list.rows[1]
      assert.matches("Poohtank", cand.cells.name:GetText())
      assert.are.equal("80", cand.cells.roll:GetText())
      cand.scripts.OnClick(cand, "LeftButton") -- a click votes
      Main.refresh()
      assert.matches("Voted: Poohtank %(Poohtank%)", d.votes:GetText())
      assert.is_true(d.award:IsShown())
      click(d.award)
      Main.refresh()
      assert.are.equal("Poohtank", s.awardedTo)
      assert.is_true(d.undo:IsShown())
      click(d.back)
      assert.matches("awarded to Poohtank", row1().cells.status:GetText())
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

  it("hides pages whose feature isn't installed", function()
    W.slash("begin " .. PASSWORD)
    W.slash("")
    assert.is_false(_G.ToadsLCMainFrame.navs.mule:IsShown())
    Main.go("mule")
    assert.are.equal("loot", Main.current())
    assert.is_false(page("raid").versions:IsShown())
  end)
end)
