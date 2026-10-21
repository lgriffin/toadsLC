-- Crypto: SHA-256, HMAC-SHA-256, PBKDF2 and base64 in plain Lua 5.1 on the `bit` library
-- (a global in the WoW client, LuaBitOp elsewhere). All words are kept as unsigned
-- numbers in [0, 2^32) so either flavour of `bit` gives the same answers.
local _, ns = ...
ns = ns or {}

local Crypto = {}
ns.Crypto = Crypto

local bit = bit or require("bit") -- luacheck: ignore 113
local band, bor, bxor, bnot, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.lshift, bit.rshift
local strbyte, strchar, strrep, strformat, concat = string.byte, string.char, string.rep, string.format, table.concat
local floor = math.floor

local MOD = 4294967296

local function u32(x) return x % MOD end
local function ror(x, n) return u32(bor(rshift(x, n), lshift(x, 32 - n))) end

local K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function compress(H, block, offset)
  local w = {}
  for i = 0, 15 do
    local a, b, c, d = strbyte(block, offset + i * 4 + 1, offset + i * 4 + 4)
    w[i] = ((a * 256 + b) * 256 + c) * 256 + d
  end
  for i = 16, 63 do
    local x, y = w[i - 15], w[i - 2]
    local s0 = bxor(bxor(ror(x, 7), ror(x, 18)), rshift(x, 3))
    local s1 = bxor(bxor(ror(y, 17), ror(y, 19)), rshift(y, 10))
    w[i] = u32(w[i - 16] + u32(s0) + w[i - 7] + u32(s1))
  end
  local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
  for i = 0, 63 do
    local S1 = u32(bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25)))
    local ch = u32(bxor(band(e, f), band(bnot(e), g)))
    local t1 = u32(h + S1 + ch + K[i + 1] + w[i])
    local S0 = u32(bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22)))
    local maj = u32(bxor(bxor(band(a, b), band(a, c)), band(b, c)))
    local t2 = u32(S0 + maj)
    h, g, f, e, d, c, b, a = g, f, e, u32(d + t1), c, b, a, u32(t1 + t2)
  end
  H[1], H[2], H[3], H[4] = u32(H[1] + a), u32(H[2] + b), u32(H[3] + c), u32(H[4] + d)
  H[5], H[6], H[7], H[8] = u32(H[5] + e), u32(H[6] + f), u32(H[7] + g), u32(H[8] + h)
end

local function word(x)
  return strchar(floor(x / 16777216) % 256, floor(x / 65536) % 256, floor(x / 256) % 256, x % 256)
end

-- sha256(s) -> 32-byte binary digest
function Crypto.sha256(s)
  local len = #s
  local padded = s .. "\128" .. strrep("\0", (55 - len) % 64) .. word(floor(len * 8 / MOD)) .. word((len * 8) % MOD)
  local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
  for offset = 0, #padded - 1, 64 do compress(H, padded, offset) end
  local out = {}
  for i = 1, 8 do out[i] = word(H[i]) end
  return concat(out)
end

local function xorStrings(a, b)
  local out = {}
  for i = 1, #a do out[i] = strchar(bxor(strbyte(a, i), strbyte(b, i))) end
  return concat(out)
end
Crypto.xor = xorStrings

local IPAD, OPAD = strrep("\54", 64), strrep("\92", 64)

-- hmac(key, msg) -> 32-byte binary HMAC-SHA-256
function Crypto.hmac(key, msg)
  if #key > 64 then key = Crypto.sha256(key) end
  key = key .. strrep("\0", 64 - #key)
  return Crypto.sha256(xorStrings(key, OPAD) .. Crypto.sha256(xorStrings(key, IPAD) .. msg))
end

-- pbkdf2(password, salt, iterations) -> 32-byte key (PBKDF2-HMAC-SHA-256, one block)
function Crypto.pbkdf2(password, salt, iterations)
  local u = Crypto.hmac(password, salt .. "\0\0\0\1")
  local t = u
  for _ = 2, iterations do
    u = Crypto.hmac(password, u)
    t = xorStrings(t, u)
  end
  return t
end

function Crypto.hex(s)
  return (s:gsub(".", function(c) return strformat("%02x", strbyte(c)) end))
end

function Crypto.unhex(h)
  if type(h) ~= "string" or #h % 2 == 1 or h:find("[^%x]") then return nil end
  return (h:gsub("%x%x", function(x) return strchar(tonumber(x, 16)) end))
end

-- equal(a, b): compare without stopping at the first difference
function Crypto.equal(a, b)
  if type(a) ~= "string" or type(b) ~= "string" or #a ~= #b then return false end
  local diff = 0
  for i = 1, #a do diff = bor(diff, bxor(strbyte(a, i), strbyte(b, i))) end
  return diff == 0
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INV = {}
for i = 1, 64 do B64INV[B64:sub(i, i)] = i - 1 end

function Crypto.base64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = strbyte(s, i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local q1, q2, q3, q4 = floor(n / 262144) % 64, floor(n / 4096) % 64, floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(q1 + 1, q1 + 1) .. B64:sub(q2 + 1, q2 + 1)
      .. (b and B64:sub(q3 + 1, q3 + 1) or "=") .. (c and B64:sub(q4 + 1, q4 + 1) or "=")
  end
  return concat(out)
end

function Crypto.unbase64(s)
  if type(s) ~= "string" or #s % 4 ~= 0 then return nil end
  local out = {}
  for i = 1, #s, 4 do
    local q = { s:byte(i, i + 3) }
    local v, pad = 0, 0
    for j = 1, 4 do
      local ch = strchar(q[j])
      local d = B64INV[ch]
      if ch == "=" and i + 3 == #s and j >= 3 then pad = pad + 1; d = 0 end
      if not d then return nil end
      v = v * 64 + d
    end
    local bytes = strchar(floor(v / 65536) % 256, floor(v / 256) % 256, v % 256)
    out[#out + 1] = bytes:sub(1, 3 - pad)
  end
  return concat(out)
end

return Crypto
