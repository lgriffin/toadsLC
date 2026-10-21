local H = require("spec.helper")

describe("Crypto", function()
  local C
  before_each(function() C = H.core().Crypto end)

  it("matches the SHA-256, HMAC and PBKDF2 test vectors", function()
    assert.are.equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", C.hex(C.sha256("")))
    assert.are.equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", C.hex(C.sha256("abc")))
    assert.are.equal("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
      C.hex(C.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")))
    assert.are.equal("f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
      C.hex(C.hmac("key", "The quick brown fox jumps over the lazy dog")))
    assert.are.equal("120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b",
      C.hex(C.pbkdf2("password", "salt", 1)))
    assert.are.equal("c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a",
      C.hex(C.pbkdf2("password", "salt", 4096)))
  end)

  it("round-trips base64 and hex", function()
    for _, s in ipairs({ "", "a", "ab", "abc", "hello!?", "\0\1\255" }) do
      assert.are.equal(s, C.unbase64(C.base64(s)))
      assert.are.equal(s, C.unhex(C.hex(s)))
    end
    assert.are.equal("aGVsbG8hPw==", C.base64("hello!?"))
    assert.is_nil(C.unbase64("abc"))
  end)
end)

describe("Wire", function()
  local ns, Wire, secret, other
  before_each(function()
    ns = H.core()
    Wire = ns.Wire
    secret = Wire.secret(Wire.keyFromPassword("frog-pond-42", 10))
    other = Wire.secret(Wire.keyFromPassword("wrong password", 10))
  end)

  local vote = { t = "VOTE", s = "2026-10-25T20:31:10Z-28830", p = "Anasazi", q = 1 }
  local award = { t = "AWARD", s = "2026-10-25T20:31:10Z-28830", p = "Anasazi", via = "list" }

  it("signs and encrypts council messages for holders of the same password", function()
    local text = Wire.seal(vote, "Hadur", secret)
    assert.matches("^T1|e|", text)
    assert.is_nil(text:find("Anasazi", 1, true)) -- the vote is not readable on the wire
    local msg, trusted = Wire.open(text, "Hadur-Spineshatter", secret)
    assert.is_true(trusted)
    assert.are.equal("Anasazi", msg.p)
  end)

  it("signs public messages but leaves them readable for raiders", function()
    local text = Wire.seal(award, "Poohtank", secret)
    assert.matches("^T1|p|", text)
    local msg, trusted = Wire.open(text, "Poohtank", nil) -- a raider without the password
    assert.are.equal("Anasazi", msg.p)
    assert.is_true(trusted) -- nothing to check against on that client
    msg, trusted = Wire.open(text, "Poohtank", other)
    assert.are.equal("Anasazi", msg.p)
    assert.is_false(trusted)
  end)

  it("cannot be read or passed off with another password, another sender or a changed body", function()
    local text = Wire.seal(vote, "Hadur", secret)
    assert.is_nil((Wire.open(text, "Hadur", other)))
    assert.is_nil((Wire.open(text, "Raider", secret))) -- replayed under another name
    local signed = Wire.seal(award, "Poohtank", secret)
    local forged = signed:gsub("Anasazi", "Raider")
    local msg, trusted = Wire.open(forged, "Poohtank", secret)
    assert.are.equal("Raider", msg.p)
    assert.is_false(trusted)
  end)

  it("treats unsigned JSON as untrusted once a password is set", function()
    local text = ns.Codec.encode(vote)
    local msg, trusted = Wire.open(text, "Raider", secret)
    assert.are.equal("VOTE", msg.t)
    assert.is_false(trusted)
    trusted = select(2, Wire.open(text, "Raider", nil))
    assert.is_true(trusted)
  end)

  it("packs into chunks under the addon message limit and back", function()
    local a = Wire.new({ secret = function() return secret end, clock = function() return 0 end })
    local b = Wire.new({ secret = function() return secret end, clock = function() return 0 end })
    local big = { t = "PROPOSE", s = "x", p = "Gally", re = string.rep("Hyjal DPS check ", 30) }
    local msg, trusted
    for _, chunk in ipairs(a.pack(big, "Poohtank")) do
      assert.is_true(#chunk <= 255)
      msg, trusted = b.unpack("Poohtank", chunk)
    end
    assert.are.equal(big.re, msg.re)
    assert.is_true(trusted)
  end)
end)
