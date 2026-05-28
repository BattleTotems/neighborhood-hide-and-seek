--[[
  One-time informational popup shown when the player first enters seeker mode.
  Suppressed permanently when "Do not show again" is checked.
]]

local NHS = NeighborhoodHideSeek

local DIALOG_WIDTH  = 340
local DIALOG_HEIGHT = 200

local dialog

local function buildDialog()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(DIALOG_WIDTH, DIALOG_HEIGHT)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

  f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile     = true,
    tileSize = 32,
    edgeSize = 16,
    insets   = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  f:SetBackdropColor(0, 0, 0, 0.9)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -18)
  title:SetText("Seeker Mode Engaged")

  local divider = f:CreateTexture(nil, "ARTWORK")
  divider:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
  divider:SetSize(DIALOG_WIDTH - 24, 4)
  divider:SetPoint("TOP", 0, -38)
  divider:SetAlpha(0.4)

  local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  desc:SetPoint("TOPLEFT", 18, -50)
  desc:SetPoint("TOPRIGHT", -18, -50)
  desc:SetJustifyH("LEFT")
  desc:SetWordWrap(true)
  desc:SetText(
    "You have entered seeker mode. By default this turns off nameplates, names, " ..
    "minimap, and raid frames. This is to make the game as fair as possible." ..
    "\n\n" ..
    "If you have custom raid frames or other UI that did not get hidden, please hide it now."
  )

  local chk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  chk:SetSize(24, 24)
  chk:SetPoint("BOTTOMLEFT", 14, 14)
  chk:SetScript("OnClick", function(self)
    NHS.EnsureSavedVars()
    NHSV.suppressSeekerModeDialog = self:GetChecked()
  end)

  local chkLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  chkLabel:SetPoint("LEFT", chk, "RIGHT", 4, 0)
  chkLabel:SetText("Do not show again")

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -4, -4)
  closeBtn:SetScript("OnClick", function()
    f:Hide()
  end)

  f:Hide()
  return f
end

function NHS.ShowSeekerModeEngagedDialog()
  NHS.EnsureSavedVars()
  if NHSV.suppressSeekerModeDialog then
    return
  end
  if not dialog then
    dialog = buildDialog()
  end
  dialog:Show()
end
