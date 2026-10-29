-- Trade: hands out what was awarded. When whoever holds the loot opens a trade with a raider,
-- the items that raider won tonight and that are in this player's bags go into the trade
-- window by themselves; the player still checks and presses Trade. Once the trade completes,
-- those awards are marked as traded, so the next trade does not offer them again.
--
-- Awards come from finished sessions this client saw (the registry), the loot list (shared
-- by the raid leader and assists, and kept over a reload), and the sessions this client led
-- (saved records), in that order, each award once by session id. /tlc sim awards are left out.
local _, ns = ...

local Trade = {}
ns.Trade = Trade

local Priority, Codec = ns.Priority, ns.Codec

Trade.MAX_AGE = 12 * 3600 -- awards older than a night are not offered
Trade.SLOTS = 6           -- trade slots that change hands (the 7th is "will not be traded")
Trade.DELAY = 0.2         -- seconds between items, so the client takes each one

local frame = CreateFrame("Frame")
local partner, pending -- this trade: who with, and what is on our side of it once we accept

local function now() return ns.App.now() end
local function key(name) return name and Priority.nameKey(ns.Roster.normalize(name)) end

local function tradedSet()
  ToadsLCDB.traded = ToadsLCDB.traded or {}
  return ToadsLCDB.traded
end

-- forget traded marks from earlier nights
local function prune()
  local t = tradedSet()
  for id, at in pairs(t) do
    if now() - at > Trade.MAX_AGE then t[id] = nil end
  end
end

---------------------------------------------------------------------------
-- what is owed
---------------------------------------------------------------------------

