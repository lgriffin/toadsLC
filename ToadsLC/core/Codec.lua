-- Codec: JSON encode/decode, schema checks for the two Toads documents, and the
-- compact wire format for addon messages. No WoW API calls: runs under plain Lua 5.1.
local _, ns = ...
ns = ns or {}

local Codec = {}
ns.Codec = Codec

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local strbyte, strchar, strfind, strformat, strsub = string.byte, string.char, string.find, string.format, string.sub
local concat, floor, huge = table.concat, math.floor, math.huge

Codec.PRIORITY_FORMAT = "toads-loot-priority"
Codec.SESSION_FORMAT = "toads-loot-session"
Codec.VERSION = 1

---------------------------------------------------------------------------
-- null, arrays and objects
---------------------------------------------------------------------------

-- JSON null. Lua nil cannot live in a table, so decoded nulls become this sentinel.
Codec.null = setmetatable({}, { __tostring = function() return "null" end })

local ARRAY = { __jsontype = "array" }
local OBJECT = { __jsontype = "object" }

-- Mark a table so it encodes as [] / {} even when empty.
function Codec.array(t) return setmetatable(t or {}, ARRAY) end
function Codec.object(t) return setmetatable(t or {}, OBJECT) end

local function isNull(v) return v == nil or v == Codec.null end
Codec.isNull = isNull

-- stripNulls(v): the same value with every null removed, for storing in SavedVariables
-- (which would turn the sentinel into an empty table).
function Codec.stripNulls(v)
  if v == Codec.null then return nil end
  if type(v) ~= "table" then return v end
  local out = setmetatable({}, getmetatable(v))
  for k, x in pairs(v) do out[k] = Codec.stripNulls(x) end
  return out
end

local function isArray(t)
  local mt = getmetatable(t)
  if mt == ARRAY then return true end
  if mt == OBJECT then return false end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or floor(k) ~= k then return false end
    if k > n then n = k end
  end
  for i = 1, n do if t[i] == nil then return false end end
  return true -- an unmarked empty table is an array
end

---------------------------------------------------------------------------
-- encode
---------------------------------------------------------------------------

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
                  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function escapeString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or strformat("\\u%04x", strbyte(c))
  end) .. '"'
end

-- format and version lead so a reader sees what the document is; the rest is sorted
-- so the same data always produces the same text.
local KEY_RANK = { format = 1, version = 2 }
local function keyLess(a, b)
  local ra, rb = KEY_RANK[a] or 99, KEY_RANK[b] or 99
  if ra ~= rb then return ra < rb end
  return a < b
end

local encodeValue

