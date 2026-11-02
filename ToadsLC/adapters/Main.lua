-- Main: the Toads LC window (/tlc, or the minimap button). Pages down a side bar, so nothing
-- needs a slash command: a Raider part anyone can use (tonight's loot and their rolls), and a
-- Loot Council part that stays locked until this character has tonight's raid password
-- (Begin for the raid leader, Join for officers, the same password /tlc begin|join take).
-- Every /tlc command has a button here; the slash commands still work as shortcuts.
--
-- Like the other frames, the pages only read state and call ns.App, ns.Loot, ns.Trade and
-- ns.Sim actions; they never change a session themselves.
local _, ns = ...

local Main = {}
ns.Main = Main

local U = ns.Frames.ui
local Priority, LootList = ns.Priority, ns.LootList
local AMBER, GREEN, GREY, RED, BLUE = U.AMBER, U.GREEN, U.GREY, U.RED, U.BLUE
local T = U.THEME
local colourText = U.colourText

local NAV_W = 150
Main.TRADE_WINDOW = 2 * 3600 -- raid loot can be traded to the raid for two hours after it is looted

local main
local pages, order = {}, {}
local current
-- "Lock" in the side bar hides the council pages again until the password is typed; kept per
-- character, so a /reload doesn't lift it
local function isLocked() return ns.Store.layout().councilLocked == true end
local function setLocked(v) ns.Store.layout().councilLocked = v or nil end

local function reg() return ns.App.registry end
local function now() return ns.App.now() end
local function me() return ns.Roster.me() end

-- unlocked(): this character typed tonight's raid password and has not locked the window since
-- (or is practising as an LC officer with /tlc sim officer, which needs no password)
function Main.unlocked()
  if ns.Sim and ns.Sim.practisingOfficer and ns.Sim.practisingOfficer() then return true end
  return ns.App.secret() ~= nil and not isLocked()
end

---------------------------------------------------------------------------
-- small widgets
---------------------------------------------------------------------------

local function text(parent, font, x, y, s)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", x or 0, y or 0)
  fs:SetJustifyH("LEFT")
  if s then fs:SetText(s) end
  return fs
end

-- para(parent, y, s): a wrapped line across the page
local function para(parent, y, s)
  local fs = text(parent, "GameFontHighlightSmall", 0, y, s)
  fs:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
  fs:SetWordWrap(true)
  return fs
end

local function heading(parent, y, s)
  local fs = text(parent, "GameFontNormal", 0, y, s)
  fs:SetTextColor(T.bronzeHi[1], T.bronzeHi[2], T.bronzeHi[3])
  return fs
end

local function button(parent, label, width, onClick, tipTitle, tipBody)
  local b = U.button(parent, label, width, onClick)
  if tipTitle then U.tip(b, tipTitle, tipBody) end
  return b
end

-- row(parent, y, buttons): buttons left to right at y; hidden ones leave no gap
local function flow(buttons, anchor, y)
  local x = 0
  for _, b in ipairs(buttons) do
    if b:IsShown() then
      b:ClearAllPoints()
      if y < 0 then b:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y) else b:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", x, y) end
      x = x + (b.width or 100) + 4
    end
  end
end

local function sized(b, w) b.width = w; return b end

-- checkbox(parent, x, y, label, get, set, tipBody)
local function checkbox(parent, x, y, label, get, set, tipBody)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", x, y)
  cb.label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cb.label:SetText(label)
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    Main.refresh()
  end)
  cb.sync = function() cb:SetChecked(get() and true or false) end
  if tipBody then U.tip(cb, label, tipBody) end
  return cb
end

-- slider(name, parent, x, y, label, min, max, step, get, set, format): a labelled slider; set runs
-- as it moves. The stock template finds its Low/High/Text labels by the slider's global name.
local function slider(name, parent, x, y, label, min, max, step, get, set, format)
  local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  sl:SetPoint("TOPLEFT", x, y)
  sl:SetWidth(220)
  sl:SetMinMaxValues(min, max)
  sl:SetValueStep(step)
  if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
  local fmt = type(format) == "function" and format or function(v) return string.format(format, v) end
  local low, high, title = _G[name .. "Low"], _G[name .. "High"], _G[name .. "Text"]
  if low then low:SetText(fmt(min)) end
  if high then high:SetText(fmt(max)) end
  sl.value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sl.value:SetPoint("LEFT", sl, "RIGHT", 10, 0)
  local function show(v)
    sl.value:SetText(fmt(v))
    if title then title:SetText(label) end
  end
  sl:SetScript("OnValueChanged", function(self, v)
    if self.syncing then return end
    v = math.floor(v / step + 0.5) * step
    show(v)
    set(v)
  end)
  sl:SetScript("OnMouseUp", function() Main.refresh() end)
  sl.sync = function()
    local v = get()
    sl.syncing = true
    sl:SetValue(v)
    sl.syncing = false
    show(v)
  end
  return sl
end

local function input(parent, width, password)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 20)
  box:SetAutoFocus(false)
  box:SetMaxLetters(240)
  if password then box:SetPassword(true) end
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return box
end

local function confirm(question, fn)
  ns.Frames.prompt(question .. " Type yes", function(answer)
    if answer and answer:lower() == "yes" then fn() end
  end)
end

local function ask(question, fn)
  ns.Frames.prompt(question, function(answer)
    answer = answer and answer:match("^%s*(.-)%s*$") or ""
    if answer ~= "" then fn(answer) end
  end)
end

local function clock(t) return t and t > 0 and date("%H:%M", t) or "?" end

-- tradeLeft(at, sessionId) -> colour, text: the two hours raid loot stays tradeable
local function tradeLeft(at, id)
  if id and ns.Trade.traded(id) then return GREEN, "traded" end
  if not at or at == 0 then return GREY, "?" end
  local left = at + Main.TRADE_WINDOW - now()
  if left <= 0 then return GREY, "expired" end
  local c = left <= 600 and RED or (left <= 1800 and AMBER or GREEN)
  if left >= 3600 then return c, string.format("%dh %02dm", math.floor(left / 3600), math.floor(left % 3600 / 60)) end
  return c, string.format("%dm", math.ceil(left / 60))
end

local RESPONSE = { bis = "BiS", main = "Upgrade", offspec = "Off-spec", pass = "Pass" }

local function answerText(s, e)
  if e.ignored then return colourText(GREY, e.ignored) end
  if e.max == s.rules.offspecRollMax or e.response == "offspec" then return colourText(BLUE, "Off-spec") end
  return RESPONSE[e.response] or "Upgrade"
end

