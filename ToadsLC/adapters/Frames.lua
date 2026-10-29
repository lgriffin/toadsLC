-- Frames: candidate frame (raiders), council frame (officers), loot list, import/export frame.
-- Built in Lua on stock templates, no XML. Frames only read session state and call
-- ns.App actions; they never change a session themselves.
local _, ns = ...

local Frames = {}
ns.Frames = Frames

local Priority = ns.Priority

local AMBER = { 1, 0.7, 0.1 }
local GREEN = { 0.3, 0.9, 0.4 }
local GREY = { 0.55, 0.55, 0.55 }
local ROW_H = 18

local function colourText(c, text)
  return string.format("|cff%02x%02x%02x%s|r", c[1] * 255, c[2] * 255, c[3] * 255, text)
end

local function classText(class, text)
  local file = class and ns.Roster.FILE[class]
  local c = file and RAID_CLASS_COLORS[file]
  if not c then return colourText(GREY, text) end
  return colourText({ c.r, c.g, c.b }, text)
end

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 100, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

-- itemHover(parent, session): a mouse area that shows the session's item tooltip (and so
-- its Priority block) on hover; place it over the item's icon and name.
local function itemHover(parent, session)
  local f = CreateFrame("Frame", nil, parent)
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self)
    local s = session()
    local link = s and (s.itemLink and s.itemLink:match("|H(item:[^|]+)|h") or (s.itemId and ("item:" .. s.itemId)))
    if not link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return f
end

---------------------------------------------------------------------------
-- windows: moved by dragging, resized by the grip in the bottom-right corner. Raiders play on
-- every size of screen, so each window's size and place, and one scale for them all, are kept
-- per character (Store.layout) and put back on the next login.
---------------------------------------------------------------------------

local windows = {}
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

-- bounds(f): the window's min and max size; never larger than the screen at the current scale
local function bounds(f)
  local o, scale = f.sizing, ns.Store.layout().scale
  local maxW, maxH = o.maxW, o.maxH
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  if sw and sw > 0 then maxW = math.max(o.minW, math.min(maxW, math.floor(sw / scale))) end
  if sh and sh > 0 then maxH = math.max(o.minH, math.min(maxH, math.floor(sh / scale))) end
  return o.minW, o.minH, maxW, maxH
end

local function clampSize(f, w, h)
  local minW, minH, maxW, maxH = bounds(f)
  return math.max(minW, math.min(maxW, w)), math.max(minH, math.min(maxH, h))
end

local function setBounds(f)
  local minW, minH, maxW, maxH = bounds(f)
  if f.SetResizeBounds then
    f:SetResizeBounds(minW, minH, maxW, maxH)
  else
    f:SetMinResize(minW, minH)
    f:SetMaxResize(maxW, maxH)
  end
end

-- resized(f, w, h): reflow the window's content for its new size
local function resized(f, w, h)
  f.width, f.height = w, h
  if f.sizing.layout then f.sizing.layout(f, w, h) end
end

local function saveLayout(f)
  local point, _, relPoint, x, y = f:GetPoint()
  if not point then return end
  ns.Store.layout().frames[f:GetName()] = {
    w = math.floor(f.width + 0.5), h = math.floor(f.height + 0.5),
    point = point, relPoint = relPoint or point, x = x or 0, y = y or 0,
  }
end

-- fitWindow(f): size and place a window from what this character saved, or its defaults
local function fitWindow(f)
  local L = ns.Store.layout()
  local saved = L.frames[f:GetName()]
  f:SetScale(L.scale)
  setBounds(f)
  local w, h = clampSize(f, saved and saved.w or f.sizing.w, saved and saved.h or f.sizing.h)
  f:SetSize(w, h)
  f:ClearAllPoints()
  if saved and saved.point then
    f:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", f.sizing.x or 0, f.sizing.y or 0)
  end
  resized(f, w, h)
end

