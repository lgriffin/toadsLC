-- /tlc version: the raid leader asks the group which Toads LC each member runs.
local W = require("spec.wow_mock")

local GROUP = {
  { name = "Poohtank", class = "PALADIN", leader = true },
  { name = "Anasazi", class = "ROGUE" }, { name = "Gally", class = "WARRIOR" },
  { name = "Hadur", class = "SHAMAN", assist = true }, { name = "Croaker", class = "HUNTER" },
  { name = "Sleepy", class = "MAGE", offline = true },
}

local function printed(c) return table.concat(c.printed, "\n") end

-- run the C_Timer.After callbacks queued so far
local function later(c)
  local fns = c.later
  c.later = {}
  for _, fn in ipairs(fns) do fn() end
end

describe("version helpers", function()
  local V
  before_each(function() V = W.client({ me = "Poohtank", group = GROUP }).ns.Version end)

  it("compares dotted versions by number", function()
    assert.are.equal(-1, V.compare("0.2.1", "0.2.10"))
    assert.are.equal(1, V.compare("0.3", "0.2.9"))
    assert.are.equal(0, V.compare("0.2", "0.2.0"))
    assert.are.equal(0, V.compare("v0.2.1", "0.2.1"))
    assert.are.equal(-1, V.compare("dev", "0.0.1"))
  end)

  it("sorts the group into newest, older, no answer and offline", function()
    local members = { { name = "A", online = true }, { name = "B", online = true }, { name = "C", online = true },
                      { name = "D", online = false }, { name = "Me", online = true } }
    local r = V.report(members, { a = "0.3.0", b = "0.2.0" }, "Me", "0.3.0")
    assert.are.equal("0.3.0", r.newest)
    assert.are.same({ "A", "Me" }, r.current)
    assert.are.same({ { name = "B", version = "0.2.0" } }, r.outdated)
    assert.are.same({ "C" }, r.missing)
    assert.are.same({ "D" }, r.offline)
  end)
end)

describe("/tlc version in a raid", function()
  local leader, officer, rogue, warrior, all

  before_each(function()
    leader = W.client({ me = "Poohtank", group = GROUP, version = "0.3.0" })
    officer = W.client({ me = "Hadur", group = GROUP, version = "0.3.0" })
    rogue = W.client({ me = "Anasazi", group = GROUP, version = "0.2.1" })
    warrior = W.client({ me = "Gally", group = GROUP, version = "0.3.0" })
    all = { leader, officer, rogue, warrior } -- Croaker has no addon, Sleepy is offline
    W.deliver(all)
    for _, c in ipairs(all) do c.printed, c.later = {}, {} end
  end)

  it("lists who is current, behind, missing and offline", function()
    leader:slash("version")
    W.deliver(all)
    later(leader)
    local out = printed(leader)
    assert.matches("4 of 6 in the group have Toads LC, 3 on the newest (0.3.0).", out, 1, true)
    assert.matches("Older version (1): Anasazi 0.2.1", out, 1, true)
    assert.matches("too old to answer (1): Croaker", out, 1, true)
    assert.matches("Offline (1): Sleepy", out, 1, true)
    local r = leader.ns.Version.last
    assert.are.same({ "Gally", "Hadur", "Poohtank" }, r.current)
  end)

  it("answers by whisper, never in raid chat", function()
    leader:slash("version")
    local sent = W.deliver(all)
    local whispers = 0
    for _, d in ipairs(sent) do
      if d.from ~= leader then
        assert.are.equal("WHISPER", d.msg.dist)
        assert.are.equal("Poohtank", d.msg.target)
        whispers = whispers + 1
      end
    end
    assert.are.equal(3, whispers)
    assert.are.same({}, leader.chat)
  end)

  it("tells a raider on an older version once", function()
    leader:slash("version")
    W.deliver(all)
    assert.matches("A newer Toads LC is out: Poohtank has 0.3.0, you have 0.2.1.", printed(rogue), 1, true)
    rogue.printed = {}
    leader:tick(10)
    officer:slash("version")
    W.deliver(all)
    assert.are.equal("", printed(rogue))
  end)

  it("works with a raid password, for raiders who don't hold it", function()
    leader:slash("begin hunter2pass")
    officer:slash("join hunter2pass")
    W.deliver(all)
    later(leader); later(officer)
    leader.printed = {}
    leader:slash("version")
    W.deliver(all)
    later(leader)
    assert.matches("4 of 6", printed(leader), 1, true)
  end)

  it("says so when the player is behind", function()
    rogue:slash("version")
    W.deliver(all)
    later(rogue)
    assert.matches("You have 0.2.1 yourself: update to 0.3.0.", printed(rogue), 1, true)
  end)

  it("does not answer the same asker twice in a few seconds", function()
    leader:slash("version")
    W.deliver(all)
    later(leader)
    leader:slash("version")
    local sent = W.deliver(all)
    local answers = 0
    for _, d in ipairs(sent) do if d.from ~= leader then answers = answers + 1 end end
    assert.are.equal(0, answers)
  end)
end)
