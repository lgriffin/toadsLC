-- Raid chat announcements for awards and trades, and the loot master's own wording for them.
local H = require("spec.helper")
local W = require("spec.wow_mock")

local sample = H.read("fixtures/priority.sample.json")
local GRUUL = "Creature-0-1-565-1-19044-1"
local CORPSE = {
  { 28830, "Dragonspine Trophy", 4, GRUUL },
  { 29765, "Leggings of the Fallen Hero", 4, GRUUL },
}

describe("filling an announcement", function()
  local fill

  before_each(function()
    W.install({})
    W.load()
    fill = W.ns.Session.fill
  end)

  it("puts the fields in, case-insensitively, and leaves unknown words alone", function()
    assert.are.equal("Gally wins [Leggings] {grats}",
      fill("{NAME} wins {item} {grats}", { name = "Gally", item = "[Leggings]" }))
  end)

  it("drops empty placeholders and the brackets and spaces they leave", function()
    assert.are.equal("[ToadsLC] [Leggings] awarded to Gally.",
      fill("[ToadsLC] {item} awarded to {name} ({details}).", { item = "[Leggings]", name = "Gally" }))
    assert.are.equal("Gally: [Leggings]", fill("{name}: {item} [{roll}]", { item = "[Leggings]", name = "Gally" }))
  end)

  it("drops a bracketed part whose placeholder is empty, words and all", function()
    local t = "Grats {name} on {item} ({response}, rolled {roll})!"
    assert.are.equal("Grats Gally on [Leggings] (BiS)!",
      fill(t, { item = "[Leggings]", name = "Gally", response = "BiS" }))
    assert.are.equal("Grats Gally on [Leggings] (BiS, rolled 41)!",
      fill(t, { item = "[Leggings]", name = "Gally", response = "BiS", roll = 41 }))
    assert.are.equal("Grats Gally on [Leggings]!", fill(t, { item = "[Leggings]", name = "Gally" }))
  end)
end)

describe("announcing awards and trades in a fake client", function()
  local function chat() return W.chatText() end

  before_each(function()
    W.install({ bags = { [0] = { [1] = { 28830 }, [2] = { 29765 } } } })
    W.load()
    W.fire("PLAYER_LOGIN")
    W.ns.App.import(sample)
    W.loot(CORPSE)
  end)

  local function award(n, name)
    W.slash("loot roll " .. n .. " 30")
    W.fire("CHAT_MSG_SYSTEM", name .. " rolls 41 (1-100)")
    W.tick(31)
    W.slash("award " .. name)
  end

  it("posts the award by default, and the trade once it completes", function()
    award(1, "Anasazi")
    assert.matches("RAID_WARNING: %[ToadsLC%] .*%[Dragonspine Trophy%].* awarded to Anasazi %(Rogue, tier 1, rolled 41%)%.",
      chat())
    W.trade("Anasazi")
    W.endTrade(true)
    assert.matches("RAID: %[ToadsLC%] .*%[Item 28830%].* traded to Anasazi%.", chat())
  end)

  it("uses the loot master's wording, and goes quiet when turned off", function()
    W.slash("announce award Grats {name} on {item} ({response}, {roll})!")
    assert.matches("Awards will read: Grats Anasazi on %[Dragonspine Trophy%] %(BiS, 87%)!", W.printed[#W.printed])
    W.slash("announce trade {name} has {item} now, from {by}")
    award(1, "Anasazi")
    assert.matches("Grats Anasazi on .*Dragonspine Trophy.*%(Upgrade, 41%)!", chat())
    W.trade("Anasazi")
    W.endTrade(true)
    assert.matches("Anasazi has .*%[Item 28830%].* now, from " .. W.ns.Roster.me(), chat())

    W.slash("announce award off")
    W.slash("announce trade off")
    local before = #W.chat
    award(2, "Gally")
    assert.is_nil(chat():find("Gally on", 1, true))
    W.trade("Gally")
    W.endTrade(true)
    for i = before + 1, #W.chat do assert.is_nil(W.chat[i].text:find("Gally has", 1, true)) end
  end)

  it("calls an off-spec button press off-spec when it is awarded before a roll", function()
    W.slash("loot 1 30")
    local s = W.ns.App.registry:latest()
    -- what the leader holds after Anasazi presses OffSpec and before any roll
    s.candidates[#s.candidates + 1] = { player = "Anasazi", class = "ROGUE", response = "offspec", note = "" }
    s.live[W.ns.Priority.nameKey("Anasazi")] = #s.candidates
    s.awardedTo = "Anasazi"
    local f = s:awardFields()
    assert.are.equal("OffSpec", f.response)
    assert.are.equal("OffSpec", f.details)
    assert.is_nil(f.tier)
  end)

  it("keeps the item link from the trade window when the item cache has none", function()
    award(1, "Anasazi")
    _G.GetItemInfo = function() return nil end
    W.trade("Anasazi")
    W.endTrade(true)
    assert.matches("RAID: %[ToadsLC%] |c.-|Hitem:28830.-|h|r traded to Anasazi%.", W.chatText())
  end)

  it("shows the settings and goes back to the default wording", function()
    W.slash("announce award {name} gets {item}")
    W.slash("announce award reset")
    assert.matches("Awards back to the default wording: %[ToadsLC%] %[Dragonspine Trophy%] awarded to Anasazi",
      W.printed[#W.printed])
    W.slash("announce")
    local printed = table.concat(W.printed, "\n")
    assert.matches("Awards in raid chat: on %(default wording%)", printed)
    assert.matches("Trades in raid chat: on %(default wording%)", printed)
    assert.matches("Placeholders: {item}, {name}", printed)
  end)
end)
