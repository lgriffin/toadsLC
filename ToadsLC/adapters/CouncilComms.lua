-- CouncilComms: addon messages with prefix ToadsLC. Messages are JSON split into chunks
-- (Codec.wireChunks) and sent through a small throttled queue; incoming chunks are
-- reassembled per sender and handed to the registry.
local _, ns = ...

local Comms = {}
ns.Comms = Comms

local Codec = ns.Codec
local PREFIX = "ToadsLC"
local PER_SECOND = 8

local queue, seq = {}, 0
local asm = Codec.newAssembler(function() return GetTime() end)
local frame = CreateFrame("Frame")

local function groupChannel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

function Comms.init(onMessage)
  Comms.onMessage = onMessage
  local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
  register(PREFIX)
  frame:RegisterEvent("CHAT_MSG_ADDON")
end

local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage

-- send(outs): outs as returned by the registry: { msg, dist = "RAID" | "WHISPER", target }
function Comms.send(outs)
  for _, o in ipairs(outs or {}) do
    local dist, target = o.dist, o.target
    if dist == "RAID" then dist = groupChannel() end
    if dist == "WHISPER" and target and ns.Priority.nameKey(target) == ns.Priority.nameKey(ns.Roster.me()) then
      dist = nil -- whisper to myself: already handled locally
    end
    if dist then
      seq = (seq % 9999) + 1
      for _, chunk in ipairs(Codec.wireChunks(o.msg, tostring(seq))) do
        queue[#queue + 1] = { chunk, dist, target }
      end
    end
  end
end

local budget = 0
frame:SetScript("OnUpdate", function(_, dt)
  if #queue == 0 then budget = 0; return end
  budget = math.min(PER_SECOND, budget + dt * PER_SECOND)
  while budget >= 1 and #queue > 0 do
    local q = table.remove(queue, 1)
    send(PREFIX, q[1], q[2], q[3])
    budget = budget - 1
  end
end)

frame:SetScript("OnEvent", function(_, _, prefix, text, _, sender)
  if prefix ~= PREFIX then return end
  sender = ns.Roster.normalize(sender)
  if ns.Priority.nameKey(sender) == ns.Priority.nameKey(ns.Roster.me()) then return end -- own echo
  local msg = asm.feed(sender, text)
  if type(msg) == "table" and Comms.onMessage then
    -- a message from another client must never break this one
    local ok, err = pcall(Comms.onMessage, msg, sender)
    if not ok and ns.Chat then ns.Chat.debug("dropped a message from " .. sender .. ": " .. tostring(err)) end
  end
end)
