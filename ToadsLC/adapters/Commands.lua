-- Commands: /tlc slash commands.
local _, ns = ...

local Commands = {}
ns.Commands = Commands

local HELP = {
  "/tlc begin <password>  raid leader: protect council traffic with a password for tonight",
  "/tlc join <password>  officer: join the raid's protected council traffic",
  "/tlc end  forget the raid password",
  "/tlc session <item> [seconds]  open a loot session for the council",
  "/tlc roll <item> [seconds]  plain priority roll in raid chat",
  "/tlc loot  the raid's loot list: what dropped, waiting for the council",
  "/tlc loot <n> [seconds] | /tlc loot next  open a council session for item n (or the next waiting one)",
  "/tlc loot all [seconds]  open every item still to hand out at once; raiders answer each in one window",
  "/tlc loot roll <n> [seconds]  plain priority roll for item n",
  "/tlc loot announce | list | add <item> | remove <n> | clear | auto on|off",
  "/tlc loot party on|off  practise in a 5-man: record party drops too (rare and up) when you lead",
  "/tlc trade  what is still to trade to the winners; a trade with one puts their items in by itself",
  "/tlc trade done <name> | on | off  mark a winner's items handed over; turn the trade filling on or off",
  "/tlc announce  the raid chat lines for awards and trades; /tlc announce award|trade on | off | reset | <text>",
  "/tlc award [name] [reason]  award the last session (default: what the list says)",
  "/tlc close  close responses on the last session",
  "/tlc reroll  re-roll the tied names on the last session",
  "/tlc undo  reopen the last award",
  "/tlc council  show the council frame",
  "/tlc import | /tlc import undo",
  "/tlc export | /tlc export all | /tlc export clear",
  "/tlc sim [boss | raid | item] [seconds]  practice solo or in a party: fake a boss kill and a raid answering it",
  "/tlc sim drop [boss | raid | item]  fake a kill whose drops only go on the loot list",
  "/tlc sim stop  stop the simulation and clear its sessions",
  "/tlc status | /tlc history | /tlc tooltip on|off",
  "/tlc scale <0.5-2> | reset  make every Toads LC window bigger or smaller; reset puts them back",
  "  (drag a window's bottom-right corner to resize it; sizes and places are kept per character)",
  "/tlc debug [item]  why the tooltip does or doesn't show priorities",
}

local function words(msg)
  local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
  return (cmd or ""):lower(), rest or ""
end

-- "<item link or name> [seconds]"
local function itemAndSeconds(rest)
  local seconds = tonumber(rest:match("%s(%d+)$"))
  if seconds then rest = rest:gsub("%s%d+$", "") end
  return rest, seconds
end

local handlers = {}

function handlers.session(rest)
  local item, seconds = itemAndSeconds(rest)
  ns.App.open(item, seconds, "session")
end

function handlers.roll(rest)
  local item, seconds = itemAndSeconds(rest)
  ns.App.open(item, seconds, "roll")
end

function handlers.loot(rest)
  local L = ns.Loot
  local sub, arg = words(rest)
  local n = tonumber(sub)
  if sub == "" then
    ns.Frames.showLoot()
  elseif n then
    L.start(n, "session", tonumber(arg))
  elseif sub == "next" then
    L.startNext("session", tonumber(arg))
  elseif sub == "all" then
    L.startAll(tonumber(arg))
  elseif sub == "roll" then
    local which, seconds = words(arg)
    if which == "" or which == "next" then L.startNext("roll", tonumber(seconds))
    else L.start(tonumber(which) or which, "roll", tonumber(seconds)) end
  elseif sub == "add" then
    L.add(arg)
  elseif sub == "remove" then
    L.remove(tonumber(arg) or arg)
  elseif sub == "announce" then
    L.announce()
  elseif sub == "list" then
    L.print()
  elseif sub == "clear" then
    L.clear()
  elseif sub == "auto" then
    local st = ns.Store.settings()
    if arg == "on" then st.lootAuto = true elseif arg == "off" then st.lootAuto = false else st.lootAuto = not st.lootAuto end
    ns.Chat.print("Recording raid drops on the loot list " .. (st.lootAuto and "on" or "off") .. ".")
  elseif sub == "party" then
    local st = ns.Store.settings()
    if arg == "on" then st.lootParty = true elseif arg == "off" then st.lootParty = false else st.lootParty = not st.lootParty end
    ns.Chat.print(st.lootParty and "Recording party drops too, rare and up, for practice in a 5-man. /tlc loot party off to stop."
      or "Recording drops in raids only.")
    if st.lootParty and st.lootAuto == false then
      ns.Chat.print("Recording corpses is off, so nothing is recorded yet: /tlc loot auto on.")
    end
  else
    ns.Chat.print("Usage: /tlc loot [n | next | all | roll <n> | announce | list | add <item> | remove <n> | clear | auto on|off | party on|off]")
  end
end

function handlers.trade(rest)
  local sub, arg = words(rest)
  if sub == "" or sub == "list" then
    ns.Trade.print()
  elseif sub == "done" and arg ~= "" then
    ns.Trade.done(arg)
  elseif sub == "on" or sub == "off" then
    ns.Store.settings().autoTrade = sub == "on"
    ns.Chat.print("Putting awarded items into trades " .. sub .. ".")
  else
    ns.Chat.print("Usage: /tlc trade [done <name> | on | off]")
  end
