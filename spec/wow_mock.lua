-- A small fake of the WoW client API: enough to load the whole addon from its .toc,
-- fire events and slash commands, and see what it sends to chat and addon channels.
--
-- W.install() / W.load() set up one client in _G, and W.fire, W.slash, ... drive it.
-- W.client(opts) makes another client in its own global table, so several raid members
-- can run the addon side by side; W.deliver() carries addon messages between them.
local H = require("spec.helper")

local M = {}

local function newWidget(C, kind, name)
  local w = { kind = kind, name = name, scripts = {}, events = {}, shown = false, text = "", children = {} }
  local methods = {}
  function methods:SetScript(which, fn) self.scripts[which] = fn end
  function methods:GetScript(which) return self.scripts[which] end
  function methods:HookScript(which, fn) self.hooks = self.hooks or {}; self.hooks[which] = fn end
  function methods:HasScript(which) return not (self.missingScripts and self.missingScripts[which]) end
  function methods:RegisterEvent(e) self.events[e] = true; C.eventFrames[self] = true end
  function methods:UnregisterEvent(e) self.events[e] = nil end
  function methods:Show() self.shown = true end
  function methods:Hide() self.shown = false end
  function methods:SetShown(v) self.shown = v and true or false end
  function methods:IsShown() return self.shown end
  function methods:SetText(t) self.text = t end
  function methods:GetText() return self.text end
  function methods:CreateFontString() return newWidget(C, "FontString") end
  function methods:CreateTexture() return newWidget(C, "Texture") end
  function methods:GetName() return self.name end
  -- a GameTooltip shown from a link fires OnTooltipSetItem, as the client does
  function methods:SetHyperlink(link)
    self.link, self.lines = link, nil
    local id = link:match("item:(%d+)")
    self.GetItem = function() return nil, "|Hitem:" .. id .. "::|h[Item]|h" end
    if self.hooks and self.hooks.OnTooltipSetItem then self.hooks.OnTooltipSetItem(self) end
  end
  function methods:AddLine(t) self.lines = self.lines or {}; table.insert(self.lines, t) end
  -- any other method is a no-op; plain fields stay nil
  return setmetatable(w, { __index = function(_, k)
    if methods[k] then return methods[k] end
    if type(k) == "string" and k:match("^%u") then return function() end end
  end })
end

