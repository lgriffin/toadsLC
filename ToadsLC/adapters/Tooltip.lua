-- Tooltip: appends the Priority block to item tooltips, in the layout of Gargul's
-- "Reserved by" block: a coloured header, then one indented line per tier, specs in
-- class colour, the viewer's own tier marked with > and the others dimmed.
local _, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

local Priority = ns.Priority

local HEADER = { 0.2, 0.8, 0.4 }
local GREY = { 0.62, 0.62, 0.62 }
local DIM = 0.8

local function hex(c, dim)
  local f = dim and DIM or 1
  return string.format("|cff%02x%02x%02x", c[1] * f * 255, c[2] * f * 255, c[3] * f * 255)
end

local function classColour(class)
  local file = class and ns.Roster.FILE[class]
  local c = file and RAID_CLASS_COLORS and RAID_CLASS_COLORS[file]
  if c then return { c.r, c.g, c.b } end
  return GREY
end

-- lines(item, viewer) -> { text, ... } for the block; exposed for /tlc status and tests.
function Tooltip.lines(item, viewer, rollLeft, offspecMax)
  local mine = viewer and Priority.tierOf(item, viewer)
  local out = { hex(HEADER) .. "Priority (Toads LC)|r" }
  for t, tier in ipairs(Priority.tiers(item)) do
    local own = (t == mine)
    local cells = {}
    for c, cell in ipairs(tier) do
      local colour = cell.class and classColour(cell.class) or GREY
      cells[c] = hex(colour, not own) .. cell.label .. "|r"
    end
    local prefix = own and "> " or "  "
    out[#out + 1] = string.format("%s%s%d.|r %s", prefix, hex({ 1, 1, 1 }, not own), t,
                                  table.concat(cells, hex(GREY, not own) .. " = |r"))
  end
  if rollLeft then
    out[#out + 1] = string.format("%sRoll open: %d s left · /roll %d for off-spec|r", hex({ 1, 0.82, 0 }),
                                  rollLeft, offspecMax or 99)
  end
  return out
end

-- what the hooks saw, for /tlc debug: hooks = tooltip names hooked, last = the last item hovered
Tooltip.hooks = {}
Tooltip.dataProcessor = false
Tooltip.seen = 0
Tooltip.last = nil

-- skip(tooltip, itemId) -> reason the block is left off, or nil
local function skip(tooltip, itemId)
  if not ns.Store.settings().tooltip then return "tooltip off (/tlc tooltip on)" end
  if GetItemInfoInstant then
    local _, _, _, _, _, classId = GetItemInfoInstant(itemId)
    if classId == 9 then return "recipe" end
  end
  local owner = tooltip.GetOwner and tooltip:GetOwner()
  local ownerName = owner and owner.GetName and owner:GetName()
  if ownerName ~= nil and ownerName:find("^Quest") ~= nil then return "quest reward" end
end

local function onItem(tooltip, data)
  local name, link = tooltip:GetItem()
  local itemId = tonumber(link and link:match("item:(%d+)")) or (data and tonumber(data.id))
  if not itemId then return end
  Tooltip.seen = Tooltip.seen + 1
  local last = { itemId = itemId, name = name, tooltip = tooltip.GetName and tooltip:GetName() or "?" }
  Tooltip.last = last
  last.why = skip(tooltip, itemId)
  if last.why then return end
  local item = Priority.lookup(ns.Store.priorities(), itemId, name)
  if not item then
    last.why = ns.Store.priorities() and "not on the imported list" or "no list imported"
    return
  end
  local s = ns.App and ns.App.openSessionFor(itemId)
  local left = s and s:timeLeft(ns.App.now())
  local me = ns.Roster.specOf("player")
  local viewer = { player = ns.Roster.me(), class = me.class, spec = me.spec }
  local lines = Tooltip.lines(item, viewer, left and left > 0 and left or nil, s and s.rules.offspecRollMax)
  tooltip:AddLine(" ")
  for _, line in ipairs(lines) do tooltip:AddLine(line) end
  tooltip:Show()
  last.shown = true
end

-- The TBC Classic client ships TooltipDataProcessor and Enum.TooltipDataType, but its
-- GameTooltip does not run on tooltip data, so post calls never fire there: hook
-- OnTooltipSetItem wherever the tooltip has it, and use the data processor only for
-- tooltips without it (clients where OnTooltipSetItem is gone).
function Tooltip.init()
  local hooked = {}
  for _, name in ipairs({ "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2" }) do
    local tt = _G[name]
    if tt and tt.HookScript and tt.HasScript and tt:HasScript("OnTooltipSetItem") then
      tt:HookScript("OnTooltipSetItem", function(self) onItem(self) end)
      hooked[tt] = true
      Tooltip.hooks[#Tooltip.hooks + 1] = name
    end
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if not hooked[tooltip] and tooltip.GetItem then onItem(tooltip, data) end
    end)
    Tooltip.dataProcessor = true
  end
end
