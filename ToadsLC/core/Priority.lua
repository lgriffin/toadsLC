-- Priority: the item list, tier parsing from the sheet wording, and candidate matching.
-- A priority is an ordered list of tiers; each tier is a set of equal candidates.
-- A candidate is { spec = "<token>" } or { player = "<name>" }.
local _, ns = ...
ns = ns or {}

local Priority = {}
ns.Priority = Priority

local pairs, ipairs, type = pairs, ipairs, type

-- Classes and their specs. Order is the talent tab order, which Roster relies on;
-- the druid's Feral tab is split into tank and cat because the sheet treats them apart.
Priority.CLASSES = {
  Warrior = { "Arms", "Fury", "Protection" },
  Paladin = { "Holy", "Protection", "Retribution" },
  Hunter  = { "BeastMastery", "Marksmanship", "Survival" },
  Rogue   = { "Assassination", "Combat", "Subtlety" },
  Priest  = { "Discipline", "Holy", "Shadow" },
  Shaman  = { "Elemental", "Enhancement", "Restoration" },
  Mage    = { "Arcane", "Fire", "Frost" },
  Warlock = { "Affliction", "Demonology", "Destruction" },
  Druid   = { "Balance", "Feral-Tank", "Feral-Cat", "Restoration" },
}

-- Tokens that stand for several specs of one class.
Priority.GROUPS = {
  ["Warrior:DPS"] = { "Warrior:Arms", "Warrior:Fury" },
}

-- Raid role of each spec, for ROLE:* tokens.
Priority.ROLE_OF = {
  ["Warrior:Protection"] = "Tank", ["Paladin:Protection"] = "Tank", ["Druid:Feral-Tank"] = "Tank",
  ["Paladin:Holy"] = "Healer", ["Priest:Discipline"] = "Healer", ["Priest:Holy"] = "Healer",
  ["Shaman:Restoration"] = "Healer", ["Druid:Restoration"] = "Healer",
  ["Priest:Shadow"] = "Caster", ["Shaman:Elemental"] = "Caster", ["Druid:Balance"] = "Caster",
  ["Mage:Arcane"] = "Caster", ["Mage:Fire"] = "Caster", ["Mage:Frost"] = "Caster",
  ["Warlock:Affliction"] = "Caster", ["Warlock:Demonology"] = "Caster", ["Warlock:Destruction"] = "Caster",
  ["Warrior:Arms"] = "Melee", ["Warrior:Fury"] = "Melee", ["Paladin:Retribution"] = "Melee",
  ["Rogue:Assassination"] = "Melee", ["Rogue:Combat"] = "Melee", ["Rogue:Subtlety"] = "Melee",
  ["Shaman:Enhancement"] = "Melee", ["Druid:Feral-Cat"] = "Melee",
  ["Hunter:BeastMastery"] = "Ranged", ["Hunter:Marksmanship"] = "Ranged", ["Hunter:Survival"] = "Ranged",
}
Priority.ROLES = { Tank = true, Healer = true, Caster = true, Melee = true, Ranged = true }

-- Short labels for tooltips and the council frame, in the guild's own vocabulary.
Priority.LABELS = {
  ["Warrior:Arms"] = "Arms", ["Warrior:Fury"] = "Fury", ["Warrior:Protection"] = "Prot War",
  ["Warrior:DPS"] = "DPS War",
  ["Paladin:Holy"] = "Holy Pally", ["Paladin:Protection"] = "Prot Pally", ["Paladin:Retribution"] = "Ret",
  ["Hunter:BeastMastery"] = "BM Hunter", ["Hunter:Marksmanship"] = "MM Hunter", ["Hunter:Survival"] = "Surv Hunter",
  ["Rogue:Assassination"] = "Assassination", ["Rogue:Combat"] = "Combat", ["Rogue:Subtlety"] = "Subtlety",
  ["Priest:Discipline"] = "Disc Priest", ["Priest:Holy"] = "Holy Priest", ["Priest:Shadow"] = "Shadow Priest",
  ["Shaman:Elemental"] = "Ele Shaman", ["Shaman:Enhancement"] = "Enhance", ["Shaman:Restoration"] = "Resto Shaman",
  ["Mage:Arcane"] = "Arcane Mage", ["Mage:Fire"] = "Fire Mage", ["Mage:Frost"] = "Frost Mage",
  ["Warlock:Affliction"] = "Affliction", ["Warlock:Demonology"] = "Demonology", ["Warlock:Destruction"] = "Destruction",
  ["Druid:Balance"] = "Boomkin", ["Druid:Feral-Tank"] = "Feral", ["Druid:Feral-Cat"] = "Kitty",
  ["Druid:Restoration"] = "Resto Druid",
  ANY = "Everyone else",
}

