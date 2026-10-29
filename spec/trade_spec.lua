-- Trading awards: when whoever holds the loot opens a trade with a winner, what they won
-- goes into the window by itself, and is marked as handed over once the trade completes.
local H = require("spec.helper")
local W = require("spec.wow_mock")

local sample = H.read("fixtures/priority.sample.json")
local GRUUL = "Creature-0-1-565-1-19044-1"

local CORPSE = {
  { 28830, "Dragonspine Trophy", 4, GRUUL },
  { 29765, "Leggings of the Fallen Hero", 4, GRUUL },
  { 29765, "Leggings of the Fallen Hero", 4, GRUUL },
}

-- what the loot master looted off the corpse, plus something else
local function bags()
  return { [0] = { [1] = { 28830 }, [2] = { 29765 }, [5] = { 29765 }, [7] = { 22829, 5 } } }
end

-- award(n, name): start loot list item n as a roll, close it, and award it to name
-- c is W (the default client) or one made with W.client
local function award(c, n, name)
  local slash = c == W and W.slash or function(m) c:slash(m) end
  local tick = c == W and W.tick or function(t) c:tick(t) end
  slash("loot roll " .. n .. " 30")
  tick(31)
  slash("award " .. name)
end

describe("trading awards in a fake client", function()
  local function printed() return table.concat(W.printed, "\n") end
  local function slots() return W.tradeSlots end

  before_each(function()
    W.install({ bags = bags() })
    W.load()
    W.fire("PLAYER_LOGIN")
    W.ns.App.import(sample)
    W.loot(CORPSE)
  end)

  local function awardAll()
    award(W, 1, "Anasazi")
    award(W, 2, "Gally")
    award(W, 3, "Gally")
  end

  it("puts what the trade partner won into the window, and only that", function()
    awardAll()
    assert.matches("Dragonspine Trophy is in your bags: open a trade with Anasazi", printed())
    W.trade("Gally")
    assert.are.same({ 29765, 29765 }, slots())
    assert.matches("Trading Leggings of the Fallen Hero, Leggings of the Fallen Hero to Gally", printed())
    W.endTrade(true)
    assert.matches("Traded Leggings of the Fallen Hero, Leggings of the Fallen Hero to Gally%.", printed())
    W.trade("Anasazi")
    assert.are.same({ 28830 }, slots())
    W.endTrade(true)
    W.trade("Gally") -- already handed over: nothing goes in
    assert.are.same({}, slots())
    W.slash("trade")
    assert.matches("Nothing awarded tonight is waiting to be traded%.", W.printed[#W.printed])
  end)

  it("offers it again after a cancelled trade, and not after an undone award", function()
    award(W, 1, "Anasazi")
    W.trade("Anasazi")
    W.endTrade(false)
    W.trade("Anasazi")
    assert.are.same({ 28830 }, slots())
    W.endTrade(false)
    W.slash("undo")
    W.trade("Anasazi")
    assert.are.same({}, slots())
  end)

  it("says what is owed but not in the bags, and lists what is still to trade", function()
    awardAll()
    W.bags[0][1] = nil -- the trophy went to someone else's bags
    W.slash("trade")
    assert.matches("Anasazi: Dragonspine Trophy %(not in your bags%)", printed())
    assert.matches("Gally: Leggings of the Fallen Hero\n", printed())
    W.trade("Anasazi")
    assert.are.same({}, slots())
    assert.matches("Anasazi also won Dragonspine Trophy, which is not in your bags%.", printed())
  end)

  it("leaves the window alone when turned off, and takes a winner's items as handed over by hand", function()
    awardAll()
    W.slash("trade off")
    W.trade("Gally")
    assert.are.same({}, slots())
    W.endTrade(false)
    W.slash("trade on")
    W.slash("trade done Gally")
    assert.matches("Marked 2 items for Gally as handed over%.", printed())
    W.trade("Gally")
    assert.are.same({}, slots())
  end)

  it("remembers the awards and what was traded over a reload", function()
    awardAll()
    W.trade("Anasazi")
    W.endTrade(true)
    local db = _G.ToadsLCDB
    W.install({ db = db, bags = W.bags })
    _G.ToadsLCDB = db
    W.load()
    W.fire("PLAYER_LOGIN")
    W.trade("Anasazi")
    assert.are.same({}, slots())
    W.endTrade(false)
    W.trade("Gally")
    assert.are.same({ 29765, 29765 }, slots())
  end)

  it("leaves /tlc sim awards out", function()
    W.ns.App.registry:add({ id = "sim-1", phase = "done", itemId = 28830, itemName = "Dragonspine Trophy",
                           awardedTo = "Anasazi", openedAt = W.time })
    W.trade("Anasazi")
    assert.are.same({}, slots())
  end)
end)

describe("trading awards across a raid", function()
  local GROUP = {
    { name = "Poohtank", class = "PALADIN", leader = true },
    { name = "Anasazi", class = "ROGUE" }, { name = "Gally", class = "WARRIOR" },
    { name = "Hadur", class = "SHAMAN", assist = true },
  }

  it("lets the assist who looted hand out what the leader's session awarded", function()
    local leader = W.client({ me = "Poohtank", group = GROUP })
    local looter = W.client({ me = "Hadur", group = GROUP, bags = bags() })
    local all = { leader, looter }
    for _, c in ipairs(all) do c.ns.App.import(sample) end
    W.deliver(all)
    looter:loot(CORPSE)
    W.deliver(all)
    leader:slash("loot roll 1 30")
    W.deliver(all)
    W.tickAll(all, 31)
    W.deliver(all)
    leader:slash("award Anasazi")
    W.deliver(all)
    looter:trade("Anasazi")
    assert.are.same({ 28830 }, looter.tradeSlots)
    looter:endTrade(true)
    looter:trade("Anasazi")
    assert.are.same({}, looter.tradeSlots)
  end)
end)
