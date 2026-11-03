-- Mule: the master looter hands the trash to one player. When the master looter opens a
-- corpse, every item of the chosen rarities (greens and blues by default) goes straight to
-- the mule through master loot, so nobody has to click through the green and blue drops.
-- Items the council hands out are never muled: anything on the priority list, and anything
-- the loot list records (epic and up in a raid, see adapters/Loot.lua), stays on the corpse.
--
-- Only items at or above the group's loot threshold can be given out through master loot;
-- anything below it is free for all, so the mule's rarities only count from the threshold up.
local _, ns = ...

local Mule = {}
ns.Mule = Mule

local Priority = ns.Priority

Mule.QUALITIES = { green = 2, blue = 3, epic = 4 }
Mule.NAMES = { [2] = "green", [3] = "blue", [4] = "epic" }
Mule.DEFAULT = { 2, 3 }
Mule.MAX_CANDIDATES = 40

local function settings() return ns.Store.settings() end
local function key(name) return name and Priority.nameKey(ns.Roster.normalize(name)) end

---------------------------------------------------------------------------
-- settings (the GUI reads and writes these too)
---------------------------------------------------------------------------

-- get() -> the mule's name (nil when off), and the rarities muled as a sorted list of qualities
function Mule.get()
  local st, out = settings(), {}
  for q in pairs(st.muleQualities or {}) do out[#out + 1] = q end
  table.sort(out)
  return st.mule, out
end

-- set(name): who gets the muled items, spelled as the group spells them; nil or "" turns the mule off
function Mule.set(name)
  if name == "" then name = nil end
  -- a name typed with its realm keeps it; one found in the group takes the group's spelling,
  -- realm included for a player from another realm
  local unit = name and not name:find("-", 1, true) and ns.Roster.unitOf(name)
  if unit then
    local n, realm = UnitName(unit)
    if n then name = (realm and realm ~= "") and (n .. "-" .. realm) or n end
  end
  settings().mule = name and ns.Roster.normalize(name) or nil
end

-- setQualities(list): the rarities muled, as qualities (2 green, 3 blue, 4 epic)
function Mule.setQualities(list)
  local set = {}
  for _, q in ipairs(list) do
    if Mule.NAMES[q] then set[q] = true end
  end
  settings().muleQualities = set
end

function Mule.qualityNames(list)
  local names = {}
  for i, q in ipairs(list) do names[i] = Mule.NAMES[q] or tostring(q) end
  return table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- giving out
---------------------------------------------------------------------------

-- masterLooter(): this player hands out the loot. The TBC Anniversary client has
-- IsMasterLooter() and C_PartyInfo.GetLootMethod(), which answers a number
-- (Enum.LootMethod.Masterlooter = 2), not the old GetLootMethod()'s "master": checking for
-- "master" alone meant the mule never ran in game.
function Mule.masterLooter()
  if not IsInGroup() then return false end
  if IsMasterLooter then return IsMasterLooter() and true or false end
  local get = (C_PartyInfo and C_PartyInfo.GetLootMethod) or GetLootMethod
  if not get then return false end
  local method, partyMaster, raidMaster = get()
  local ml = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter or 2
  if method ~= "master" and method ~= ml then return false end
  if IsInRaid() then return raidMaster ~= nil and UnitIsUnit("raid" .. raidMaster, "player") end
  return partyMaster == 0
end

-- candidate(slot, name) -> the mule's index in the slot's master loot list, or nil when the
-- mule can't take it (out of range, not on the kill, not in the group)
-- mule can't take it (out of range, not on the kill, not in the group). The full name
-- (realm and all) wins; a bare name only counts when one candidate has it, so two players of
-- the same name from different realms never get each other's loot.
local function candidate(slot, name)
  local full, short = name:lower(), key(name)
  local found, matches = nil, 0
  local realm = name:match("%-(.+)$")
  local home = not realm or realm:gsub("%s", ""):lower() == (GetRealmName() or ""):gsub("%s", ""):lower()
  for i = 1, Mule.MAX_CANDIDATES do
    local who = GetMasterLootCandidate(slot, i)
    if who then
      if who:lower() == full then return i end
      -- a bare candidate is from our realm: the mule only when the mule is from it too
      if key(who) == short and not who:find("-", 1, true) and home then found, matches = i, matches + 1 end
    end
  end
  if matches == 1 then return found end
end

local function isItem(slot)
  if GetLootSlotType then return GetLootSlotType(slot) == (LOOT_SLOT_ITEM or 1) end
  return LootSlotHasItem == nil or LootSlotHasItem(slot)
end

-- where(slot) -> link, "mule" | "self": this slot goes to the mule, or (a council item) into
-- the master looter's own bags to be traded once it is awarded
local function where(slot, qualities, threshold, mule)
  if not isItem(slot) then return nil end
  local link = GetLootSlotLink(slot)
  local itemId = link and tonumber(link:match("item:(%d+)"))
  local _, _, _, _, quality, locked, isQuestItem = GetLootSlotInfo(slot)
  if not itemId or locked or isQuestItem or not quality or quality < threshold then return nil end
  if ns.Loot.wanted(itemId, quality) then -- the council's, not the mule's
    if settings().lootSelf ~= false then return link, "self" end
    return nil
  end
  if mule and qualities[quality] then return link, "mule" end
  return nil
end

-- onLootOpened(): called by Loot once the corpse is on the loot list
function Mule.onLootOpened()
  local name = settings().mule
  if not Mule.masterLooter() then return end
  local qualities = settings().muleQualities or {}
  local threshold = GetLootThreshold and GetLootThreshold() or 2
  local given, missed, kept = {}, {}, {}
  local me = ns.Roster.me()
  for slot = GetNumLootItems(), 1, -1 do
    local link, to = where(slot, qualities, threshold, name)
    if link then
      local i = candidate(slot, to == "self" and me or name)
      if i then
        GiveMasterLoot(slot, i)
        table.insert(to == "self" and kept or given, 1, link)
      elseif to == "mule" then
        table.insert(missed, 1, link)
      end
    end
  end
  if #given > 0 then
    ns.Chat.print(string.format("Muled to %s: %s.", name, table.concat(given, ", ")))
  end
  if #kept > 0 then
    ns.Chat.print(string.format("Looted for the council: %s. Trade them once they're awarded.", table.concat(kept, ", ")))
  end
  if #missed > 0 then
    ns.Chat.print(string.format("%s can't take %s from this corpse (out of range, or not eligible). Left on the corpse.",
      name, table.concat(missed, ", ")))
  end
end

---------------------------------------------------------------------------
-- /tlc mule
---------------------------------------------------------------------------

function Mule.status()
  local name, list = Mule.get()
  if not name then
    ns.Chat.print("No loot mule. /tlc mule <name> (or target) sends greens and blues to one player when you're master looter.")
    return
  end
  ns.Chat.print(string.format("Loot mule: %s gets every %s item when you're master looter (the council's items excepted).",
    name, #list > 0 and Mule.qualityNames(list) or "(no rarities chosen)"))
  if not Mule.masterLooter() then
    ns.Chat.print("You aren't master looter right now, so nothing is muled.")
  elseif GetLootThreshold then
    local threshold = GetLootThreshold()
    for _, q in ipairs(list) do
      if q < threshold then
        ns.Chat.print(string.format("The loot threshold is above %s, so %s items are free for all and can't be muled.",
          Mule.NAMES[q], Mule.NAMES[q]))
      end
    end
  end
end

-- /tlc mule [<name> | target | me | off | quality <green blue epic ...>]
function Mule.command(rest)
  local sub, arg = rest:match("^%s*(%S*)%s*(.-)%s*$")
  local lower = (sub or ""):lower()
  if lower == "" then return Mule.status() end
  if lower == "off" then
    Mule.set(nil)
    ns.Chat.print("Loot mule off.")
  elseif lower == "quality" or lower == "qualities" or lower == "rarity" then
    local list = {}
    for word in arg:lower():gmatch("%a+") do
      local q = Mule.QUALITIES[word] or Mule.QUALITIES[(word:gsub("s$", ""))]
      if not q then ns.Chat.print("Usage: /tlc mule quality green blue epic (any of them)"); return end
      list[#list + 1] = q
    end
    if #list == 0 then ns.Chat.print("Usage: /tlc mule quality green blue epic (any of them)"); return end
    Mule.setQualities(list)
    local _, set = Mule.get()
    ns.Chat.print("Muling " .. Mule.qualityNames(set) .. " items.")
  else
    local name = sub
    if lower == "target" then name = UnitName("target") elseif lower == "me" then name = UnitName("player") end
    if not name then ns.Chat.print("Target the player to mule to first, or /tlc mule <name>."); return end
    Mule.set(name)
    Mule.status()
  end
end

function Mule.init()
  local st = settings()
  if st.muleQualities == nil then Mule.setQualities(Mule.DEFAULT) end
  -- LOOT_OPENED reaches Mule through Loot, after the corpse is recorded
end

return Mule