local SPEC_SET = {}
for class, specs in pairs(Priority.CLASSES) do
  for _, s in ipairs(specs) do SPEC_SET[class .. ":" .. s] = class end
end

local function classOfToken(tok)
  return type(tok) == "string" and tok:match("^(%a+):") or nil
end

-- isToken(tok): any token a priority candidate may carry.
function Priority.isToken(tok)
  if type(tok) ~= "string" then return false end
  if tok == "ANY" then return true end
  local role = tok:match("^ROLE:(%a+)$")
  if role then return Priority.ROLES[role] == true end
  if SPEC_SET[tok] or Priority.GROUPS[tok] then return true end
  local class = tok:match("^(%a+):%*$")
  return class ~= nil and Priority.CLASSES[class] ~= nil
end

-- isMemberSpec(tok, class): a spec a roster member can have ("Class:*" when unknown).
function Priority.isMemberSpec(tok, class)
  if tok == class .. ":*" then return true end
  return SPEC_SET[tok] == class
end

function Priority.isSpec(tok) return SPEC_SET[tok] ~= nil end

function Priority.label(tok)
  if Priority.LABELS[tok] then return Priority.LABELS[tok] end
  local role = type(tok) == "string" and tok:match("^ROLE:(%a+)$")
  if role then return role .. "s" end
  local class = classOfToken(tok)
  if class and tok:sub(-1) == "*" then return class end
  if class and tok:sub(-1) == "?" then return class .. "?" end
  return tostring(tok)
end

-- Class a candidate draws its colour from; nil for ROLE:*, ANY and players.
function Priority.classOf(cand)
  if cand.spec and not cand.spec:match("^ROLE:") then return classOfToken(cand.spec) end
end

---------------------------------------------------------------------------
-- names
---------------------------------------------------------------------------

-- Character names compare without realm and case, so "Tajt-Spineshatter" is "tajt".
function Priority.nameKey(name)
  if type(name) ~= "string" then return nil end
  return (name:match("^([^%-]+)") or name):lower()
end

---------------------------------------------------------------------------
-- matching
---------------------------------------------------------------------------

-- matches(cand, entry): entry is { player, class, spec }; spec may be nil or "Class:*"/"Class:?"
-- when unknown, in which case only Class:* (and player/ANY) can match.
function Priority.matches(cand, entry)
  if cand.player then
    return Priority.nameKey(cand.player) == Priority.nameKey(entry.player)
  end
  local tok, spec = cand.spec, entry.spec
  if tok == "ANY" then return true end
  local known = SPEC_SET[spec] ~= nil
  local role = tok:match("^ROLE:(%a+)$")
  if role then return known and Priority.ROLE_OF[spec] == role end
  local class = tok:match("^(%a+):%*$")
  if class then return entry.class == class or classOfToken(spec) == class end
  local group = Priority.GROUPS[tok]
  if group then
    for _, g in ipairs(group) do if g == spec then return true end end
    return false
  end
  return known and tok == spec
end

-- match(item, entry) -> tier, candidate index; nil when the entry matches no tier.
-- Tiers are walked in order; ANY only catches entries that no other candidate in the
-- whole list matched ("everyone else").
function Priority.match(item, entry)
  if not item or not item.priority then return nil end
  local anyTier, anyIndex
  for t, tier in ipairs(item.priority) do
    for c, cand in ipairs(tier) do
      if cand.spec == "ANY" then
        if not anyTier then anyTier, anyIndex = t, c end
      elseif Priority.matches(cand, entry) then
        return t, c
      end
    end
  end
  return anyTier, anyIndex
end

function Priority.tierOf(item, entry)
  return (Priority.match(item, entry))
end

---------------------------------------------------------------------------
-- the stored list
---------------------------------------------------------------------------

