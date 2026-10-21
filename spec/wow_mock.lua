-- A small fake of the WoW client API: enough to load the whole addon from its .toc,
-- fire events and slash commands, and see what it sends to chat and addon channels.
local H = require("spec.helper")

local M = {}

local function newWidget(kind, name)
  local w = { kind = kind, name = name, scripts = {}, events = {}, shown = false, text = "", children = {} }
  local methods = {}
  function methods:SetScript(which, fn) self.scripts[which] = fn end
  function methods:GetScript(which) return self.scripts[which] end
  function methods:HookScript(which, fn) self.hooks = self.hooks or {}; self.hooks[which] = fn end
  function methods:RegisterEvent(e) self.events[e] = true; M.eventFrames[self] = true end
  function methods:UnregisterEvent(e) self.events[e] = nil end
  function methods:Show() self.shown = true end
  function methods:Hide() self.shown = false end
  function methods:SetShown(v) self.shown = v and true or false end
  function methods:IsShown() return self.shown end
  function methods:SetText(t) self.text = t end
  function methods:GetText() return self.text end
  function methods:CreateFontString() return newWidget("FontString") end
  function methods:CreateTexture() return newWidget("Texture") end
  function methods:GetName() return self.name end
  function methods:AddLine(t) self.lines = self.lines or {}; table.insert(self.lines, t) end
  -- any other method is a no-op; plain fields stay nil
  return setmetatable(w, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:match("^%u") then return function() end end
  end })
end

function M.install(opts)
  opts = opts or {}
  M.eventFrames, M.chat, M.addon, M.printed, M.rolls = {}, {}, {}, {}, {}
  M.time = opts.time or 1792614670
  M.me = opts.me or "Poohtank"
  M.group = opts.group or {
    { name = "Poohtank", class = "PALADIN", leader = true },
    { name = "Anasazi", class = "ROGUE" }, { name = "Gally", class = "WARRIOR" },
    { name = "Hadur", class = "SHAMAN", assist = true },
  }
  M.timers = {}
  local G = _G
  G.WOW_PROJECT_ID, G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = opts.project or 5, 5
  G.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
  G.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  G.UIParent = newWidget("Frame", "UIParent")
  G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) table.insert(M.printed, t) end }
  G.UISpecialFrames, G.StaticPopupDialogs, G.SlashCmdList = {}, {}, {}
  G.ACCEPT, G.CANCEL = "Accept", "Cancel"
  G.tinsert = table.insert
  G.date, G.time = os.date, function() return M.time end
  G.GameTooltip = newWidget("GameTooltip", "GameTooltip")
  G.ItemRefTooltip = newWidget("GameTooltip", "ItemRefTooltip")
  G.CreateFrame = function(kind, name) local w = newWidget(kind, name); if name then G[name] = w end; return w end
  G.GetServerTime = function() return M.time end
  G.GetAddOnMetadata = function() return "0.1.0" end
  G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, dist, target)
      table.insert(M.addon, { prefix = prefix, text = text, dist = dist, target = target })
    end,
  }
  G.C_Timer = {
    NewTicker = function(_, fn) table.insert(M.timers, fn) end,
    After = function() end,
  }
  G.SendChatMessage = function(text, ch) table.insert(M.chat, { text = text, channel = ch }) end
  G.RandomRoll = function(a, b) table.insert(M.rolls, { a, b }) end
  G.IsInRaid = function() return true end
  G.IsInGroup = function() return true end
  G.GetNumGroupMembers = function() return #M.group end
  G.GetNumSubgroupMembers = function() return 0 end
  local function member(unit)
    if unit == "player" then
      for _, m in ipairs(M.group) do if m.name == M.me then return m end end
    end
    local i = tonumber((unit or ""):match("^raid(%d+)$"))
    return i and M.group[i]
  end
  G.UnitName = function(unit) local m = member(unit); return m and m.name end
  G.UnitClass = function(unit) local m = member(unit); return m and m.class, m and m.class end
  G.UnitIsUnit = function(a, b) local x, y = member(a), member(b); return x ~= nil and x == y end
  G.UnitIsGroupLeader = function(unit) local m = member(unit); return m and m.leader or false end
  G.UnitIsGroupAssistant = function(unit) local m = member(unit); return m and m.assist or false end
  G.Ambiguate = function(n) return n end
  G.GetTalentTabInfo = function(i) local m = member("player"); return "tab", "icon", (m.talents or {})[i] or 0 end
  G.GetInstanceInfo = function() return "Gruul's Lair" end
  G.GetRealmName = function() return "Spineshatter" end
  G.GetItemInfo = function(id) return "Item " .. id, "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[Item " .. id .. "]|h|r" end
  G.GetItemInfoInstant = function() return nil end
  G.GetItemIcon = function() return "icon" end
  G.InCombatLockdown = function() return false end
  G.CanInspect = function() return false end
  G.CheckInteractDistance = function() return false end
  G.StaticPopup_Show = function() end
  G.ChatFontNormal = {}
  G.ToadsLCDB = opts.db
end

-- load(): run every file listed in ToadsLC.toc, as the client does.
function M.load()
  local ns = {}
  for line in H.read("ToadsLC/ToadsLC.toc"):gmatch("[^\r\n]+") do
    if not line:match("^##") and line:match("%S") then
      local path = line:gsub("\\", "/")
      assert(loadfile(H.root .. "ToadsLC/" .. path))("ToadsLC", ns)
    end
  end
  M.ns = ns
  return ns
end

function M.fire(event, ...)
  for f in pairs(M.eventFrames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

function M.slash(msg) _G.SlashCmdList.TOADSLC(msg) end

function M.tick(seconds)
  M.time = M.time + (seconds or 0)
  for _, fn in ipairs(M.timers) do fn() end
end

-- flush the throttled addon-message queue
function M.flushComms()
  for f in pairs(M.eventFrames) do
    if f.events.CHAT_MSG_ADDON and f.scripts.OnUpdate then for _ = 1, 50 do f.scripts.OnUpdate(f, 1) end end
  end
end

function M.chatText()
  local t = {}
  for _, c in ipairs(M.chat) do t[#t + 1] = c.channel .. ": " .. c.text end
  return table.concat(t, "\n")
end

return M