-- setup(C, G, opts): install a fake client into the global table G, its state kept on C
local function setup(C, G, opts)
  opts = opts or {}
  C.env = G
  C.eventFrames, C.chat, C.addon, C.printed, C.rolls = {}, {}, {}, {}, {}
  C.time = opts.time or 1792614670
  C.me = opts.me or "Poohtank"
  C.group = opts.group or {
    { name = "Poohtank", class = "PALADIN", leader = true },
    { name = "Anasazi", class = "ROGUE" }, { name = "Gally", class = "WARRIOR" },
    { name = "Hadur", class = "SHAMAN", assist = true },
  }
  C.timers, C.later, C.inspects = {}, {}, {}
  G.WOW_PROJECT_ID, G.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = opts.project or 5, 5
  G.RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
  G.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 1, b = 1 } end })
  G.UIParent = newWidget(C, "Frame", "UIParent")
  G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, t) table.insert(C.printed, t) end }
  G.UISpecialFrames, G.StaticPopupDialogs, G.SlashCmdList = {}, {}, {}
  G.ACCEPT, G.CANCEL = "Accept", "Cancel"
  G.tinsert = table.insert
  G.date, G.time = os.date, function() return C.time end
  G.GameTooltip = newWidget(C, "GameTooltip", "GameTooltip")
  G.ItemRefTooltip = newWidget(C, "GameTooltip", "ItemRefTooltip")
  -- opts.tooltipData: a TooltipDataProcessor whose post calls land in C.tooltipPostCalls
  -- (the TBC Classic client has one, but its tooltips never call it);
  -- opts.noSetItem: tooltips without OnTooltipSetItem, as on clients that removed it
  C.tooltipPostCalls = {}
  G.TooltipDataProcessor = opts.tooltipData and {
    AddTooltipPostCall = function(kind, fn) table.insert(C.tooltipPostCalls, { kind = kind, fn = fn }) end,
  } or nil
  G.Enum = opts.tooltipData and { TooltipDataType = { Item = 0 } } or nil
  if opts.noSetItem then
    G.GameTooltip.missingScripts = { OnTooltipSetItem = true }
    G.ItemRefTooltip.missingScripts = { OnTooltipSetItem = true }
  end
  G.CreateFrame = function(kind, name) local w = newWidget(C, kind, name); if name then G[name] = w end; return w end
  G.GetServerTime = function() return C.time end
  G.GetAddOnMetadata = function() return "0.1.0" end
  G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, text, dist, target)
      table.insert(C.addon, { prefix = prefix, text = text, dist = dist, target = target })
    end,
  }
  G.C_Timer = {
    NewTicker = function(_, fn) table.insert(C.timers, fn) end,
    After = function(_, fn) table.insert(C.later, fn) end,
  }
  G.SendChatMessage = function(text, ch) table.insert(C.chat, { text = text, channel = ch }) end
  G.RandomRoll = function(a, b) table.insert(C.rolls, { a, b }) end
  G.IsInRaid = function() return true end
  G.IsInGroup = function() return true end
  G.GetNumGroupMembers = function() return #C.group end
  G.GetNumSubgroupMembers = function() return 0 end
  local function member(unit)
    if unit == "player" then
      for _, m in ipairs(C.group) do if m.name == C.me then return m end end
    end
    local i = tonumber((unit or ""):match("^raid(%d+)$"))
    return i and C.group[i]
  end
  G.GetTime = function() return C.time end
  G.UnitGUID = function(unit) local m = member(unit); return m and ("Player-" .. m.name) end
  G.UnitName = function(unit) local m = member(unit); return m and m.name end
  G.UnitClass = function(unit) local m = member(unit); return m and m.class, m and m.class end
  G.UnitIsUnit = function(a, b) local x, y = member(a), member(b); return x ~= nil and x == y end
  G.UnitIsGroupLeader = function(unit) local m = member(unit); return m and m.leader or false end
  G.UnitIsGroupAssistant = function(unit) local m = member(unit); return m and m.assist or false end
  G.Ambiguate = function(n) return n end
  -- talents: the player's own, or the last NotifyInspect target's when inspect is true
  G.GetTalentTabInfo = function(i, inspect)
    local m = inspect and C.inspecting or member("player")
    return "tab", "icon", ((m and m.talents) or {})[i] or 0
  end
  G.NotifyInspect = function(unit) C.inspecting = member(unit); table.insert(C.inspects, unit) end
  G.ClearInspectPlayer = function() C.inspecting = nil end
  G.GetInstanceInfo = function() return "Gruul's Lair" end
  G.GetRealmName = function() return "Spineshatter" end
  G.GetItemInfo = function(id) return "Item " .. id, "|cffa335ee|Hitem:" .. id .. "::::::::70:::::|h[Item " .. id .. "]|h|r" end
  G.GetItemInfoInstant = function() return nil end
  -- the corpse being looted: C.corpse = { { id, name, quality, source }, ... } (W.loot fills it)
  C.corpse = {}
  G.GetNumLootItems = function() return #C.corpse end
  G.GetLootSlotLink = function(i)
    local l = C.corpse[i]
    return l and string.format("|cffa335ee|Hitem:%d::::::::70:::::|h[%s]|h|r", l[1], l[2])
  end
  G.GetLootSlotInfo = function(i) local l = C.corpse[i]; return "icon", l and l[2], 1, nil, l and l[3] end
  G.GetLootSourceInfo = function(i) local l = C.corpse[i]; return l and l[4], 1 end
  G.GetBuildInfo = function() return "2.5.5", "65000", "Oct 1 2026", 20505 end
  G.GetItemIcon = function() return "icon" end
  G.InCombatLockdown = function() return false end
  G.CanInspect = function() return opts.canInspect or false end
  G.CheckInteractDistance = function() return opts.canInspect or false end
  G.StaticPopup_Show = function() end
  G.ChatFontNormal = {}
  -- a client in its own table starts with its own SavedVariables, never _G's
  G.ToadsLCDB = opts.db or (G ~= _G and {} or nil)