-- window(name, title, opts): opts.w, opts.h default size; minW, minH, maxW, maxH;
-- x, y offset from the screen's centre; layout(f, w, h) lays the content out for a size.
-- The builder calls fitWindow(f) once its content exists.
local function window(name, title, opts)
  local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
  f.sizing = opts
  f.width, f.height = opts.w, opts.h
  f:SetSize(opts.w, opts.h)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:SetResizable(true)
  if f.SetDontSavePosition then f:SetDontSavePosition(true) end -- ours to keep, not the client's layout cache
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    saveLayout(self)
  end)
  f:SetScript("OnSizeChanged", function(self, w, h)
    if w and h then resized(self, w, h) end
  end)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("DIALOG")
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -5)
  f.title:SetText(title)
  tinsert(UISpecialFrames, name)

  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -3, 3)
  grip:SetFrameLevel((f:GetFrameLevel() or 0) + 20)
  grip:SetNormalTexture(GRIP .. "Up")
  grip:SetHighlightTexture(GRIP .. "Highlight")
  grip:SetPushedTexture(GRIP .. "Down")
  grip:SetScript("OnMouseDown", function(_, which)
    if which ~= "LeftButton" then return end
    setBounds(f)
    f:StartSizing("BOTTOMRIGHT")
  end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    local w, h = clampSize(f, f:GetWidth() or f.width, f:GetHeight() or f.height)
    f:SetSize(w, h) -- for clients without resize bounds
    resized(f, w, h)
    saveLayout(f)
  end)
  f.grip = grip

  windows[#windows + 1] = f
  f:Hide()
  return f
end

function Frames.scale() return ns.Store.layout().scale end

-- setScale(s): one scale for every Toads LC window, kept per character
function Frames.setScale(s)
  ns.Store.layout().scale = s
  for _, f in ipairs(windows) do fitWindow(f) end
end

-- resetLayout(): every window back to its default size and place, at scale 1
function Frames.resetLayout()
  local L = ns.Store.layout()
  L.frames, L.scale = {}, 1
  for _, f in ipairs(windows) do fitWindow(f) end
end

-- prompt(title, onAccept(text)): one-line text input.
StaticPopupDialogs.TOADSLC_PROMPT = {
  text = "%s",
  button1 = ACCEPT,
  button2 = CANCEL,
  hasEditBox = true,
  maxLetters = 120,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  OnAccept = function(self, data)
    local box = self.editBox or self.EditBox
    data(box:GetText())
  end,
  EditBoxOnEnterPressed = function(self, data)
    data(self:GetText())
    self:GetParent():Hide()
  end,
}

function Frames.prompt(text, onAccept)
  StaticPopup_Show("TOADSLC_PROMPT", text, nil, onAccept)
end

local function contextMenu(owner, entries)
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner, function(_, root)
      for _, e in ipairs(entries) do
        if e.children then
          local sub = root:CreateButton(e.text)
          for _, c in ipairs(e.children) do sub:CreateButton(c.text, c.func) end
        else
          root:CreateButton(e.text, e.func)
        end
      end
    end)
    return
  end
  Frames.menuFrame = Frames.menuFrame or CreateFrame("Frame", "ToadsLCMenu", UIParent, "UIDropDownMenuTemplate")
  local menu = {}
  for _, e in ipairs(entries) do
    local item = { text = e.text, func = e.func, notCheckable = true }
    if e.children then
      item.hasArrow = true
      item.menuList = {}
      for _, c in ipairs(e.children) do item.menuList[#item.menuList + 1] = { text = c.text, func = c.func, notCheckable = true } end
    end
    menu[#menu + 1] = item
  end
  EasyMenu(menu, Frames.menuFrame, "cursor", 0, 0, "MENU")
end

---------------------------------------------------------------------------
-- candidate frame: what a raider sees when sessions open. One row per item still waiting for
-- this player's answer, so a whole loot pool opened at once (/tlc loot all) is answered in one
-- window; the note goes with the next button pressed.
---------------------------------------------------------------------------

local cand
local CAND_ROWS, CAND_MAX = 6, 12 -- rows at the default size, and at most
local CAND_H = 44
local CAND_BUTTONS = 162 -- the answer buttons, measured from the row's right edge

local function waitingForMe()
  local reg, out = ns.App.registry, {}
  for _, id in ipairs(reg.order) do
    local s = reg:get(id)
    if s.mode == "session" and s.phase == "open" and not s.myResponse and s:timeLeft(ns.App.now()) > 0 then
      out[#out + 1] = s
    end
  end
  return out
end

local function tierText(s)
  local me = ns.Roster.specOf("player")
  local tier = s.item and Priority.tierOf(s.item, { player = ns.Roster.me(), class = me.class, spec = me.spec })
  if not s.item then return "Not on the priority list: highest roll wins" end
  if tier then return string.format("Your tier: %d of %d", tier, #s.item.priority) end
  return "Your spec is not on the list for this item"
end

local function buildCandidate()
  cand = window("ToadsLCCandidateFrame", "Toads LC: loot", {
    w = 470, h = 96 + CAND_ROWS * CAND_H, minW = 420, minH = 96 + CAND_H, maxW = 900, maxH = 96 + CAND_MAX * CAND_H,
    y = 180, layout = function(f, w, h)
      f.visible = math.max(1, math.min(CAND_MAX, math.floor((h - 96) / CAND_H)))
      local rowW = w - 24
      for _, row in ipairs(f.rows) do
        row:SetWidth(rowW)
        row.item:SetWidth(rowW - 80)
        row.tier:SetWidth(rowW - 44 - CAND_BUTTONS)
        row.hover:SetWidth(rowW - 4 - CAND_BUTTONS)
      end
      if f:IsShown() then Frames.refreshCandidate() end
    end,
  })
  cand.offset = 0
  local function answer(row, response)
    return function()
      if not row.session then return end
      ns.App.respond(row.session.id, response, cand.note:GetText())
      cand.note:SetText("")
      Frames.refreshCandidate()
    end
  end
  cand.rows = {}
  for i = 1, CAND_MAX do
    local row = CreateFrame("Frame", nil, cand)
    row:SetSize(446, CAND_H)
    row:SetPoint("TOPLEFT", 12, -28 - (i - 1) * CAND_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", 2, 0)
    row.item = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.item:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, 0)
    row.item:SetWidth(220)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)
    row.tier = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.tier:SetPoint("TOPLEFT", row.item, "BOTTOMLEFT", 0, -3)
    row.tier:SetWidth(220)
    row.tier:SetJustifyH("LEFT")
    row.timer = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.timer:SetPoint("TOPRIGHT", -2, -2)
    row.hover = itemHover(row, function() return row.session end)
    row.hover:SetPoint("LEFT", 2, 0)
    row.hover:SetSize(280, 36)
    row.main = button(row, "MS", 50, answer(row, "main"))
    row.main:SetPoint("BOTTOMRIGHT", -112, 2)
    row.off = button(row, "OS", 64, answer(row, "offspec"))
    row.off:SetPoint("LEFT", row.main, "RIGHT", 2, 0)
    row.pass = button(row, "Pass", 44, answer(row, "pass"))
    row.pass:SetPoint("LEFT", row.off, "RIGHT", 2, 0)
    cand.rows[i] = row
  end
  cand.more = cand:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cand.more:SetPoint("TOPRIGHT", -30, -6)
  cand:EnableMouseWheel(true)
  cand:SetScript("OnMouseWheel", function(self, delta)
    self.offset = math.max(0, self.offset - delta)
    Frames.refreshCandidate()
  end)
  cand.note = CreateFrame("EditBox", nil, cand, "InputBoxTemplate")
  cand.note:SetHeight(20)
  cand.note:SetPoint("BOTTOMLEFT", 20, 14)
  cand.note:SetPoint("BOTTOMRIGHT", -26, 14)
  cand.note:SetAutoFocus(false)
  cand.note:SetMaxLetters(80)
  local hint = cand:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", cand.note, "TOPLEFT", -4, 2)
  hint:SetText("Note to the council (optional, sent with your next answer)")
  cand:SetScript("OnUpdate", function(self, dt)
    self.acc = (self.acc or 0) + dt
    if self.acc < 0.5 then return end
    self.acc = 0
    Frames.refreshCandidate()
  end)
  fitWindow(cand)
end

-- refreshCandidate(): one row per open session still waiting for my answer; hidden when none
function Frames.refreshCandidate()
  if not cand then return end
  local list = waitingForMe()
  if #list == 0 then cand:Hide(); return end
  local shown = cand.visible
  cand.offset = math.max(0, math.min(cand.offset, #list - shown))
  cand.title:SetText(#list == 1 and "Toads LC: loot" or string.format("Toads LC: loot (%d items)", #list))
  cand.more:SetText(#list > shown and string.format("%d-%d of %d (scroll)", cand.offset + 1,
    math.min(#list, cand.offset + shown), #list) or "")
  local now = ns.App.now()
  for i, row in ipairs(cand.rows) do
    local s = i <= shown and list[i + cand.offset]
    row.session = s
    if not s then
      row:Hide()
    else
      row:Show()
      row.icon:SetTexture(s.itemId and GetItemIcon(s.itemId) or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.item:SetText(s.itemLink or s.itemName)
      row.tier:SetText(tierText(s))
      row.timer:SetText(string.format("%d s", s:timeLeft(now)))
      row.off:SetText(string.format("OS (%d)", s.rules.offspecRollMax))
    end
  end
  cand:Show()
end

function Frames.showCandidate()
  if not cand then buildCandidate() end
  Frames.refreshCandidate()
end

function Frames.hideCandidate()
  if cand then Frames.refreshCandidate() end
end

---------------------------------------------------------------------------
-- council frame
---------------------------------------------------------------------------

local council
local ROWS, ROWS_MAX = 30, 40 -- candidate rows at the default size, and at most

-- the Note column takes whatever width the others leave
local COLS = {
  { key = "name", title = "Name", w = 100 },
  { key = "spec", title = "Spec", w = 96 },
  { key = "tier", title = "Tier", w = 34 },
  { key = "resp", title = "Response", w = 64 },
  { key = "roll", title = "Roll", w = 40 },
  { key = "votes", title = "Votes", w = 60 },
  { key = "note", title = "Note", w = 186 },
}

local function shownSession()
  local reg = ns.App.registry
  local id = council.order and council.order[council.index]
  return id and reg:get(id)
end

local function rowMenu(row)
  local s, e = shownSession(), row.entry
  if not s or not e then return end
  local me = ns.Roster.me()
  local entries = {
    { text = "Vote for " .. e.player, func = function() ns.App.vote(s.id, e.player) end },
    { text = "Propose " .. e.player .. "…", func = function()
        Frames.prompt("Propose " .. e.player .. ": reason", function(reason) ns.App.propose(s.id, e.player, reason) end)
      end },
  }
  if s:isLeader(me) then
    local class = e.class
    if class and Priority.CLASSES[class] then
      local specs = {}
      for _, sp in ipairs(Priority.CLASSES[class]) do
        local tok = class .. ":" .. sp
        specs[#specs + 1] = { text = Priority.label(tok), func = function() ns.App.setSpec(s.id, e.player, tok) end }
      end
      entries[#entries + 1] = { text = "Set spec", children = specs }
    end
    entries[#entries + 1] = { text = "Award to " .. e.player .. "…", func = function()
        Frames.prompt("Award to " .. e.player .. ": reason (recorded if this departs from the list)",
          function(reason) ns.App.award(s.id, e.player, "manual", reason) end)
      end }
  end
  contextMenu(row, entries)
end

local function buildCouncil()
  council = window("ToadsLCCouncilFrame", "Toads LC: council", {
    w = 640, h = 150 + ROWS * ROW_H, minW = 560, minH = 150 + 5 * ROW_H, maxW = 1400, maxH = 150 + ROWS_MAX * ROW_H,
    layout = function(f, w, h)
      f.visible = math.max(5, math.min(ROWS_MAX, math.floor((h - 150) / ROW_H)))
      for _, row in ipairs(f.rows) do
        row:SetWidth(w - 40)
        row.cells.note:SetWidth(w - 454)
      end
      Frames.refresh()
    end,
  })
  council.item = council:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  council.item:SetPoint("TOPLEFT", 16, -32)
  council.itemHover = itemHover(council, function() return shownSession() end)
  council.itemHover:SetPoint("TOPLEFT", council.item, "TOPLEFT")
  council.itemHover:SetSize(300, 20)
  council.status = council:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  council.status:SetPoint("TOPRIGHT", -40, -36)
  council.prev = button(council, "<", 24, function() council.index = math.max(1, council.index - 1); Frames.refresh() end)
  council.prev:SetPoint("TOPRIGHT", -12, -30)
  council.next = button(council, ">", 24, function() council.index = math.min(#council.order, council.index + 1); Frames.refresh() end)
  council.next:SetPoint("RIGHT", council.prev, "LEFT", -2, 0)
  council.status:ClearAllPoints()
  council.status:SetPoint("RIGHT", council.next, "LEFT", -8, 0)

  local x = 16
  for _, col in ipairs(COLS) do
    local h = council:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", x, -58)
    h:SetText(col.title)
    col.x = x
    x = x + col.w
  end

  council.rows = {}
  for i = 1, ROWS_MAX do
    local row = CreateFrame("Button", nil, council)
    row:SetSize(600, ROW_H)
    row:SetPoint("TOPLEFT", 12, -72 - (i - 1) * ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.cells = {}
    for _, col in ipairs(COLS) do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", col.x - 12, 0)
      fs:SetWidth(col.w - 4)
      fs:SetJustifyH("LEFT")
      fs:SetWordWrap(false)
      row.cells[col.key] = fs
    end
    row:SetScript("OnClick", function(self, which)
      local s = shownSession()
      if not s or not self.entry or self.entry.ignored then return end
      if which == "RightButton" then rowMenu(self) else ns.App.vote(s.id, self.entry.player) end
    end)
    row:SetScript("OnEnter", function(self)
      local s = shownSession()
      if not s or not self.entry or not self.voters or s.rules.votesVisibleTo ~= "council" then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Votes for " .. self.entry.player)
      for _, v in ipairs(self.voters) do GameTooltip:AddLine((v:gsub("^%l", string.upper)), 1, 1, 1) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    council.rows[i] = row
  end

  -- more candidates than rows: the mouse wheel scrolls the list
  council.offset = 0
  council.more = council:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  council.more:SetPoint("TOPRIGHT", -16, -58)
  council:EnableMouseWheel(true)
  council:SetScript("OnMouseWheel", function(self, delta)
    self.offset = math.max(0, math.min((self.total or 0) - self.visible, self.offset - delta * 3))
    Frames.refresh()
  end)

  council.footer = council:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  council.footer:SetPoint("BOTTOMLEFT", 16, 66)
  council.footer:SetPoint("RIGHT", -16, 0)
  council.footer:SetJustifyH("LEFT")

  -- leader's award buttons, laid out left to right; text is set on refresh
  council.buttons = {}
  local defs = {
    { key = "votes", via = "votes" }, { key = "proposal", via = "proposal" }, { key = "list", via = "list" },
    { key = "listRoll", via = "highest-roll" }, { key = "highest", via = "highest-roll" },
  }
  council.awardOrder = {}
  for i, d in ipairs(defs) do
    local b = button(council, "", 120, function(self)
      local s = shownSession()
      if s and self.player then ns.App.award(s.id, self.player, self.via, self.reason) end
    end)
    b.via = d.via
    b:SetPoint("BOTTOMLEFT", 14 + (i - 1) * 122, 38)
    council.buttons[d.key] = b
    council.awardOrder[i] = b
  end
  council.awardTo = button(council, "Award to…", 100, function()
    local s = shownSession()
    if not s then return end
    Frames.prompt("Award to (name):", function(name)
      if name and name ~= "" then
        Frames.prompt("Reason for awarding " .. name .. ":", function(reason) ns.App.award(s.id, name, "manual", reason) end)
      end
    end)
  end)
  council.awardTo:SetPoint("BOTTOMLEFT", 14, 12)
  council.noAward = button(council, "No award", 90, function()
    local s = shownSession()
    if s then ns.App.award(s.id, nil, nil) end
  end)
  council.noAward:SetPoint("LEFT", council.awardTo, "RIGHT", 4, 0)
  council.closeBtn = button(council, "Close responses", 120, function()
    local s = shownSession()
    if s then ns.App.close(s.id) end
  end)
  council.closeBtn:SetPoint("LEFT", council.noAward, "RIGHT", 4, 0)
  council.reroll = button(council, "Re-roll tied", 100, function()
    local s = shownSession()
    if s then ns.App.reroll(s.id) end
  end)
  council.reroll:SetPoint("LEFT", council.closeBtn, "RIGHT", 4, 0)
  council.propose = button(council, "Propose…", 90, function()
    local s = shownSession()
    if not s then return end
    Frames.prompt("Propose (name):", function(name)
      if name and name ~= "" then
        Frames.prompt("Reason for proposing " .. name .. ":", function(reason) ns.App.propose(s.id, name, reason) end)
      end
    end)
  end)
  council.propose:SetPoint("BOTTOMRIGHT", -24, 12)

  council:SetScript("OnUpdate", function(self, dt)
    self.acc = (self.acc or 0) + dt
    if self.acc < 0.5 then return end
    self.acc = 0
    local s = shownSession()
    if s and s.phase == "open" then Frames.refresh() end
  end)
  fitWindow(council)
end

local function setButton(b, label, player, reason)
  if player then
    b:SetText(label .. ": " .. player)
    b.player, b.reason = player, reason
    b:Show()
  else
    b.player = nil
    b:Hide()
  end
end

local function orderSessions()
  local reg = ns.App.registry
  local list = {}
  for _, id in ipairs(reg.order) do
    local s = reg:get(id)
    if s.mode == "session" and s:isCouncil(ns.Roster.me()) then list[#list + 1] = id end
  end
  return list
end

-- refresh(): redraw the council frame from the session shown.
function Frames.refresh()
  if not council or not council:IsShown() then return end
  local s = shownSession()
  if not s then council:Hide(); return end
  local me = ns.Roster.me()
  local leader = s:isLeader(me)
  local now = ns.App.now()
  council.prev:SetEnabled(council.index > 1)
  council.next:SetEnabled(council.index < #council.order)
  council.item:SetText(s.itemLink or s.itemName)
  if s.phase == "open" then
    council.status:SetText(string.format("Responses open: %d s · %d passed", s:timeLeft(now), s:passCount()))
  elseif s.phase == "voting" then
    council.status:SetText(string.format("Voting · %d passed", s:passCount()))
  else
    council.status:SetText("Awarded: " .. (s.awardedTo or "nobody"))
  end

  local r = s:result()
  local opts = s:awardOptions()
  local counts = s:voteCounts()
  local voters = {}
  for officer, c in pairs(s.votes) do
    local k = Priority.nameKey(c)
    voters[k] = voters[k] or {}
    table.insert(voters[k], officer)
  end
  local tied = {}
  for _, n in ipairs(r.tied or {}) do tied[Priority.nameKey(n)] = true end

  -- ranked rows, then responses still waiting for their roll, then ignored lines in grey
  local rows = {}
  for _, e in ipairs(r.ranked) do rows[#rows + 1] = e end
  for _, e in ipairs(s.candidates) do
    if not e.ignored and not e.roll then rows[#rows + 1] = e end
  end
  for _, e in ipairs(s.candidates) do
    if e.ignored then rows[#rows + 1] = e end
  end

  local myVote = s.votes[Priority.nameKey(me)]
  council.total = #rows
  local shown = council.visible
  council.offset = math.max(0, math.min(council.offset, #rows - shown))
  if #rows > shown then
    council.more:SetText(string.format("%d-%d of %d (scroll)", council.offset + 1,
      math.min(#rows, council.offset + shown), #rows))
  else
    council.more:SetText("")
  end
  for i, row in ipairs(council.rows) do
    local e = i <= shown and rows[i + council.offset]
    row.entry = e
    if not e then
      row:Hide()
    else
      row:Show()
      local k = Priority.nameKey(e.player)
      local tier = not e.ignored and e.tier
      local specLabel = e.spec and Priority.label(e.spec) or ((e.class or "?") .. "?")
      local says
      if not e.ignored and r.ranked[1] == e and (r.winner == e or not r.winner) then says = "list says" end
      if not e.ignored and opts.listRoll and Priority.nameKey(opts.listRoll) == k then
        says = says and "list says (both)" or "list says (roll)"
      elseif says and opts.listRoll then
        says = "list says (priority)"
      end
      local resp = e.ignored and e.ignored or (e.max == s.rules.offspecRollMax and "off-spec" or (e.response == "offspec" and "off-spec" or "main"))
      local n = counts[k] or 0
      row.voters = voters[k]
      local pips = string.rep("|TInterface\\COMMON\\Indicator-Green:12|t", math.min(n, 6))
      if myVote and Priority.nameKey(myVote) == k then pips = pips .. colourText(GREEN, " (you)") end
      local cells = {
        name = classText(e.class, e.player),
        spec = specLabel,
        tier = tier and tostring(tier) or "-",
        resp = resp,
        roll = e.roll and tostring(e.roll) or "…",
        votes = pips,
        note = (says and colourText(GREEN, says .. "  ") or "") .. (e.note or ""),
      }
      for key, fs in pairs(row.cells) do
        fs:SetText(cells[key])
        if e.ignored then fs:SetTextColor(GREY[1], GREY[2], GREY[3]) else fs:SetTextColor(1, 1, 1) end
      end
      if e.ignored then row.cells.name:SetText(colourText(GREY, e.player)) end
      local proposed = s.proposal and Priority.nameKey(s.proposal.player) == k
      if proposed or (tied[k] and not e.ignored) then
        row.bg:SetColorTexture(AMBER[1], AMBER[2], AMBER[3], 0.25)
      elseif says then
        row.bg:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 0.12)
      else
        row.bg:SetColorTexture(0, 0, 0, 0)
      end
    end
  end

  if s.proposal then
    council.footer:SetText(string.format("Proposal by %s: %s%s", s.proposal.by, s.proposal.player,
      (s.proposal.reason ~= "" and (": " .. s.proposal.reason) or "")))
  else
    council.footer:SetText(s.phase == "done" and s:awardLine() or "Click a row to vote; right-click to propose.")
  end

  local canAward = leader and s.phase ~= "done"
  local B = council.buttons
  setButton(B.votes, string.format("Votes (%d)", opts.voteCount or 0), canAward and opts.votes)
  setButton(B.proposal, "Proposal", canAward and opts.proposal, s.proposal and s.proposal.reason)
  setButton(B.list, "List says", canAward and (opts.list or opts.listPriority))
  B.list.via = "list"
  setButton(B.listRoll, "List (roll)", canAward and opts.listRoll)
  setButton(B.highest, "Highest roll", canAward and not opts.listRoll and opts.highest)
  local x = 14 -- the award buttons shown, side by side, so a narrow window still fits them
  for _, b in ipairs(council.awardOrder) do
    if b:IsShown() then
      b:ClearAllPoints()
      b:SetPoint("BOTTOMLEFT", x, 38)
      x = x + 122
    end
  end
  for _, b in pairs({ council.awardTo, council.noAward }) do b:SetShown(canAward) end
  council.closeBtn:SetShown(leader and s.phase == "open")
  council.reroll:SetShown(leader and s.phase == "voting" and r.tie)
  council.propose:SetShown(s.phase ~= "done")
end

function Frames.showCouncil(id)
  if not council then buildCouncil() end
  council.order = orderSessions()
  if #council.order == 0 then return false end
  council.index = #council.order
  for i, sid in ipairs(council.order) do if sid == id then council.index = i end end
  council:Show()
  Frames.refresh()
  return true
end

function Frames.councilShown() return council and council:IsShown() end

function Frames.sessionsChanged()
  Frames.refreshLoot()
  if not council then return end
  local current = shownSession()
  council.order = orderSessions()
  council.index = #council.order
  for i, sid in ipairs(council.order) do if current and sid == current.id then council.index = i end end
  Frames.refresh()
end

---------------------------------------------------------------------------
-- loot list frame: what dropped tonight; the leader starts each item from here
---------------------------------------------------------------------------

local lootFrame
local LOOT_ROWS, LOOT_MAX = 16, 30 -- rows at the default size, and at most
local LOOT_H = 22

local function lootEntries() return ns.Loot.list.entries end

local function buildLoot()
  -- the Item column takes whatever width Boss, Status and the buttons leave
  lootFrame = window("ToadsLCLootFrame", "Toads LC: raid loot", {
    w = 580, h = 110 + LOOT_ROWS * LOOT_H, minW = 480, minH = 110 + 4 * LOOT_H, maxW = 1100, maxH = 110 + LOOT_MAX * LOOT_H,
    layout = function(f, w, h)
      f.visible = math.max(4, math.min(LOOT_MAX, math.floor((h - 110) / LOOT_H)))
      local rowW = w - 30
      local itemW = rowW - 324
      local bossX = 28 + itemW + 4
      f.heads.boss:SetPoint("TOPLEFT", 12 + bossX, -32)
      f.heads.status:SetPoint("TOPLEFT", 12 + bossX + 100, -32)
      for _, row in ipairs(f.rows) do
        row:SetWidth(rowW)
        row.item:SetWidth(itemW)
        row.hover:SetWidth(itemW)
        row.boss:SetPoint("LEFT", bossX, 0)
        row.status:SetPoint("LEFT", bossX + 100, 0)
      end
      Frames.refreshLoot()
    end,
  })
  lootFrame.offset = 0
  lootFrame.heads = {}
  local heads = { { "num", "#", 16 }, { "item", "Item", 40 }, { "boss", "Boss", 270 }, { "status", "Status", 370 } }
  for _, h in ipairs(heads) do
    local fs = lootFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", h[3], -32)
    fs:SetText(h[2])
    lootFrame.heads[h[1]] = fs
  end
  lootFrame.rows = {}
  for i = 1, LOOT_MAX do
    local row = CreateFrame("Frame", nil, lootFrame)
    row:SetSize(530, LOOT_H)
    row:SetPoint("TOPLEFT", 12, -46 - (i - 1) * LOOT_H)
    row.num = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.num:SetPoint("LEFT", 4, 0)
    row.item = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.item:SetPoint("LEFT", 28, 0)
    row.item:SetWidth(226)
    row.item:SetJustifyH("LEFT")
    row.item:SetWordWrap(false)
    row.hover = itemHover(row, function() return row.entry and { itemLink = ns.Loot.linkOf(row.entry), itemId = row.entry.itemId } end)
    row.hover:SetPoint("LEFT", 28, 0)
    row.hover:SetSize(226, 20)
    row.boss = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.boss:SetPoint("LEFT", 258, 0)
    row.boss:SetWidth(96)
    row.boss:SetJustifyH("LEFT")
    row.boss:SetWordWrap(false)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("LEFT", 358, 0)
    row.status:SetWidth(90)
    row.status:SetJustifyH("LEFT")
    row.status:SetWordWrap(false)
    row.session = button(row, "Session", 58, function()
      if row.entry then ns.Loot.start(ns.Loot.list:numberOf(row.entry), "session") end
    end)
    row.session:SetPoint("RIGHT", -40, 0)
    row.roll = button(row, "Roll", 40, function()
      if row.entry then ns.Loot.start(ns.Loot.list:numberOf(row.entry), "roll") end
    end)
    row.roll:SetPoint("LEFT", row.session, "RIGHT", 0, 0)
    lootFrame.rows[i] = row
  end
  lootFrame:EnableMouseWheel(true)
  lootFrame:SetScript("OnMouseWheel", function(self, delta)
    self.offset = math.max(0, math.min(#lootEntries() - self.visible, self.offset - delta * 3))
    Frames.refreshLoot()
  end)
  lootFrame.footer = lootFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lootFrame.footer:SetPoint("BOTTOMLEFT", 16, 40)
  lootFrame.footer:SetPoint("RIGHT", -16, 0)
  lootFrame.footer:SetJustifyH("LEFT")
  lootFrame.nextBtn = button(lootFrame, "Start next", 100, function() ns.Loot.startNext("session") end)
  lootFrame.nextBtn:SetPoint("BOTTOMLEFT", 14, 12)
  lootFrame.all = button(lootFrame, "Start all", 90, function() ns.Loot.startAll() end)
  lootFrame.all:SetPoint("LEFT", lootFrame.nextBtn, "RIGHT", 4, 0)
  lootFrame.announce = button(lootFrame, "Announce list", 110, function() ns.Loot.announce() end)
  lootFrame.announce:SetPoint("LEFT", lootFrame.all, "RIGHT", 4, 0)
  lootFrame.clear = button(lootFrame, "Clear list", 90, function()
    Frames.prompt("Clear the whole loot list? Type yes", function(text)
      if text and text:lower() == "yes" then ns.Loot.clear() end
    end)
  end)
  lootFrame.clear:SetPoint("BOTTOMRIGHT", -24, 12)
  fitWindow(lootFrame)
end

local STATUS_COLOUR = { waiting = AMBER, awarded = GREEN, none = GREY }

function Frames.refreshLoot()
  if not lootFrame or not lootFrame:IsShown() then return end
  local entries = lootEntries()
  local lead = ns.Roster.canLead()
  local busy = ns.App.registry:rolling() ~= nil
  local shown = lootFrame.visible
  lootFrame.offset = math.max(0, math.min(lootFrame.offset, #entries - shown))
  for i, row in ipairs(lootFrame.rows) do
    local n = i + lootFrame.offset
    local e = i <= shown and entries[n]
    row.entry = e
    if not e then
      row:Hide()
    else
      row:Show()
      row.num:SetText(tostring(n))
      row.item:SetText(ns.Loot.linkOf(e))
      row.boss:SetText((e.sim and "[sim] " or "") .. (e.boss ~= "" and e.boss or "?"))
      row.status:SetText(colourText(STATUS_COLOUR[e.status] or { 1, 1, 1 }, ns.LootList.label(e)))
      local can = lead and ns.LootList.startable(e)
      row.session:SetShown(can)
      row.roll:SetShown(can and not e.sim)
      row.session:SetEnabled(not busy)
      row.roll:SetEnabled(not busy)
    end
  end
  local waiting = #ns.Loot.list:waiting()
  if #entries == 0 then
    lootFrame.footer:SetText("Nothing recorded yet. Drops you loot in a raid appear here; /tlc loot add <item> adds one by hand.")
  else
    lootFrame.footer:SetText(string.format("%d item%s, %d waiting%s.", #entries, #entries == 1 and "" or "s", waiting,
      busy and "; one is taking rolls now" or ""))
  end
  lootFrame.nextBtn:SetShown(lead and waiting > 0)
  lootFrame.nextBtn:SetEnabled(not busy)
  lootFrame.all:SetShown(lead and waiting > 1)
  lootFrame.all:SetEnabled(not busy)
  lootFrame.announce:SetShown(lead and waiting > 0)
  lootFrame.clear:SetShown(lead and #entries > 0)
end

function Frames.showLoot()
  if not lootFrame then buildLoot() end
  lootFrame:Show()
  Frames.refreshLoot()
  return true
end

function Frames.lootChanged() Frames.refreshLoot() end

---------------------------------------------------------------------------
-- import / export frame
---------------------------------------------------------------------------

local ioFrame

local function buildIO()
  ioFrame = window("ToadsLCIOFrame", "Toads LC", {
    w = 560, h = 420, minW = 360, minH = 200, maxW = 1400, maxH = 1000,
    layout = function(f, w) if f.box then f.box:SetWidth(w - 60) end end,
  })
  local scroll = CreateFrame("ScrollFrame", nil, ioFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -32)
  scroll:SetPoint("BOTTOMRIGHT", -34, 48)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(500)
  box:SetAutoFocus(false)
  box:SetScript("OnEscapePressed", function() ioFrame:Hide() end)
  box:SetScript("OnTextChanged", function(self)
    if ioFrame.readOnly and self:GetText() ~= ioFrame.text then
      self:SetText(ioFrame.text)
      self:HighlightText()
    end
  end)
  scroll:SetScrollChild(box)
  ioFrame.box = box
  ioFrame.status = ioFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ioFrame.status:SetPoint("BOTTOMLEFT", 16, 18)
  ioFrame.status:SetPoint("RIGHT", -120, 0)
  ioFrame.status:SetJustifyH("LEFT")
  ioFrame.action = button(ioFrame, "Import", 96, function()
    local ok, msg = ns.App.import(ioFrame.box:GetText())
    ioFrame.status:SetText(msg)
    if ok then ioFrame.status:SetTextColor(GREEN[1], GREEN[2], GREEN[3]) else ioFrame.status:SetTextColor(1, 0.3, 0.3) end
  end)
  ioFrame.action:SetPoint("BOTTOMRIGHT", -24, 12)
  fitWindow(ioFrame)
end

function Frames.showExport(text, status)
  if not ioFrame then buildIO() end
  ioFrame.title:SetText("Toads LC: export (Ctrl+C to copy)")
  ioFrame.readOnly, ioFrame.text = true, text
  ioFrame.box:SetText(text)
  ioFrame.status:SetText(status or "")
  ioFrame.status:SetTextColor(1, 1, 1)
  ioFrame.action:Hide()
  ioFrame:Show()
  ioFrame.box:SetFocus()
  ioFrame.box:HighlightText()
end

function Frames.showImport()
  if not ioFrame then buildIO() end
  ioFrame.title:SetText("Toads LC: import priorities (paste, then Import)")
  ioFrame.readOnly, ioFrame.text = false, nil
  ioFrame.box:SetText("")
  ioFrame.status:SetText("Paste the toads-loot-priority JSON from the site.")
  ioFrame.status:SetTextColor(1, 1, 1)
  ioFrame.action:Show()
  ioFrame:Show()
  ioFrame.box:SetFocus()
end
