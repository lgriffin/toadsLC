-- Frames: candidate frame (raiders), council frame (officers), import/export frame.
-- Built in Lua on stock templates, no XML. Frames only read session state and call
-- ns.App actions; they never change a session themselves.
local _, ns = ...

local Frames = {}
ns.Frames = Frames

local Priority = ns.Priority

local AMBER = { 1, 0.7, 0.1 }
local GREEN = { 0.3, 0.9, 0.4 }
local GREY = { 0.55, 0.55, 0.55 }
local ROWS = 30
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

local function window(name, title, w, h)
  local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetFrameStrata("DIALOG")
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOP", 0, -5)
  f.title:SetText(title)
  tinsert(UISpecialFrames, name)
  f:Hide()
  return f
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
-- candidate frame: what a raider sees when a session opens
---------------------------------------------------------------------------

local cand

local function buildCandidate()
  cand = window("ToadsLCCandidateFrame", "Toads LC: loot", 340, 170)
  cand:SetPoint("CENTER", 0, 180)
  cand.icon = cand:CreateTexture(nil, "ARTWORK")
  cand.icon:SetSize(36, 36)
  cand.icon:SetPoint("TOPLEFT", 14, -32)
  cand.item = cand:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  cand.item:SetPoint("TOPLEFT", cand.icon, "TOPRIGHT", 8, 0)
  cand.item:SetPoint("RIGHT", -12, 0)
  cand.item:SetJustifyH("LEFT")
  cand.tier = cand:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cand.tier:SetPoint("TOPLEFT", cand.item, "BOTTOMLEFT", 0, -4)
  cand.timer = cand:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cand.timer:SetPoint("TOPRIGHT", -14, -32)
  cand.note = CreateFrame("EditBox", nil, cand, "InputBoxTemplate")
  cand.note:SetSize(300, 20)
  cand.note:SetPoint("TOPLEFT", 20, -84)
  cand.note:SetAutoFocus(false)
  cand.note:SetMaxLetters(80)
  local hint = cand:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", cand.note, "TOPLEFT", -4, 2)
  hint:SetText("Note to the council (optional)")
  local function answer(response)
    return function()
      ns.App.respond(cand.session.id, response, cand.note:GetText())
      cand:Hide()
    end
  end
  cand.main = button(cand, "Main spec", 96, answer("main"))
  cand.main:SetPoint("BOTTOMLEFT", 14, 14)
  cand.off = button(cand, "Off-spec", 96, answer("offspec"))
  cand.off:SetPoint("LEFT", cand.main, "RIGHT", 6, 0)
  cand.pass = button(cand, "Pass", 96, answer("pass"))
  cand.pass:SetPoint("LEFT", cand.off, "RIGHT", 6, 0)
  cand:SetScript("OnUpdate", function(self)
    local left = self.session and self.session:timeLeft(ns.App.now()) or 0
    self.timer:SetText(string.format("%d s", left))
    if left <= 0 then self:Hide() end
  end)
end

function Frames.showCandidate(s)
  if not cand then buildCandidate() end
  cand.session = s
  cand.icon:SetTexture(s.itemId and GetItemIcon(s.itemId) or "Interface\\Icons\\INV_Misc_QuestionMark")
  cand.item:SetText(s.itemLink or s.itemName)
  local me = ns.Roster.specOf("player")
  local tier = s.item and Priority.tierOf(s.item, { player = ns.Roster.me(), class = me.class, spec = me.spec })
  if not s.item then
    cand.tier:SetText("Not on the priority list: highest roll wins")
  elseif tier then
    cand.tier:SetText(string.format("Your tier: %d of %d", tier, #s.item.priority))
  else
    cand.tier:SetText("Your spec is not on the list for this item")
  end
  cand.off:SetText(string.format("Off-spec (%d)", s.rules.offspecRollMax))
  cand.note:SetText("")
  cand:Show()
end

function Frames.hideCandidate(s)
  if cand and cand.session and (not s or cand.session.id == s.id) then cand:Hide() end
end

---------------------------------------------------------------------------
-- council frame
---------------------------------------------------------------------------

local council

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
  council = window("ToadsLCCouncilFrame", "Toads LC: council", 640, 150 + ROWS * ROW_H)
  council.item = council:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  council.item:SetPoint("TOPLEFT", 16, -32)
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
  for i = 1, ROWS do
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
  for i, d in ipairs(defs) do
    local b = button(council, "", 120, function(self)
      local s = shownSession()
      if s and self.player then ns.App.award(s.id, self.player, self.via, self.reason) end
    end)
    b.via = d.via
    b:SetPoint("BOTTOMLEFT", 14 + ((i - 1) % 5) * 122, 38)
    council.buttons[d.key] = b
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
  council.propose:SetPoint("BOTTOMRIGHT", -14, 12)

  council:SetScript("OnUpdate", function(self, dt)
    self.acc = (self.acc or 0) + dt
    if self.acc < 0.5 then return end
    self.acc = 0
    local s = shownSession()
    if s and s.phase == "open" then Frames.refresh() end
  end)
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
  for i, row in ipairs(council.rows) do
    local e = rows[i]
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
  if not council then return end
  local current = shownSession()
  council.order = orderSessions()
  council.index = #council.order
  for i, sid in ipairs(council.order) do if current and sid == current.id then council.index = i end end
  Frames.refresh()
end

---------------------------------------------------------------------------
-- import / export frame
---------------------------------------------------------------------------

local ioFrame

local function buildIO()
  ioFrame = window("ToadsLCIOFrame", "Toads LC", 560, 420)
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
  ioFrame.action:SetPoint("BOTTOMRIGHT", -14, 12)
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
