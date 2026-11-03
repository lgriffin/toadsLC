-- Resolver: a sort, not a vote. Candidates are ordered main spec first, then tier ascending,
-- then BiS above Upgrade, then roll descending; the first row is what the list says.
local _, ns = ...
ns = ns or {}

local Resolver = {}
ns.Resolver = Resolver

local Priority = ns.Priority
local unpack = unpack or table.unpack -- luacheck: ignore 143
local huge = math.huge

Resolver.DEFAULT_RULES = {
  offspecRollMax = 99,
  allOffspecMode = "ask",
  sessionSeconds = 30,
  votesVisibleTo = "council",
}

function Resolver.rules(r)
  local out = {}
  for k, v in pairs(Resolver.DEFAULT_RULES) do out[k] = v end
  for k, v in pairs(r or {}) do out[k] = v end
  return out
end

-- Equal tier and roll falls back to the name so every client sorts identically.
local function nameLess(a, b) return Priority.nameKey(a.player) < Priority.nameKey(b.player) end

local function byPriority(a, b)
  if a.offspec ~= b.offspec then return not a.offspec end -- main spec first, always
  local ta, tb = a.tier or huge, b.tier or huge
  if ta ~= tb then return ta < tb end
  if a.bis ~= b.bis then return a.bis end -- BiS above Main within a tier
  local ra, rb = a.roll or 0, b.roll or 0
  if ra ~= rb then return ra > rb end
  return nameLess(a, b)
end

local function byRoll(a, b)
  if a.offspec ~= b.offspec then return not a.offspec end
  local ra, rb = a.roll or 0, b.roll or 0
  if ra ~= rb then return ra > rb end
  return nameLess(a, b)
end

-- resolve(item, entries, rules) -> result
-- entries: { player, class, spec, response, roll, max [, ignored] }; max 100 = main spec
-- (BiS when response is "bis", Upgrade otherwise), rules.offspecRollMax (99) = off-spec.
-- Ignored entries are skipped. A council session takes no rolls: an answer (BiS / Main / OS)
-- with no roll ranks by main spec, tier and BiS alone, and equal answers tie for the council
-- to decide by vote. In a plain roll an entry still waiting for its roll is skipped.
-- result: { ranked, winner, by, allOffspec, highestRoll, tie }
--   by is "priority", "highest-roll" or "none" (nobody rolled).
--   In allOffspecMode "ask" with only off-spec rolls, winner is nil and the LC picks
--   between ranked[1] (by priority) and highestRoll.
function Resolver.resolve(item, entries, rules)
  rules = Resolver.rules(rules)
  local live = {}
  for _, e in ipairs(entries) do
    if not e.ignored and (e.roll or (not rules.rolls and e.response)) then
      e.offspec = (e.max == rules.offspecRollMax) or (e.max == nil and e.response == "offspec")
      e.bis = not e.offspec and e.response == "bis"
      e.tier = Priority.tierOf(item, e)
      live[#live + 1] = e
    end
  end
  if #live == 0 then
    return { ranked = live, winner = nil, by = "none", allOffspec = false, tie = false }
  end

  local allOffspec, anyRoll = true, false
  for _, e in ipairs(live) do
    if not e.offspec then allOffspec = false end
    if e.roll then anyRoll = true end
  end

  table.sort(live, byPriority)
  local result = { ranked = live, winner = live[1], by = "priority", allOffspec = allOffspec }
  -- with only OS answers, the highest roll can be offered too; with no rolls the list decides
  if allOffspec and anyRoll and rules.allOffspecMode ~= "priority" then
    local copy = { unpack(live) }
    table.sort(copy, byRoll)
    result.highestRoll = copy[1]
    if rules.allOffspecMode == "highest" then result.winner, result.by = copy[1], "highest-roll" end
    if rules.allOffspecMode == "ask" then result.winner = nil end -- window shows both, LC picks
  end
  -- A tie is on whatever decided the winner: tier, BiS and roll by priority, the roll alone
  -- when the highest roll decides.
  local order, sameRank = live, function(x, y) return x.offspec == y.offspec and x.bis == y.bis and x.tier == y.tier and x.roll == y.roll end
  if result.by == "highest-roll" then
    order = { unpack(live) }
    table.sort(order, byRoll)
    sameRank = function(x, y) return x.offspec == y.offspec and x.roll == y.roll end
  end
  local a, b = order[1], order[2]
  result.tie = (b ~= nil and sameRank(a, b)) or false
  if result.tie then
    result.tied = {}
    for _, e in ipairs(order) do
      if sameRank(a, e) then result.tied[#result.tied + 1] = e.player end
    end
  end
  return result
end

-- highestRoll(entries, rules): the plain /roll winner, ignoring the list (main spec still first).
function Resolver.highestRoll(entries, rules)
  rules = Resolver.rules(rules)
  local best
  for _, e in ipairs(entries) do
    if not e.ignored and e.roll then
      e.offspec = (e.max == rules.offspecRollMax) or (e.max == nil and e.response == "offspec")
      if not best or byRoll(e, best) then best = e end
    end
  end
  return best
end

return Resolver