-- awards() -> { { session, itemId, itemName, winner, at }, ... }, oldest first, untraded only
function Trade.awards()
  local out, seen = {}, {}
  local traded = tradedSet()
  local function add(id, itemId, itemName, winner, at)
    if not id or seen[id] then return end
    seen[id] = true
    if not itemId or not winner or traded[id] or ns.Sim.isSim({ id = id }) then return end
    if at and now() - at > Trade.MAX_AGE then return end
    out[#out + 1] = { session = id, itemId = itemId, itemName = itemName, winner = winner, at = at or 0 }
  end
  local reg = ns.App.registry
  for _, id in ipairs(reg and reg.order or {}) do
    local s = reg.sessions[id]
    -- an unfinished or undone session counts too: it is not owed yet, whatever older copies say
    if s then add(s.id, s.phase == "done" and s.itemId or nil, s.itemName, s.awardedTo, s.openedAt) end
  end
  for _, e in ipairs(ns.Loot.list.entries) do
    if e.session then add(e.session, e.status == "awarded" and e.itemId or nil, e.name, e.winner, e.at) end
  end
  for _, r in ipairs(ns.Store.since(now() - Trade.MAX_AGE)) do
    if r and r.id then
      local winner = r.awardedTo ~= Codec.null and r.awardedTo or nil
      local itemId = r.itemId ~= Codec.null and r.itemId or nil
      add(r.id, itemId, r.itemName, winner, nil)
    end
  end
  table.sort(out, function(a, b) return a.at < b.at end)
  return out
end

-- owed(name) -> the awards still to trade to name
function Trade.owed(name)
  local out, k = {}, key(name)
  for _, a in ipairs(Trade.awards()) do
    if key(a.winner) == k then out[#out + 1] = a end
  end
  return out
end

---------------------------------------------------------------------------
-- bags and the trade window
---------------------------------------------------------------------------

local Container = C_Container or {}
local numSlots = Container.GetContainerNumSlots or GetContainerNumSlots
local pickup = Container.PickupContainerItem or PickupContainerItem

-- slotInfo(bag, slot) -> itemId, count, locked
local function slotInfo(bag, slot)
  if Container.GetContainerItemInfo then
    local info = Container.GetContainerItemInfo(bag, slot)
    if not info then return nil end
    return info.itemID, info.stackCount, info.isLocked
  end
  local _, count, locked, _, _, _, link = GetContainerItemInfo(bag, slot)
  return link and tonumber(link:match("item:(%d+)")), count, locked
end

-- find(itemId, used) -> bag, slot of a single, unlocked copy not already picked
local function find(itemId, used)
  for bag = 0, NUM_BAG_SLOTS or 4 do
    for slot = 1, numSlots(bag) or 0 do
      local id, count, locked = slotInfo(bag, slot)
      local at = bag .. ":" .. slot
      if id == itemId and not locked and not used[at] and (count or 1) == 1 then
        used[at] = true
        return bag, slot
      end
    end
  end
end

-- freeSlots() -> the trade slots nothing is in yet
local function freeSlots()
  local out = {}
  for i = 1, Trade.SLOTS do
    if not GetTradePlayerItemLink(i) then out[#out + 1] = i end
  end
  return out
end

local function partnerName()
  local name = UnitName("NPC")
  if not name and TradeFrameRecipientNameText then name = TradeFrameRecipientNameText:GetText() end
  return name and ns.Roster.normalize(name)
end

-- fill(name): put what name is owed into the trade window
function Trade.fill(name)
  local owed = Trade.owed(name)
  if #owed == 0 then return end
  local free, used, put, missing = freeSlots(), {}, {}, {}
  for _, a in ipairs(owed) do
    local bag, slot = find(a.itemId, used)
    if not bag then
      missing[#missing + 1] = a
    elseif #put < #free then
      put[#put + 1] = { award = a, bag = bag, slot = slot, tradeSlot = free[#put + 1] }
    end
  end
  for i, p in ipairs(put) do
    C_Timer.After(Trade.DELAY * i, function()
      if partner ~= name then return end -- the trade closed or changed hands
      ClearCursor()
      pickup(p.bag, p.slot)
      ClickTradeButton(p.tradeSlot)
      ClearCursor()
    end)
  end
  local Chat = ns.Chat
  if #put > 0 then
    local names = {}
    for i, p in ipairs(put) do names[i] = p.award.itemName end
    Chat.print(string.format("Trading %s to %s. Check the window, then press Trade.", table.concat(names, ", "), name))
  end
  local left = #owed - #put - #missing
  if left > 0 then
    Chat.print(string.format("%d more for %s after this trade (6 items per trade).", left, name))
  end
  if #missing > 0 then
    local names = {}
    for i, a in ipairs(missing) do names[i] = a.itemName end
    Chat.print(string.format("%s also won %s, which is not in your bags.", name, table.concat(names, ", ")))
  end
end

function Trade.onShow()
  partner, pending = partnerName(), nil
  if not partner or ns.Store.settings().autoTrade == false then return end
  Trade.fill(partner)
end

-- the items in our side of the window when we accept: what actually changes hands
local function snapshot()
  local items = { links = {} } -- links by item id, for the raid chat line
  for i = 1, Trade.SLOTS do
    local link = GetTradePlayerItemLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id then items[#items + 1] = id; items.links[id] = link end
  end
  return items
end

-- onComplete(): mark one owed award per item that went over
function Trade.onComplete()
  local items, name = pending, partner
  partner, pending = nil, nil
  if not items or not name then return end
  local marked, handed = {}, {}
  local owed = Trade.owed(name)
  for _, id in ipairs(items) do
    for _, a in ipairs(owed) do
      if a.itemId == id and not a.done then
        a.done = true
        tradedSet()[a.session] = now()
        marked[#marked + 1] = a.itemName
        a.link = items.links and items.links[id]
        handed[#handed + 1] = a
        break
      end
    end
  end
  if #marked > 0 then
    ns.Chat.print(string.format("Traded %s to %s.", table.concat(marked, ", "), name))
  end
  Trade.announce(handed, name)
end

-- announce(awards, name): one raid chat line per award handed over, so the raid sees it arrive.
-- One line each keeps item links whole under the chat limit.
function Trade.announce(awards, name)
  local set = ns.Store.settings()
  if #awards == 0 or set.announceTrade == false or not IsInGroup() then return end
  for _, a in ipairs(awards) do
    local link = a.link or select(2, GetItemInfo(a.itemId)) or a.itemName
    local fields = { item = link, name = name, by = ns.Roster.me() }
    ns.Chat.say(ns.Session.fill(set.tradeMessage or ns.Session.TRADE_TEMPLATE, fields))
  end
end

function Trade.onEvent(event, ...)
  if event == "TRADE_SHOW" then
    Trade.onShow()
  elseif event == "TRADE_ACCEPT_UPDATE" then
    local mine = ...
    pending = mine == 1 and partner and snapshot() or nil -- either side changing the window unaccepts
  elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
    -- TRADE_CLOSED comes before the completion message, so the message decides how it ended
    local a, b = ...
    local text = type(b) == "string" and b or a
    if text == ERR_TRADE_COMPLETE then Trade.onComplete()
    elseif text == ERR_TRADE_CANCELLED then partner, pending = nil, nil end
  elseif event == "TRADE_REQUEST_CANCEL" then
    partner, pending = nil, nil
  end
end

---------------------------------------------------------------------------
-- /tlc trade
---------------------------------------------------------------------------

-- print(): what is still to hand out, by winner, and whether it is in this player's bags
function Trade.print()
  local awards = Trade.awards()
  local me = key(ns.Roster.me())
  local lines, used = {}, {}
  for _, a in ipairs(awards) do
    if key(a.winner) ~= me then
      local held = find(a.itemId, used) and "" or " (not in your bags)"
      lines[#lines + 1] = string.format("%s: %s%s", a.winner, a.itemName, held)
    end
  end
  if #lines == 0 then ns.Chat.print("Nothing awarded tonight is waiting to be traded."); return end
  ns.Chat.print("Still to trade (open a trade with the winner and it goes in by itself):")
  for _, l in ipairs(lines) do ns.Chat.print(l) end
end

-- onAward(session): tell whoever holds the item that the next trade with the winner hands it over
function Trade.onAward(s)
  if not s.awardedTo or not s.itemId or ns.Sim.isSim(s) or ns.Store.settings().autoTrade == false then return end
  if key(s.awardedTo) == key(ns.Roster.me()) or not find(s.itemId, {}) then return end
  ns.Chat.print(string.format("%s is in your bags: open a trade with %s and it goes in by itself.", s.itemName,
    s.awardedTo))
end

-- done(name): mark everything owed to name as traded (handed over some other way)
function Trade.done(name)
  local owed = Trade.owed(name)
  if #owed == 0 then ns.Chat.print("Nothing is waiting to be traded to " .. tostring(name) .. "."); return end
  for _, a in ipairs(owed) do tradedSet()[a.session] = now() end
  ns.Chat.print(string.format("Marked %d item%s for %s as handed over.", #owed, #owed == 1 and "" or "s", name))
end

function Trade.init()
  prune()
  partner, pending = nil, nil
  for _, e in ipairs({ "TRADE_SHOW", "TRADE_REQUEST_CANCEL", "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE",
                       "UI_ERROR_MESSAGE" }) do
    frame:RegisterEvent(e)
  end
  frame:SetScript("OnEvent", function(_, event, ...) Trade.onEvent(event, ...) end)
end

return Trade
