-- Prints a toads-loot-session document produced by the real addon code in the fake
-- client, for the contract check against schemas/session.json.
--   lua5.1 tools/export_sample.lua > session.export.json
package.path = "./?.lua;" .. package.path
local H = require("spec.helper")
local W = require("spec.wow_mock")

W.install()
local ns = W.load()
W.fire("PLAYER_LOGIN")
assert(ns.App.import(H.read("fixtures/priority.sample.json")))

W.slash("roll [Dragonspine Trophy]")
for _, line in ipairs({ "Anasazi rolls 41 (1-100)", "Gally rolls 97 (1-100)", "Hadur rolls 88 (1-100)",
                        "Poohtank rolls 94 (1-99)", "Anasazi rolls 99 (1-100)", "Gally rolls 400 (1-1000)" }) do
  W.fire("CHAT_MSG_SYSTEM", line)
end
W.tick(31)
W.slash("award")

W.slash("roll [Dragonspine Trophy]")
W.tick(31)
W.slash("award Gally bank for Hyjal")

W.slash("export")
io.write(_G.ToadsLCIOFrame.box:GetText(), "\n")
