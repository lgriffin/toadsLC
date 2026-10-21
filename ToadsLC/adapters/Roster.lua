-- Roster: raid members, their class and spec, and council membership.
-- Spec comes from talents (own, or inspected), else the imported members[] block,
-- else only the class is known (Rogue:* still matches).
local _, ns = ...

local Roster = {}
ns.Roster = Roster

local Priority = ns.Priority

Roster.CLASS = {
  WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
Roster.FILE = {}
for file, class in pairs(Roster.CLASS) do Roster.FILE[class] = file end

-- talent tab -> spec name; the druid's Feral tab cannot tell bear from cat
local TABS = {
  Warrior = { "Arms", "Fury", "Protection" },
  Paladin = { "Holy", "Protection", "Retribution" },
  Hunter  = { "BeastMastery", "Marksmanship", "Survival" },
  Rogue   = { "Assassination", "Combat", "Subtlety" },
  Priest  = { "Discipline", "Holy", "Shadow" },
  Shaman  = { "Elemental", "Enhancement", "Restoration" },
  Mage    = { "Arcane", "Fire", "Frost" },
  Warlock = { "Affliction", "Demonology", "Destruction" },
  Druid   = { "Balance", "Feral", "Restoration" },
}

local inspected = {} -- nameKey -> spec token

function Roster.normalize(name)
  if not name then return nil end
  if Ambiguate then return Ambiguate(name, "none") end
  return name
end

function Roster.me() return Roster.normalize(UnitName("player")) end

-- units() -> iterator over unit ids in the group, the player included
function Roster.units()
  local list = {}
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do list[#list + 1] = "raid" .. i end
  else
    list[1] = "player"
    for i = 1, GetNumSubgroupMembers() do list[#list + 1] = "party" .. i end
  end
  local i = 0
  return function() i = i + 1; return list[i] end
end

function Roster.unitOf(name)
  local key = Priority.nameKey(name)
  for unit in Roster.units() do
    local n, realm = UnitName(unit)
    if n and Priority.nameKey(n) == key then return unit, realm end
  end
end

function Roster.classOf(unit)
  local _, file = UnitClass(unit)
  return file and Roster.CLASS[file]
end

-- specFromTalents(class, inspect) -> token or nil
local function specFromTalents(class, inspect)
  local tabs = TABS[class]
  if not tabs or not GetTalentTabInfo then return nil end
  local best, bestPoints, total = nil, -1, 0
  for i = 1, #tabs do
    -- The return layout differs between client builds: (name, icon, points, ...) or
    -- (id, name, description, icon, points, ...).
    local r1, _, r3, _, r5 = GetTalentTabInfo(i, inspect)
    local points = (type(r1) == "number" and r5) or r3
    points = tonumber(points) or 0
    total = total + points
    if points > bestPoints then best, bestPoints = tabs[i], points end
  end
  if total == 0 then return nil end
  if best == "Feral" then return nil end -- bear or cat: leave it to members[] or the LC
  return class .. ":" .. best
end

local function memberSpec(name, class)
  local p = ns.Store.priorities()
  local m = p and p.members and p.members[Priority.nameKey(name)]
  if m and m.spec and (not class or m.class == class) and Priority.isSpec(m.spec) then return m.spec, m.class end
  return nil, m and m.class
end

-- who(name) -> { class, spec } (spec nil when unknown)
function Roster.who(name)
  local fake = ns.Sim and ns.Sim.who(name) -- /tlc sim's raiders
  if fake then return fake end
  local unit = Roster.unitOf(name)
  local class = unit and Roster.classOf(unit)
  local spec
  if unit and UnitIsUnit(unit, "player") then
    spec = specFromTalents(class, false)
  else
    spec = inspected[Priority.nameKey(name)]
  end
  local mspec, mclass = memberSpec(name, class)
  class = class or mclass
  if not spec then spec = mspec end
  return { class = class, spec = spec }
end

function Roster.specOf(unit)
  if unit == "player" then return Roster.who(Roster.me()) end
  return Roster.who(Roster.normalize(UnitName(unit)))
end

-- council() -> names: the priorities document's council[], or raid members with assist.
function Roster.council()
  local p = ns.Store.priorities()
  if p and p.council and #p.council > 0 then return p.council end
  local out = {}
  for unit in Roster.units() do
    if UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit) then
      out[#out + 1] = Roster.normalize(UnitName(unit))
    end
  end
  return out
end

function Roster.canLead()
  return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

---------------------------------------------------------------------------
-- inspect queue for raiders without the addon (one NotifyInspect every 2 s)
---------------------------------------------------------------------------

local queue, pending = {}, nil
local frame = CreateFrame("Frame")

function Roster.queueInspect(names)
  for _, name in ipairs(names) do
    if not inspected[Priority.nameKey(name)] then queue[#queue + 1] = name end
  end
end

local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + dt
  if elapsed < 2 or #queue == 0 or InCombatLockdown() then return end
  elapsed = 0
  if pending and GetTime() - pending.at > 10 then pending = nil end -- no answer: give up on it
  if pending then return end
  local name = table.remove(queue, 1)
  local unit = Roster.unitOf(name)
  if unit and CanInspect(unit) and CheckInteractDistance(unit, 1) then
    pending = { name = name, unit = unit, class = Roster.classOf(unit), guid = UnitGUID(unit), at = GetTime() }
    NotifyInspect(unit)
  end
end)

frame:RegisterEvent("INSPECT_READY")
frame:SetScript("OnEvent", function(_, _, guid)
  -- only our own request: anything else (the Inspect frame, another addon) is someone else's talents
  if not pending or guid ~= pending.guid then return end
  local spec = specFromTalents(pending.class, true)
  if spec then inspected[Priority.nameKey(pending.name)] = spec end
  pending = nil
  if ClearInspectPlayer then ClearInspectPlayer() end
end)
