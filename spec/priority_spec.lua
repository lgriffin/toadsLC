local H = require("spec.helper")

describe("Priority", function()
  local ns, P, Codec, item
  before_each(function()
    ns = H.core()
    P, Codec = ns.Priority, ns.Codec
    item = assert(Codec.decode(H.read("fixtures/priority.sample.json"))).items[1]
  end)

  local function entry(player, class, spec) return { player = player, class = class, spec = spec } end

  describe("matching", function()
    it("matches every token kind", function()
      local rogue = entry("Anasazi", "Rogue", "Rogue:Combat")
      assert.is_true(P.matches({ spec = "Rogue:Combat" }, rogue))
      assert.is_true(P.matches({ spec = "Rogue:*" }, rogue))
      assert.is_true(P.matches({ spec = "ROLE:Melee" }, rogue))
      assert.is_true(P.matches({ spec = "ANY" }, rogue))
      assert.is_true(P.matches({ player = "anasazi-Spineshatter" }, rogue))
      assert.is_false(P.matches({ spec = "Rogue:Subtlety" }, rogue))
      assert.is_false(P.matches({ spec = "ROLE:Healer" }, rogue))
      assert.is_true(P.matches({ spec = "Warrior:DPS" }, entry("Gally", "Warrior", "Warrior:Fury")))
      assert.is_false(P.matches({ spec = "Warrior:DPS" }, entry("Tank", "Warrior", "Warrior:Protection")))
      assert.is_true(P.matches({ spec = "ROLE:Healer" }, entry("Moo", "Druid", "Druid:Restoration")))
    end)

    it("matches an unknown spec on Class:* only", function()
      local unknown = entry("Hadur", "Shaman", nil)
      assert.is_true(P.matches({ spec = "Shaman:*" }, unknown))
      assert.is_false(P.matches({ spec = "Shaman:Enhancement" }, unknown))
      assert.is_false(P.matches({ spec = "ROLE:Melee" }, unknown))
    end)

    it("walks tiers in order and keeps ANY for everyone else", function()
      assert.are.equal(1, P.tierOf(item, entry("Anasazi", "Rogue", "Rogue:Combat")))
      assert.are.equal(2, P.tierOf(item, entry("Gally", "Warrior", "Warrior:Fury")))
      assert.are.equal(4, P.tierOf(item, entry("Hadur", "Shaman", "Shaman:Enhancement")))
      assert.is_nil(P.tierOf(item, entry("Poohtank", "Paladin", "Paladin:Protection")))
      local list = { priority = { { { spec = "ANY" } }, { { player = "Tajt" } } } }
      assert.are.equal(2, P.tierOf(list, entry("Tajt", "Monk", nil)))
      assert.are.equal(1, P.tierOf(list, entry("Bob", "Mage", "Mage:Fire")))
    end)
  end)

  describe("sheet wording", function()
    it("parses > into tiers and = within a tier", function()
      local tiers = assert(P.parseText(item.priorityText))
      assert.are.equal(Codec.encode(item.priority), Codec.encode(tiers))
    end)

    it("parses roles, ANY and named players", function()
      local tiers = assert(P.parseText("Tajt (MW) > Prot Pally = Feral > Healers > Everyone else"))
      assert.are.same({ { { player = "Tajt" } }, { { spec = "Paladin:Protection" }, { spec = "Druid:Feral-Tank" } },
                        { { spec = "ROLE:Healer" } }, { { spec = "ANY" } } }, tiers)
    end)

    it("names the word it does not know", function()
      local v, err = P.parseText("Rogue > Tinkers")
      assert.is_nil(v)
      assert.are.equal('"Tinkers" is not a known token', err)
    end)
  end)

  describe("tooltip text", function()
    it("uses the guild's own wording when it lines up with the tiers", function()
      local tiers = P.tiers(item)
      assert.are.equal(6, #tiers)
      assert.are.equal("BM Hunter", tiers[1][1].label)
      assert.are.equal("Hunter", tiers[1][1].class)
      assert.are.equal("Rogue", tiers[1][2].label)
      assert.are.equal("BM Hunter = Rogue > Fury > Arms > Enhance = Ret > Surv Hunter > Kitty", P.text(item))
    end)

    it("falls back to generated labels, with no class colour for roles", function()
      local tiers = P.tiers({ priority = { { { spec = "Paladin:Protection" } }, { { spec = "ROLE:Healer" }, { spec = "ANY" } } } })
      assert.are.equal("Prot Pally", tiers[1][1].label)
      assert.are.equal("Healers", tiers[2][1].label)
      assert.is_nil(tiers[2][1].class)
      assert.are.equal("Everyone else", tiers[2][2].label)
    end)
  end)

  describe("lookup", function()
    it("The addon shall store priorities keyed by item ID and fall back to a name match only for items whose ID is unknown", function()
      local doc = assert(Codec.decode(H.read("fixtures/priority.sample.json")))
      doc.items[2] = { name = "Twinblade of the Phoenix", priority = { { { player = "Tajt" } } } }
      local db = P.index(doc, "Poohtank", 0)
      assert.are.equal("Dragonspine Trophy", P.lookup(db, 28830).name)
      assert.are.equal("Dragonspine Trophy", P.lookup(db, nil, "dragonspine trophy").name)
      assert.is_nil(P.lookup(db, 99999, "Dragonspine Trophy")) -- a known name with a different ID
      assert.are.equal("Twinblade of the Phoenix", P.lookup(db, 29993, "Twinblade of the Phoenix").name)
      assert.is_nil(P.lookup(db, 1, "Something else"))
      assert.are.equal(2, db.count)
    end)
  end)
end)