-- councilOf(s) -> the leader and council, once each
local function councilOf(s)
  local out, seen = {}, {}
  for _, n in ipairs({ s.leader, unpack(s.council or {}) }) do
    local k = Priority.nameKey(n)
    if not seen[k] then seen[k] = true; out[#out + 1] = n end
  end
  return out
end

-- missingVotes(s) -> who on the council has not voted, and how many the council is
function Main.missingVotes(s)
  local missing, all = {}, councilOf(s)
  for _, n in ipairs(all) do
    if not s.votes[Priority.nameKey(n)] then missing[#missing + 1] = n end
  end
  return missing, #all
end

-- missingAnswers(s) -> who in the group hasn't answered (no roll or button press counted, no
-- pass), and how many the group is; nil, 0 when the group isn't known (not in one)
function Main.missingAnswers(s)
  local group = ns.Sim.isSim(s) and ns.Sim.group() or ns.Roster.group()
  if not group then return nil, 0 end
  local missing = {}
  for _, n in ipairs(group) do
    local k = Priority.nameKey(n)
    if not s.live[k] and not s.passed[k] then missing[#missing + 1] = n end
  end
  table.sort(missing)
  return missing, #group
end

local function answered(s)
  local n = s:passCount()
  for _, e in ipairs(s.candidates) do if not e.ignored then n = n + 1 end end
  return n
end

-- statusOf(entry) -> colour, text: where a loot list item is, with the council's detail
function Main.statusOf(e)
  local s = e.session and reg():get(e.session)
  if e.status == "waiting" then return AMBER, "waiting to announce" end
  if e.status == "open" then
    if not s then return BLUE, "awaiting rolls" end
    local _, total = Main.missingAnswers(s)
    local left = s:countdown(now())
    local time = left and string.format(", %d s", left) or ""
    if total > 0 then return BLUE, string.format("awaiting rolls: %d of %d in%s", answered(s), total, time) end
    return BLUE, string.format("awaiting rolls: %d in%s", answered(s), time)
  end
  if e.status == "voting" then
    if not s then return BLUE, "council deciding" end
    local missing, total = Main.missingVotes(s)
    if #missing > 0 then return AMBER, string.format("missing votes: %d of %d", #missing, total) end
    return BLUE, "votes in: ready to award"
  end
  if e.status == "awarded" then return GREEN, "awarded to " .. (e.winner or "?") end
  return GREY, "not awarded"
end

---------------------------------------------------------------------------
-- lists: a header, rows of cells, the mouse wheel to scroll. One column may have no width;
-- it takes what the others leave. A column with icon = true shows the row's item icon.
---------------------------------------------------------------------------

local function list(parent, opts)
  local L = { offset = 0, rows = {}, cols = opts.cols, rowH = opts.rowH or 18, top = opts.top,
              bottom = opts.bottom or 8, max = opts.max or 30, visible = 3, heads = {} }
  for _, c in ipairs(opts.cols) do
    L.heads[c.key] = text(parent, "GameFontNormalSmall", 0, -opts.top, c.title)
  end
  local line = parent:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(T.line[1], T.line[2], T.line[3], 0.9)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", 0, -opts.top - 13)
  line:SetPoint("TOPRIGHT", 0, -opts.top - 13)
  for i = 1, L.max do
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(L.rowH)
    local y = -(opts.top + 15 + (i - 1) * L.rowH)
    row:SetPoint("TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", 0, y)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    U.stripe(row, i)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)
    if opts.click then
      row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      row:SetScript("OnClick", function(self, which) if self.item then opts.click(self.item, which, self) end end)
    end
    if opts.hover then
      row:SetScript("OnEnter", function(self) if self.item then opts.hover(self.item, self) end end)
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    row.cells = {}
    for _, c in ipairs(opts.cols) do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetJustifyH("LEFT")
      fs:SetWordWrap(false)
      row.cells[c.key] = fs
      if c.icon then
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.hover = U.itemHover(row, function() return row.link end)
        row.hover:SetHeight(L.rowH)
        if opts.click then -- the hover area takes the mouse: a click on the item name still opens the row
          row.hover:SetScript("OnMouseUp", function(_, which) if row.item then opts.click(row.item, which, row) end end)
        end
      end
    end
    if opts.build then opts.build(row) end
    L.rows[i] = row
  end
  L.empty = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  L.empty:SetPoint("TOPLEFT", 20, -opts.top - 40)
  L.empty:SetPoint("TOPRIGHT", -20, -opts.top - 40)
  L.empty:SetJustifyH("CENTER")
  L.more = text(parent, "GameFontDisableSmall", 0, 0)
  L.more:ClearAllPoints()
  L.more:SetPoint("TOPRIGHT", 0, -opts.top + 14)
  parent:EnableMouseWheel(true)
  parent:SetScript("OnMouseWheel", function(_, delta)
    L.offset = math.max(0, L.offset - delta * 3)
    Main.refresh()
  end)

  function L.layout(w, h)
    local fixed = 0
    for _, c in ipairs(L.cols) do fixed = fixed + (c.w or 0) end
    local x = 2
    for _, c in ipairs(L.cols) do
      local cw = c.w or math.max(60, w - fixed - 2)
      L.heads[c.key]:SetPoint("TOPLEFT", x + (c.icon and 20 or 0), -opts.top)
      for _, row in ipairs(L.rows) do
        local fs = row.cells[c.key]
        if c.icon then
          row.icon:SetPoint("LEFT", row, "LEFT", x, 0)
          fs:SetPoint("LEFT", row, "LEFT", x + 20, 0)
          fs:SetWidth(cw - 24)
          row.hover:SetPoint("LEFT", row, "LEFT", x, 0)
          row.hover:SetWidth(math.min(cw, 220))
        else
          fs:SetPoint("LEFT", row, "LEFT", x, 0)
          fs:SetWidth(cw - 4)
        end
      end
      x = x + cw
    end
    L.visible = math.max(3, math.min(L.max, math.floor((h - opts.top - 15 - L.bottom) / L.rowH)))
  end

  -- fill(items, draw(row, item, n), emptyText)
  function L.fill(items, draw, empty)
    L.offset = math.max(0, math.min(L.offset, #items - L.visible))
    for i, row in ipairs(L.rows) do
      local n = i + L.offset
      local item = i <= L.visible and items[n]
      row.item = item
      if item then
        row:Show()
        row.bg:SetColorTexture(0, 0, 0, 0)
        draw(row, item, n)
      else
        row:Hide()
      end
    end
    L.empty:SetText(#items == 0 and (empty or "") or "")
    L.more:SetText(#items > L.visible and string.format("%d-%d of %d (scroll)", L.offset + 1,
      math.min(#items, L.offset + L.visible), #items) or "")
  end
  return L
end

local function setItem(row, itemId, link)
  row.icon:SetTexture(U.iconOf(itemId))
  row.link = { itemLink = link, itemId = itemId }
end

---------------------------------------------------------------------------
-- pages
---------------------------------------------------------------------------

-- page(key, def): def.title, def.nav (side bar label), def.section ("raider" | "council" | "other"),
-- def.about (the line under the title), def.build(p), def.refresh(p), def.layout(p, w, h), def.show(p)
local function page(key, def)
  def.key = key
  pages[key] = def
  order[#order + 1] = key
  return def
end

local function lead() return ns.Roster.canLead() end
local BUSY = "Another item is taking answers. Wait for it to close."

---------------------------------------------------------------------------
-- Raider: tonight's loot and your answers
---------------------------------------------------------------------------

local function waitingForMe()
  local out = {}
  for _, id in ipairs(reg().order) do
    local s = reg():get(id)
    if s.mode == "session" and s.phase == "open" and not s.myResponse and s:timeLeft(now()) > 0 then out[#out + 1] = s end
  end
  return out
end

page("rolls", {
  nav = "Rolls", section = "raider", title = "Your rolls",
  about = "Tonight's loot, and what you answered. When the council announces an item, a window pops up for your answer.",
  build = function(p)
    p.waiting = text(p, "GameFontHighlight", 0, -46)
    p.answer = button(p, "Answer now", 110, function() ns.Frames.showCandidate() end,
      "Answer now", "Opens the window with your answer buttons for every item still waiting for you.")
    p.answer:SetPoint("TOPRIGHT", 0, -42)
    p.list = list(p, {
      top = 76,
      cols = { { key = "item", title = "Item", icon = true }, { key = "boss", title = "Boss", w = 110 },
               { key = "status", title = "Status", w = 150 }, { key = "mine", title = "Your answer", w = 90 },
               { key = "roll", title = "Your roll", w = 60 } },
      click = function(e)
        local s = e.session and reg():get(e.session)
        if s and s.phase == "open" and not s.myResponse then ns.Frames.showCandidate() end
      end,
    })
  end,
  layout = function(p, w, h) p.list.layout(w, h) end,
  refresh = function(p)
    local waiting = #waitingForMe()
    p.waiting:SetText(waiting > 0
      and colourText(AMBER, string.format("%d item%s waiting for your answer.", waiting, waiting == 1 and " is" or "s are"))
      or colourText(GREY, "Nothing is waiting for your answer."))
    p.answer:SetShown(waiting > 0)
    p.list.fill(ns.Loot.list.entries, function(row, e)
      setItem(row, e.itemId, ns.Loot.linkOf(e))
      row.cells.item:SetText(ns.Loot.linkOf(e))
      row.cells.boss:SetText((e.sim and "[sim] " or "") .. (e.boss ~= "" and e.boss or "?"))
      local c = e.status == "awarded" and GREEN or (e.status == "waiting" and AMBER or (e.status == "none" and GREY or BLUE))
      row.cells.status:SetText(colourText(c, LootList.label(e)))
      local s = e.session and reg():get(e.session)
      local mine = s and s.myResponse
      if mine then row.cells.mine:SetText(RESPONSE[mine] or mine)
      elseif s and s.phase == "open" then row.cells.mine:SetText(colourText(AMBER, "not answered"))
      else row.cells.mine:SetText(colourText(GREY, "-")) end
      local mineE = s and s:entryFor(me())
      row.cells.roll:SetText(mineE and mineE.roll and tostring(mineE.roll)
        or colourText(GREY, mine and mine ~= "pass" and "…" or "-"))
    end, "Nothing has dropped yet tonight. Items appear here as the raid leader loots them.")
  end,
})

---------------------------------------------------------------------------
-- Unlock: the raid password, for the council pages
---------------------------------------------------------------------------

page("unlock", {
  nav = "Unlock", section = "gate", title = "Unlock the loot council",
  about = "The council pages need tonight's raid password. The raid leader picks one and presses Begin raid; "
    .. "officers type the same password and press Join. Raiders don't need it: their rolls work without it.",
  build = function(p)
    text(p, "GameFontNormalSmall", 0, -76, "Raid password")
    p.box = input(p, 220, true)
    p.box:SetPoint("TOPLEFT", 6, -92)
    p.unlock = sized(button(p, "Unlock", 90, function() Main.unlock(p.box:GetText()) end,
      "Unlock", "Opens the council pages again: type the password you joined with tonight."), 90)
    p.join = sized(button(p, "Join as officer", 120, function() Main.join(p.box:GetText(), false) end,
      "Join as officer", "Use the password the raid leader gave the council (not in raid chat). Your votes count once it matches theirs."), 120)
    p.begin = sized(button(p, "Begin raid", 100, function() Main.join(p.box:GetText(), true) end,
      "Begin raid (raid leader)", "Pick tonight's password: council traffic is signed and encrypted with it. Give it to the officers."), 100)
    p.forget = sized(button(p, "Use another password", 150, function()
      confirm("Forget tonight's raid password on this character? You'll be out of the council's traffic until you Join again.",
        function() ns.App.endRaid(); setLocked(false); Main.refresh() end)
    end,
      "Use another password", "Forgets tonight's password on this character, so you can Join or Begin with a new one."), 150)
    p.box:SetScript("OnEnterPressed", function()
      if ns.App.secret() then Main.unlock(p.box:GetText()) else Main.join(p.box:GetText(), false) end
    end)
    p.msg = para(p, -150)
  end,
  refresh = function(p)
    local set = ns.App.secret() ~= nil
    p.unlock:SetShown(set)
    p.forget:SetShown(set)
    p.join:SetShown(not set)
    p.begin:SetShown(not set and lead())
    flow({ p.unlock, p.join, p.begin, p.forget }, p, -118)
  end,
  show = function(p) p.box:SetText(""); p.msg:SetText("") end,
})

local function gateMsg(s, c)
  local p = pages.unlock.frame
  if p and p.msg then p.msg:SetText(colourText(c or RED, s)) end
end

-- unlock(password): the council pages again, once the password matches tonight's
function Main.unlock(password)
  local raid = ns.Store.settings().raid
  if not ns.App.secret() or not raid then gateMsg("No raid password is set on this character yet: Join or Begin."); return false end
  if ns.Crypto.hex(ns.Wire.keyFromPassword(password or "")) ~= raid.key then
    gateMsg("That isn't the password you joined with tonight.")
    return false
  end
  setLocked(false)
  Main.go("loot")
  return true
end

-- join(password, hosting): /tlc begin or /tlc join from the window
function Main.join(password, hosting)
  if not password or #password < 6 then
    gateMsg("Use a password of at least 6 characters, shared with the council only (not raid chat).")
    return false
  end
  if hosting then ns.App.beginRaid(password) else ns.App.joinRaid(password) end
  if not ns.App.secret() then return false end
  setLocked(false)
  Main.go("loot")
  return true
end

function Main.lock()
  setLocked(true)
  Main.go("rolls")
end

---------------------------------------------------------------------------
-- Loot (council): the main page. Every item tonight, its status and trade timer; click one
-- for its answers and votes.
---------------------------------------------------------------------------

local lootPage

local function entryNumber(e) return ns.Loot.list:numberOf(e) end

local function buildLootList(p)
  local v = CreateFrame("Frame", nil, p)
  v:SetAllPoints()
  p.listView = v
  v.summary = text(v, "GameFontHighlightSmall", 0, -24)
  v.list = list(v, {
    top = 46, bottom = 66, rowH = 22,
    cols = { { key = "num", title = "#", w = 22 }, { key = "item", title = "Item", icon = true },
             { key = "boss", title = "Boss", w = 90 }, { key = "dropped", title = "Dropped", w = 46 },
             { key = "trade", title = "Trade left", w = 62 }, { key = "status", title = "Status", w = 160 },
             { key = "act", title = "", w = 122 } },
    click = function(e) p.detail = e.key; Main.refresh() end,
    build = function(row)
      row.announce = button(row, "Announce", 76, function()
        if row.item then ns.Loot.start(entryNumber(row.item), "session") end
      end, "Announce", "Opens this item to the raid: it is announced in raid chat, raiders answer, the council votes.")
      row.announce:SetPoint("RIGHT", -46, 0)
      row.roll = button(row, "Roll", 44, function()
        if row.item then ns.Loot.start(entryNumber(row.item), "roll") end
      end, "Plain roll", "Announced in raid chat and raiders /roll; no council vote. Main spec and priority tier still rank before the roll.")
      row.roll:SetPoint("LEFT", row.announce, "RIGHT", 0, 0)
    end,
  })
  v.all = sized(button(v, "Announce all", 110, function() ns.Loot.startAll() end, "Announce all",
    "Opens every item still to hand out at once, so the whole raid has time to answer and the council time to vote."), 110)
  v.nextBtn = sized(button(v, "Announce next", 110, function() ns.Loot.startNext("session") end, "Announce next",
    "Opens the first item still waiting."), 110)
  v.post = sized(button(v, "List to raid chat", 120, function() ns.Loot.announce() end, "List to raid chat",
    "Posts the items still waiting to raid chat, without opening them, so raiders know what's coming."), 120)
  v.add = sized(button(v, "Add item…", 90, function() ask("Add to the loot list (item link or name):", ns.Loot.add) end,
    "Add item", "Puts an item on the list by hand: shift-click its link or type its name."), 90)
  v.clear = sized(button(v, "Clear list…", 90, function() confirm("Clear the whole loot list?", ns.Loot.clear) end,
    "Clear list", "Empties tonight's loot list for the whole raid."), 90)
  local set = ns.Store.settings
  v.auto = checkbox(v, 0, 0, "Record drops when I loot a boss", function() return set().lootAuto ~= false end,
    function(on) set().lootAuto = on end, "As raid leader or assist, opening a corpse puts its epics and priority-list items here.")
  v.party = checkbox(v, 0, 0, "Party drops too (5-man practice)", function() return set().lootParty == true end,
    function(on) set().lootParty = on end, "Records party drops, rare and up, when you lead a 5-man.")
  v.auto:ClearAllPoints()
  v.auto:SetPoint("BOTTOMLEFT", 0, 30)
  v.party:ClearAllPoints()
  v.party:SetPoint("BOTTOMLEFT", 230, 30)
end

local function refreshLootList(p)
  local v = p.listView
  local entries = ns.Loot.list.entries
  local canLead, busy = lead(), reg():rolling() ~= nil
  local counts = { waiting = 0, open = 0, voting = 0, awarded = 0 }
  for _, e in ipairs(entries) do counts[e.status] = (counts[e.status] or 0) + 1 end
  v.summary:SetText(#entries == 0 and "" or string.format("%d item%s: %s waiting, %s awaiting rolls, %s with the council, %s awarded.",
    #entries, #entries == 1 and "" or "s", counts.waiting, counts.open, counts.voting, counts.awarded))
  v.list.fill(entries, function(row, e, n)
    setItem(row, e.itemId, ns.Loot.linkOf(e))
    row.cells.num:SetText(colourText(GREY, tostring(n)))
    row.cells.item:SetText(ns.Loot.linkOf(e))
    row.cells.boss:SetText((e.sim and "[sim] " or "") .. (e.boss ~= "" and e.boss or "?"))
    row.cells.dropped:SetText(clock(e.at))
    local tc, tt = tradeLeft(e.at, e.status == "awarded" and e.session)
    row.cells.trade:SetText(colourText(tc, tt))
    local sc, st = Main.statusOf(e)
    row.cells.status:SetText(colourText(sc, st))
    local can = canLead and LootList.startable(e)
    row.announce:SetShown(can)
    row.roll:SetShown(can and not e.sim)
    row.announce:SetEnabled(not busy)
    row.roll:SetEnabled(not busy)
    row.announce.disabledWhy, row.roll.disabledWhy = BUSY, BUSY
  end, "Nothing recorded yet.\nOpen a boss's corpse in a raid and its drops appear here,\nor Add item to put one on by hand.")
  local startable = 0
  for _, e in ipairs(entries) do if LootList.startable(e) then startable = startable + 1 end end
  v.all:SetShown(canLead and startable > 1)
  v.nextBtn:SetShown(canLead and startable > 0)
  v.post:SetShown(canLead and counts.waiting > 0)
  v.add:SetShown(canLead)
  v.clear:SetShown(canLead and #entries > 0)
  for _, b in ipairs({ v.all, v.nextBtn }) do b:SetEnabled(not busy); b.disabledWhy = BUSY end
  flow({ v.all, v.nextBtn, v.post, v.add, v.clear }, v, 2)
  v.auto.sync()
  v.party.sync()
  v.auto:SetShown(canLead)
  v.party:SetShown(canLead)
end

local function detailRows(s)
  local r = s:result()
  local rows = {}
  for _, e in ipairs(r.ranked) do rows[#rows + 1] = e end
  for _, e in ipairs(s.candidates) do if not e.ignored and not e.roll then rows[#rows + 1] = e end end
  for _, e in ipairs(s.candidates) do if e.ignored then rows[#rows + 1] = e end end
  return rows, r
end

local function detailMenu(s, e, row)
  local entries = { { text = "Vote for " .. e.player, func = function() ns.App.vote(s.id, e.player) end },
    { text = "Propose " .. e.player .. "…", func = function()
      ns.Frames.prompt("Propose " .. e.player .. ": reason", function(reason) ns.App.propose(s.id, e.player, reason) end)
    end } }
  if s:isLeader(me()) and s.phase ~= "done" then
    entries[#entries + 1] = { text = "Award to " .. e.player .. "…", func = function()
      ns.Frames.prompt("Award to " .. e.player .. ": reason (recorded if this departs from the list)",
        function(reason) ns.App.award(s.id, e.player, "manual", reason) end)
    end }
  end
  U.contextMenu(row, entries)
end

local function buildLootDetail(p)
  local d = CreateFrame("Frame", nil, p)
  d:SetAllPoints()
  p.detailView = d
  d.back = button(d, "< All loot", 90, function() p.detail = nil; Main.refresh() end)
  d.back:SetPoint("TOPLEFT", 0, 0)
  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(20, 20)
  d.icon:SetPoint("TOPLEFT", 0, -28)
  d.item = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  d.item:SetPoint("LEFT", d.icon, "RIGHT", 6, 0)
  d.hover = U.itemHover(d, function() return d.link end)
  d.hover:SetPoint("TOPLEFT", d.icon, "TOPLEFT")
  d.hover:SetSize(320, 20)
  d.info = para(d, -54)
  d.votes = para(d, -70)
  d.answers = para(d, -86)
  d.list = list(d, {
    top = 112, bottom = 36,
    cols = { { key = "name", title = "Name", w = 100 }, { key = "spec", title = "Spec", w = 100 },
             { key = "answer", title = "Answer", w = 70 }, { key = "roll", title = "Roll", w = 40 },
             { key = "tier", title = "Tier", w = 34 }, { key = "votes", title = "Votes", w = 110 },
             { key = "note", title = "Note" } },
    click = function(e, which, row)
      local s = d.session
      if not s or e.ignored or s.phase == "done" then return end
      if which == "RightButton" then detailMenu(s, e, row) else ns.App.vote(s.id, e.player) end
    end,
  })
  local function sid() return d.session and d.session.id end
  local function entryN() local e = ns.Loot.list:byKeyOf(p.detail); return e and entryNumber(e) end
  d.announce = sized(button(d, "Announce", 90, function() ns.Loot.start(entryN(), "session") end, "Announce",
    "Opens this item to the raid: raiders answer, the council votes."), 90)
  d.roll = sized(button(d, "Roll", 60, function() ns.Loot.start(entryN(), "roll") end, "Plain roll",
    "Raiders /roll in raid chat; no council vote."), 60)
  d.close = sized(button(d, "Last call (10 s)", 120, function() ns.App.close(sid()) end, "Close responses early",
    "Gives raiders a last call: answers close in 10 seconds, announced in raid chat. Press again to close straight away."), 120)
  d.reroll = sized(button(d, "Re-roll tied", 100, function() ns.App.reroll(sid()) end, "Re-roll tied",
    "The players tied at the top roll again."), 100)
  d.award = sized(button(d, "Award", 160, function(self) if self.player then ns.App.award(sid(), self.player, self.via) end end,
    "Award", function(self)
      return self.via == "votes" and "Awards the item to the council's vote." or "Awards the item to the list's pick."
    end), 160)
  d.awardTo = sized(button(d, "Award to…", 90, function()
    ask("Award to (name):", function(name)
      ask("Reason for awarding " .. name .. ":", function(reason) ns.App.award(sid(), name, "manual", reason) end)
    end)
  end, "Award to anyone", "Name a player and a reason. The reason is recorded with the award."), 90)
  d.undo = sized(button(d, "Undo award", 90, function() ns.App.unaward(sid()) end, "Undo award",
    "Reopens the item for the council to award again."), 90)
  d.window = sized(button(d, "Council window", 120, function() ns.Frames.showCouncil(sid()) end, "Council window",
    "The full council frame for this item: votes, proposals, setting a raider's spec."), 120)
  d.callout = sized(button(d, "Call out missing", 120, function()
    local s = d.session
    local missing = s and Main.missingAnswers(s)
    if not missing or #missing == 0 then return end
    local left = s:countdown(now())
    ns.App.announce(s, string.format("[ToadsLC] Still to answer for %s%s: %s.", s.itemLink or s.itemName,
      left and string.format(" (%d s left)", left) or "", table.concat(missing, ", ")))
  end, "Call out missing", "Posts the names still to answer this item in raid chat, with the time left."), 120)
  d.remove = sized(button(d, "Remove…", 80, function()
    confirm("Take this item off the loot list?", function() ns.Loot.remove(entryN()); p.detail = nil end)
  end, "Remove", "Takes this item off tonight's loot list for the whole raid."), 80)
end

-- answersLine(s): how many have answered, who passed, and who is still to answer (or didn't)
local function answersLine(s)
  local missing, total = Main.missingAnswers(s)
  local passed = {}
  for k in pairs(s.passed) do passed[#passed + 1] = (k:gsub("^%l", string.upper)) end
  table.sort(passed)
  local n = answered(s)
  local line = total > 0 and string.format("Answered %d of %d.", n, total) or string.format("Answered: %d.", n)
  if #passed > 0 then line = line .. " Passed: " .. table.concat(passed, ", ") .. "." end
  if not missing then return line end
  if #missing == 0 then return line .. " " .. colourText(GREEN, "Everyone has answered.") end
  if s.phase == "open" then
    return line .. " " .. colourText(AMBER, "Still to answer: " .. table.concat(missing, ", ") .. ".")
  end
  return line .. " " .. colourText(GREY, "Didn't answer: " .. table.concat(missing, ", ") .. ".")
end

local function refreshLootDetail(p)
  local d = p.detailView
  local e = ns.Loot.list:byKeyOf(p.detail)
  if not e then p.detail = nil; return false end
  local s = e.session and reg():get(e.session)
  d.session = s
  local link = ns.Loot.linkOf(e)
  d.link = { itemLink = link, itemId = e.itemId }
  d.icon:SetTexture(U.iconOf(e.itemId))
  d.item:SetText(link)
  local sc, st = Main.statusOf(e)
  local tc, tt = tradeLeft(e.at, e.status == "awarded" and e.session)
  d.info:SetText(string.format("%s · dropped %s · trade %s · %s%s", e.boss ~= "" and e.boss or "?", clock(e.at),
    colourText(tc, tt), colourText(sc, st), s and string.format(" · %d passed", s:passCount()) or ""))
  local leader = s and s:isLeader(me())
  d.answers:SetText(s and answersLine(s) or "")
  if not s then
    d.votes:SetText(colourText(GREY, e.session and "This item's session isn't on this client (it may have been run before you joined)."
      or "Not announced yet. Announce it and the raiders' answers appear here as they come in."))
    d.list.fill({}, function() end, "")
  else
    local missing, total = Main.missingVotes(s)
    -- who voted for whom only when the rules show it (votesVisibleTo = "council"); else counts
    local named = s.rules.votesVisibleTo == "council"
    local voted = {}
    for _, n in ipairs(councilOf(s)) do
      local v = s.votes[Priority.nameKey(n)]
      if v then voted[#voted + 1] = named and (n .. " (" .. v .. ")") or n end
    end
    local line = string.format("Council votes %d of %d.", total - #missing, total)
    if #voted > 0 then line = line .. " Voted: " .. table.concat(voted, ", ") .. "." end
    if #missing > 0 and s.phase ~= "done" then line = line .. " " .. colourText(AMBER, "Still to vote: " .. table.concat(missing, ", ") .. ".") end
    if s.proposal then line = line .. string.format(" Proposal by %s: %s%s.", s.proposal.by, s.proposal.player,
      s.proposal.reason ~= "" and (" (" .. s.proposal.reason .. ")") or "") end
    d.votes:SetText(line)
    local rows, r = detailRows(s)
    local counts, myVote = s:voteCounts(), s.votes[Priority.nameKey(me())]
    local voters = {}
    for officer, c in pairs(s.votes) do
      local k = Priority.nameKey(c)
      voters[k] = voters[k] or {}
      table.insert(voters[k], (officer:gsub("^%l", string.upper)))
    end
    d.list.fill(rows, function(row, c)
      local k = Priority.nameKey(c.player)
      row.cells.name:SetText(c.ignored and colourText(GREY, c.player) or U.classText(c.class, c.player))
      row.cells.spec:SetText(c.spec and Priority.label(c.spec) or ((c.class or "?") .. "?"))
      row.cells.answer:SetText(answerText(s, c))
      row.cells.roll:SetText(c.roll and tostring(c.roll) or colourText(GREY, "…"))
      row.cells.tier:SetText(not c.ignored and c.tier and tostring(c.tier) or "-")
      local n = counts[k] or 0
      local who = n == 0 and "" or (named and table.concat(voters[k] or {}, ", ") or tostring(n))
      if myVote and Priority.nameKey(myVote) == k then who = colourText(GREEN, who) end
      row.cells.votes:SetText(who)
      local pick = not c.ignored and r.ranked[1] == c and (r.winner == c or not r.winner)
      row.cells.note:SetText((pick and colourText(GREEN, "list pick  ") or "") .. (c.note or ""))
      if pick then row.bg:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.12) end
    end, s.phase == "open" and "No answers yet. Raiders appear here, ranked, as they answer." or "Nobody answered for this item.")
  end
  local canStart = lead() and LootList.startable(e)
  local busy = reg():rolling() ~= nil
  d.announce:SetShown(canStart)
  d.roll:SetShown(canStart and not e.sim)
  d.announce:SetEnabled(not busy); d.roll:SetEnabled(not busy)
  d.announce.disabledWhy, d.roll.disabledWhy = BUSY, BUSY
  d.close:SetShown(leader and s.phase == "open" or false)
  d.close:SetText(s and s:inFinalCall(now()) and "Close now" or "Last call (10 s)")
  d.reroll:SetShown(leader and s.phase == "voting" and s:result().tie or false)
  local opts = s and s:awardOptions() or {}
  -- only the list's pick or the council's votes: a tie, or a list that names nobody, goes to
  -- Re-roll tied, the council window or Award to… (whose reason is recorded)
  local pick, via = opts.list or opts.listPriority, "list"
  if not pick and opts.votes then pick, via = opts.votes, "votes" end
  local canAward = leader and s.phase ~= "done" or false
  d.award.player, d.award.via = canAward and pick or nil, via
  d.award:SetText(pick and ("Award: " .. pick) or "Award")
  d.award:SetShown(canAward and pick ~= nil)
  d.awardTo:SetShown(canAward)
  d.undo:SetShown(leader and s.phase == "done" or false)
  d.window:SetShown(s ~= nil and s.mode == "session")
  d.remove:SetShown(lead())
  local missing = s and s.phase == "open" and Main.missingAnswers(s)
  d.callout:SetShown(missing and #missing > 0 or false)
  flow({ d.announce, d.roll, d.close, d.callout, d.reroll, d.award, d.awardTo, d.undo, d.window, d.remove }, d, 2)
  return true
end

lootPage = page("loot", {
  nav = "Loot", section = "council", title = "Raid loot",
  build = function(p)
    buildLootList(p)
    buildLootDetail(p)
  end,
  layout = function(p, w, h)
    p.listView.list.layout(w, h)
    p.detailView.list.layout(w, h)
  end,
  refresh = function(p)
    local detail = p.detail and refreshLootDetail(p)
    p.detailView:SetShown(detail and true or false)
    p.listView:SetShown(not detail)
    p.titleText:SetShown(not detail)
    if not detail then refreshLootList(p) end
  end,
})

-- showItem(entry): the loot page, opened on one item
function Main.showItem(e)
  if not main then Main.build() end
  if lootPage.frame then lootPage.frame.detail = e and e.key end
  Main.go("loot")
end

---------------------------------------------------------------------------
-- Trades
---------------------------------------------------------------------------

page("trades", {
  nav = "Trades", section = "council", title = "Trades",
  about = "Awards still to hand over. Open a trade with the winner and their items go in by themselves; "
    .. "raid loot can only be traded for two hours after it is looted.",
  build = function(p)
    p.auto = checkbox(p, 0, -44, "Put a winner's items into the trade window by themselves",
      function() return ns.Store.settings().autoTrade ~= false end, function(on) ns.Store.settings().autoTrade = on end)
    p.list = list(p, {
      top = 78,
      cols = { { key = "winner", title = "Winner", w = 110 }, { key = "item", title = "Item", icon = true },
               { key = "left", title = "Trade left", w = 70 }, { key = "bags", title = "In your bags", w = 90 },
               { key = "act", title = "", w = 110 } },
      build = function(row)
        row.done = button(row, "Handed over", 100, function() if row.item then ns.Trade.done(row.item.winner) end end,
          "Handed over", "Marks everything owed to this winner as traded, for an item handed over some other way.")
        row.done:SetPoint("RIGHT", -4, 0)
      end,
    })
  end,
  layout = function(p, w, h) p.list.layout(w, h) end,
  refresh = function(p)
    p.auto.sync()
    local mine, rows = Priority.nameKey(me()), {}
    for _, a in ipairs(ns.Trade.awards()) do
      if Priority.nameKey(a.winner) ~= mine then rows[#rows + 1] = a end
    end
    p.list.fill(rows, function(row, a)
      local e = ns.Loot.list:forSession(a.session)
      local _, link = GetItemInfo(a.itemId)
      setItem(row, a.itemId, link)
      row.cells.winner:SetText(a.winner)
      row.cells.item:SetText(link or a.itemName)
      local c, t = tradeLeft(e and e.at or a.at)
      row.cells.left:SetText(colourText(c, t))
      row.cells.bags:SetText(ns.Trade.held(a.itemId) and colourText(GREEN, "yes") or colourText(GREY, "no"))
    end, "Nothing awarded tonight is waiting to be traded.")
  end,
})

---------------------------------------------------------------------------
-- Raid & council: the password, the council, items by hand, the last item you led
---------------------------------------------------------------------------

local function lastLed()
  local name = me()
  return reg():latest(function(s) return s:isLeader(name) end)
end

page("raid", {
  nav = "Raid & council", section = "council", title = "Raid & council",
  build = function(p)
    heading(p, -28, "Raid password")
    p.password = para(p, -46)
    p.endRaid = sized(button(p, "End raid", 90, function()
      confirm("Forget tonight's raid password on this character?", function() ns.App.endRaid(); Main.go("rolls") end)
    end, "End raid", "Forgets the raid password here: council traffic is unsigned again and these pages lock."), 90)
    p.status = sized(button(p, "Status to chat", 110, function() ns.App.status() end, "Status",
      "Prints the priority list's date, sessions waiting for export and the password fingerprint."), 110)
    p.versions = sized(button(p, "Check addon versions", 150, function() if ns.Version then ns.Version.check() end end,
      "Check addon versions", "Asks the raid who has Toads LC and which version; the answers print in chat after a few seconds."), 150)
    heading(p, -104, "Council")
    p.council = para(p, -122)
    heading(p, -158, "Items by hand")
    p.session = sized(button(p, "Session for an item…", 150, function()
      ask("Council session for (item link or name):", function(t) ns.App.open(t, nil, "session") end)
    end, "Session for an item", "Opens a council session for any item, on the list or not."), 150)
    p.roll = sized(button(p, "Roll for an item…", 130, function()
      ask("Plain roll for (item link or name):", function(t) ns.App.open(t, nil, "roll") end)
    end, "Roll for an item", "A plain priority roll in raid chat, no council."), 130)
    heading(p, -222, "The last item you led")
    p.last = para(p, -240)
    p.awardList = sized(button(p, "Award as the list says", 160, function() ns.App.awardLast() end, "Award as the list says",
      "Closes answers if they're still open and awards to the list's pick."), 160)
    p.awardTo = sized(button(p, "Award to…", 90, function()
      ask("Award the last item to (name):", function(name)
        ns.Frames.prompt("Reason for awarding " .. name .. ":", function(reason) ns.App.awardLast(name, reason) end)
      end)
    end), 90)
    p.closeLast = sized(button(p, "Last call (10 s)", 120, function() ns.App.closeLast() end, "Close responses early",
      "Gives raiders a last call: answers close in 10 seconds, announced in raid chat. Press again to close straight away."), 120)
    p.rerollLast = sized(button(p, "Re-roll tied", 100, function() ns.App.rerollLast() end), 100)
    p.undoLast = sized(button(p, "Undo award", 90, function() ns.App.undoLast() end), 90)
    heading(p, -300, "Answer time")
    p.itemSec = slider("ToadsLCItemSecondsSlider", p, 4, -330, "One item", 10, 120, 5,
      function() return ns.Store.settings().itemSeconds or 15 end,
      function(v) ns.Store.settings().itemSeconds = v end, "%d s")
    p.itemSecHelp = para(p, -360, colourText(GREY, "How long raiders have to answer one announced item. "
      .. "Announce all has no timer: the items stay open until you give a last call or everyone has answered."))
    p.councilWin = sized(button(p, "Council window", 120, function()
      if not ns.Frames.showCouncil() then ns.Chat.print("No council session to show.") end
    end), 120)
  end,
  refresh = function(p)
    p.itemSec.sync()
    local secret, raid = ns.App.secret(), ns.Store.settings().raid
    p.password:SetText(secret and string.format("Set (%s), fingerprint %s. Every officer should see the same fingerprint.",
      raid.hosting and "you lead" or "joined", colourText(GREEN, secret.fingerprint)) or colourText(GREY, "None."))
    p.versions:SetShown(ns.Version ~= nil and ns.Version.check ~= nil)
    flow({ p.endRaid, p.status, p.versions }, p, -64)
    local pdb = ns.Store.priorities()
    local from = pdb and pdb.council and #pdb.council > 0 and "from the priority list" or "the raid leader and assists"
    local names = ns.Roster.council()
    p.council:SetText(string.format("%s (%s).", #names > 0 and table.concat(names, ", ") or "nobody yet", from))
    flow({ p.session, p.roll }, p, -176)
    p.session:SetShown(lead()); p.roll:SetShown(lead())
    local s = lastLed()
    if s then
      local where = s.phase == "open" and "taking answers" or (s.phase == "voting" and "with the council"
        or (s.awardedTo and ("awarded to " .. s.awardedTo) or "not awarded"))
      p.last:SetText(string.format("%s: %s.", s.itemLink or s.itemName, where))
    else
      p.last:SetText(colourText(GREY, "You haven't led an item tonight."))
    end
    p.awardList:SetShown(s ~= nil and s.phase ~= "done")
    p.awardTo:SetShown(s ~= nil and s.phase ~= "done")
    p.closeLast:SetShown(s ~= nil and s.phase == "open")
    p.closeLast:SetText(s and s:inFinalCall(now()) and "Close now" or "Last call (10 s)")
    p.rerollLast:SetShown(s ~= nil and s.phase == "voting" and s:result().tie or false)
    p.undoLast:SetShown(s ~= nil and s.phase == "done")
    p.councilWin:SetShown(true)
    flow({ p.awardList, p.awardTo, p.closeLast, p.rerollLast, p.undoLast, p.councilWin }, p, -258)
  end,
})

---------------------------------------------------------------------------
-- Loot mule: who gets the greens and blues (adapters/Mule.lua, when it is installed)
---------------------------------------------------------------------------

local QUALITIES = { { 2, "Uncommon (green)" }, { 3, "Rare (blue)" }, { 4, "Epic (purple)" } }

page("mule", {
  nav = "Loot mule", section = "council", title = "Loot mule",
  about = "Hand loot of the chosen qualities straight to one player as you loot, instead of putting it on the list.",
  needs = function() return ns.Mule ~= nil end,
  build = function(p)
    text(p, "GameFontNormalSmall", 0, -56, "Mule")
    p.who = para(p, -72)
    p.box = input(p, 180, false)
    p.box:SetPoint("TOPLEFT", 6, -92)
    p.set = sized(button(p, "Set mule", 90, function()
      local name = p.box:GetText():match("^%s*(.-)%s*$")
      if name ~= "" then ns.Mule.set(name) end
      Main.refresh()
    end, "Set mule", "The player who gets the chosen qualities. Type their name."), 90)
    p.target = sized(button(p, "Use my target", 110, function()
      local name = UnitName("target")
      if name then ns.Mule.set(name) end
      Main.refresh()
    end), 110)
    p.clear = sized(button(p, "No mule", 80, function() ns.Mule.set(nil); Main.refresh() end), 80)
    text(p, "GameFontNormalSmall", 0, -150, "Qualities that go to the mule")
    p.boxes = {}
    for i, q in ipairs(QUALITIES) do
      p.boxes[i] = checkbox(p, 0, -164 - (i - 1) * 24, q[2], function()
        local _, qs = ns.Mule.get()
        for _, v in ipairs(qs or {}) do if v == q[1] then return true end end
        return false
      end, function(on)
        local _, qs = ns.Mule.get()
        local out = {}
        for _, v in ipairs(qs or {}) do if v ~= q[1] then out[#out + 1] = v end end
        if on then out[#out + 1] = q[1] end
        table.sort(out)
        ns.Mule.setQualities(out)
      end)
    end
  end,
  refresh = function(p)
    local name = ns.Mule.get()
    p.who:SetText(name and colourText(GREEN, name) or colourText(GREY, "Nobody: loot goes on the list as usual."))
    flow({ p.set, p.target, p.clear }, p, -116)
    for _, cb in ipairs(p.boxes) do cb.sync() end
  end,
})

---------------------------------------------------------------------------
-- Raid chat lines (/tlc announce)
---------------------------------------------------------------------------

page("announce", {
  nav = "Raid chat lines", section = "council", title = "Raid chat lines",
  about = "What the raid sees when an item is awarded or traded.",
  build = function(p)
    local C = ns.Commands
    p.parts = {}
    local LABELS = { award = "Announce awards in raid chat", trade = "Announce trades in raid chat",
                     whisper = "Whisper the winner when they're awarded an item" }
    p.kinds = {}
    for _, which in ipairs({ "award", "whisper", "trade" }) do
      if C.ANNOUNCE[which] then p.kinds[#p.kinds + 1] = which end -- the whisper comes with its own change
    end
    for i, which in ipairs(p.kinds) do
      local a, y = C.ANNOUNCE[which], -40 - (i - 1) * 104
      local part = {}
      part.on = checkbox(p, 0, y, LABELS[which] or (a.what .. " announced"),
        function() return ns.Store.settings()[a.toggle] ~= false end, function(on) ns.Store.settings()[a.toggle] = on end)
      text(p, "GameFontNormalSmall", 0, y - 26, "Wording")
      part.box = input(p, 300, false)
      part.box:SetPoint("TOPLEFT", 56, y - 22)
      part.box:SetPoint("RIGHT", p, "RIGHT", -4, 0)
      part.save = sized(button(p, "Save", 70, function()
        local t = part.box:GetText()
        if t ~= "" then ns.Store.settings()[a.text] = t; ns.Store.settings()[a.toggle] = true end
        Main.refresh()
      end), 70)
      part.reset = sized(button(p, "Default wording", 120, function()
        ns.Store.settings()[a.text] = nil
        part.box:SetText(ns.Session[a.default])
        Main.refresh()
      end), 120)
      part.y = y - 52
      part.sample = para(p, y - 80)
      p.parts[which] = part
    end
    p.help = para(p, -40 - #p.kinds * 104 + 4)
  end,
  show = function(p)
    for which, part in pairs(p.parts) do
      local a = ns.Commands.ANNOUNCE[which]
      part.box:SetText(ns.Store.settings()[a.text] or ns.Session[a.default])
    end
  end,
  refresh = function(p)
    for which, part in pairs(p.parts) do
      local a = ns.Commands.ANNOUNCE[which]
      part.on.sync()
      flow({ part.save, part.reset }, p, part.y)
      part.sample:SetText("e.g. " .. ns.Commands.sample(which, ns.Store.settings()[a.text]))
    end
    p.help:SetText("Placeholders: {" .. table.concat(ns.Session.PLACEHOLDERS, "}, {")
      .. "}. {by} is who traded it. A bracketed part whose placeholder is empty is left out.")
  end,
})

---------------------------------------------------------------------------
-- Import / export
---------------------------------------------------------------------------

page("data", {
  nav = "Import / export", section = "council", title = "Import / export",
  build = function(p)
    heading(p, -28, "Priority list")
    p.list = para(p, -46)
    p.import = sized(button(p, "Import…", 90, function() ns.Frames.showImport() end, "Import",
      "Paste the toads-loot-priority JSON from the site."), 90)
    p.undo = sized(button(p, "Undo last import", 130, function() ns.App.undoImport() end, "Undo last import",
      "Puts back the list you had before the last import."), 130)
    heading(p, -110, "Sessions for the site")
    p.sessions = para(p, -128)
    p.export = sized(button(p, "Export new", 100, function() ns.App.export(false) end, "Export new",
      "The sessions not sent to the site yet, ready to copy."), 100)
    p.exportAll = sized(button(p, "Export all", 100, function() ns.App.export(true) end, "Export all",
      "Every saved session, sent or not."), 100)
    p.sent = sized(button(p, "Mark as sent…", 110, function()
      confirm("Mark every waiting session as sent to the site?", ns.App.exportClear)
    end, "Mark as sent", "Once the site has accepted the export, so the next export only has new sessions."), 110)
  end,
  refresh = function(p)
    local pdb = ns.Store.priorities()
    p.list:SetText(pdb and string.format("%d items, exported %s, imported by %s.", pdb.count or 0,
      tostring(pdb.exportedAt or "?"):sub(1, 10), pdb.importedBy or "?") or colourText(AMBER, "None imported yet."))
    flow({ p.import, p.undo }, p, -64)
    local _, ids = ns.Store.records(false)
    p.sessions:SetText(string.format("%d session%s waiting to be sent.", #ids, #ids == 1 and "" or "s"))
    flow({ p.export, p.exportAll, p.sent }, p, -146)
  end,
})

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------

page("history", {
  nav = "History", section = "council", title = "Tonight's awards",
  build = function(p)
    p.list = list(p, {
      top = 28,
      cols = { { key = "item", title = "Item" }, { key = "to", title = "Awarded to", w = 120 }, { key = "why", title = "Override", w = 220 } },
    })
  end,
  layout = function(p, w, h) p.list.layout(w, h) end,
  refresh = function(p)
    local null = ns.Codec.null
    p.list.fill(ns.App.tonight(), function(row, r)
      row.cells.item:SetText(r.itemName or "?")
      row.cells.to:SetText(r.awardedTo ~= null and r.awardedTo or colourText(GREY, "not awarded"))
      local ov = r.override ~= null and r.override
      row.cells.why:SetText(ov and (ov.reason or "") or "")
    end, "No awards tonight.")
  end,
})

---------------------------------------------------------------------------
-- Practice (/tlc sim) and settings: for everyone
---------------------------------------------------------------------------

page("practice", {
  nav = "Practice", section = "other", title = "Practice",
  about = "Fake a boss kill and a raid answering it, solo or in a party. Nothing is sent to anyone or saved.",
  build = function(p)
    text(p, "GameFontNormalSmall", 0, -56, "Boss, raid or item (empty: a random boss)")
    p.box = input(p, 260, false)
    p.box:SetPoint("TOPLEFT", 6, -72)
    p.raider = sized(button(p, "Practise as a raider", 150, function() ns.Sim.start(p.box:GetText(), nil, "raider") end,
      "Practise as a raider", "The drops all open at once: answer each with BiS, Upgrade, OffSpec or Pass, as on raid night. "
      .. "A fake officer votes and hands each one out."), 150)
    p.officer = sized(button(p, "Practise as LC officer", 160, function() ns.Sim.drop(p.box:GetText(), "officer") end,
      "Practise as LC officer", "A fake kill's drops go on the Loot page, which opens without a raid password. "
      .. "Announce them, give a last call, vote and award while a fake raid answers."), 160)
    p.start = sized(button(p, "Fake a kill", 100, function() ns.Sim.start(p.box:GetText()) end, "Fake a kill",
      "Opens its drops one by one, with a fake raid answering and officers voting."), 100)
    p.drop = sized(button(p, "Fake drops to the list", 160, function() ns.Sim.drop(p.box:GetText()) end, "Fake drops",
      "Puts a fake kill's drops on the loot list, to practise announcing them."), 160)
    p.stop = sized(button(p, "Stop", 70, function() ns.Sim.stop() end, "Stop", "Stops the simulation and clears its items."), 70)
    p.state = para(p, -160)
  end,
  refresh = function(p)
    flow({ p.raider, p.officer, p.stop }, p, -100)
    flow({ p.start, p.drop }, p, -128)
    local role = ns.Sim.role == "raider" and "Raider practice is running." or (ns.Sim.role == "officer"
      and "LC officer practice is running: the council pages are open until you press Stop." or "A simulation is running.")
    p.state:SetText(ns.Sim.active and colourText(BLUE, role) or colourText(GREY, "No simulation running."))
  end,
})

page("settings", {
  nav = "Settings", section = "other", title = "Settings",
  build = function(p)
    local set, layout = ns.Store.settings, ns.Store.layout
    p.tooltip = checkbox(p, 0, -30, "Show Toads priorities on item tooltips", function() return set().tooltip end,
      function(on) set().tooltip = on end)
    p.minimap = checkbox(p, 0, -54, "Minimap button", function() return set().minimapHidden ~= true end,
      function(on) set().minimapHidden = not on; Main.minimap() end)
    p.locked = checkbox(p, 0, -78, "Lock window positions", function() return layout().locked == true end,
      function(on) layout().locked = on end, "Windows can't be dragged by accident; they can still be resized.")
    heading(p, -114, "Windows")
    p.alpha = slider("ToadsLCOpacitySlider", p, 4, -146, "Opacity", 0.3, 1, 0.05, ns.Frames.alpha,
      function(v) ns.Frames.setAlpha(v) end, function(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end)
    p.scaleSl = slider("ToadsLCScaleSlider", p, 4, -196, "Size", 0.5, 2, 0.05, ns.Frames.scale,
      function(v) p.pendingScale = v end, "%.2f")
    -- rescaling every window as the slider moves would move the slider under the mouse: apply on release
    p.scaleSl:SetScript("OnMouseUp", function()
      if p.pendingScale then ns.Frames.setScale(p.pendingScale); p.pendingScale = nil end
      Main.refresh()
    end)
    p.reset = sized(button(p, "Reset windows", 110, function() ns.Frames.resetLayout(); Main.refresh() end, "Reset windows",
      "Every Toads LC window back to its default size, place, scale and opacity."), 110)
    p.hint = para(p, -226, "Drag a window's bottom-right corner to resize it. Sizes, places, scale and opacity are kept per character.")
    heading(p, -280, "Help")
    p.debug = sized(button(p, "Tooltip check", 110, function() ns.App.debug("") end, "Tooltip check",
      "Prints why item tooltips do or don't show priorities."), 110)
    p.commands = sized(button(p, "Slash commands", 120, function() ns.Commands.help() end, "Slash commands",
      "Prints every /tlc command: shortcuts for what this window does."), 120)
  end,
  refresh = function(p)
    p.tooltip.sync()
    p.minimap.sync()
    p.locked.sync()
    p.alpha.sync()
    if not p.pendingScale then p.scaleSl.sync() end
    flow({ p.reset }, p, -252)
    flow({ p.debug, p.commands }, p, -298)
  end,
})

---------------------------------------------------------------------------
-- the window and its side bar
---------------------------------------------------------------------------

local SECTIONS = {
  { key = "raider", title = "Raider" },
  { key = "council", title = "Loot council" },
  { key = "other", title = "" },
}

-- guard(def, step, ...): runs a page's build, layout or refresh. One page that breaks on the
-- live client must not take the side bar or the other pages with it: the page shows what
-- went wrong instead, the error goes to the client's error handler once, and the page is
-- left alone after that.
local reported = {}
local function guard(def, step, ...)
  local ok, err = pcall(def[step], ...)
  if ok then return true end
  err = tostring(err)
  def.failed = step .. ": " .. err
  local p = def.frame
  if p then
    if p.GetChildren then for _, child in ipairs({ p:GetChildren() }) do child:Hide() end end
    if p.GetRegions then -- labels made straight on the page, all but its title
      for _, region in ipairs({ p:GetRegions() }) do if region ~= p.titleText then region:Hide() end end
    end
    p.failText = p.failText or para(p, -44)
    p.failText:SetText(colourText(RED, "This page didn't load (" .. def.failed .. ").\n"
      .. "Please send this line to whoever looks after Toads LC. The other pages still work."))
    p.failText:Show()
  end
  if not reported[def.key .. def.failed] then
    reported[def.key .. def.failed] = true
    ns.Chat.print("Toads LC: the " .. (def.nav or def.key) .. " page failed to " .. def.failed)
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, "ToadsLC " .. def.key .. " page, " .. def.failed) end
  end
  return false
end

local function allowed(def)
  if def.needs and not def.needs() then return false end
  if def.section == "council" then return Main.unlocked() end
  if def.section == "gate" then return not Main.unlocked() end
  return true
end

local function navButton(key, label)
  local b = CreateFrame("Button", nil, main.nav)
  b:SetSize(NAV_W - 8, 22)
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetColorTexture(T.teal[1], T.teal[2], T.teal[3], 0.22)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.label:SetPoint("LEFT", 10, 0)
  b.label:SetText(label)
  b:SetScript("OnClick", function() Main.go(key) end)
  return b
end

local function refreshNav()
  local y = -6
  for _, sec in ipairs(SECTIONS) do
    local h = main.headers[sec.key]
    if sec.title ~= "" then
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", 8, y)
      local practice = ns.Sim.practisingOfficer and ns.Sim.practisingOfficer()
      local lockText = sec.key == "council" and (practice and colourText(BLUE, " (practice)")
        or (Main.unlocked() and colourText(GREEN, " (unlocked)") or colourText(GREY, " (locked)"))) or ""
      h:SetText(sec.title .. lockText)
      y = y - 18
    else
      y = y - 10
    end
    for _, key in ipairs(order) do
      local def = pages[key]
      local inSection = def.section == sec.key or (sec.key == "council" and def.section == "gate")
      local b = main.navs[key]
      if inSection and allowed(def) then
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 4, y)
        b:Show()
        b.sel:SetShown(current == key)
        y = y - 24
      elseif inSection then
        b:Hide()
      end
    end
    y = y - 6
  end
  main.lockBtn:SetShown(Main.unlocked())
end

function Main.build()
  main = U.window("ToadsLCMainFrame", "Toads LC", {
    w = 840, h = 500, minW = 760, minH = 420, maxW = 1500, maxH = 1100,
    layout = function(f, w, h)
      f.cw, f.ch = w - NAV_W - 34, h - 44
      for _, key in ipairs(order) do
        local def = pages[key]
        if def.frame and def.layout and not def.failed then guard(def, "layout", def.frame, f.cw, f.ch) end
      end
      if f:IsShown() then Main.refresh() end
    end,
  })
  main.nav = CreateFrame("Frame", nil, main)
  main.nav:SetPoint("TOPLEFT", 8, -28)
  main.nav:SetPoint("BOTTOMLEFT", 8, 8)
  main.nav:SetWidth(NAV_W)
  local well = main.nav:CreateTexture(nil, "BACKGROUND")
  well:SetAllPoints()
  well:SetColorTexture(T.menu[1], T.menu[2], T.menu[3], 0.95)
  local edge = main.nav:CreateTexture(nil, "ARTWORK")
  edge:SetColorTexture(T.line[1], T.line[2], T.line[3], 0.9)
  edge:SetWidth(1)
  edge:SetPoint("TOPRIGHT")
  edge:SetPoint("BOTTOMRIGHT")
  main.headers = {}
  for _, sec in ipairs(SECTIONS) do
    local h = text(main.nav, "GameFontNormalSmall", 8, 0, sec.title)
    h:SetTextColor(T.bronze[1], T.bronze[2], T.bronze[3])
    main.headers[sec.key] = h
  end
  main.navs = {}
  for _, key in ipairs(order) do main.navs[key] = navButton(key, pages[key].nav) end
  main.lockBtn = button(main.nav, "Lock", 70, function() Main.lock() end, "Lock the council pages",
    "Hides the council pages until the raid password is typed again. Council traffic keeps working.")
  main.lockBtn:SetPoint("BOTTOMLEFT", 8, 8)

  main.content = CreateFrame("Frame", nil, main)
  main.content:SetPoint("TOPLEFT", NAV_W + 20, -32)
  main.content:SetPoint("BOTTOMRIGHT", -14, 12)
  for _, key in ipairs(order) do
    local def = pages[key]
    local p = CreateFrame("Frame", nil, main.content)
    p:SetAllPoints()
    p.titleText = text(p, "GameFontNormalLarge", 0, 0, def.title)
    p.titleText:SetTextColor(T.bronzeHi[1], T.bronzeHi[2], T.bronzeHi[3])
    if def.about then para(p, -22, def.about) end
    def.frame = p
    if def.build then guard(def, "build", p) end
    p:Hide()
  end
  main:SetScript("OnUpdate", function(self, dt)
    self.acc = (self.acc or 0) + dt
    if self.acc < 1 then return end
    self.acc = 0
    Main.refresh()
  end)
  U.fitWindow(main)
end

-- go(key): show a page; a locked council page shows the password page instead
function Main.go(key)
  if not main then Main.build() end
  local def = pages[key] or pages.rolls
  if not allowed(def) then def = Main.unlocked() and pages.loot or (def.section == "council" and pages.unlock or pages.rolls) end
  for k, d in pairs(pages) do if k ~= def.key and d.frame then d.frame:Hide() end end
  local changed = current ~= def.key
  current = def.key
  def.frame:Show()
  if changed and def.show and not def.failed then guard(def, "show", def.frame) end
  main:Show()
  Main.refresh()
end

function Main.current() return current end
function Main.page(key) return pages[key] and pages[key].frame end

function Main.refresh()
  if not main or not main:IsShown() then return end
  local def = pages[current]
  if def and not allowed(def) then return Main.go(def.key) end
  refreshNav()
  if def and def.refresh and not def.failed then guard(def, "refresh", def.frame) end
end

-- toggle(): /tlc and the minimap button. Opens on the loot page once unlocked, else on your rolls.
function Main.toggle()
  if main and main:IsShown() then main:Hide(); return end
  Main.go(current or (Main.unlocked() and "loot" or "rolls"))
end

---------------------------------------------------------------------------
-- minimap button: drag it round the minimap's edge; left-click opens the window
---------------------------------------------------------------------------

local mini

local function placeMini()
  local angle = math.rad(ns.Store.settings().minimapAngle or 200)
  mini:ClearAllPoints()
  mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

function Main.minimap()
  if not Minimap then return end
  if not mini then
    mini = CreateFrame("Button", "ToadsLCMinimapButton", Minimap)
    mini:SetSize(31, 31)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(8)
    mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mini:RegisterForDrag("LeftButton")
    mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = mini:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture(ns.Frames.LOGO or "Interface\\Icons\\INV_Misc_Bag_10") -- the Toads medallion
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    local border = mini:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    mini:SetScript("OnClick", function(_, which)
      if which == "RightButton" then Main.go(Main.unlocked() and "loot" or "rolls") else Main.toggle() end
    end)
    mini:SetScript("OnDragStart", function(self)
      self:SetScript("OnUpdate", function(btn)
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then btn:SetScript("OnUpdate", nil); return end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        ns.Store.settings().minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
        placeMini()
      end)
    end)
    mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    U.tip(mini, "Toads LC", "Click: open the window. Drag: move this button.")
  end
  placeMini()
  mini:SetShown(ns.Store.settings().minimapHidden ~= true)
end

function Main.init()
  Main.minimap()
end

return Main
