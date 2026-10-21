-- CouncilComms: addon messages with prefix ToadsLC. Messages are packed by core/Wire.lua
-- (signed and, for council traffic, encrypted once a raid password is set) and sent
-- through a small throttled queue; incoming chunks are reassembled per sender, checked
-- and handed to the registry with whether they were signed with our password.
local _, ns = ...

local Comms = {}
ns.Comms = Comms

local PREFIX = "ToadsLC"
local PER_SECOND = 8

local queue = {}
local wire = ns.Wire.new({
  secret = function() return ns.App and ns.App.secret() end,
  clock = function() return GetTime() end,
})
local frame = CreateFrame("Frame")

local function groupChannel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
end

-- init(onMessage(msg, sender, trusted, signed), onSealed(sender)): onSealed is told about
-- council traffic sealed under a password this client does not hold.
function Comms.init(onMessage, onSealed)
  Comms.onMessage, Comms.onSealed = onMessage, onSealed
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
      for _, chunk in ipairs(wire.pack(o.msg, ns.Roster.me())) do
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
  local msg, trusted, signed = wire.unpack(sender, text)
  if msg == nil and trusted == "sealed for another password" and Comms.onSealed then
    pcall(Comms.onSealed, sender)
  end
  if type(msg) == "table" and Comms.onMessage then
    -- a message from another client must never break this one
    local ok, err = pcall(Comms.onMessage, msg, sender, trusted, signed)
    if not ok and ns.Chat then ns.Chat.debug("dropped a message from " .. sender .. ": " .. tostring(err)) end
  end
end)