end

-- load(C): run every file listed in ToadsLC.toc, as the client does.
local function load(C)
  local ns = {}
  for line in H.read("ToadsLC/ToadsLC.toc"):gmatch("[^\r\n]+") do
    if not line:match("^##") and line:match("%S") then
      local path = line:gsub("\\", "/")
      local chunk = assert(loadfile(H.root .. "ToadsLC/" .. path))
      if C.env ~= _G then setfenv(chunk, C.env) end
      chunk("ToadsLC", ns)
    end
  end
  C.ns = ns
  return ns
end

local function fire(C, event, ...)
  for f in pairs(C.eventFrames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end

local function slash(C, msg) C.env.SlashCmdList.TOADSLC(msg) end

-- loot(C, items): open a corpse holding items ({ id, name, quality, source }), as LOOT_OPENED does
local function loot(C, items)
  C.corpse = items
  fire(C, "LOOT_OPENED")
end

local function tick(C, seconds)
  C.time = C.time + (seconds or 0)
  for _, fn in ipairs(C.timers) do fn() end
end

-- flush the throttled addon-message queue
local function flushComms(C)
  for f in pairs(C.eventFrames) do
    if f.events.CHAT_MSG_ADDON and f.scripts.OnUpdate then for _ = 1, 50 do f.scripts.OnUpdate(f, 1) end end
  end
end

local function chatText(C)
  local t = {}
  for _, c in ipairs(C.chat) do t[#t + 1] = c.channel .. ": " .. c.text end
  return table.concat(t, "\n")
end

local function printedText(C) return table.concat(C.printed, "\n") end

-- the default client lives in _G and is driven with W.fire(...), W.slash(...), ...
function M.install(opts) setup(M, _G, opts) end
function M.load() return load(M) end
function M.fire(...) return fire(M, ...) end
function M.slash(msg) return slash(M, msg) end
function M.loot(items) return loot(M, items) end
function M.tick(seconds) return tick(M, seconds) end
function M.flushComms() return flushComms(M) end
function M.chatText() return chatText(M) end

-- client(opts) -> a client in its own global table, already logged in; c:fire(...), c:slash(...), ...
local Client = { fire = fire, slash = slash, loot = loot, tick = tick, flushComms = flushComms, chatText = chatText,
                 printedText = printedText }
Client.__index = Client

function M.client(opts)
  local c = setmetatable({}, Client)
  setup(c, setmetatable({}, { __index = _G }), opts)
  load(c)
  c:fire("PLAYER_LOGIN")
  return c
end

-- deliver(clients): flush each client's addon messages and hand them to the others, as
-- CHAT_MSG_ADDON on every group member (RAID/PARTY) or the one named (WHISPER). Repeats
-- until nobody has anything left to say; returns the messages delivered.
function M.deliver(clients)
  local delivered = {}
  for _ = 1, 20 do
    local outgoing = {}
    for _, c in ipairs(clients) do
      c:flushComms()
      for _, a in ipairs(c.addon) do outgoing[#outgoing + 1] = { from = c, msg = a } end
      c.addon = {}
    end
    if #outgoing == 0 then return delivered end
    for _, o in ipairs(outgoing) do
      delivered[#delivered + 1] = o
      for _, c in ipairs(clients) do
        if c ~= o.from and (o.msg.dist ~= "WHISPER" or o.msg.target == c.me) then
          c:fire("CHAT_MSG_ADDON", o.msg.prefix, o.msg.text, o.msg.dist, o.from.me)
        end
      end
    end
  end
  error("addon messages kept flowing after 20 rounds")
end

-- tickAll(clients, seconds): advance every client's clock together
function M.tickAll(clients, seconds)
  for _, c in ipairs(clients) do c:tick(seconds) end
end

return M
