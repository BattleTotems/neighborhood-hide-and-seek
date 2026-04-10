--[[
  Options window (seeker UI toggles, gameplay prefs, seeker mode button).
  Loaded after Core.lua; see NeighborhoodHideSeek.toc (Ui/Options.lua).
]]

function NeighborhoodHideSeek.CreateOptionsFrame()
  local NHS = NeighborhoodHideSeek

  local function ensureSaved()
    if NHS.EnsureSavedVars then
      NHS.EnsureSavedVars()
    end
  end

  local optf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  optf:SetSize(340, 338)
  optf:SetClampedToScreen(true)
  optf:SetMovable(true)
  optf:EnableMouse(true)
  optf:RegisterForDrag("LeftButton")
  optf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  optf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSaved()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.optionsFramePoint = { p, rp or "UIParent", x, y }
  end)
  optf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  optf:SetBackdropColor(0, 0, 0, 0.88)

  local optTitle = optf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  optTitle:SetPoint("TOP", 0, -14)
  optTitle:SetText("Options")

  local optGameplayHeader = optf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  optGameplayHeader:SetPoint("TOPLEFT", 20, -42)
  optGameplayHeader:SetWidth(300)
  optGameplayHeader:SetJustifyH("LEFT")
  optGameplayHeader:SetText("Gameplay Options:")

  local cbHouseSaved = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbHouseSaved:SetSize(22, 22)
  cbHouseSaved:SetPoint("TOPLEFT", optGameplayHeader, "BOTTOMLEFT", -4, -8)
  local cbHouseSavedText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbHouseSavedText:SetPoint("LEFT", cbHouseSaved, "RIGHT", 4, 0)
  cbHouseSavedText:SetWidth(292)
  cbHouseSavedText:SetJustifyH("LEFT")
  cbHouseSavedText:SetText("Use saved house list (off = current neighborhood list)")

  local cbRandPickAnim = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbRandPickAnim:SetSize(22, 22)
  cbRandPickAnim:SetPoint("TOPLEFT", cbHouseSavedText, "BOTTOMLEFT", -26, -6)
  local cbRandPickAnimText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbRandPickAnimText:SetPoint("LEFT", cbRandPickAnim, "RIGHT", 4, 0)
  cbRandPickAnimText:SetWidth(292)
  cbRandPickAnimText:SetJustifyH("LEFT")
  cbRandPickAnimText:SetText("Use selection animation")

  local optMidSep = optf:CreateTexture(nil, "ARTWORK", nil, 1)
  optMidSep:SetColorTexture(1, 1, 1, 0.12)
  optMidSep:SetSize(300, 1)
  optMidSep:SetPoint("TOPLEFT", cbRandPickAnimText, "BOTTOMLEFT", -26, -12)

  local optSeekerHeader = optf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  optSeekerHeader:SetPoint("TOPLEFT", optMidSep, "BOTTOMLEFT", 0, -10)
  optSeekerHeader:SetWidth(300)
  optSeekerHeader:SetJustifyH("LEFT")
  optSeekerHeader:SetText("Seeker Mode Options:")

  local cbParty = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbParty:SetSize(22, 22)
  cbParty:SetPoint("TOPLEFT", optSeekerHeader, "BOTTOMLEFT", -4, -8)
  local cbPartyText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbPartyText:SetPoint("LEFT", cbParty, "RIGHT", 4, 0)
  cbPartyText:SetText("Hide party / raid frames")

  local cbMini = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbMini:SetSize(22, 22)
  cbMini:SetPoint("TOPLEFT", cbParty, "BOTTOMLEFT", 0, -6)
  local cbMiniText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbMiniText:SetPoint("LEFT", cbMini, "RIGHT", 4, 0)
  cbMiniText:SetText("Hide minimap (entire cluster)")

  local optSeekerModeBtn = CreateFrame("Button", nil, optf, "UIPanelButtonTemplate")
  optSeekerModeBtn:SetSize(300, 26)
  optSeekerModeBtn:SetPoint("TOPLEFT", cbMini, "BOTTOMLEFT", -4, -12)
  optSeekerModeBtn:SetText("Enter seeker mode")

  local optSeekerHint = optf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  optSeekerHint:SetPoint("TOPLEFT", optSeekerModeBtn, "BOTTOMLEFT", 0, -10)
  optSeekerHint:SetWidth(300)
  optSeekerHint:SetJustifyH("LEFT")
  optSeekerHint:SetText(
    "Seeker mode is usually enabled automatically during hiding/searching when you are the seeker. Use the button above if you need it manually to view the changes made in the options."
  )

  local function syncSeekerModeOptionButton()
    local st = NHS.State
    optSeekerModeBtn:SetText(st.seekerMode and "Leave seeker mode" or "Enter seeker mode")
    if st.seekerMode then
      optSeekerModeBtn:SetEnabled(true)
    else
      optSeekerModeBtn:SetEnabled(NHS.MayEnterSeekerMode())
    end
  end

  optSeekerModeBtn:SetScript("OnClick", function()
    local st = NHS.State
    NHS.SetSeekerMode(not st.seekerMode)
  end)

  local function syncSeekerUiOptionsFromSaved()
    ensureSaved()
    cbParty:SetChecked(NHSV.hideGroupFramesInSeeker ~= false)
    cbMini:SetChecked(NHSV.hideMinimapInSeeker == true)
    cbHouseSaved:SetChecked(NHSV.selectHouseFromSavedList ~= false)
    cbRandPickAnim:SetChecked(NHSV.useRandomPickAnimation ~= false)
    syncSeekerModeOptionButton()
  end

  local function applySeekerUiOptionChange()
    ensureSaved()
    NHSV.hideGroupFramesInSeeker = cbParty:GetChecked() and true or false
    NHSV.hideMinimapInSeeker = cbMini:GetChecked() and true or false
    NHSV.selectHouseFromSavedList = cbHouseSaved:GetChecked() and true or false
    NHSV.useRandomPickAnimation = cbRandPickAnim:GetChecked() and true or false
    if NHS.State.seekerMode then
      if NHSV.hideGroupFramesInSeeker or NHSV.hideMinimapInSeeker then
        NHS.SeekerUiPoll:Show()
      else
        NHS.SeekerUiSuppressStop()
      end
    end
  end

  cbParty:SetScript("OnClick", applySeekerUiOptionChange)
  cbMini:SetScript("OnClick", applySeekerUiOptionChange)
  cbHouseSaved:SetScript("OnClick", applySeekerUiOptionChange)
  cbRandPickAnim:SetScript("OnClick", applySeekerUiOptionChange)

  local optCloseBtn = CreateFrame("Button", nil, optf, "UIPanelCloseButton")
  optCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  optCloseBtn:SetScript("OnClick", function()
    optf:Hide()
  end)

  return {
    frame = optf,
    syncFromSaved = syncSeekerUiOptionsFromSaved,
  }
end
