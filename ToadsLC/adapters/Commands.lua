-- Commands: /tlc slash commands.
local _, ns = ...

local Commands = {}
ns.Commands = Commands

local HELP = {
  "/tlc session <item> [seconds]  open a loot session for the council",
  "/tlc roll <item> [seconds]  plain priority roll in raid chat",
  "/tlc award [name] [reason]  award the last session (default: what the list says)",
  "/tlc close  close responses on the last session",
  "/tlc reroll  re-roll the tied names on the last session",
  "/tlc undo  reopen the last award",
  "/tlc council  show the council frame",
  "/tlc import | /tlc import undo",
  "/tlc export | /tlc export all | /tlc export clear",
  "/tlc status | /tlc history | /tlc tooltip on|off",
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

function handlers.status() ns.App.status() end
function handlers.history() ns.App.history() end

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
