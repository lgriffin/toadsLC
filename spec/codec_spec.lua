local H = require("spec.helper")

describe("Codec", function()
  local ns, Codec
  before_each(function()
    ns = H.core()
    Codec = ns.Codec
  end)

  describe("JSON", function()
    it("round-trips both sample documents", function()
      for _, path in ipairs({ "fixtures/priority.sample.json", "fixtures/session.sample.json" }) do
        local doc = assert(Codec.decode(H.read(path)))
        local again = assert(Codec.decode(Codec.encode(doc)))
        assert.are.equal(Codec.encode(doc), Codec.encode(again))
        assert.are.equal(Codec.encode(doc, "  "), Codec.encode(again, "  "))
      end
    end)

    it("keeps empty arrays and objects apart", function()
      local doc = assert(Codec.decode('{"a":[],"b":{},"c":null}'))
      assert.are.equal('{"a":[],"b":{},"c":null}', Codec.encode(doc))
    end)

    it("decodes escapes and unicode", function()
      local s = assert(Codec.decode('"a\\"b\\\\c\\n\\u00e9\\ud83d\\ude00"'))
      assert.are.equal('a"b\\c\n\195\169\240\159\152\128', s)
    end)

    it("encodes numbers as integers where they are", function()
      assert.are.equal("[1,2.5,-3]", Codec.encode({ 1, 2.5, -3 }))
    end)

    it("reports where malformed JSON breaks", function()
      local v, err = Codec.decode('{"a": [1, 2,}')
      assert.is_nil(v)
      assert.matches("character 13", err)
      assert.is_nil((Codec.decode("[1] x")))
      assert.is_nil((Codec.decode('"open')))
    end)
  end)

  describe("priority schema", function()
    local function sample() return assert(Codec.decode(H.read("fixtures/priority.sample.json"))) end

    it("accepts the sample document", function()
      assert.is_true(Codec.validatePriority(sample()))
    end)

    it("When a user pastes JSON into the import frame, the addon shall reject the whole file on the first error, naming the item and field", function()
      local doc = sample()
      doc.items[1].priority[3][1].spec = "Shamans"
      local ok, err = Codec.validatePriority(doc)
      assert.is_false(ok)
      assert.are.equal('items[0].priority[2][0].spec "Shamans" is not a known token', err)
    end)

    it("rejects the wrong format, version, empty tiers, unknown fields and bad members", function()
      local cases = {
        { function(d) d.format = "toads-loot-session" end, "^format must be one of" },
        { function(d) d.version = 2 end, "^version must be 1" },
        { function(d) d.items[1].priority[2] = Codec.array() end, "^items%[0%]%.priority%[1%] must not be an empty tier" },
        { function(d) d.items[1].colour = "red" end, "^items%[0%] has unknown field colour" },
        { function(d) d.items[1].name = nil end, "^items%[0%]%.name must be a string" },
        { function(d) d.members[1].spec = "Warrior:Fury" end, '^members%[0%]%.spec "Warrior:Fury" is not a Rogue spec' },
        { function(d) d.rules.allOffspecMode = "dice" end, "^rules%.allOffspecMode must be one of" },
        { function(d) d.items[1].priority[1][1] = { spec = "Rogue:*", player = "Tajt" } end, "not both" },
      }
      for _, c in ipairs(cases) do
        local doc = sample()
        c[1](doc)
        local ok, err = Codec.validatePriority(doc)
        assert.is_false(ok)
        assert.matches(c[2], err)
      end
    end)
  end)

  describe("session schema", function()
    it("accepts the sample document", function()
      local doc = assert(Codec.decode(H.read("fixtures/session.sample.json")))
      assert.is_true(Codec.validateSession(doc))
    end)

    it("rejects an unknown awardedVia", function()
      local doc = assert(Codec.decode(H.read("fixtures/session.sample.json")))
      doc.sessions[1].awardedVia = "coin-flip"
      local ok, err = Codec.validateSession(doc)
      assert.is_false(ok)
      assert.matches("^sessions%[0%]%.awardedVia must be one of", err)
    end)
  end)

  describe("wire format", function()
    it("splits long messages into chunks under the addon message limit and reassembles them", function()
      local msg = { t = "STATE", note = string.rep("x", 1000), list = { 1, 2, 3 } }
      local chunks = Codec.wireChunks(msg, "7")
      assert.is_true(#chunks > 1)
      local asm = Codec.newAssembler()
      local got
      for i = #chunks, 1, -1 do -- out of order
        assert.is_true(#chunks[i] <= 255)
        got = asm.feed("Gally", chunks[i])
      end
      got = Codec.decode(got)
      assert.are.equal(Codec.encode(msg), Codec.encode(got))
    end)

    it("bounds and expires incomplete messages", function()
      local t = 0
      local asm = Codec.newAssembler(function() return t end)
      assert.is_nil(select(1, asm.feed("A", "1:1/65:x")))
      for i = 1, Codec.MAX_PENDING do assert.is_nil(asm.feed("A", i .. ":1/2:x")) end
      local _, err = asm.feed("A", "late:1/2:x")
      assert.are.equal("too many incomplete messages", err)
      t = Codec.PENDING_SECONDS + 1
      _, err = asm.feed("A", "late:1/2:x")
      assert.is_nil(err)
    end)

    it("keeps senders apart", function()
      local asm = Codec.newAssembler()
      local a = Codec.wireChunks({ t = "VOTE", p = string.rep("a", 300) }, "1")
      local b = Codec.wireChunks({ t = "VOTE", p = string.rep("b", 300) }, "1")
      assert.is_nil(asm.feed("A", a[1]))
      assert.is_nil(asm.feed("B", b[1]))
      assert.are.equal(string.rep("a", 300), Codec.decode(asm.feed("A", a[2])).p)
      assert.are.equal(string.rep("b", 300), Codec.decode(asm.feed("B", b[2])).p)
    end)
  end)
end)
