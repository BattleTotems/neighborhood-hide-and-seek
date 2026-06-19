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
  optf:SetSize(340, 540)
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

  local cbRandPickAnim = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbRandPickAnim:SetSize(22, 22)
  cbRandPickAnim:SetPoint("TOPLEFT", optGameplayHeader, "BOTTOMLEFT", -4, -8)
  local cbRandPickAnimText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbRandPickAnimText:SetPoint("LEFT", cbRandPickAnim, "RIGHT", 4, 0)
  cbRandPickAnimText:SetWidth(292)
  cbRandPickAnimText:SetJustifyH("LEFT")
  cbRandPickAnimText:SetText("Use selection animation")

  local cbGameplaySounds = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbGameplaySounds:SetSize(22, 22)
  cbGameplaySounds:SetPoint("TOPLEFT", cbRandPickAnimText, "BOTTOMLEFT", -26, -6)
  local cbGameplaySoundsText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbGameplaySoundsText:SetPoint("LEFT", cbGameplaySounds, "RIGHT", 4, 0)
  cbGameplaySoundsText:SetWidth(292)
  cbGameplaySoundsText:SetJustifyH("LEFT")
  cbGameplaySoundsText:SetText("Gameplay sounds")

  local cbMinimapLauncher = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbMinimapLauncher:SetSize(22, 22)
  cbMinimapLauncher:SetPoint("TOPLEFT", cbGameplaySoundsText, "BOTTOMLEFT", -26, -6)
  local cbMinimapLauncherText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbMinimapLauncherText:SetPoint("LEFT", cbMinimapLauncher, "RIGHT", 4, 0)
  cbMinimapLauncherText:SetWidth(292)
  cbMinimapLauncherText:SetJustifyH("LEFT")
  cbMinimapLauncherText:SetText("Show minimap launcher button")

  local gameModeDefaultsBtn = CreateFrame("Button", nil, optf, "UIPanelButtonTemplate")
  gameModeDefaultsBtn:SetSize(300, 26)
  gameModeDefaultsBtn:SetPoint("TOPLEFT", cbMinimapLauncher, "BOTTOMLEFT", -4, -10)
  gameModeDefaultsBtn:SetText("Game Mode Defaults...")

  local gameModeDefaultsHint = optf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  gameModeDefaultsHint:SetPoint("TOPLEFT", gameModeDefaultsBtn, "BOTTOMLEFT", 4, -4)
  gameModeDefaultsHint:SetWidth(296)
  gameModeDefaultsHint:SetJustifyH("LEFT")
  gameModeDefaultsHint:SetText("Configure which modes are included in Random by default.")

  local optMidSep = optf:CreateTexture(nil, "ARTWORK", nil, 1)
  optMidSep:SetColorTexture(1, 1, 1, 0.12)
  optMidSep:SetSize(300, 1)
  optMidSep:SetPoint("TOPLEFT", gameModeDefaultsHint, "BOTTOMLEFT", 0, -10)

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
  optSeekerModeBtn:SetText("Enter Seeker Mode")

  local optSeekerHint = optf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  optSeekerHint:SetPoint("TOPLEFT", optSeekerModeBtn, "BOTTOMLEFT", 0, -10)
  optSeekerHint:SetWidth(300)
  optSeekerHint:SetJustifyH("LEFT")
  optSeekerHint:SetText(
    "Seeker mode is usually enabled automatically during hiding/searching when you are the seeker. Use the button above if you need it manually to view the changes made in the options."
  )

  local function syncSeekerModeOptionButton()
    local st = NHS.State
    optSeekerModeBtn:SetText(st.seekerMode and "Leave Seeker Mode" or "Enter Seeker Mode")
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
    cbRandPickAnim:SetChecked(NHSV.useRandomPickAnimation ~= false)
    cbGameplaySounds:SetChecked(NHSV.gameplaySoundsEnabled ~= false)
    cbMinimapLauncher:SetChecked(NHSV.showMinimapButton ~= false)
    syncSeekerModeOptionButton()
  end

  local function applySeekerUiOptionChange()
    ensureSaved()
    NHSV.hideGroupFramesInSeeker = cbParty:GetChecked() and true or false
    NHSV.hideMinimapInSeeker = cbMini:GetChecked() and true or false
    NHSV.useRandomPickAnimation = cbRandPickAnim:GetChecked() and true or false
    NHSV.gameplaySoundsEnabled = cbGameplaySounds:GetChecked() and true or false
    NHSV.showMinimapButton = cbMinimapLauncher:GetChecked() and true or false
    if NHS.InitMinimapButton then
      NHS.InitMinimapButton()
    end
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
  cbRandPickAnim:SetScript("OnClick", applySeekerUiOptionChange)
  cbGameplaySounds:SetScript("OnClick", applySeekerUiOptionChange)
  cbMinimapLauncher:SetScript("OnClick", applySeekerUiOptionChange)

  local optSeekerSep2 = optf:CreateTexture(nil, "ARTWORK", nil, 1)
  optSeekerSep2:SetColorTexture(1, 1, 1, 0.12)
  optSeekerSep2:SetSize(300, 1)
  optSeekerSep2:SetPoint("TOPLEFT", optSeekerHint, "BOTTOMLEFT", 0, -14)

  local optResetDialogBtn = CreateFrame("Button", nil, optf, "UIPanelButtonTemplate")
  optResetDialogBtn:SetSize(300, 26)
  optResetDialogBtn:SetPoint("TOPLEFT", optSeekerSep2, "BOTTOMLEFT", 0, -8)
  optResetDialogBtn:SetText("Reset Seeker Mode Dialog")
  optResetDialogBtn:SetScript("OnClick", function()
    ensureSaved()
    NHSV.suppressSeekerModeDialog = false
  end)

  local optVersionSep = optf:CreateTexture(nil, "ARTWORK", nil, 1)
  optVersionSep:SetColorTexture(1, 1, 1, 0.12)
  optVersionSep:SetSize(300, 1)
  optVersionSep:SetPoint("TOPLEFT", optResetDialogBtn, "BOTTOMLEFT", 0, -10)

  local optVersionCheckBtn = CreateFrame("Button", nil, optf, "UIPanelButtonTemplate")
  optVersionCheckBtn:SetSize(300, 26)
  optVersionCheckBtn:SetPoint("TOPLEFT", optVersionSep, "BOTTOMLEFT", 0, -8)
  optVersionCheckBtn:SetText("Check Group Versions")
  optVersionCheckBtn:SetScript("OnClick", function()
    if NHS.VersionCheck and NHS.VersionCheck.TriggerCheck then
      NHS.VersionCheck.TriggerCheck()
    end
  end)

  local optVersionCheckHint = optf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  optVersionCheckHint:SetPoint("TOPLEFT", optVersionCheckBtn, "BOTTOMLEFT", 4, -4)
  optVersionCheckHint:SetWidth(296)
  optVersionCheckHint:SetJustifyH("LEFT")
  optVersionCheckHint:SetText("Check that all party members have the same addon version.")

  local optCloseBtn = CreateFrame("Button", nil, optf, "UIPanelCloseButton")
  optCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  optCloseBtn:SetScript("OnClick", function()
    optf:Hide()
  end)
  optf._nhsCloseButton = optCloseBtn

  return {
    frame = optf,
    syncFromSaved = syncSeekerUiOptionsFromSaved,
    gameModeDefaultsBtn = gameModeDefaultsBtn,
  }
end
