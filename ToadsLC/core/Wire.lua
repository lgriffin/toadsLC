-- Wire: what goes over the addon channel. A message is JSON; with a council password set,
-- every message is signed (HMAC-SHA-256 over sender, nonce and body) and the private ones
-- (responses, notes, votes, proposals, state) are encrypted, so only clients holding the
-- same password can read council traffic or pass it off as an officer's. The result is
-- split into chunks under the 255-byte addon message limit.
--
--   plain:  {...json...}
--   signed: T1|p|<nonce>|<mac>|{...json...}
--   sealed: T1|e|<nonce>|<mac>|<base64 ciphertext>
local _, ns = ...
ns = ns or {}

local Wire = {}
ns.Wire = Wire

local Codec, Crypto, Priority = ns.Codec, ns.Crypto, ns.Priority

Wire.ITERATIONS = 1000
Wire.SALT = "ToadsLC council v1"
Wire.MAC_BYTES = 16

-- Messages only the council should read. The rest stay readable so raiders without the
-- password can still follow a session's open, close and award.
Wire.PRIVATE = { RESPONSE = true, VOTE = true, PROPOSE = true, STATE = true, RSP = true }

---------------------------------------------------------------------------
-- keys
---------------------------------------------------------------------------

-- keyFromPassword(password [, iterations]) -> 32-byte key. Slow on purpose (PBKDF2), so
-- it runs once when the password is set; only the key is stored, never the password.
function Wire.keyFromPassword(password, iterations)
  return Crypto.pbkdf2(password, Wire.SALT, iterations or Wire.ITERATIONS)
end

-- secret(key) -> { mac, enc, fingerprint }; fingerprint is 8 hex digits officers can
-- compare in /tlc status to check they typed the same password.
function Wire.secret(key)
  return {
    mac = Crypto.hmac(key, "mac"),
    enc = Crypto.hmac(key, "enc"),
    fingerprint = Crypto.hex(Crypto.hmac(key, "fingerprint")):sub(1, 8),
  }
end

local function keystream(secret, sender, nonce, n)
  local out, i = {}, 0
  while #out * 32 < n do
    i = i + 1
    out[i] = Crypto.hmac(secret.enc, sender .. "|" .. nonce .. "|" .. i)
  end
  return table.concat(out):sub(1, n)
end

local function mac(secret, sender, kind, nonce, body)
  return Crypto.hex(Crypto.hmac(secret.mac, "T1|" .. sender .. "|" .. kind .. "|" .. nonce .. "|" .. body))
    :sub(1, Wire.MAC_BYTES * 2)
end

---------------------------------------------------------------------------
-- seal / open
---------------------------------------------------------------------------

local counter = 0
local function newNonce(clock)
  counter = (counter + 1) % 1000000
  return string.format("%x%x%x", math.floor(clock()), counter, math.random(0, 0xFFFFFF))
end

-- seal(msg, sender, secret, clock) -> string
function Wire.seal(msg, sender, secret, clock)
  local body = Codec.encode(msg)
  if not secret then return body end
  local who = Priority.nameKey(sender)
  local nonce = newNonce(clock or (os and os.time) or time) -- the client has time(), not os
  local kind = "p"
  if Wire.PRIVATE[msg.t] then
    kind = "e"
    body = Crypto.base64(Crypto.xor(body, keystream(secret, who, nonce, #body)))
  end
  return table.concat({ "T1", kind, nonce, mac(secret, who, kind, nonce, body), body }, "|")
end

-- open(text, sender, secret) -> msg, trusted, signed | nil, reason
-- trusted is true when the message carries a valid signature for our password, or when
-- no password is set on this client (nothing to check against); signed is true when it
-- carries a signature at all.
function Wire.open(text, sender, secret)
  if type(text) ~= "string" then return nil, "not a string" end
  local kind, nonce, tag, body = text:match("^T1|([pe])|([%x]+)|(%x+)|(.*)$")
  if not kind then
    local msg, err = Codec.decode(text)
    if not msg then return nil, err end
    return msg, secret == nil, false
  end
  local who = Priority.nameKey(sender)
  local valid = secret ~= nil and Crypto.equal(tag, mac(secret, who, kind, nonce, body))
  if kind == "e" then
    -- a raider with no password sees the council's sealed traffic on RAID all night: only a
    -- client holding a different password has something to report
    if not valid then return nil, secret and "sealed for another password" or "sealed for the council" end
    local cipher = Crypto.unbase64(body)
    if not cipher then return nil, "bad ciphertext" end
    body = Crypto.xor(cipher, keystream(secret, who, nonce, #cipher))
  end
  local msg, err = Codec.decode(body)
  if not msg then return nil, err end
  return msg, valid or secret == nil, true
end

---------------------------------------------------------------------------
-- a sender/receiver pair over chunks
---------------------------------------------------------------------------

-- new{ secret = function() -> secret|nil, clock = function() -> seconds }
function Wire.new(opts)
  local w = { opts = opts, seq = 0, asm = Codec.newAssembler(opts.clock) }

  -- pack(msg, me) -> chunks
  function w.pack(msg, me)
    w.seq = (w.seq % 9999) + 1
    return Codec.wireChunks(Wire.seal(msg, me, opts.secret(), opts.clock), tostring(w.seq))
  end

  -- unpack(sender, chunk) -> msg, trusted, signed once every chunk has arrived
  function w.unpack(sender, chunk)
    local text, err = w.asm.feed(sender, chunk)
    if not text then return nil, err end
    return Wire.open(text, sender, opts.secret())
  end

  return w
end

return Wire
