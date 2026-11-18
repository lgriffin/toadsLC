-- The addon on the WoW Forever client: the same raid night as raid_spec, on a client where
-- item calls live under C_Item, chat under C_ChatInfo, talents are a trait tree, tooltips
-- have no OnTooltipSetItem, and boss fights put chat into messaging lockdown.
local H = require("spec.helper")
local W = require("spec.wow_mock")

local sample = H.read("fixtures/priority.sample.json")
local DST = "|cffa335ee|Hitem:28830::::::::70:::::|h[Dragonspine Trophy]|h|r"

local GROUP = {
  { name = "Poohtank", class = "PALADIN", leader = true },
  { name = "Anasazi", class = "ROGUE", talents = { 15, 41, 5 } }, { name = "Gally", class = "WARRIOR" },
  { name = "Hadur", class = "SHAMAN", assist = true }, { name = "Croaker", class = "HUNTER" },
}

local function latest(c) return c.ns.App.registry:latest() end

describe("on the WoW Forever client", function()
  local leader, officer, rogue, warrior, hunter, all

  before_each(function()
    leader = W.client({ forever = true, me = "Poohtank", group = GROUP })
    officer = W.client({ forever = true, me = "Hadur", group = GROUP })
    rogue = W.client({ forever = true, me = "Anasazi", group = GROUP })
    warrior = W.client({ forever = true, me = "Gally", group = GROUP })
    hunter = W.client({ forever = true, me = "Croaker", group = GROUP })
    all = { leader, officer, rogue, warrior, hunter }
    for _, c in ipairs(all) do c.ns.App.import(sample) end
    W.deliver(all)
  end)

  it("loads and says which client it is on", function()
    assert.is_function(leader.env.SlashCmdList.TOADSLC)
    assert.is_true(leader.ns.Client.isForever())
    leader:slash("debug")
    assert.matches("interface 16001, project 18 %(WoW Forever%)", leader:printedText())
  end)

  it("carries a council session from open to award, announced in raid chat", function()
    leader:slash("session " .. DST .. " 30")
    W.deliver(all)
    local s = latest(leader)
    assert.is_truthy(latest(rogue), "the raider never saw the session")
    rogue.ns.App.respond(s.id, "main")
    warrior.ns.App.respond(s.id, "main")
    W.deliver(all)
    W.tickAll(all, 31)
    W.deliver(all)
    assert.are.equal("voting", s.phase)
    assert.are.equal("Anasazi", s.computedWinner)
    leader:slash("award")
    W.deliver(all)
    for _, c in ipairs(all) do assert.are.equal("Anasazi", latest(c).awardedTo, c.me) end
    assert.matches("Anasazi", leader.chat[#leader.chat - 1].text)
    assert.are.equal("Anasazi", leader.chat[#leader.chat].target)
  end)

  it("holds addon messages and raid chat during a boss fight and sends them after", function()
    for _, c in ipairs(all) do c.lockdown = true end
    leader:slash("session " .. DST .. " 30")
    W.deliver(all)
    assert.is_nil(latest(rogue), "nothing reaches the raid mid-fight")
    assert.is_true(leader.ns.Comms.pending() > 0, "the session waits in the queue")
    local said, held = #leader.chat, #leader.ns.Chat.held
    leader.ns.Chat.say("[ToadsLC] after the pull")
    assert.are.equal(said, #leader.chat, "no chat sends mid-fight")
    assert.are.equal(held + 1, #leader.ns.Chat.held)

    for _, c in ipairs(all) do c.lockdown = false end
    W.tickAll(all, 1) -- the retry wait after the refused send
    W.deliver(all)
    assert.are.equal(latest(leader).id, latest(rogue).id)
    leader.ns.Chat.flush()
    assert.are.equal(0, #leader.ns.Chat.held)
    assert.are.equal("after the pull", leader.chat[#leader.chat].text:gsub("^%[ToadsLC%] ", ""))
  end)

  it("ignores system chat it can't read mid-fight", function()
    leader:slash("roll " .. DST)
    assert.has_no.errors(function() leader:fire("CHAT_MSG_SYSTEM", { secret = true }) end)
    leader:slash("debug")
    assert.matches("System chat hidden by the client: 1 lines", leader:printedText())
  end)

  it("reads specs from the trait tree, its own and inspected", function()
    local c = W.client({ forever = true, me = "Anasazi", group = GROUP })
    assert.are.equal("Rogue:Combat", c.ns.Roster.who("Anasazi").spec)

    local lead = W.client({ forever = true, me = "Poohtank", canInspect = true, group = GROUP })
    lead.ns.Roster.queueInspect({ "Anasazi" })
    for f in pairs(lead.eventFrames) do
      if f.events.INSPECT_READY and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 2) end
    end
    lead:fire("INSPECT_READY", "Player-Anasazi")
    assert.are.equal("Rogue:Combat", lead.ns.Roster.who("Anasazi").spec)
  end)

  it("puts the priorities on item tooltips through TooltipDataProcessor", function()
    local tt = leader.env.GameTooltip
    assert.is_nil(tt.hooks and tt.hooks.OnTooltipSetItem)
    tt.GetItem = function() return "Dragonspine Trophy", nil end
    leader.tooltipPostCalls[1].fn(tt, { id = 28830 })
    assert.are.equal(8, #tt.lines)
  end)
end)
