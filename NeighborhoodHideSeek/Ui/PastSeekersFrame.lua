--[[
  "Previous seekers" popup. Load after Ui/ScrollUtil.lua; before Ui/MainFrame.lua.
]]

local NHS = NeighborhoodHideSeek

function NHS.CreatePastSeekersFrame()
  local State = NHS.State

  local psf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  psf:SetSize(300, 280)
  psf:SetClampedToScreen(true)
  psf:SetMovable(true)
  psf:EnableMouse(true)
  psf:RegisterForDrag("LeftButton")
  psf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  psf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    NHS.EnsureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.pastSeekersFramePoint = { p, rp or "UIParent", x, y }
  end)
  psf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  psf:SetBackdropColor(0, 0, 0, 0.88)

  local psfTitle = psf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  psfTitle:SetPoint("TOP", 0, -14)
  psfTitle:SetText("Previous Seekers")

  local psScroll = CreateFrame("ScrollFrame", nil, psf)
  psScroll:SetPoint("TOPLEFT", 16, -42)
  psScroll:SetSize(268, 210)
  NHS.SetupScrollFrameMouseWheel(psScroll)

  local psScrollChild = CreateFrame("Frame", nil, psScroll)
  psScrollChild:SetSize(268, 1)
  psScroll:SetScrollChild(psScrollChild)
  local pastSeekersBody = psScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  pastSeekersBody:SetPoint("TOPLEFT", psScrollChild, "TOPLEFT", 0, 0)
  pastSeekersBody:SetWidth(258)
  pastSeekersBody:SetJustifyH("LEFT")
  pastSeekersBody:SetJustifyV("TOP")

  local psfCloseBtn = CreateFrame("Button", nil, psf, "UIPanelCloseButton")
  psfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  psfCloseBtn:SetScript("OnClick", function()
    psf:Hide()
  end)
  psf:Hide()

  local function refreshPastSeekersPanel()
    local t = #State.gameSeekerHistory == 0 and "No seekers recorded this session yet."
      or table.concat(State.gameSeekerHistory, "\n")
    pastSeekersBody:SetText(t)
    psScrollChild:SetHeight(math.max(pastSeekersBody:GetStringHeight() + 8, 1))
    psScroll:SetVerticalScroll(0)
  end

  return {
    frame = psf,
    refresh = refreshPastSeekersPanel,
  }
end
