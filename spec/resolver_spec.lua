local H = require("spec.helper")

describe("Resolver", function()
  local ns, R, item, rules
  before_each(function()
    ns = H.core()
    R = ns.Resolver
    local doc = assert(ns.Codec.decode(H.read("fixtures/priority.sample.json")))
    item, rules = doc.items[1], doc.rules
  end)

  local function e(player, class, spec, roll, max) return { player = player, class = class, spec = spec, roll = roll, max = max or 100 } end

  it("a mage in tier 1 beats a warlock in tier 2 regardless of numbers: Anasazi 41 beats Gally 97", function()
    local r = R.resolve(item, { e("Gally", "Warrior", "Warrior:Fury", 97), e("Anasazi", "Rogue", "Rogue:Combat", 41) }, rules)
    assert.are.equal("Anasazi", r.winner.player)
    assert.are.equal("priority", r.by)
    assert.are.equal(1, r.ranked[1].tier)
    assert.are.equal(2, r.ranked[2].tier)
  end)

  it("a main-spec roll always beats an off-spec roll: Poohtank's off-spec 94 loses to Hadur's main-spec 88", function()
    local r = R.resolve(item, { e("Poohtank", "Paladin", "Paladin:Protection", 94, 99), e("Hadur", "Shaman", "Shaman:Enhancement", 88) }, rules)
    assert.are.equal("Hadur", r.winner.player)
    assert.is_true(r.ranked[2].offspec)
  end)

  it("BiS trumps Upgrade whatever the tier: Gally's tier 2 BiS 12 beats Anasazi's tier 1 Upgrade 97", function()
    local gally = e("Gally", "Warrior", "Warrior:Fury", 12)
    gally.response = "bis"
    local anasazi = e("Anasazi", "Rogue", "Rogue:Combat", 97)
    anasazi.response = "main"
    local r = R.resolve(item, { anasazi, gally }, rules)
    assert.are.equal("Gally", r.winner.player)
    assert.is_true(r.ranked[1].bis)
    assert.is_false(r.ranked[2].bis)
  end)

  it("puts BiS above Upgrade on an item that isn't on the list too", function()
    local low = e("Gally", "Warrior", "Warrior:Fury", 1)
    low.response = "bis"
    local r = R.resolve({ priority = {} }, { e("Anasazi", "Rogue", "Rogue:Combat", 100), low }, rules)
    assert.are.equal("Gally", r.winner.player)
    assert.is_false(r.tie)
  end)

  it("ranks two BiS rolls by tier then roll, and never lifts an off-spec roll", function()
    local function bis(...) local x = e(...); x.response = "bis"; return x end
    local r = R.resolve(item, { bis("Gally", "Warrior", "Warrior:Fury", 99), bis("Anasazi", "Rogue", "Rogue:Combat", 3),
                                bis("Poohtank", "Paladin", "Paladin:Protection", 98, 99) }, rules)
    assert.are.same({ "Anasazi", "Gally", "Poohtank" }, { r.ranked[1].player, r.ranked[2].player, r.ranked[3].player })
    assert.is_false(r.ranked[3].bis)
  end)

  it("When every response is off-spec, shows two list-says rows and awards neither", function()
    local r = R.resolve(item, { e("Poohtank", "Paladin", "Paladin:Protection", 94, 99), e("Gally", "Warrior", "Warrior:Fury", 12, 99) }, rules)
    assert.is_true(r.allOffspec)
    assert.is_nil(r.winner)
    assert.are.equal("Gally", r.ranked[1].player) -- by priority (Fury is tier 2)
    assert.are.equal("Poohtank", r.highestRoll.player)
  end)

  it("follows allOffspecMode highest and priority", function()
    local entries = { e("Poohtank", "Paladin", "Paladin:Protection", 94, 99), e("Gally", "Warrior", "Warrior:Fury", 12, 99) }
    local r = R.resolve(item, entries, { allOffspecMode = "highest" })
    assert.are.equal("Poohtank", r.winner.player)
    assert.are.equal("highest-roll", r.by)
    r = R.resolve(item, entries, { allOffspecMode = "priority" })
    assert.are.equal("Gally", r.winner.player)
    assert.are.equal("priority", r.by)
  end)

  it("flags a tie on tier and roll", function()
    local r = R.resolve(item, { e("Anasazi", "Rogue", "Rogue:Combat", 50), e("Hunt", "Hunter", "Hunter:BeastMastery", 50), e("Gally", "Warrior", "Warrior:Fury", 99) }, rules)
    assert.is_true(r.tie)
    assert.are.same({ "Anasazi", "Hunt" }, r.tied)
  end)

  it("reports nobody rolling", function()
    local r = R.resolve(item, {}, rules)
    assert.are.equal("none", r.by)
    assert.is_nil(r.winner)
  end)

  it("ranks an item not in the list by highest roll", function()
    local r = R.resolve(nil, { e("A", "Mage", "Mage:Fire", 20), e("B", "Rogue", "Rogue:Combat", 70) }, rules)
    assert.are.equal("B", r.winner.player)
    assert.is_nil(r.winner.tier)
  end)

  it("skips ignored entries and puts unlisted specs last", function()
    local dup = e("Anasazi", "Rogue", "Rogue:Combat", 99)
    dup.ignored = "duplicate"
    local r = R.resolve(item, { dup, e("Poohtank", "Paladin", "Paladin:Protection", 100), e("Hadur", "Shaman", "Shaman:Enhancement", 2) }, rules)
    assert.are.equal("Hadur", r.winner.player)
    assert.are.equal(2, #r.ranked)
  end)
end)
