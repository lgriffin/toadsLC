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