-- index(doc) -> the SavedVariables form: items keyed by item ID, byName for the rest.
function Priority.index(doc, importedBy, now)
  local db = {
    version = doc.exportedAt,
    exportedAt = doc.exportedAt,
    importedBy = importedBy,
    importedAt = now,
    rules = doc.rules or {},
    council = doc.council or {},
    members = {},
    items = {},
    byName = {},
    count = 0,
  }
  for _, item in ipairs(doc.items) do
    local key = item.name:lower()
    if item.itemId then
      db.items[item.itemId] = item
      db.byName[key] = db.byName[key] or item.itemId
    else
      db.byName[key] = item
    end
    db.count = db.count + 1
  end
  for _, m in ipairs(doc.members or {}) do
    db.members[Priority.nameKey(m.name)] = m
  end
  return db
end

-- lookup(db, itemId, name): by ID first; by name only for items whose ID is unknown
-- (or when the caller has no ID, e.g. a pasted item name).
function Priority.lookup(db, itemId, name)
  if not db or not db.items then return nil end
  if itemId and db.items[itemId] then return db.items[itemId] end
  if not name then return nil end
  local hit = db.byName[name:lower()]
  if type(hit) == "table" then return hit end
  if hit and not itemId then return db.items[hit] end
  return nil
end

---------------------------------------------------------------------------
-- display
---------------------------------------------------------------------------

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function splitText(text)
  local tiers = {}
  for part in (text .. ">"):gmatch("([^>]*)>") do
    local tier = {}
    for word in (part .. "="):gmatch("([^=]*)=") do tier[#tier + 1] = trim(word) end
    tiers[#tiers + 1] = tier
  end
  return tiers
end

-- tiers(item) -> { { {label=, class=}, ... }, ... }. Uses the guild's own wording from
-- priorityText when it has the same shape as the structured list, else generated labels.
function Priority.tiers(item)
  local words = item.priorityText and item.priorityText ~= "" and splitText(item.priorityText)
  if words and #words == #item.priority then
    for t, tier in ipairs(item.priority) do
      if #words[t] ~= #tier then words = nil; break end
    end
  else
    words = nil
  end
  local out = {}
  for t, tier in ipairs(item.priority) do
    local row = {}
    for c, cand in ipairs(tier) do
      row[c] = {
        label = words and words[t][c] or (cand.player or Priority.label(cand.spec)),
        class = Priority.classOf(cand),
        cand = cand,
      }
    end
    out[t] = row
  end
  return out
end

-- text(item) -> "BM Hunter = Rogue > Fury > ..." for chat.
function Priority.text(item)
  if not item then return nil end
  local parts = {}
  for t, tier in ipairs(Priority.tiers(item)) do
    local names = {}
    for c, cell in ipairs(tier) do names[c] = cell.label end
    parts[t] = table.concat(names, " = ")
  end
  return table.concat(parts, " > ")
end

---------------------------------------------------------------------------
-- sheet wording -> tokens (the CSV converter and tests use this)
---------------------------------------------------------------------------

Priority.ALIASES = {
  ["prot pally"] = "Paladin:Protection", ["prot paladin"] = "Paladin:Protection", ["prot pal"] = "Paladin:Protection",
  ["holy pally"] = "Paladin:Holy", ["holy paladin"] = "Paladin:Holy", ["hpal"] = "Paladin:Holy",
  ["ret"] = "Paladin:Retribution", ["ret pally"] = "Paladin:Retribution", ["ret paladin"] = "Paladin:Retribution",
  ["retri"] = "Paladin:Retribution",
  ["pally"] = "Paladin:*", ["paladin"] = "Paladin:*", ["paladins"] = "Paladin:*", ["pallies"] = "Paladin:*",
  ["rogue"] = "Rogue:*", ["rogues"] = "Rogue:*", ["combat rogue"] = "Rogue:Combat",
  ["assassination"] = "Rogue:Assassination", ["sub rogue"] = "Rogue:Subtlety",
  ["feral"] = "Druid:Feral-Tank", ["bear"] = "Druid:Feral-Tank", ["feral tank"] = "Druid:Feral-Tank",
  ["bear tank"] = "Druid:Feral-Tank",
  ["kitty"] = "Druid:Feral-Cat", ["cat"] = "Druid:Feral-Cat", ["feral cat"] = "Druid:Feral-Cat",
  ["feral dps"] = "Druid:Feral-Cat",
  ["boomkin"] = "Druid:Balance", ["moonkin"] = "Druid:Balance", ["balance"] = "Druid:Balance",
  ["resto druid"] = "Druid:Restoration", ["tree"] = "Druid:Restoration",
  ["druid"] = "Druid:*", ["druids"] = "Druid:*",
  ["dps war"] = "Warrior:DPS", ["dps warrior"] = "Warrior:DPS", ["dps warriors"] = "Warrior:DPS",
  ["fury"] = "Warrior:Fury", ["fury war"] = "Warrior:Fury", ["fury warrior"] = "Warrior:Fury",
  ["arms"] = "Warrior:Arms", ["arms war"] = "Warrior:Arms", ["arms warrior"] = "Warrior:Arms",
  ["prot war"] = "Warrior:Protection", ["prot warrior"] = "Warrior:Protection",
  ["tank warrior"] = "Warrior:Protection",
  ["warrior"] = "Warrior:*", ["warriors"] = "Warrior:*",
  ["bm"] = "Hunter:BeastMastery", ["bm hunter"] = "Hunter:BeastMastery", ["beast mastery"] = "Hunter:BeastMastery",
  ["mm"] = "Hunter:Marksmanship", ["mm hunter"] = "Hunter:Marksmanship",
  ["surv"] = "Hunter:Survival", ["surv hunter"] = "Hunter:Survival", ["survival"] = "Hunter:Survival",
  ["hunter"] = "Hunter:*", ["hunters"] = "Hunter:*",
  ["shadow"] = "Priest:Shadow", ["shadow priest"] = "Priest:Shadow", ["spriest"] = "Priest:Shadow",
  ["disc"] = "Priest:Discipline", ["disc priest"] = "Priest:Discipline",
  ["holy priest"] = "Priest:Holy",
  -- The sheet's bare "Priest" means Holy Priest (open question in the design doc).
  ["priest"] = "Priest:Holy", ["priests"] = "Priest:Holy",
  ["ele"] = "Shaman:Elemental", ["elemental"] = "Shaman:Elemental", ["ele shaman"] = "Shaman:Elemental",
  ["enh"] = "Shaman:Enhancement", ["enhance"] = "Shaman:Enhancement", ["enhancement"] = "Shaman:Enhancement",
  ["enh shaman"] = "Shaman:Enhancement", ["enhance shaman"] = "Shaman:Enhancement",
  ["resto shaman"] = "Shaman:Restoration", ["resto sham"] = "Shaman:Restoration",
  ["shaman"] = "Shaman:*", ["shamans"] = "Shaman:*", ["shammy"] = "Shaman:*",
  ["mage"] = "Mage:*", ["mages"] = "Mage:*", ["fire mage"] = "Mage:Fire", ["frost mage"] = "Mage:Frost",
  ["arcane mage"] = "Mage:Arcane",
  ["warlock"] = "Warlock:*", ["warlocks"] = "Warlock:*", ["lock"] = "Warlock:*", ["locks"] = "Warlock:*",
  ["affliction"] = "Warlock:Affliction", ["affli"] = "Warlock:Affliction",
  ["demo"] = "Warlock:Demonology", ["destro"] = "Warlock:Destruction",
  ["healer"] = "ROLE:Healer", ["healers"] = "ROLE:Healer", ["other healers"] = "ROLE:Healer",
  ["caster"] = "ROLE:Caster", ["casters"] = "ROLE:Caster",
  ["tank"] = "ROLE:Tank", ["tanks"] = "ROLE:Tank", ["melee"] = "ROLE:Melee",
  ["everyone else"] = "ANY", ["others"] = "ANY", ["stat stick"] = "ANY", ["anyone"] = "ANY", ["any"] = "ANY",
}

-- parseText("Prot Pally > Ret > Shamans = Rogue") -> priority tiers | nil, err.
-- "Name (note)" is a named player, e.g. "Tajt (MW)".
function Priority.parseText(text)
  if type(text) ~= "string" or trim(text) == "" then return nil, "empty priority" end
  local out = {}
  for t, tier in ipairs(splitText(text)) do
    local row = {}
    for _, word in ipairs(tier) do
      if word == "" then return nil, "empty candidate in tier " .. t end
      local key = word:lower():gsub("%s+", " ")
      local tok = Priority.ALIASES[key]
      if tok then
        row[#row + 1] = { spec = tok }
      elseif Priority.isToken(word) then
        row[#row + 1] = { spec = word }
      else
        local player = word:match("^(%u[%a\128-\255]+)%s*%(.*%)$") or word:match("^@(%S+)$")
        if not player then return nil, '"' .. word .. '" is not a known token' end
        row[#row + 1] = { player = player }
      end
    end
    out[t] = row
  end
  return out
end

return Priority
