--[[
  “Game Modes” scrollable help window.
  Loaded after Core.lua; see NeighborhoodHideSeek.toc (Ui/GameModesInfo.lua).
]]


local function nhsBuildGameModesBody()
  local lines = {}
  for _, id in ipairs(NeighborhoodHideSeek.GAME_MODE_IDS) do
    local def = NeighborhoodHideSeek.GameModeDefinition(id)
    if def and def.description then
      local line = ("• %s: %s"):format(def.label, def.description)
      if def.warning then
        line = line .. " " .. def.warning
      end
      lines[#lines + 1] = line
    end
  end
  return table.concat(lines, "\n")
end

local NHS_HOW_TO_PLAY_SECTIONS = {
  {
    title = "Game Modes",
    body = nhsBuildGameModesBody(),
  },
}

function NeighborhoodHideSeek.CreateGameModesInfoFrame()
  local NHS = NeighborhoodHideSeek

  local function ensureSaved()
    if NHS.EnsureSavedVars then
      NHS.EnsureSavedVars()
    end
  end

  local htpf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  htpf:SetSize(360, 420)
  htpf:SetClampedToScreen(true)
  htpf:SetMovable(true)
  htpf:EnableMouse(true)
  htpf:RegisterForDrag("LeftButton")
  htpf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  htpf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSaved()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.gameModesInfoFramePoint = { p, rp or "UIParent", x, y }
  end)
  htpf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  htpf:SetBackdropColor(0, 0, 0, 0.9)

  local htpfTitle = htpf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  htpfTitle:SetPoint("TOP", 0, -14)
  htpfTitle:SetText("Game Modes")

  local htpScroll = CreateFrame("ScrollFrame", nil, htpf)
  htpScroll:SetPoint("TOPLEFT", 16, -42)
  htpScroll:SetSize(328, 358)
  NeighborhoodHideSeek.SetupScrollFrameMouseWheel(htpScroll)
  local htpScrollChild = CreateFrame("Frame", nil, htpScroll)
  htpScrollChild:SetSize(328, 1)
  htpScroll:SetScrollChild(htpScrollChild)

  local textWidth = 318
  local gapTitleToBody = 6
  local gapBetweenSections = 14
  local bottomPad = 12

  local yOffset = 0
  local n = #NHS_HOW_TO_PLAY_SECTIONS
  for i, sec in ipairs(NHS_HOW_TO_PLAY_SECTIONS) do
    local hdr = htpScrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr:SetWidth(textWidth)
    hdr:SetJustifyH("LEFT")
    hdr:SetText(sec.title .. ":")
    hdr:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", 0, -yOffset)
    yOffset = yOffset + hdr:GetStringHeight() + gapTitleToBody

    local body = htpScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    body:SetWidth(textWidth)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(4)
    body:SetText(sec.body)
    body:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", 0, -yOffset)
    yOffset = yOffset + body:GetStringHeight()
    if i < n then
      yOffset = yOffset + gapBetweenSections
    end
  end

  htpScrollChild:SetHeight(math.max(yOffset + bottomPad, 1))
  htpScroll:SetVerticalScroll(0)

  local htpfCloseBtn = CreateFrame("Button", nil, htpf, "UIPanelCloseButton")
  htpfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  htpfCloseBtn:SetScript("OnClick", function()
    htpf:Hide()
  end)
  htpf._nhsCloseButton = htpfCloseBtn
  htpf:Hide()

  return { frame = htpf }
end
