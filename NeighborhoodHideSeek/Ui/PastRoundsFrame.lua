--[[
  "Previous rounds" multi-block scroll popup. Load after Ui/ScrollUtil.lua; before Ui/MainFrame.lua.
]]

local NHS = NeighborhoodHideSeek

function NHS.CreatePastRoundsFrame()
  local State = NHS.State

  local pastRoundsFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  pastRoundsFrame:SetSize(320, 380)
  pastRoundsFrame:SetClampedToScreen(true)
  pastRoundsFrame:SetMovable(true)
  pastRoundsFrame:EnableMouse(true)
  pastRoundsFrame:RegisterForDrag("LeftButton")
  pastRoundsFrame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  pastRoundsFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    NHS.EnsureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.pastRoundsFramePoint = { p, rp or "UIParent", x, y }
  end)
  pastRoundsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  pastRoundsFrame:SetBackdropColor(0, 0, 0, 0.9)
  local pastRoundsTitle = pastRoundsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  pastRoundsTitle:SetPoint("TOP", 0, -14)
  pastRoundsTitle:SetText("Previous Rounds")
  local pastRoundsScroll = CreateFrame("ScrollFrame", nil, pastRoundsFrame)
  pastRoundsScroll:SetPoint("TOPLEFT", 16, -42)
  pastRoundsScroll:SetSize(288, 310)
  NHS.SetupScrollFrameMouseWheel(pastRoundsScroll)

  local pastRoundsScrollChild = CreateFrame("Frame", nil, pastRoundsScroll)
  pastRoundsScrollChild:SetSize(288, 1)
  pastRoundsScroll:SetScrollChild(pastRoundsScrollChild)
  local pastRoundsBody = pastRoundsScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  pastRoundsBody:SetPoint("TOPLEFT", pastRoundsScrollChild, "TOPLEFT", 0, 0)
  pastRoundsBody:SetWidth(278)
  pastRoundsBody:SetJustifyH("LEFT")
  pastRoundsBody:SetJustifyV("TOP")
  pastRoundsBody:SetSpacing(4)
  local pastRoundsBlockTexts = {}
  local pastRoundsDividers = {}
  local pastRoundsCloseBtn = CreateFrame("Button", nil, pastRoundsFrame, "UIPanelCloseButton")
  pastRoundsCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  pastRoundsCloseBtn:SetScript("OnClick", function()
    pastRoundsFrame:Hide()
  end)
  pastRoundsFrame:Hide()

  local function refreshPastRoundsPanel()
    local n = #State.pastRounds
    for _, fs in ipairs(pastRoundsBlockTexts) do
      fs:Hide()
    end
    for _, div in ipairs(pastRoundsDividers) do
      div:Hide()
    end
    if n == 0 then
      pastRoundsBody:Show()
      pastRoundsBody:ClearAllPoints()
      pastRoundsBody:SetPoint("TOPLEFT", pastRoundsScrollChild, "TOPLEFT", 0, 0)
      pastRoundsBody:SetText("No completed rounds in the list yet.")
      pastRoundsScrollChild:SetHeight(math.max(pastRoundsBody:GetStringHeight() + 8, 1))
      pastRoundsScroll:SetVerticalScroll(0)
      return
    end
    pastRoundsBody:Hide()
    local gap = 12
    local ruleW = 278
    local y = 0
    for i = 1, n do
      local r = State.pastRounds[i]
      if i > 1 then
        y = y + gap
        local div = pastRoundsDividers[i - 1]
        if not div then
          div = CreateFrame("Frame", nil, pastRoundsScrollChild)
          div:SetSize(ruleW, 1)
          local tex = div:CreateTexture(nil, "ARTWORK")
          tex:SetAllPoints()
          tex:SetColorTexture(1, 1, 1, 0.12)
          pastRoundsDividers[i - 1] = div
        end
        div:SetParent(pastRoundsScrollChild)
        div:ClearAllPoints()
        div:SetPoint("TOPLEFT", pastRoundsScrollChild, "TOPLEFT", 0, -y)
        div:Show()
        y = y + 1 + gap
      end
      local fs = pastRoundsBlockTexts[i]
      if not fs then
        fs = pastRoundsScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetWidth(278)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetSpacing(4)
        pastRoundsBlockTexts[i] = fs
      end
      fs:SetParent(pastRoundsScrollChild)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", pastRoundsScrollChild, "TOPLEFT", 0, -y)
      local lines = { r.house or "" }
      if r.mode and r.mode ~= "" then
        lines[#lines + 1] = r.mode
      end
      lines[#lines + 1] = r.seeker or ""
      lines[#lines + 1] = r.hidden or ""
      lines[#lines + 1] = r.found or ""
      fs:SetText(table.concat(lines, "\n"))
      fs:Show()
      y = y + fs:GetStringHeight()
    end
    pastRoundsScrollChild:SetHeight(math.max(y + 8, 1))
    pastRoundsScroll:SetVerticalScroll(0)
  end

  return {
    frame = pastRoundsFrame,
    refresh = refreshPastRoundsPanel,
  }
end