end

-- /tlc announce [award | trade] [on | off | reset | <text>]
local ANNOUNCE = {
  award = { toggle = "announceAward", text = "awardMessage", default = "AWARD_TEMPLATE", what = "Awards" },
  trade = { toggle = "announceTrade", text = "tradeMessage", default = "TRADE_TEMPLATE", what = "Trades" },
}

local function sample(which, text)
  local S = ns.Session
  local fields = { item = "[Dragonspine Trophy]", name = "Anasazi", details = "Rogue, tier 1, rolled 87",
                   response = "BiS", spec = "Rogue", tier = 1, roll = 87, by = ns.Roster.me() }
  return S.fill(text or S[ANNOUNCE[which].default], fields)
end

local function showAnnounce()
  local set, S = ns.Store.settings(), ns.Session
  for _, which in ipairs({ "award", "trade" }) do
    local a = ANNOUNCE[which]
    local text = set[a.text] or S[a.default]
    ns.Chat.print(string.format("%s in raid chat: %s%s. %s", a.what, set[a.toggle] == false and "off" or "on",
      set[a.text] and "" or " (default wording)", text))
    ns.Chat.print("  e.g. " .. sample(which, text))
  end
  ns.Chat.print("Placeholders: {" .. table.concat(S.PLACEHOLDERS, "}, {") .. "} ({by} is who traded it).")
  ns.Chat.print("Change with /tlc announce award|trade <text>, on, off or reset.")
end

function handlers.announce(rest)
  local which, arg = words(rest)
  local a = ANNOUNCE[which]
  if which == "" then return showAnnounce() end
  if not a then
    ns.Chat.print("Usage: /tlc announce [award | trade] [on | off | reset | <text with {item} {name} ...>]")
    return
  end
  local set, lower = ns.Store.settings(), arg:lower()
  if lower == "on" or lower == "off" then
    set[a.toggle] = lower == "on"
    ns.Chat.print(a.what .. " announced in raid chat: " .. lower .. ".")
  elseif lower == "reset" then
    set[a.text] = nil
    ns.Chat.print(a.what .. " back to the default wording: " .. sample(which))
  elseif arg == "" then
    showAnnounce()
  else
    set[a.text] = arg
    set[a.toggle] = true
    ns.Chat.print(a.what .. " will read: " .. sample(which, arg))
  end
end

function handlers.award(rest)
  local name, reason = rest:match("^(%S+)%s*(.*)$")
  ns.App.awardLast(name, reason)
end

function handlers.close() ns.App.closeLast() end
function handlers.reroll() ns.App.rerollLast() end
function handlers.undo() ns.App.undoLast() end

function handlers.council()
  if not ns.Frames.showCouncil() then ns.Chat.print("No council session to show.") end
end

function handlers.import(rest)
  if rest:lower() == "undo" then ns.App.undoImport() else ns.Frames.showImport() end
end

function handlers.export(rest)
  rest = rest:lower()
  if rest == "clear" then ns.App.exportClear() else ns.App.export(rest == "all") end
end

function handlers.sim(rest)
  if rest:lower() == "stop" then ns.Sim.stop(); return end
  local sub, kill = words(rest)
  if sub == "drop" then ns.Sim.drop(kill); return end
  local query, seconds = itemAndSeconds(rest)
  if tonumber(query) and tonumber(query) < 1000 then query, seconds = "", tonumber(query) end -- "/tlc sim 20"
  ns.Sim.start(query, seconds)
end

-- the password is taken as typed (spaces included), never echoed back
function handlers.begin(rest) ns.App.beginRaid(rest) end
function handlers.join(rest) ns.App.joinRaid(rest) end
handlers["end"] = function() ns.App.endRaid() end

function handlers.status() ns.App.status() end
function handlers.history() ns.App.history() end
function handlers.debug(rest) ns.App.debug(rest) end

function handlers.tooltip(rest)
  local s = ns.Store.settings()
  if rest == "on" then s.tooltip = true elseif rest == "off" then s.tooltip = false else s.tooltip = not s.tooltip end
  ns.Chat.print("Tooltip priorities " .. (s.tooltip and "on" or "off") .. ".")
end

function handlers.scale(rest)
  rest = rest:lower()
  if rest == "reset" then
    ns.Frames.resetLayout()
    ns.Chat.print("Windows back to their default size, place and scale.")
    return
  end
  local n = tonumber(rest)
  if n and n >= 0.5 and n <= 2 then
    ns.Frames.setScale(n)
    ns.Chat.print(string.format("Window scale %.2f.", n))
  else
    ns.Chat.print(string.format("Window scale is %.2f. Usage: /tlc scale <0.5-2> | reset. "
      .. "Drag a window's bottom-right corner to resize it.", ns.Frames.scale()))
  end
end

function handlers.help()
  for _, line in ipairs(HELP) do ns.Chat.print(line) end
end

function Commands.init()
  SLASH_TOADSLC1 = "/tlc"
  SLASH_TOADSLC2 = "/toadslc"
  SlashCmdList.TOADSLC = function(msg)
    local cmd, rest = words(msg or "")
    local fn = handlers[cmd] or handlers.help
    fn(rest)
  end
end
