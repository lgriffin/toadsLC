-- Client: the few places where the TBC Anniversary client and the WoW Forever client differ.
-- Every other adapter asks this file instead of reaching for a global that one of them lacks.
--
-- WoW Forever (game type "camelot", interface 16001) runs on the modern client: GetItemInfo
-- and friends live only under C_Item, SendChatMessage under C_ChatInfo, talents are a trait
-- tree (C_Traits) instead of GetTalentTabInfo, and during a boss fight the client is in chat
-- messaging lockdown: addon messages and chat sends are refused and CHAT_MSG_SYSTEM text
-- arrives as a secret value that can't be read.
local _, ns = ...

local Client = {}
ns.Client = Client

Client.FOREVER_PROJECT = 18 -- WOW_PROJECT_CAMELOT, when the client doesn't name it

function Client.isTBC()
  return WOW_PROJECT_ID ~= nil and WOW_PROJECT_BURNING_CRUSADE_CLASSIC ~= nil
     and WOW_PROJECT_ID == WOW_PROJECT_BURNING_CRUSADE_CLASSIC
end

function Client.isForever()
  return WOW_PROJECT_ID ~= nil and WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or Client.FOREVER_PROJECT)
end

function Client.supported() return Client.isTBC() or Client.isForever() end

function Client.name()
  if Client.isForever() then return "WoW Forever" end
  if Client.isTBC() then return "TBC Anniversary" end
  return "unsupported"
end

---------------------------------------------------------------------------
-- items
---------------------------------------------------------------------------

-- itemInfo(item) -> GetItemInfo's returns (name, link, quality, ...); nil until cached
function Client.itemInfo(item)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if get then return get(item) end
end

function Client.itemInfoInstant(item)
  local get = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if get then return get(item) end
end

function Client.itemIcon(itemId)
  local get = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
  if get then return get(itemId) end
end

---------------------------------------------------------------------------
-- chat
---------------------------------------------------------------------------

-- secret(v): a value the client hides from addons (WoW Forever, in lockdown); comparing or
-- matching it is an error, so callers drop it
function Client.secret(v)
  return issecretvalue ~= nil and issecretvalue(v) and true or false
end

-- chatLocked(): addon messages and chat sends are refused right now (WoW Forever, mid-fight)
function Client.chatLocked()
  return C_ChatInfo ~= nil and C_ChatInfo.InChatMessagingLockdown ~= nil
     and C_ChatInfo.InChatMessagingLockdown() and true or false
end

function Client.sendChat(text, channel, target)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  return send(text, channel, nil, target)
end

---------------------------------------------------------------------------
-- talents
---------------------------------------------------------------------------

-- WoW Forever: the trait tree's groups are the three talent tabs, in orderIndex order, and
-- each group's currency says how many points are spent in it.
local function traitPoints(inspect)
  if not (C_Traits and C_Traits.GetConfigInfo and C_Traits.GetGroupDisplayInfoByTreeID
          and C_Traits.GetGroupCurrencyInfo) then return nil end
  local configID
  if inspect then
    configID = (Constants and Constants.TraitConsts and Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID) or -1
  else
    local S = C_SpecializationInfo
    if S and S.GetCombatConfigIDForSpecGroup and S.GetActiveSpecGroup then
      configID = S.GetCombatConfigIDForSpecGroup(S.GetActiveSpecGroup())
    end
    if not configID and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
      configID = C_ClassTalents.GetActiveConfigID()
    end
  end
  if not configID then return nil end
  local config = C_Traits.GetConfigInfo(configID)
  local treeID = config and config.treeIDs and config.treeIDs[1]
  if not treeID then return nil end
  local groups = {}
  for _, g in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do groups[#groups + 1] = g end
  table.sort(groups, function(a, b) return (a.orderIndex or 0) < (b.orderIndex or 0) end)
  local ids = {}
  for i, g in ipairs(groups) do ids[i] = g.groupID end
  local spent = {}
  for _, info in ipairs(C_Traits.GetGroupCurrencyInfo(configID, ids) or {}) do
    local c = info.currencyInfos and info.currencyInfos[1]
    spent[info.traitNodeGroupID] = c and tonumber(c.spent) or 0
  end
  local points = {}
  for i, g in ipairs(groups) do points[i] = spent[g.groupID] or 0 end
  return points
end

-- talentPoints(inspect, tabs) -> { points in tab 1, tab 2, tab 3 } for the player, or for the
-- last inspected player when inspect is true; nil when the client can't say
function Client.talentPoints(inspect, tabs)
  if GetTalentTabInfo then
    local points = {}
    for i = 1, tabs do
      -- The return layout differs between client builds: (name, icon, points, ...) or
      -- (id, name, description, icon, points, ...).
      local r1, _, r3, _, r5 = GetTalentTabInfo(i, inspect)
      points[i] = tonumber((type(r1) == "number" and r5) or r3) or 0
    end
    return points
  end
  return traitPoints(inspect)
end
