-- RollParser: turns CHAT_MSG_SYSTEM roll lines into (name, roll, min, max).
-- The pattern is built from the client's own RANDOM_ROLL_RESULT format string, so every
-- locale works; the EN/DE/FR formats are kept as a fallback and for the tests.
local _, ns = ...
ns = ns or {}

local RollParser = {}
ns.RollParser = RollParser

RollParser.FORMATS = {
  enUS = "%s rolls %d (%d-%d)",
  deDE = "%s würfelt. Ergebnis: %d (%d-%d)",
  frFR = "%s obtient un %d (%d-%d).",
}

-- patternFrom("%s rolls %d (%d-%d)") -> "^(.+) rolls (%d+) %((%d+)%-(%d+)%)$"
-- Positional forms such as %1$s are accepted and their order remembered.
function RollParser.patternFrom(fmt)
  local order, n = {}, 0
  local pat = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  pat = pat:gsub("%%%%(%d?)%%?%$?([sd])", function(pos, kind)
    n = n + 1
    order[n] = tonumber(pos) or n
    return kind == "s" and "(.+)" or "(%d+)"
  end)
  return "^" .. pat .. "$", order
end

function RollParser.new(fmt)
  local pat, order = RollParser.patternFrom(fmt)
  return function(msg)
    local caps = { msg:match(pat) }
    if #caps ~= 4 then return nil end
    local v = {}
    for i, pos in ipairs(order) do v[pos] = caps[i] end
    local roll, min, max = tonumber(v[2]), tonumber(v[3]), tonumber(v[4])
    if not (v[1] and roll and min and max) then return nil end
    return v[1], roll, min, max
  end
end

local parsers
function RollParser.parse(msg)
  if not parsers then
    parsers = {}
    if RANDOM_ROLL_RESULT then parsers[1] = RollParser.new(RANDOM_ROLL_RESULT) end
    for _, fmt in pairs(RollParser.FORMATS) do parsers[#parsers + 1] = RollParser.new(fmt) end
  end
  for _, p in ipairs(parsers) do
    local name, roll, min, max = p(msg)
    if name then return name, roll, min, max end
  end
end

return RollParser
