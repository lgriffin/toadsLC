-- Minimap: a round Toads button on the minimap rim. Left-click opens the loot list,
-- right-click the council frame; drag it round the rim. /tlc minimap on|off shows or hides it.
local _, ns = ...

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local RADIUS = 80
local button

local function place()
  local angle = math.rad(ns.Store.layout().minimap.angle or 200)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

-- angleToCursor(): degrees from the minimap's centre to the cursor, for dragging round the rim
local function angleToCursor()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  return math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
end

local function build()
  button = CreateFrame("Button", "ToadsLCMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexture(ns.Frames.LOGO)
  button.icon = icon

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button:SetScript("OnClick", function(_, which)
    if which == "RightButton" then
      if not ns.Frames.showCouncil() then ns.Chat.print("No council session to show.") end
    else
      ns.Frames.showLoot()
    end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      ns.Store.layout().minimap.angle = angleToCursor()
      place()
    end)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Toads LC")
    GameTooltip:AddLine("Left-click: loot list", 1, 1, 1)
    GameTooltip:AddLine("Right-click: council", 1, 1, 1)
    GameTooltip:AddLine("Drag: move round the minimap", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
end

function MinimapButton.init()
  if not Minimap then return end
  build()
  MinimapButton.setShown(not ns.Store.layout().minimap.hide)
end

function MinimapButton.shown() return not ns.Store.layout().minimap.hide end

function MinimapButton.setShown(on)
  ns.Store.layout().minimap.hide = (not on) or nil
  if button then button:SetShown(on and true or false) end
end
