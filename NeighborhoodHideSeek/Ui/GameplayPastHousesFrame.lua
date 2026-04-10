--[[
  "Houses this session" popup. Load after Ui/ScrollUtil.lua; before Ui/MainFrame.lua.
]]

local NHS = NeighborhoodHideSeek

function NHS.CreateGameplayPastHousesFrame()
  local State = NHS.State

  local ghpf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  ghpf:SetSize(300, 260)
  ghpf:SetClampedToScreen(true)
  ghpf:SetMovable(true)
  ghpf:EnableMouse(true)
  ghpf:RegisterForDrag("LeftButton")
  ghpf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  ghpf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    NHS.EnsureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.gameplayPastHousesFramePoint = { p, rp or "UIParent", x, y }
  end)
  ghpf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  ghpf:SetBackdropColor(0, 0, 0, 0.9)
  local ghpfTitle = ghpf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ghpfTitle:SetPoint("TOP", 0, -14)
  ghpfTitle:SetText("Houses this session")
  local ghpastScroll = CreateFrame("ScrollFrame", nil, ghpf)
  ghpastScroll:SetPoint("TOPLEFT", 16, -42)
  ghpastScroll:SetSize(268, 200)
  NHS.SetupScrollFrameMouseWheel(ghpastScroll)

  local ghpastScrollChild = CreateFrame("Frame", nil, ghpastScroll)
  ghpastScrollChild:SetSize(268, 1)
  ghpastScroll:SetScrollChild(ghpastScrollChild)
  local ghpastBody = ghpastScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  ghpastBody:SetPoint("TOPLEFT", ghpastScrollChild, "TOPLEFT", 0, 0)
  ghpastBody:SetWidth(258)
  ghpastBody:SetJustifyH("LEFT")
  ghpastBody:SetJustifyV("TOP")
  local ghpfCloseBtn = CreateFrame("Button", nil, ghpf, "UIPanelCloseButton")
  ghpfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  ghpfCloseBtn:SetScript("OnClick", function()
    ghpf:Hide()
  end)
  ghpf:Hide()

  local function refreshGameplayPastHousesPanel()
    local t = #State.gameHouseHistory == 0 and "No houses chosen this session yet."
      or table.concat(State.gameHouseHistory, "\n")
    ghpastBody:SetText(t)
    ghpastScrollChild:SetHeight(math.max(ghpastBody:GetStringHeight() + 8, 1))
    ghpastScroll:SetVerticalScroll(0)
  end

  return {
    frame = ghpf,
    refresh = refreshGameplayPastHousesPanel,
  }
end