local function encodeTable(t, indent, depth, seen)
  if seen[t] then error("cannot encode a table that contains itself") end
  seen[t] = true
  local nl, pad, padIn, sep = "", "", "", ":"
  if indent then
    nl = "\n"
    pad = indent:rep(depth)
    padIn = indent:rep(depth + 1)
    sep = ": "
  end
  local parts = {}
  local out
  if isArray(t) then
    for i = 1, #t do parts[i] = padIn .. encodeValue(t[i], indent, depth + 1, seen) end
    out = #parts == 0 and "[]" or ("[" .. nl .. concat(parts, "," .. nl) .. nl .. pad .. "]")
  else
    local keys = {}
    for k in pairs(t) do
      if type(k) ~= "string" then error("object keys must be strings, got " .. type(k)) end
      keys[#keys + 1] = k
    end
    table.sort(keys, keyLess)
    for i, k in ipairs(keys) do
      parts[i] = padIn .. escapeString(k) .. sep .. encodeValue(t[k], indent, depth + 1, seen)
    end
    out = #parts == 0 and "{}" or ("{" .. nl .. concat(parts, "," .. nl) .. nl .. pad .. "}")
  end
  seen[t] = nil
  return out
end

function encodeValue(v, indent, depth, seen)
  local tv = type(v)
  if v == nil or v == Codec.null then return "null"
  elseif tv == "boolean" then return tostring(v)
  elseif tv == "number" then
    if v ~= v or v == huge or v == -huge then error("cannot encode " .. tostring(v)) end
    if floor(v) == v and v > -1e15 and v < 1e15 then return strformat("%d", v) end
    return strformat("%.14g", v)
  elseif tv == "string" then return escapeString(v)
  elseif tv == "table" then return encodeTable(v, indent, depth, seen)
  end
  error("cannot encode a " .. tv)
end

-- encode(value [, indent]) -> string. indent is e.g. "  " for pretty output.
function Codec.encode(value, indent)
  return encodeValue(value, indent, 0, {})
end

---------------------------------------------------------------------------
-- decode
---------------------------------------------------------------------------

local function utf8char(cp)
  if cp < 0x80 then return strchar(cp)
  elseif cp < 0x800 then return strchar(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return strchar(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return strchar(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40,
                 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local UNESCAPE = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local Decoder = {}
Decoder.__index = Decoder

function Decoder:fail(msg)
  error({ json = strformat("%s at character %d", msg, self.pos) }, 0)
end

function Decoder:skip()
  local _, e = strfind(self.s, "^[ \t\r\n]*", self.pos)
  self.pos = e + 1
end

function Decoder:peek() return strsub(self.s, self.pos, self.pos) end

function Decoder:string()
  local s, pos, buf = self.s, self.pos + 1, {}
  while true do
    local a = strfind(s, '["\\%c]', pos)
    if not a then self.pos = pos; self:fail("unterminated string") end
    buf[#buf + 1] = strsub(s, pos, a - 1)
    local c = strsub(s, a, a)
    if c == '"' then self.pos = a + 1; return concat(buf) end
    if c ~= "\\" then self.pos = a; self:fail("control character in string") end
    local e = strsub(s, a + 1, a + 1)
    if e == "u" then
      local hex = strsub(s, a + 2, a + 5)
      local cp = hex:match("^%x%x%x%x$") and tonumber(hex, 16)
      if not cp then self.pos = a; self:fail("bad \\u escape") end
      local b = a + 5
      if cp >= 0xD800 and cp <= 0xDBFF then -- surrogate pair
        local lo = strsub(s, b + 1, b + 6):match("^\\u(%x%x%x%x)$")
        lo = lo and tonumber(lo, 16)
        if lo and lo >= 0xDC00 and lo <= 0xDFFF then
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
          b = b + 6
        end
      end
      buf[#buf + 1] = utf8char(cp)
      pos = b + 1
    elseif UNESCAPE[e] then
      buf[#buf + 1] = UNESCAPE[e]
      pos = a + 2
    else
      self.pos = a; self:fail("bad escape")
    end
  end
end

function Decoder:value()
  self:skip()
  local c = self:peek()
  if c == "{" then
    self.pos = self.pos + 1
    local obj = Codec.object()
    self:skip()
    if self:peek() == "}" then self.pos = self.pos + 1; return obj end
    while true do
      self:skip()
      if self:peek() ~= '"' then self:fail("expected a key") end
      local k = self:string()
      self:skip()
      if self:peek() ~= ":" then self:fail("expected ':'") end
      self.pos = self.pos + 1
      obj[k] = self:value()
      self:skip()
      c = self:peek()
      self.pos = self.pos + 1
      if c == "}" then return obj end
      if c ~= "," then self.pos = self.pos - 1; self:fail("expected ',' or '}'") end
    end
  elseif c == "[" then
    self.pos = self.pos + 1
    local arr = Codec.array()
    self:skip()
    if self:peek() == "]" then self.pos = self.pos + 1; return arr end
    while true do
      arr[#arr + 1] = self:value()
      self:skip()
      c = self:peek()
      self.pos = self.pos + 1
      if c == "]" then return arr end
      if c ~= "," then self.pos = self.pos - 1; self:fail("expected ',' or ']'") end
    end
  elseif c == '"' then
    return self:string()
  else
    local num = self.s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", self.pos)
    if num and num ~= "" and num ~= "-" then
      self.pos = self.pos + #num
      local n = tonumber(num)
      if not n or n ~= n or n == huge or n == -huge then self:fail("bad number") end
      return n
    end
    for word, val in pairs({ ["true"] = true, ["false"] = false, ["null"] = Codec.null }) do
      if strsub(self.s, self.pos, self.pos + #word - 1) == word then
        self.pos = self.pos + #word
        return val
      end
    end
    self:fail(c == "" and "unexpected end of input" or ("unexpected '" .. c .. "'"))
  end
end

-- decode(text) -> value | nil, err. Arrays and objects come back marked, nulls as Codec.null.
function Codec.decode(text)
  if type(text) ~= "string" then return nil, "expected a string" end
  local d = setmetatable({ s = text, pos = 1 }, Decoder)
  local ok, res = pcall(function()
    local v = d:value()
    d:skip()
    if d.pos <= #text then d:fail("trailing characters") end
    return v
  end)
  if ok then return res end
  if type(res) == "table" and res.json then return nil, res.json end
  error(res, 0)
end

---------------------------------------------------------------------------
-- schema checks
---------------------------------------------------------------------------
-- Hand-written to match schemas/priority.json and schemas/session.json; the contract
-- test validates the fixtures against both. The first failure aborts with a path such as
-- items[41].priority[2][0].spec, indexed from 0 as in the JSON.

local function fail(path, msg) error({ schema = path .. " " .. msg }, 0) end

local function describe(v)
  if isNull(v) then return "null" end
  if type(v) == "string" then return '"' .. v .. '"' end
  if type(v) == "table" then return isArray(v) and "an array" or "an object" end
  return tostring(v)
end

local function isObject(v)
  if type(v) ~= "table" or v == Codec.null then return false end
  local mt = getmetatable(v)
  if mt == OBJECT then return true end
  if mt == ARRAY then return false end
  return next(v) == nil or not isArray(v)
end

local function str(v, path, opt)
  if opt and isNull(v) then return end
  if type(v) ~= "string" then fail(path, "must be a string, got " .. describe(v)) end
end
local function nonEmpty(v, path)
  str(v, path)
  if v == "" then fail(path, "must not be empty") end
end
local function int(v, path, opt, min, max)
  if opt and isNull(v) then return end
  if type(v) ~= "number" or floor(v) ~= v then fail(path, "must be an integer, got " .. describe(v)) end
  if (min and v < min) or (max and v > max) then
    fail(path, strformat("must be between %s and %s, got %d", tostring(min), tostring(max or "any"), v))
  end
end
local function oneOf(v, path, allowed, opt)
  if opt and isNull(v) then return end
  for _, a in ipairs(allowed) do if v == a then return end end
  fail(path, "must be one of " .. concat(allowed, ", ") .. ", got " .. describe(v))
end
local function obj(v, path, opt)
  if opt and isNull(v) then return false end
  if not isObject(v) then fail(path, "must be an object, got " .. describe(v)) end
  return true
end
local function arr(v, path, opt)
  if opt and isNull(v) then return false end
  if type(v) ~= "table" or v == Codec.null or not isArray(v) then fail(path, "must be an array, got " .. describe(v)) end
  return true
end
local function only(v, path, allowed)
  local set = {}
  for _, k in ipairs(allowed) do set[k] = true end
  local extra = {}
  for k in pairs(v) do if not set[k] then extra[#extra + 1] = tostring(k) end end
  if #extra > 0 then
    table.sort(extra)
    fail(path, "has unknown field " .. extra[1])
  end
end
local function header(doc, format)
  obj(doc, "document")
  oneOf(doc.format, "format", { format })
  int(doc.version, "version")
  if doc.version ~= Codec.VERSION then fail("version", "must be " .. Codec.VERSION .. ", got " .. describe(doc.version)) end
  nonEmpty(doc.exportedAt, "exportedAt")
end

local function checkRules(r, path)
  if not obj(r, path, true) then return end
  only(r, path, { "offspecRollMax", "allOffspecMode", "sessionSeconds", "votesVisibleTo" })
  int(r.offspecRollMax, path .. ".offspecRollMax", true, 2, 99)
  oneOf(r.allOffspecMode, path .. ".allOffspecMode", { "ask", "priority", "highest" }, true)
  int(r.sessionSeconds, path .. ".sessionSeconds", true, 5, 300)
  oneOf(r.votesVisibleTo, path .. ".votesVisibleTo", { "council", "counts" }, true)
end

local function checkNames(list, path)
  if not arr(list, path, true) then return end
  for i, n in ipairs(list) do nonEmpty(n, strformat("%s[%d]", path, i - 1)) end
end

local function checkCandidate(c, path)
  obj(c, path)
  only(c, path, { "spec", "player" })
  if c.spec ~= nil and c.player ~= nil then fail(path, "must have spec or player, not both") end
  if c.player ~= nil then nonEmpty(c.player, path .. ".player"); return end
  if c.spec == nil then fail(path, "must have spec or player") end
  str(c.spec, path .. ".spec")
  if not ns.Priority.isToken(c.spec) then fail(path .. ".spec", describe(c.spec) .. " is not a known token") end
end

local function checkItem(item, path)
  obj(item, path)
  only(item, path, { "itemId", "name", "zone", "boss", "phase", "priority", "priorityText", "notes" })
  int(item.itemId, path .. ".itemId", true, 1)
  nonEmpty(item.name, path .. ".name")
  str(item.zone, path .. ".zone", true)
  str(item.boss, path .. ".boss", true)
  int(item.phase, path .. ".phase", true, 0, 10)
  str(item.priorityText, path .. ".priorityText", true)
  str(item.notes, path .. ".notes", true)
  arr(item.priority, path .. ".priority")
  for t, tier in ipairs(item.priority) do
    local tp = strformat("%s.priority[%d]", path, t - 1)
    arr(tier, tp)
    if #tier == 0 then fail(tp, "must not be an empty tier") end
    for c, cand in ipairs(tier) do checkCandidate(cand, strformat("%s[%d]", tp, c - 1)) end
  end
end

local function checkMember(m, path)
  obj(m, path)
  only(m, path, { "name", "class", "spec" })
  nonEmpty(m.name, path .. ".name")
  str(m.class, path .. ".class")
  if not ns.Priority.CLASSES[m.class] then fail(path .. ".class", describe(m.class) .. " is not a class") end
  if m.spec ~= nil then
    str(m.spec, path .. ".spec")
    if not ns.Priority.isMemberSpec(m.spec, m.class) then
      fail(path .. ".spec", describe(m.spec) .. " is not a " .. m.class .. " spec")
    end
  end
end

local function run(fn, doc)
  local ok, err = pcall(fn, doc)
  if ok then return true end
  if type(err) == "table" and err.schema then return false, err.schema end
  error(err, 0)
end

-- validatePriority(doc) -> true | false, "items[3].priority[0][1].spec ..."
function Codec.validatePriority(doc)
  return run(function(d)
    header(d, Codec.PRIORITY_FORMAT)
    only(d, "document", { "format", "version", "exportedAt", "guild", "rules", "council", "items", "members" })
    if obj(d.guild, "guild", true) then
      only(d.guild, "guild", { "name", "realm", "region" })
      str(d.guild.name, "guild.name", true)
      str(d.guild.realm, "guild.realm", true)
      str(d.guild.region, "guild.region", true)
    end
    checkRules(d.rules, "rules")
    checkNames(d.council, "council")
    arr(d.items, "items")
    for i, item in ipairs(d.items) do checkItem(item, strformat("items[%d]", i - 1)) end
    if arr(d.members, "members", true) then
      for i, m in ipairs(d.members) do checkMember(m, strformat("members[%d]", i - 1)) end
    end
  end, doc)
end

local RESPONSES = { "main", "offspec" }
local VIA = { "votes", "proposal", "list", "highest-roll", "manual" }

local function checkSession(s, path)
  obj(s, path)
  only(s, path, { "id", "itemId", "itemName", "zone", "boss", "openedAt", "closedAt", "leader", "council",
                  "candidates", "passes", "votes", "proposal", "computedWinner", "computedBy",
                  "awardedTo", "awardedBy", "awardedVia", "override" })
  nonEmpty(s.id, path .. ".id")
  int(s.itemId, path .. ".itemId", true, 1)
  nonEmpty(s.itemName, path .. ".itemName")
  str(s.zone, path .. ".zone", true)
  str(s.boss, path .. ".boss", true)
  nonEmpty(s.openedAt, path .. ".openedAt")
  str(s.closedAt, path .. ".closedAt", true)
  nonEmpty(s.leader, path .. ".leader")
  checkNames(s.council, path .. ".council")
  arr(s.candidates, path .. ".candidates")
  for i, c in ipairs(s.candidates) do
    local cp = strformat("%s.candidates[%d]", path, i - 1)
    obj(c, cp)
    only(c, cp, { "player", "class", "spec", "response", "roll", "max", "tier", "note", "ignored" })
    nonEmpty(c.player, cp .. ".player")
    str(c.class, cp .. ".class", true)
    str(c.spec, cp .. ".spec", true)
    oneOf(c.response, cp .. ".response", RESPONSES)
    int(c.roll, cp .. ".roll", true, 0)
    int(c.max, cp .. ".max", true, 0)
    int(c.tier, cp .. ".tier", true, 1)
    str(c.note, cp .. ".note", true)
    if c.ignored ~= nil and c.ignored ~= true then str(c.ignored, cp .. ".ignored") end
  end
  int(s.passes, path .. ".passes", true, 0)
  if obj(s.votes, path .. ".votes", true) then
    for k, v in pairs(s.votes) do
      str(k, path .. ".votes key")
      str(v, path .. ".votes." .. tostring(k))
    end
  end
  if obj(s.proposal, path .. ".proposal", true) then
    only(s.proposal, path .. ".proposal", { "by", "player", "reason" })
    nonEmpty(s.proposal.by, path .. ".proposal.by")
    nonEmpty(s.proposal.player, path .. ".proposal.player")
    str(s.proposal.reason, path .. ".proposal.reason", true)
  end
  str(s.computedWinner, path .. ".computedWinner", true)
  oneOf(s.computedBy, path .. ".computedBy", { "priority", "highest-roll", "none" })
  str(s.awardedTo, path .. ".awardedTo", true)
  str(s.awardedBy, path .. ".awardedBy", true)
  oneOf(s.awardedVia, path .. ".awardedVia", VIA, true)
  if obj(s.override, path .. ".override", true) then
    only(s.override, path .. ".override", { "by", "reason" })
    nonEmpty(s.override.by, path .. ".override.by")
    str(s.override.reason, path .. ".override.reason")
  end
end

function Codec.validateSession(doc)
  return run(function(d)
    header(d, Codec.SESSION_FORMAT)
    only(d, "document", { "format", "version", "exportedAt", "exportedBy", "addonVersion", "priorityVersion", "sessions" })
    nonEmpty(d.exportedBy, "exportedBy")
    nonEmpty(d.addonVersion, "addonVersion")
    str(d.priorityVersion, "priorityVersion", true)
    arr(d.sessions, "sessions")
    for i, s in ipairs(d.sessions) do checkSession(s, strformat("sessions[%d]", i - 1)) end
  end, doc)
end

---------------------------------------------------------------------------
-- time
---------------------------------------------------------------------------

local dateFn = (os and os.date) or date

function Codec.isoTime(t)
  return dateFn("!%Y-%m-%dT%H:%M:%SZ", t)
end

---------------------------------------------------------------------------
-- wire format: addon messages are capped at 255 bytes, so a JSON payload is split
-- into numbered chunks "<msgId>:<i>/<n>:<data>" and reassembled per sender.
---------------------------------------------------------------------------

Codec.CHUNK = 230

-- wireChunks(text, msgId): text is the string to send (a table is JSON-encoded first).
function Codec.wireChunks(text, msgId)
  local body = type(text) == "table" and Codec.encode(text) or text
  local n = math.max(1, math.ceil(#body / Codec.CHUNK))
  local out = {}
  for i = 1, n do
    out[i] = strformat("%s:%d/%d:%s", msgId, i, n, strsub(body, (i - 1) * Codec.CHUNK + 1, i * Codec.CHUNK))
  end
  return out
end

Codec.MAX_PARTS = 128       -- about 29 KB: a full STATE, encrypted and base64'd, fits easily
Codec.MAX_PENDING = 100     -- incomplete messages held at once, across senders
Codec.PENDING_SECONDS = 30  -- an incomplete message older than this is dropped

-- Assembler: feed(sender, chunk) returns the reassembled text once every part has arrived.
-- clock() (optional) returns seconds; incomplete messages expire after PENDING_SECONDS.
function Codec.newAssembler(clock)
  local pending, count = {}, 0
  local A = {}
  local function expire(now)
    for key, p in pairs(pending) do
      if now - p.at > Codec.PENDING_SECONDS then pending[key] = nil; count = count - 1 end
    end
  end
  function A.feed(sender, chunk)
    local id, i, n, data = chunk:match("^([^:]+):(%d+)/(%d+):(.*)$")
    if not id then return nil, "malformed chunk" end
    i, n = tonumber(i), tonumber(n)
    if i < 1 or i > n or n > Codec.MAX_PARTS then return nil, "malformed chunk" end
    local now = clock and clock() or 0
    local key = sender .. "\0" .. id
    local p = pending[key]
    if not p then
      if count >= Codec.MAX_PENDING then expire(now) end
      if count >= Codec.MAX_PENDING then return nil, "too many incomplete messages" end
      p = { n = n, got = 0, parts = {}, at = now }
      pending[key] = p
      count = count + 1
    end
    if p.n ~= n then return nil, "malformed chunk" end
    if not p.parts[i] then p.parts[i] = data; p.got = p.got + 1 end
    if p.got < p.n then return nil end
    pending[key] = nil
    count = count - 1
    return concat(p.parts)
  end
  return A
end

return Codec
