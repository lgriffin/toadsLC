-- Chat: announcements to raid chat (RAID_WARNING for the open and the award when the
-- player has assist). Outside a raid it falls back to party, then to the chat frame.
local _, ns = ...

local Chat = {}
ns.Chat = Chat

local LIMIT = 250

function Chat.print(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33cc66[ToadsLC]|r " .. text)
end

-- split(text) -> lines under the 255-byte chat limit, broken on spaces
function Chat.split(text)
  local out = {}
  while #text > LIMIT do
    local cut = text:sub(1, LIMIT):match("^.*() ") or LIMIT
    out[#out + 1] = text:sub(1, cut - 1)
    text = text:sub(cut + 1)
  end
  out[#out + 1] = text
  return out
end

local function channel(warn)
  if IsInRaid() then
    if warn and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return "RAID_WARNING" end
    return ns.Store.settings().announceChannel or "RAID"
  end
  if IsInGroup() then return "PARTY" end
end

-- say(text, warn): warn also posts the first line as a raid warning.
function Chat.say(text, warn)
  local ch = channel(false)
  if not ch then
    Chat.print(text:gsub("^%[ToadsLC%] ", ""))
    return
  end
  for _, line in ipairs(Chat.split(text)) do SendChatMessage(line, ch) end
  if warn and channel(true) == "RAID_WARNING" then
    SendChatMessage(Chat.split(text)[1], "RAID_WARNING")
  end
end
