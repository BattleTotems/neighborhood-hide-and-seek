--[[
  Draggable minimap launcher (no external libs). Loaded after Core.lua; see NeighborhoodHideSeek.toc (Ui/MinimapButton.lua).
  PNG works on many Retail builds; if the icon is green or missing, export the same image as
  MinimapIcon.tga (power-of-2 size) in Textures/ and switch the extension below.
]]

local NHS = NeighborhoodHideSeek
local ADDON_NAME = NHS.ADDON_NAME or "NeighborhoodHideSeek"
local NHS_MINIMAP_ICON_TEXTURE = "Interface\\AddOns\\NeighborhoodHideSeek\\Textures\\MinimapIcon.tga"

local nhsMinimapButton

local function ensureSavedVars()
  if NHS.EnsureSavedVars then
    NHS.EnsureSavedVars()
  end
end

-- Distance from minimap center to button center: outside the circular map (not tucked inside).
local function nhsMinimapOrbitRadius()
  if not Minimap then
    return 100
  end
  local w = Minimap:GetWidth() or 140
  local half = w * 0.5
  return half + 10
end

local function nhsMinimapButton_ApplyPosition()
  local b = nhsMinimapButton
  if not b or not Minimap then
    return
  end
  ensureSavedVars()
  local angle = NHSV.minimapButtonAngle or math.rad(200)
  local r = nhsMinimapOrbitRadius()
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function nhsMinimapButton_OnDragUpdate(self)
  if not Minimap then
    return
  end
  local scale = UIParent:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  local left = Minimap:GetLeft()
  local bottom = Minimap:GetBottom()
  if not left or not bottom then
    return
  end
  local w, h = Minimap:GetWidth(), Minimap:GetHeight()
  local mx = left + w / 2
  local my = bottom + h / 2
  local dx = cx - mx
  local dy = cy - my
  local angle = math.atan2(dy, dx)
  local r = nhsMinimapOrbitRadius()
  self:ClearAllPoints()
  self:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
  self._dragAngle = angle
end

local function nhsMinimapButton_Create()
  if nhsMinimapButton or not Minimap then
    return
  end
  local b = CreateFrame("Button", ADDON_NAME .. "MinimapButton", Minimap)
  nhsMinimapButton = b
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(9)
  b:SetMovable(true)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("RightButton")
  -- Icon: direct texture on the button (no child Frame + SetAllPoints); TOPLEFT from CENTER ± half
  -- size keeps the spell art centered on the 32×32 hit box.
  local iconSize = 20
  -- MiniMap-TrackingBorder: the gold ring sits low/right inside the bitmap; a centered 54×54 quad leaves the
  -- circle’s bottom-right on the icon. Nudge the ring frame down/right (positive x, negative y on CENTER).
  local ringSize = 54
  local ringCenterNudgeX = 10
  local ringCenterNudgeY = -11
  local halfIcon = iconSize / 2
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture(NHS_MINIMAP_ICON_TEXTURE)
  icon:SetTexCoord(0, 1, 0, 1)
  icon:SetSize(iconSize, iconSize)
  icon:ClearAllPoints()
  icon:SetPoint("TOPLEFT", b, "CENTER", -halfIcon, halfIcon)
  if icon.SetSnapToPixelGrid then
    icon:SetSnapToPixelGrid(false)
  end
  if icon.SetTexelSnappingBias then
    icon:SetTexelSnappingBias(0)
  end
  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(ringSize, ringSize)
  ring:SetTexCoord(0, 1, 0, 1)
  ring:ClearAllPoints()
  ring:SetPoint(
    "CENTER",
    b,
    "CENTER",
    ringCenterNudgeX + (NHSV.minimapRingOffsetX or 0),
    ringCenterNudgeY + (NHSV.minimapRingOffsetY or 0)
  )
  if ring.SetSnapToPixelGrid then
    ring:SetSnapToPixelGrid(false)
  end
  if ring.SetTexelSnappingBias then
    ring:SetTexelSnappingBias(0)
  end
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  b:SetScript("OnClick", function(_, btn)
    if btn == "LeftButton" and NHS.ToggleMainWindow then
      NHS.ToggleMainWindow()
    end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Neighborhood Hide & Seek", 1, 1, 1)
    GameTooltip:AddLine("Click to open or close the window.", 1, 1, 1, true)
    GameTooltip:AddLine("Right-drag to move this icon.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("/nhs visitinfo — why Visit may do nothing", 0.6, 0.6, 0.6, true)
    GameTooltip:AddLine("/nhs", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", nhsMinimapButton_OnDragUpdate)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    if self._dragAngle ~= nil then
      ensureSavedVars()
      NHSV.minimapButtonAngle = self._dragAngle
      self._dragAngle = nil
    end
    nhsMinimapButton_ApplyPosition()
  end)
end

function NHS.InitMinimapButton()
  if not Minimap then
    return
  end
  ensureSavedVars()
  if NHSV.showMinimapButton == false then
    if nhsMinimapButton then
      nhsMinimapButton:Hide()
    end
    return
  end
  if not nhsMinimapButton then
    nhsMinimapButton_Create()
  end
  if nhsMinimapButton then
    nhsMinimapButton:Show()
    nhsMinimapButton_ApplyPosition()
  end
end
