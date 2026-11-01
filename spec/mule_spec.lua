-- The loot mule: as master looter, greens and blues go straight to one player, while the
-- council's items (epics, anything on the priority list) stay on the corpse for the loot list.
local H = require("spec.helper")
local W = require("spec.wow_mock")

local sample = H.read("fixtures/priority.sample.json")
local GRUUL = "Creature-0-1-565-1-19044-1"

-- Dragonspine Trophy (epic, listed), a blue, a green, a grey, a blue quest item
local CORPSE = {
  { 28830, "Dragonspine Trophy", 4, GRUUL },
  { 28795, "Bladespire Warbands", 3, GRUUL },
  { 24000, "Some Green Bracers", 2, GRUUL },
  { 25000, "Broken Fang", 0, GRUUL },
  { 26000, "Quest Blue", 3, GRUUL, quest = true },
}

describe("the loot mule", function()
  local function printed() return table.concat(W.printed, "\n") end

  local function login(opts)
    W.install(opts or { lootMethod = "master" })
    W.load()
    W.fire("PLAYER_LOGIN")
    W.ns.App.import(sample)
  end

  before_each(function() login() end)

  it("is off until a mule is named, greens and blues by default", function()
    W.loot(CORPSE)
    assert.are.same({}, W.given)
    local name, list = W.ns.Mule.get()
    assert.is_nil(name)
    assert.are.same({ 2, 3 }, list)
  end)

  it("gives greens and blues to the mule and leaves the council's items", function()
    W.slash("mule Gally")
    W.loot(CORPSE)
    assert.are.same({ [2] = "Gally", [3] = "Gally" }, W.given)
    assert.matches("Muled to Gally: .*Bladespire Warbands.*Some Green Bracers", printed())
    -- the epic is on the loot list, not muled
    assert.are.equal(1, #W.ns.Loot.list.entries)
    assert.are.equal(28830, W.ns.Loot.list.entries[1].itemId)
  end)

  it("never mules an item on the priority list, whatever its rarity", function()
    W.slash("mule Gally")
    W.slash("mule quality green blue epic")
    W.loot({ { 28830, "Dragonspine Trophy", 4, GRUUL }, { 28795, "Bladespire Warbands", 3, GRUUL } })
    assert.is_nil(W.given[1])
    assert.are.equal("Gally", W.given[2])
  end)

  it("mules only the rarities chosen", function()
    W.slash("mule Gally")
    W.slash("mule quality greens")
    W.loot(CORPSE)
    assert.are.same({ [3] = "Gally" }, W.given)
    assert.matches("Muling green items", printed())
  end)

  it("leaves items below the loot threshold alone", function()
    login({ lootMethod = "master", lootThreshold = 3 })
    W.slash("mule Gally")
    W.loot(CORPSE)
    assert.are.same({ [2] = "Gally" }, W.given)
  end)

  it("does nothing unless this player is master looter", function()
    login({ lootMethod = "group" })
    W.slash("mule Gally")
    W.loot(CORPSE)
    assert.are.same({}, W.given)
    assert.matches("aren't master looter", printed())
  end)

  it("says so when the mule can't take the loot", function()
    W.slash("mule Gally")
    W.candidates = { "Poohtank", "Anasazi" }
    W.loot(CORPSE)
    assert.are.same({}, W.given)
    assert.matches("Gally can't take .*Bladespire Warbands", printed())
  end)

  it("turns off, keeps its settings over a reload, and takes a name case-insensitively", function()
    W.slash("mule gally")
    W.loot(CORPSE)
    assert.are.equal("Gally", W.given[2])
    local db = _G.ToadsLCDB
    login({ lootMethod = "master", db = db })
    assert.are.equal("Gally", (W.ns.Mule.get())) -- as the roster spells it
    W.slash("mule off")
    W.loot(CORPSE)
    assert.are.same({}, W.given)
  end)

  it("never gives a mule's loot to a namesake from another realm", function()
    W.slash("mule Gally-Firemaw")
    W.candidates = { "Poohtank", "Gally" } -- Gally of our realm, not the mule
    W.loot(CORPSE)
    assert.are.same({}, W.given)
    W.candidates = { "Gally", "Gally-Firemaw" }
    W.loot(CORPSE)
    assert.are.same({ [2] = "Gally-Firemaw", [3] = "Gally-Firemaw" }, W.given)
    W.given = {}
    W.slash("mule Gally-Spineshatter") -- our own realm: the client lists them bare
    W.candidates = { "Poohtank", "Gally" }
    W.loot(CORPSE)
    assert.are.same({ [2] = "Gally", [3] = "Gally" }, W.given)
  end)

  it("doesn't take a bare name for a player from another realm", function()
    W.slash("mule Gally")
    W.candidates = { "Poohtank", "Gally-Firemaw" }
    W.loot(CORPSE)
    assert.are.same({}, W.given)
  end)

  it("rejects an unknown rarity", function()
    W.slash("mule quality purple")
    assert.matches("Usage: /tlc mule quality", printed())
    local _, list = W.ns.Mule.get()
    assert.are.same({ 2, 3 }, list)
  end)
end)
