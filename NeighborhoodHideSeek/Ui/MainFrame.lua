--[[
  Main window (game rounds strip, house list wiring, random pick). Satellite popups live in Ui/*.lua;
  Core.lua seeds BuildMainFrameBridge; Gameplay/* modules add keys before Ui/MainFrame.lua runs.
]]

function NeighborhoodHideSeek.BuildMainFrame(UI)
  local NHS = NeighborhoodHideSeek
  local State = NHS.State
  local Phase = NHS.Phase
  local IsRoundPhase = NHS.IsRoundPhase
  local B = NHS.BuildMainFrameBridge
  assert(B, "NeighborhoodHideSeek.BuildMainFrameBridge missing (load order).")
  -- Unnamed frame avoids CreateFrame failing if a stale global name already exists.
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(360, 380)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    NHS.EnsureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.framePoint = { p, rp or "UIParent", x, y }
  end)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  f:SetBackdropColor(0, 0, 0, 0.85)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  title:SetText("Neighborhood Hide & Seek")

  local roundsHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  roundsHint:SetWidth(328)
  roundsHint:SetJustifyH("LEFT")
  roundsHint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)

  local sessionToggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sessionToggleBtn:SetSize(218, 24)
  sessionToggleBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -63)

  local gameplayGroupCatchUpBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  gameplayGroupCatchUpBtn:SetSize(90, 24)
  gameplayGroupCatchUpBtn:SetText("Group Sync")
  gameplayGroupCatchUpBtn:SetPoint("LEFT", sessionToggleBtn, "RIGHT", 6, 0)
  gameplayGroupCatchUpBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(
      "Leader: replay the addon lines for your current round so late joiners and desynced clients catch up."
    )
    GameTooltip:Show()
  end)
  gameplayGroupCatchUpBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  gameplayGroupCatchUpBtn:Disable()

  local endRoundBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  endRoundBtn:SetSize(308, 24)
  endRoundBtn:SetText("End Round")
  endRoundBtn:SetPoint("TOPLEFT", sessionToggleBtn, "BOTTOMLEFT", 0, -8)
  endRoundBtn:Hide()

  local gameModeHdr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gameModeHdr:SetPoint("TOPLEFT", endRoundBtn, "BOTTOMLEFT", 0, -12)
  gameModeHdr:SetWidth(328)
  gameModeHdr:SetJustifyH("LEFT")
  gameModeHdr:SetText("Game Mode")
  gameModeHdr:Hide()

  -- local gameModeInfoBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  -- gameModeInfoBtn:SetSize(100, 26)
  -- gameModeInfoBtn:SetText("Info")
  -- gameModeInfoBtn:SetPoint("RIGHT", gameModeHdr, "RIGHT", 0, 0)
  -- gameModeInfoBtn:Hide()

  local gameModeInfoBtn = CreateFrame("Button", nil, f)
  gameModeInfoBtn:SetSize(24, 24)
  gameModeInfoBtn:SetPoint("RIGHT", gameModeHdr, "RIGHT", 0, 0)
  gameModeInfoBtn:SetNormalTexture("Interface\\Common\\help-i")
  gameModeInfoBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  gameModeInfoBtn:Hide()
  gameModeInfoBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Game Mode Info", 1, 1, 1)
    GameTooltip:AddLine("Click to learn about the different game modes.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  gameModeInfoBtn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
  end)

  -- Game Mode Buttons — built dynamically from NHS.GAME_MODE_IDS, 2-column grid.
  local gameModeButtons = {}
  for i, id in ipairs(NHS.GAME_MODE_IDS) do
    local def = NHS.GameModeDefinition(id)
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(150, 22)
    btn:SetText(def.label)
    btn._gameModeId = id
    btn:Hide()
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    if col == 0 then
      if row == 0 then
        btn:SetPoint("TOPLEFT", gameModeHdr, "BOTTOMLEFT", 0, -4)
      else
        btn:SetPoint("TOPLEFT", gameModeButtons[2 * row - 1], "BOTTOMLEFT", 0, -4)
      end
    else
      btn:SetPoint("LEFT", gameModeButtons[i - 1], "RIGHT", 8, 0)
    end
    if def.tooltip and def.tooltip ~= "" then
      btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(def.label, 1, 1, 1)
        GameTooltip:AddLine(def.tooltip, nil, nil, nil, true)
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    end
    gameModeButtons[i] = btn
  end

  local gameModeRandomBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  gameModeRandomBtn:SetSize(150, 22)
  gameModeRandomBtn:SetText("Random")
  gameModeRandomBtn:Hide()
  local _gmn = #NHS.GAME_MODE_IDS
  if _gmn % 2 == 0 then
    gameModeRandomBtn:SetPoint("TOPLEFT", gameModeButtons[_gmn - 1], "BOTTOMLEFT", 0, -4)
  else
    gameModeRandomBtn:SetPoint("LEFT", gameModeButtons[_gmn], "RIGHT", 8, 0)
  end
  gameModeRandomBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Random", 1, 1, 1)
    GameTooltip:AddLine("Picks a game mode at random.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  gameModeRandomBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- House Selection

  local houseSelectHdr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  houseSelectHdr:SetPoint("TOPLEFT", endRoundBtn, "BOTTOMLEFT", 0, -12)
  houseSelectHdr:SetWidth(328)
  houseSelectHdr:SetJustifyH("LEFT")
  houseSelectHdr:SetText("House selection")

  local sessionHouseListHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sessionHouseListHint:SetWidth(328)
  sessionHouseListHint:SetJustifyH("LEFT")
  sessionHouseListHint:SetPoint("TOPLEFT", houseSelectHdr, "BOTTOMLEFT", 0, -4)
  sessionHouseListHint:SetText("Choose the house list for this session (first round only).")
  sessionHouseListHint:Hide()

  local sessionListNeighborhoodBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sessionListNeighborhoodBtn:SetSize(308, 22)
  sessionListNeighborhoodBtn:SetText("Current Neighborhood")
  sessionListNeighborhoodBtn:SetPoint("TOPLEFT", sessionHouseListHint, "BOTTOMLEFT", 0, -6)
  sessionListNeighborhoodBtn:Hide()

  local sessionListSavedBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sessionListSavedBtn:SetSize(308, 22)
  sessionListSavedBtn:SetText("Saved List")
  sessionListSavedBtn:SetPoint("TOPLEFT", sessionListNeighborhoodBtn, "BOTTOMLEFT", 0, -4)
  sessionListSavedBtn:Hide()

  local sessionListGroupBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sessionListGroupBtn:SetSize(308, 22)
  sessionListGroupBtn:SetText("Group Members")
  sessionListGroupBtn:SetPoint("TOPLEFT", sessionListSavedBtn, "BOTTOMLEFT", 0, -4)
  sessionListGroupBtn:Hide()

  local lockedRoundHouseLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lockedRoundHouseLbl:SetPoint("TOPLEFT", houseSelectHdr, "BOTTOMLEFT", 0, -4)
  lockedRoundHouseLbl:SetWidth(328)
  lockedRoundHouseLbl:SetJustifyH("LEFT")
  lockedRoundHouseLbl:SetText("House for this round: —")

  local candidateGameHouseLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  candidateGameHouseLbl:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -4)
  candidateGameHouseLbl:SetWidth(328)
  candidateGameHouseLbl:SetJustifyH("LEFT")
  candidateGameHouseLbl:SetText("House pick (not confirmed): —")

  local randGameHouseBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  randGameHouseBtn:SetSize(150, 22)
  randGameHouseBtn:SetText("Random House")
  randGameHouseBtn:SetPoint("TOPLEFT", candidateGameHouseLbl, "BOTTOMLEFT", 0, -8)

  local viewGameHousePickBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewGameHousePickBtn:SetSize(150, 22)
  viewGameHousePickBtn:SetText("View House List")
  viewGameHousePickBtn:SetPoint("LEFT", randGameHouseBtn, "RIGHT", 8, 0)

  local confirmGameHouseBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  confirmGameHouseBtn:SetSize(308, 22)
  confirmGameHouseBtn:SetText("Confirm House")
  confirmGameHouseBtn:SetPoint("TOPLEFT", randGameHouseBtn, "BOTTOMLEFT", 0, -8)

  local function nhsRestoreGameplayHousePickRowLayout()
    candidateGameHouseLbl:ClearAllPoints()
    candidateGameHouseLbl:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -4)
    randGameHouseBtn:ClearAllPoints()
    randGameHouseBtn:SetPoint("TOPLEFT", candidateGameHouseLbl, "BOTTOMLEFT", 0, -8)
    viewGameHousePickBtn:ClearAllPoints()
    viewGameHousePickBtn:SetPoint("LEFT", randGameHouseBtn, "RIGHT", 8, 0)
    confirmGameHouseBtn:ClearAllPoints()
    confirmGameHouseBtn:SetPoint("TOPLEFT", randGameHouseBtn, "BOTTOMLEFT", 0, -8)
  end

  local function nhsHideSessionHouseListPickUi()
    sessionHouseListHint:Hide()
    sessionListNeighborhoodBtn:Hide()
    sessionListSavedBtn:Hide()
    sessionListGroupBtn:Hide()
    lockedRoundHouseLbl:ClearAllPoints()
    lockedRoundHouseLbl:SetPoint("TOPLEFT", houseSelectHdr, "BOTTOMLEFT", 0, -4)
    nhsRestoreGameplayHousePickRowLayout()
  end

  local seekerSelectHdr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  seekerSelectHdr:SetPoint("TOPLEFT", confirmGameHouseBtn, "BOTTOMLEFT", 0, -12)
  seekerSelectHdr:SetWidth(328)
  seekerSelectHdr:SetJustifyH("LEFT")
  seekerSelectHdr:SetText("Seeker selection")

  local candidateSeekerLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  candidateSeekerLbl:SetPoint("TOPLEFT", seekerSelectHdr, "BOTTOMLEFT", 0, -4)
  candidateSeekerLbl:SetWidth(328)
  candidateSeekerLbl:SetJustifyH("LEFT")
  candidateSeekerLbl:SetText("Current seeker (not locked in): —")

  local randSeekerBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  randSeekerBtn:SetSize(150, 22)
  randSeekerBtn:SetText("Random Seeker")
  randSeekerBtn:SetPoint("TOPLEFT", candidateSeekerLbl, "BOTTOMLEFT", 0, -8)

  local selectSeekerBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  selectSeekerBtn:SetSize(150, 22)
  selectSeekerBtn:SetText("Select Seeker")
  selectSeekerBtn:SetPoint("LEFT", randSeekerBtn, "RIGHT", 8, 0)

  local startRoundBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  startRoundBtn:SetSize(308, 22)
  startRoundBtn:SetText("Confirm Seeker")
  startRoundBtn:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -8)

  local hideRowLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hideRowLbl:SetPoint("TOPLEFT", startRoundBtn, "BOTTOMLEFT", 0, -12)
  hideRowLbl:SetWidth(308)
  hideRowLbl:SetJustifyH("LEFT")
  hideRowLbl:SetText("Hiding")

  local hidePresetBtns = {}
  for i = 1, 4 do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(150, 22)
    b._presetIdx = i
    b._kind = "hide"
    hidePresetBtns[i] = b
  end
  hidePresetBtns[1]:SetPoint("TOPLEFT", hideRowLbl, "BOTTOMLEFT", 0, -6)
  hidePresetBtns[2]:SetPoint("LEFT", hidePresetBtns[1], "RIGHT", 8, 0)
  hidePresetBtns[3]:SetPoint("TOPLEFT", hidePresetBtns[1], "BOTTOMLEFT", 0, -6)
  hidePresetBtns[4]:SetPoint("LEFT", hidePresetBtns[3], "RIGHT", 8, 0)

  local hideCustomSecEdit = CreateFrame("EditBox", nil, f, "BackdropTemplate")
  hideCustomSecEdit:SetSize(150, 22)
  hideCustomSecEdit:SetFontObject("GameFontHighlightSmall")
  hideCustomSecEdit:SetAutoFocus(false)
  hideCustomSecEdit:SetMaxLetters(4)
  hideCustomSecEdit:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBorder",
    tile = true,
    tileSize = 8,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  hideCustomSecEdit:SetBackdropColor(0, 0, 0, 0.35)
  hideCustomSecEdit:SetBackdropBorderColor(0.4, 0.4, 0.45, 0.9)
  hideCustomSecEdit:SetPoint("TOPLEFT", hidePresetBtns[3], "BOTTOMLEFT", 0, -6)
  hideCustomSecEdit:SetText("180")

  local hideCustomCountdownBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  hideCustomCountdownBtn:SetSize(150, 22)
  hideCustomCountdownBtn:SetText("Custom")
  hideCustomCountdownBtn:SetPoint("LEFT", hideCustomSecEdit, "RIGHT", 8, 0)
  hideCustomCountdownBtn._kind = "hide"
  hideCustomCountdownBtn._isCustom = true
  hideCustomCountdownBtn._secEdit = hideCustomSecEdit

  local searchRowLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  searchRowLbl:SetPoint("TOPLEFT", hideCustomSecEdit, "BOTTOMLEFT", 0, -12)
  searchRowLbl:SetWidth(308)
  searchRowLbl:SetJustifyH("LEFT")
  searchRowLbl:SetText("Searching")

  local searchPresetBtns = {}
  for i = 1, 4 do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(150, 22)
    b._presetIdx = i
    b._kind = "search"
    searchPresetBtns[i] = b
  end
  searchPresetBtns[1]:SetPoint("TOPLEFT", searchRowLbl, "BOTTOMLEFT", 0, -6)
  searchPresetBtns[2]:SetPoint("LEFT", searchPresetBtns[1], "RIGHT", 8, 0)
  searchPresetBtns[3]:SetPoint("TOPLEFT", searchPresetBtns[1], "BOTTOMLEFT", 0, -6)
  searchPresetBtns[4]:SetPoint("LEFT", searchPresetBtns[3], "RIGHT", 8, 0)

  local searchCustomSecEdit = CreateFrame("EditBox", nil, f, "BackdropTemplate")
  searchCustomSecEdit:SetSize(150, 22)
  searchCustomSecEdit:SetFontObject("GameFontHighlightSmall")
  searchCustomSecEdit:SetAutoFocus(false)
  searchCustomSecEdit:SetMaxLetters(4)
  searchCustomSecEdit:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBorder",
    tile = true,
    tileSize = 8,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  searchCustomSecEdit:SetBackdropColor(0, 0, 0, 0.35)
  searchCustomSecEdit:SetBackdropBorderColor(0.4, 0.4, 0.45, 0.9)
  searchCustomSecEdit:SetPoint("TOPLEFT", searchPresetBtns[3], "BOTTOMLEFT", 0, -6)
  searchCustomSecEdit:SetText("240")

  local function configureCountdownSecEdit(edit)
    edit:SetNumeric(true)
    edit:SetJustifyH("RIGHT")
    edit:SetTextInsets(10, 8, 0, 0)
    edit:SetScript("OnTextChanged", function(self, userInput)
      if not userInput then
        return
      end
      local t = self:GetText() or ""
      local cleaned = t:gsub("%D", "")
      if cleaned ~= t then
        local pos = self:GetCursorPosition()
        local prefix = string.sub(t, 1, pos)
        local newPos = #(prefix:gsub("%D", ""))
        self:SetText(cleaned)
        self:SetCursorPosition(math.min(newPos, #cleaned))
      end
    end)
  end
  configureCountdownSecEdit(hideCustomSecEdit)
  configureCountdownSecEdit(searchCustomSecEdit)

  local searchCustomCountdownBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  searchCustomCountdownBtn:SetSize(150, 22)
  searchCustomCountdownBtn:SetText("Custom")
  searchCustomCountdownBtn:SetPoint("LEFT", searchCustomSecEdit, "RIGHT", 8, 0)
  searchCustomCountdownBtn._kind = "search"
  searchCustomCountdownBtn._isCustom = true
  searchCustomCountdownBtn._secEdit = searchCustomSecEdit

  local revealRowLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  revealRowLbl:SetPoint("TOPLEFT", searchCustomSecEdit, "BOTTOMLEFT", 0, -12)
  revealRowLbl:SetWidth(308)
  revealRowLbl:SetJustifyH("LEFT")
  revealRowLbl:SetText("Revealing")

  local revealBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  revealBtn:SetSize(308, 22)
  revealBtn:SetText("Begin Revealing")
  revealBtn:SetPoint("TOPLEFT", revealRowLbl, "BOTTOMLEFT", 0, -6)

  local orphanSessionBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  orphanSessionBtn:SetSize(308, 24)
  orphanSessionBtn:SetText("End Game Session")
  orphanSessionBtn:Hide()

  local divControlOptions = f:CreateTexture(nil, "ARTWORK", nil, 1)
  divControlOptions:SetColorTexture(1, 1, 1, 0.12)
  divControlOptions:SetSize(312, 1)
  divControlOptions:SetPoint("TOPLEFT", endRoundBtn, "BOTTOMLEFT", -8, -10)

  -- History section
  local historySectionHdr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  historySectionHdr:SetPoint("TOPLEFT", divControlOptions, "BOTTOMLEFT", 8, -8)
  historySectionHdr:SetWidth(328)
  historySectionHdr:SetJustifyH("LEFT")
  historySectionHdr:SetText("History")

  local pastRoundsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  pastRoundsBtn:SetSize(308, 26)
  pastRoundsBtn:SetText("Previous Rounds")
  pastRoundsBtn:SetPoint("TOPLEFT", historySectionHdr, "BOTTOMLEFT", 0, -6)

  local pastSeekersBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  pastSeekersBtn:SetSize(150, 26)
  pastSeekersBtn:SetText("Previous Seekers")
  pastSeekersBtn:SetPoint("TOPLEFT", pastRoundsBtn, "BOTTOMLEFT", 0, -8)

  local pastHousesBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  pastHousesBtn:SetSize(150, 26)
  pastHousesBtn:SetText("Previous Houses")
  pastHousesBtn:SetPoint("LEFT", pastSeekersBtn, "RIGHT", 8, 0)

  local divHistoryOptions = f:CreateTexture(nil, "ARTWORK", nil, 1)
  divHistoryOptions:SetColorTexture(1, 1, 1, 0.12)
  divHistoryOptions:SetSize(312, 1)
  divHistoryOptions:SetPoint("TOPLEFT", pastSeekersBtn, "BOTTOMLEFT", -8, -10)

  -- Options section header + bottom row: How to play, View house list, Options.
  local optionsSectionHdr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  optionsSectionHdr:SetPoint("TOPLEFT", divHistoryOptions, "BOTTOMLEFT", 8, -8)
  optionsSectionHdr:SetWidth(328)
  optionsSectionHdr:SetJustifyH("LEFT")
  optionsSectionHdr:SetText("Options")

  local howToPlayBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  howToPlayBtn:SetSize(308, 26)
  howToPlayBtn:SetText("How To Play")
  howToPlayBtn:SetPoint("TOPLEFT", optionsSectionHdr, "BOTTOMLEFT", 0, -6)

  local viewHouseListBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewHouseListBtn:SetSize(308, 26)
  viewHouseListBtn:SetText("View House List")
  viewHouseListBtn:SetPoint("TOPLEFT", howToPlayBtn, "BOTTOMLEFT", 0, -8)

  local optionsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  optionsBtn:SetSize(308, 26)
  optionsBtn:SetText("Options")
  optionsBtn:SetPoint("TOPLEFT", viewHouseListBtn, "BOTTOMLEFT", 0, -8)

  local versionLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  versionLabel:SetPoint("TOP", optionsBtn, "BOTTOM", 0, -6)
  versionLabel:SetWidth(328)
  versionLabel:SetJustifyH("CENTER")
  versionLabel:SetText(NHS.ADDON_VERSION_DISPLAY or "Version —")

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -6, -6)

  local optionsMod = NeighborhoodHideSeek.CreateOptionsFrame()
  local optf = optionsMod.frame
  local syncSeekerUiOptionsFromSaved = optionsMod.syncFromSaved
  UI.syncOptionsFromSaved = syncSeekerUiOptionsFromSaved

  local hl = NeighborhoodHideSeek.CreateHouseListFrame(viewHouseListBtn)
  local hf = hl.frame
  local listStatus = hl.listStatus
  local refreshBtn = hl.refreshBtn
  local updateSavedListBtn = hl.updateSavedListBtn
  local pinBtn = hl.pinBtn
  local sharePinBtn = hl.sharePinBtn
  local housingSelText = hl.housingSelText
  local housingSizeText = hl.housingSizeText
  local houseSizePresetBtns = hl.houseSizePresetBtns
  local houseSizeClearBtn = hl.houseSizeClearBtn
  local savedListBtn = hl.savedListBtn
  local scroll = hl.scroll
  local child = hl.child
  local syncViewHouseListButtonLabel = hl.syncViewHouseListButtonLabel
  UI.syncViewHouseListButtonLabel = syncViewHouseListButtonLabel

  local psMod = NHS.CreatePastSeekersFrame()
  local psf = psMod.frame
  local refreshPastSeekersPanel = psMod.refresh

  local howToPlayMod = NHS.CreateHowToPlayFrame()
  local htpf = howToPlayMod.frame

  local gameModeInfoMod = NHS.CreateGameModesInfoFrame()
  local gmif = gameModeInfoMod.frame

  local savedSizesCallbacks = {}
  local shmod = NHS.CreateSavedSizesFrame(savedSizesCallbacks)
  local shf = shmod.frame
  local refreshSavedHousesPanel = shmod.refresh

  local houseButtons = {}
  local housesCache = {}

  local ghPickMod = NHS.CreateGameplayHousePickFrame({
    getHousesCache = function()
      return housesCache
    end,
    onAfterPick = function()
      if UI.RefreshGameRounds then
        UI.RefreshGameRounds()
      end
      B.nhsSessionHudUpdate()
    end,
  })
  local ghfp = ghPickMod.frame
  local refreshGameplayHousePickList = ghPickMod.refresh

  local ghpastMod = NHS.CreateGameplayPastHousesFrame()
  local ghpf = ghpastMod.frame
  local refreshGameplayPastHousesPanel = ghpastMod.refresh

  local pastRoundsMod = NHS.CreatePastRoundsFrame()
  local pastRoundsFrame = pastRoundsMod.frame
  local refreshPastRoundsPanel = pastRoundsMod.refresh

  local randomPickAnim = NHS.CreateRandomPickAnimationFrame()
  local randomPickFrame = randomPickAnim.frame

  local gsPickMod = NHS.CreateGameplaySeekerPickFrame({
    onAfterPick = function()
      if UI.RefreshGameRounds then
        UI.RefreshGameRounds()
      end
      B.nhsSessionHudUpdate()
    end,
  })
  local gsfp = gsPickMod.frame
  local gsfpAnimRandomSeekerBtn = gsPickMod.animRandomSeekerBtn
  local refreshGroupSeekerPickList = gsPickMod.refresh

  howToPlayBtn:SetScript("OnClick", function()
    if NHS.RestoreEmbeddedSettingsFrames then
      NHS.RestoreEmbeddedSettingsFrames()
    end
    htpf:Show()
  end)

  gameModeInfoBtn:SetScript("OnClick", function()
    if NHS.RestoreEmbeddedSettingsFrames then
      NHS.RestoreEmbeddedSettingsFrames()
    end
    gmif:Show()
  end)

  pastRoundsBtn:SetScript("OnClick", function()
    if pastRoundsFrame:IsShown() then
      pastRoundsFrame:Hide()
    else
      refreshPastRoundsPanel()
      pastRoundsFrame:Show()
    end
  end)

  pastSeekersBtn:SetScript("OnClick", function()
    if psf:IsShown() then
      psf:Hide()
    else
      refreshPastSeekersPanel()
      psf:Show()
    end
  end)

  pastHousesBtn:SetScript("OnClick", function()
    if ghpf:IsShown() then
      ghpf:Hide()
    else
      refreshGameplayPastHousesPanel()
      ghpf:Show()
    end
  end)

  closeBtn:SetScript("OnClick", function()
    NHS.HideMainWindowFully(UI)
  end)

  optionsBtn:SetScript("OnClick", function()
    if optf:IsShown() then
      optf:Hide()
    else
      if NHS.RestoreEmbeddedSettingsFrames then
        NHS.RestoreEmbeddedSettingsFrames()
      end
      syncSeekerUiOptionsFromSaved()
      optf:Show()
    end
  end)

  local function updateMainHouseSizeLine()
    local idx = NeighborhoodHideSeek.SavedHouses.GetSavedPresetIndexForEntry(State.selectedEntry)
    if idx then
      local pr = NHS.ROUND_PRESETS[idx]
      housingSizeText:SetText(("Saved size: %s"):format(pr.label))
    else
      housingSizeText:SetText("")
    end
  end

  local function updateHouseListButtonLabels()
    for i, entry in ipairs(housesCache) do
      local btn = houseButtons[i]
      if btn and btn:IsShown() then
        btn:SetText(NeighborhoodHideSeek.LabelFromEntry(entry, i) .. NeighborhoodHideSeek.SavedHouses.SavedSizeSuffixForEntry(entry))
      end
    end
  end

  local function syncHouseSizePickerEnabled()
    local canKey = State.selectedEntry ~= nil
      and NeighborhoodHideSeek.EntryHasOwnerDisplay(State.selectedEntry)
      and NeighborhoodHideSeek.SavedHouses.StableKeyFromEntry(State.selectedEntry) ~= nil
    for _, b in ipairs(houseSizePresetBtns) do
      b:SetEnabled(canKey)
    end
    houseSizeClearBtn:SetEnabled(canKey and NeighborhoodHideSeek.SavedHouses.GetSavedPresetIndexForEntry(State.selectedEntry) ~= nil)
    savedListBtn:SetText(("Saved Sizes… (%d)"):format(NeighborhoodHideSeek.SavedHouses.CountSavedHouseSizes()))
  end

  savedSizesCallbacks.afterRowRemove = function()
    updateHouseListButtonLabels()
    updateMainHouseSizeLine()
    syncHouseSizePickerEnabled()
    if UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    end
  end

  -- Match row spacing in refreshHouseList (y += 24 per button).
  local HOUSE_LIST_ROW_H = 24
  local HOUSE_LIST_SCROLL_MIN = 52
  local HOUSE_LIST_SCROLL_MAX = 280
  local HOUSE_LIST_BOTTOM_PAD = 16

  local function syncHouseListFrameHeight()
    if not hf or not scroll then
      return
    end
    local n = #housesCache
    local listWant = math.max(n, 1) * HOUSE_LIST_ROW_H
    local scrollH = math.min(HOUSE_LIST_SCROLL_MAX, math.max(HOUSE_LIST_SCROLL_MIN, listWant))
    scroll:SetHeight(scrollH)
    local hfTop = hf:GetTop()
    local scrollTop = scroll:GetTop()
    if not hfTop or not scrollTop then
      return
    end
    local chromeAboveScroll = hfTop - scrollTop
    hf:SetHeight(chromeAboveScroll + scrollH + HOUSE_LIST_BOTTOM_PAD)
  end

  local function selectHouse(index)
    local entry = housesCache[index]
    if not entry then
      return
    end
    if not NeighborhoodHideSeek.EntryHasOwnerDisplay(entry) then
      return
    end
    State.selectedEntry = entry
    State.selectedIndex = index
    State.selectedNeighborID = NeighborhoodHideSeek.NeighborIDFromEntry(entry)
    State.selectedLabel = NeighborhoodHideSeek.LabelFromEntry(entry, index)
    housingSelText:SetText(
      State.selectedLabel and ("Selected House: %s"):format(State.selectedLabel)
        or "Selected House: (none)"
    )
    local can = NeighborhoodHideSeek.HousingApi.Available()
    pinBtn:SetEnabled(can)
    sharePinBtn:SetEnabled(can)
    updateMainHouseSizeLine()
    syncHouseSizePickerEnabled()
    updateHouseListButtonLabels()
    if UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    end
    B.nhsSessionHudUpdate()
  end

  local function refreshHouseList()
    -- Once the session house list source is committed the cache is frozen for the
    -- remainder of the session. Entering a house, zoning, or any other refresh
    -- trigger must not overwrite the list the leader chose at selection time.
    if State.gameSessionActive and State.gameSessionHouseListSource ~= nil then
      return
    end
    local list = NeighborhoodHideSeek.HousingApi.FetchVisitableHouses()
    housesCache = list
    NeighborhoodHideSeek.HousingApi.RebuildPlotPinIndexFromRoot()
    for _, b in ipairs(houseButtons) do
      b:Hide()
    end
    local y = 0
    local ownedCount = 0
    for i, entry in ipairs(housesCache) do
      local btn = houseButtons[i]
      if not btn then
        btn = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
        btn:SetSize(268, 22)
        btn:SetScript("OnClick", function()
          selectHouse(btn._idx)
        end)
        btn:SetScript("OnEnter", function(self)
          if self:IsEnabled() then
            return
          end
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText("Empty plot", 1, 1, 1)
          GameTooltip:AddLine(
            "No neighbor in this plot. You cannot select it, save a size, or use it in neighborhood rounds.",
            1,
            0.82,
            0,
            true
          )
          GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)
        houseButtons[i] = btn
      end
      btn._idx = i
      local hasOwner = NeighborhoodHideSeek.EntryHasOwnerDisplay(entry)
      if hasOwner then
        ownedCount = ownedCount + 1
      end
      btn:SetEnabled(hasOwner)
      btn:SetText(NeighborhoodHideSeek.LabelFromEntry(entry, i) .. NeighborhoodHideSeek.SavedHouses.SavedSizeSuffixForEntry(entry))
      btn:SetPoint("TOPLEFT", 10, -y)
      btn:Show()
      y = y + 24
    end
    child:SetHeight(math.max(y, 1))
    scroll:SetVerticalScroll(0)
    if State.selectedEntry and not NeighborhoodHideSeek.EntryHasOwnerDisplay(State.selectedEntry) then
      State.selectedEntry = nil
      State.selectedIndex = nil
      State.selectedNeighborID = nil
      State.selectedLabel = nil
      housingSelText:SetText("Selected House: (none)")
      updateMainHouseSizeLine()
      local canH = NeighborhoodHideSeek.HousingApi.Available()
      pinBtn:SetEnabled(canH and State.selectedEntry ~= nil)
      sharePinBtn:SetEnabled(canH and State.selectedEntry ~= nil)
    end
    listStatus:SetText(("Plots: %d (%d occupied)"):format(#housesCache, ownedCount))
    syncHouseSizePickerEnabled()
    syncHouseListFrameHeight()
  end

  viewHouseListBtn:SetScript("OnClick", function()
    if hf:IsShown() then
      hf:Hide()
    else
      hf:Show()
      refreshHouseList()
    end
    syncViewHouseListButtonLabel()
  end)



  -- Main window height sync
  local function syncMainFrameHeight()
    if not f or not optionsBtn then
      return
    end
    local topEdge = f:GetTop()
    local btnBottom = optionsBtn:GetBottom()
    if not topEdge or not btnBottom then
      return
    end
    local lowest = btnBottom
    if versionLabel then
      local vb = versionLabel:GetBottom()
      if vb then
        lowest = math.min(lowest, vb)
      end
    end
    local pad = 22
    local h = topEdge - lowest + pad 
    f:SetHeight(h)
  end

  local function setControlSectionVisible(show)
    if not show then
      nhsHideSessionHouseListPickUi()
    end
    sessionToggleBtn:SetShown(show)
    gameModeHdr:SetShown(show)
    gameModeInfoBtn:SetShown(show)
    for _, b in ipairs(gameModeButtons) do b:SetShown(show) end
    gameModeRandomBtn:SetShown(show)
    houseSelectHdr:SetShown(show)
    lockedRoundHouseLbl:SetShown(show)
    candidateGameHouseLbl:SetShown(show)
    randGameHouseBtn:SetShown(show)
    viewGameHousePickBtn:SetShown(show)
    confirmGameHouseBtn:SetShown(show)
    seekerSelectHdr:SetShown(show)
    candidateSeekerLbl:SetShown(show)
    randSeekerBtn:SetShown(show)
    selectSeekerBtn:SetShown(show)
    startRoundBtn:SetShown(show)
    hideRowLbl:SetShown(show)
    searchRowLbl:SetShown(show)
    for _, b in ipairs(hidePresetBtns) do
      b:SetShown(show)
    end
    for _, b in ipairs(searchPresetBtns) do
      b:SetShown(show)
    end
    hideCustomSecEdit:SetShown(show)
    hideCustomCountdownBtn:SetShown(show)
    searchCustomSecEdit:SetShown(show)
    searchCustomCountdownBtn:SetShown(show)
    revealRowLbl:SetShown(show)
    revealBtn:SetShown(show)
    endRoundBtn:SetShown(show)
    gameplayGroupCatchUpBtn:SetShown(show)
    divControlOptions:SetShown(show)
  end

  local function nhsCountdownFormatDuration(sec)
    sec = math.floor(tonumber(sec) or 0)
    if sec < 1 then
      return "0 sec"
    end
    if sec < 60 then
      return ("%d sec"):format(sec)
    end
    if sec % 60 == 0 then
      local m = sec / 60
      return m == 1 and "1 min" or ("%d min"):format(m)
    end
    return ("%d min %d s"):format(math.floor(sec / 60), sec % 60)
  end

  local function nhsPresetButtonCaptionWithDuration(label, sec)
    return ("%s (%s)"):format(label, nhsCountdownFormatDuration(sec))
  end

  local function refreshGameRounds()
    local leader = B.nhsIsRoundLeader()
    local ingroup = IsInGroup()
    local useLeaderUi = not ingroup or leader
    local mayAct = B.nhsMayUseLeaderGameActions()
    local sess = State.gameSessionActive
    local pickGameMode = sess and State.phase == Phase.PICK_GAME_MODE
    local pickHouse = sess and State.phase == Phase.PICK_HOUSE
    local pickSeeker = sess and State.phase == Phase.PICK_SEEKER
    local inRound = sess and IsRoundPhase(State.phase)
    local showOrphanEnd = sess and ingroup and not leader

    randomPickAnim.syncPhase(
      sess,
      pickHouse and State.gameSessionHouseListSource ~= nil,
      pickSeeker,
      useLeaderUi
    )

    if not useLeaderUi then
      setControlSectionVisible(false)
      roundsHint:Hide()
      orphanSessionBtn:SetShown(showOrphanEnd)
      historySectionHdr:ClearAllPoints()
      historySectionHdr:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -44)
      syncSeekerUiOptionsFromSaved()
      syncMainFrameHeight()
      if B.nhsSessionHudUpdate then
        B.nhsSessionHudUpdate()
      end
      return
    end

    -- Leader or solo (not in group): show full control strip
    setControlSectionVisible(true)
    roundsHint:Hide()
    sessionToggleBtn:Show()
    orphanSessionBtn:Hide()
    historySectionHdr:ClearAllPoints()
    historySectionHdr:SetPoint("TOPLEFT", divControlOptions, "BOTTOMLEFT", 8, -8)

    sessionToggleBtn:SetText(sess and "End Game Session" or "Start Game Session")
    sessionToggleBtn:SetEnabled(mayAct)
    gameplayGroupCatchUpBtn:SetEnabled(sess and ingroup and mayAct)

    if State.gameHouseCandidateDisplay then
      candidateGameHouseLbl:SetText(
        ("House pick (not confirmed): %s"):format(State.gameHouseCandidateDisplay)
      )
    else
      candidateGameHouseLbl:SetText("House pick (not confirmed): —")
    end
    if State.gameLockedHouseDisplay then
      lockedRoundHouseLbl:SetText(
        ("House for this round: %s"):format(State.gameLockedHouseDisplay)
      )
    else
      lockedRoundHouseLbl:SetText("House for this round: —")
    end

    if not sess then
      nhsHideSessionHouseListPickUi()
      gameModeHdr:Hide()
      gameModeInfoBtn:Hide()
      for _, b in ipairs(gameModeButtons) do b:Hide() end
      gameModeRandomBtn:Hide()
      houseSelectHdr:Hide()
      lockedRoundHouseLbl:Hide()
      candidateGameHouseLbl:Hide()
      randGameHouseBtn:Hide()
      viewGameHousePickBtn:Hide()
      confirmGameHouseBtn:Hide()
      seekerSelectHdr:Hide()
      candidateSeekerLbl:Hide()
      randSeekerBtn:Hide()
      selectSeekerBtn:Hide()
      startRoundBtn:Hide()
    else
      gameModeHdr:SetShown(pickGameMode)
      gameModeInfoBtn:SetShown(pickGameMode)
      for _, b in ipairs(gameModeButtons) do b:SetShown(pickGameMode) end
      gameModeRandomBtn:SetShown(pickGameMode)
      local showHouseSection = pickHouse or pickGameMode or pickSeeker
        or (inRound and State.phase ~= Phase.SEARCHING and State.phase ~= Phase.REVEALING)
      houseSelectHdr:SetShown(showHouseSection)
      local showHousePick = pickHouse
      local needSessionListPick = showHousePick and mayAct and State.gameSessionHouseListSource == nil
      if needSessionListPick then
        sessionHouseListHint:Show()
        sessionListNeighborhoodBtn:Show()
        sessionListSavedBtn:Show()
        sessionListGroupBtn:Show()
        local ownedN = 0
        for _, e in ipairs(housesCache) do
          if NeighborhoodHideSeek.EntryHasOwnerDisplay(e) then
            ownedN = ownedN + 1
          end
        end
        local nab = NeighborhoodHideSeek.HousingApi.Available() and ownedN > 0
        sessionListNeighborhoodBtn:SetEnabled(nab)
        sessionListSavedBtn:SetEnabled(NeighborhoodHideSeek.SavedHouses.CountSavedHouseSizes() > 0)
        sessionListGroupBtn:SetEnabled(#B.nhsGetGroupRoster() > 0)
      else
        nhsHideSessionHouseListPickUi()
      end
      candidateGameHouseLbl:SetShown(showHousePick and not needSessionListPick)
      randGameHouseBtn:SetShown(showHousePick and not needSessionListPick)
      viewGameHousePickBtn:SetShown(showHousePick and not needSessionListPick)
      confirmGameHouseBtn:SetShown(showHousePick and not needSessionListPick)
      lockedRoundHouseLbl:SetShown(pickGameMode or pickSeeker
        or (inRound and State.phase ~= Phase.SEARCHING and State.phase ~= Phase.REVEALING))
      seekerSelectHdr:SetShown(pickSeeker)
      candidateSeekerLbl:SetShown(pickSeeker)
      randSeekerBtn:SetShown(pickSeeker)
      selectSeekerBtn:SetShown(pickSeeker)
      startRoundBtn:SetShown(pickSeeker)
      -- Update role-specific labels for hider mode (chosen_one: seekers=0).
      if NHS.IsHiderMode and NHS.IsHiderMode() then
        seekerSelectHdr:SetText("Hider selection")
        randSeekerBtn:SetText("Random Hider")
        selectSeekerBtn:SetText("Select Hider")
      else
        seekerSelectHdr:SetText("Seeker selection")
        randSeekerBtn:SetText("Random Seeker")
        selectSeekerBtn:SetText("Select Seeker")
      end
    end

    local showRoundTimers = sess and inRound
    local showHidePhaseRow = showRoundTimers and State.phase == Phase.PENDING
    local showSearchPhaseRow = showRoundTimers and State.phase == Phase.HIDING
    local showRevealPhaseRow = showRoundTimers and State.phase == Phase.SEARCHING

    hideRowLbl:SetShown(showHidePhaseRow)
    for _, b in ipairs(hidePresetBtns) do
      b:SetShown(showHidePhaseRow)
    end
    hideCustomSecEdit:SetShown(showHidePhaseRow)
    hideCustomCountdownBtn:SetShown(showHidePhaseRow)

    searchRowLbl:SetShown(showSearchPhaseRow)
    for _, b in ipairs(searchPresetBtns) do
      b:SetShown(showSearchPhaseRow)
    end
    searchCustomSecEdit:SetShown(showSearchPhaseRow)
    searchCustomCountdownBtn:SetShown(showSearchPhaseRow)

    revealRowLbl:SetShown(showRevealPhaseRow)
    revealBtn:SetShown(showRevealPhaseRow)

    -- End Round is always visible in a session; disabled only during game mode selection.
    -- Text changes to "Start Next Round" in Revealing (no other controls shown then).
    endRoundBtn:SetShown(sess)
    endRoundBtn:SetText(sess and State.phase == Phase.REVEALING and "Start Next Round" or "End Round")
    endRoundBtn:SetEnabled(mayAct and sess and State.phase ~= Phase.PICK_HOUSE)

    do
      local required = B.nhsGetRequiredSeekerCount and B.nhsGetRequiredSeekerCount() or 1
      local isHiderMode = NHS.IsHiderMode and NHS.IsHiderMode()
      local picked = #State.gameCandidateKeys
      if picked > 0 then
        local names = {}
        for _, k in ipairs(State.gameCandidateKeys) do
          names[#names + 1] = Ambiguate(k, "short")
        end
        local nameStr = table.concat(names, ", ")
        if required > 1 then
          candidateSeekerLbl:SetText(("Seekers (%d/%d): %s"):format(picked, required, nameStr))
        elseif isHiderMode then
          candidateSeekerLbl:SetText(("Hider (not confirmed): %s"):format(nameStr))
        else
          candidateSeekerLbl:SetText(("Seeker (not confirmed): %s"):format(nameStr))
        end
      else
        if required > 1 then
          candidateSeekerLbl:SetText(("Seekers (0/%d): — (pick %d seekers)"):format(required, required))
        elseif isHiderMode then
          candidateSeekerLbl:SetText("Hider (not confirmed): —")
        else
          candidateSeekerLbl:SetText("Seeker (not confirmed): —")
        end
      end
      if isHiderMode then
        startRoundBtn:SetText("Confirm Hider")
      else
        startRoundBtn:SetText(required > 1 and "Confirm Seekers" or "Confirm Seeker")
      end
    end

    for i, b in ipairs(hidePresetBtns) do
      local pr = NHS.ROUND_PRESETS[i]
      local hideSec = pr.hideSec
      if NHS.GetRoundHideSeconds then
        hideSec = NHS.GetRoundHideSeconds(pr.hideSec)
      end
      b:SetText(nhsPresetButtonCaptionWithDuration(pr.label, hideSec))
    end
    for i, b in ipairs(searchPresetBtns) do
      local pr = NHS.ROUND_PRESETS[i]
      local searchSec = pr.searchSec
      if NHS.GetRoundSearchSeconds then
        searchSec = NHS.GetRoundSearchSeconds(pr.searchSec)
      end
      b:SetText(nhsPresetButtonCaptionWithDuration(pr.label, searchSec))
    end

    if not sess then
      randGameHouseBtn:SetEnabled(false)
      viewGameHousePickBtn:SetEnabled(false)
      confirmGameHouseBtn:SetEnabled(false)
      randSeekerBtn:SetEnabled(false)
      selectSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      revealBtn:SetEnabled(false)

      hideCustomSecEdit:SetEnabled(false)
      hideCustomCountdownBtn:SetEnabled(false)
      searchCustomSecEdit:SetEnabled(false)
      searchCustomCountdownBtn:SetEnabled(false)
    elseif pickGameMode then
      for _, b in ipairs(gameModeButtons) do b:SetEnabled(mayAct) end
      gameModeRandomBtn:SetEnabled(mayAct)
      randGameHouseBtn:SetEnabled(false)
      viewGameHousePickBtn:SetEnabled(false)
      confirmGameHouseBtn:SetEnabled(false)
      randSeekerBtn:SetEnabled(false)
      selectSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      revealBtn:SetEnabled(false)

      hideCustomSecEdit:SetEnabled(false)
      hideCustomCountdownBtn:SetEnabled(false)
      searchCustomSecEdit:SetEnabled(false)
      searchCustomCountdownBtn:SetEnabled(false)
    elseif pickHouse then
      local needSessionListPick = mayAct and State.gameSessionHouseListSource == nil
      randGameHouseBtn:SetEnabled(mayAct and not needSessionListPick)
      viewGameHousePickBtn:SetEnabled(mayAct and not needSessionListPick)
      confirmGameHouseBtn:SetEnabled(mayAct and not needSessionListPick and State.gameHouseCandidateKey ~= nil)
      randSeekerBtn:SetEnabled(false)
      selectSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      revealBtn:SetEnabled(false)

      hideCustomSecEdit:SetEnabled(false)
      hideCustomCountdownBtn:SetEnabled(false)
      searchCustomSecEdit:SetEnabled(false)
      searchCustomCountdownBtn:SetEnabled(false)
    elseif pickSeeker then
      randGameHouseBtn:SetEnabled(false)
      viewGameHousePickBtn:SetEnabled(false)
      confirmGameHouseBtn:SetEnabled(false)
      randSeekerBtn:SetEnabled(mayAct)
      selectSeekerBtn:SetEnabled(mayAct)
      do
        local required = B.nhsGetRequiredSeekerCount and B.nhsGetRequiredSeekerCount() or 1
        startRoundBtn:SetEnabled(
          mayAct and #State.gameCandidateKeys == required and State.gameLockedHouseDisplay ~= nil
        )
      end
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      revealBtn:SetEnabled(false)

      hideCustomSecEdit:SetEnabled(false)
      hideCustomCountdownBtn:SetEnabled(false)
      searchCustomSecEdit:SetEnabled(false)
      searchCustomCountdownBtn:SetEnabled(false)
    elseif inRound then
      randGameHouseBtn:SetEnabled(false)
      viewGameHousePickBtn:SetEnabled(false)
      confirmGameHouseBtn:SetEnabled(false)
      randSeekerBtn:SetEnabled(false)
      selectSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      local hideOn = mayAct and State.phase == Phase.PENDING
      local searchOn = mayAct and State.phase == Phase.HIDING
      local revealOn = mayAct and State.phase == Phase.SEARCHING
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(hideOn)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(searchOn)
      end
      revealBtn:SetEnabled(revealOn)
      hideCustomSecEdit:SetEnabled(hideOn)
      hideCustomCountdownBtn:SetEnabled(hideOn)
      searchCustomSecEdit:SetEnabled(searchOn)
      searchCustomCountdownBtn:SetEnabled(searchOn)
    else
      randGameHouseBtn:SetEnabled(false)
      viewGameHousePickBtn:SetEnabled(false)
      confirmGameHouseBtn:SetEnabled(false)
      randSeekerBtn:SetEnabled(false)
      selectSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      revealBtn:SetEnabled(false)

      hideCustomSecEdit:SetEnabled(false)
      hideCustomCountdownBtn:SetEnabled(false)
      searchCustomSecEdit:SetEnabled(false)
      searchCustomCountdownBtn:SetEnabled(false)
    end

    if sess then
      if pickHouse then
        seekerSelectHdr:ClearAllPoints()
        seekerSelectHdr:SetPoint("TOPLEFT", confirmGameHouseBtn, "BOTTOMLEFT", 0, -12)
      else
        seekerSelectHdr:ClearAllPoints()
        seekerSelectHdr:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -12)
      end
      candidateSeekerLbl:ClearAllPoints()
      candidateSeekerLbl:SetPoint("TOPLEFT", seekerSelectHdr, "BOTTOMLEFT", 0, -4)
      randSeekerBtn:ClearAllPoints()
      randSeekerBtn:SetPoint("TOPLEFT", candidateSeekerLbl, "BOTTOMLEFT", 0, -8)
      selectSeekerBtn:ClearAllPoints()
      selectSeekerBtn:SetPoint("LEFT", randSeekerBtn, "RIGHT", 8, 0)
      startRoundBtn:ClearAllPoints()
      startRoundBtn:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -8)
      if inRound then
        hideRowLbl:ClearAllPoints()
        hideRowLbl:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -12)
        hidePresetBtns[1]:ClearAllPoints()
        hidePresetBtns[1]:SetPoint("TOPLEFT", hideRowLbl, "BOTTOMLEFT", 0, -6)
        hidePresetBtns[2]:ClearAllPoints()
        hidePresetBtns[2]:SetPoint("LEFT", hidePresetBtns[1], "RIGHT", 8, 0)
        hidePresetBtns[3]:ClearAllPoints()
        hidePresetBtns[3]:SetPoint("TOPLEFT", hidePresetBtns[1], "BOTTOMLEFT", 0, -6)
        hidePresetBtns[4]:ClearAllPoints()
        hidePresetBtns[4]:SetPoint("LEFT", hidePresetBtns[3], "RIGHT", 8, 0)
        hideCustomSecEdit:ClearAllPoints()
        hideCustomSecEdit:SetPoint("TOPLEFT", hidePresetBtns[3], "BOTTOMLEFT", 0, -6)
        hideCustomCountdownBtn:ClearAllPoints()
        hideCustomCountdownBtn:SetPoint("LEFT", hideCustomSecEdit, "RIGHT", 8, 0)
        searchRowLbl:ClearAllPoints()
        if showHidePhaseRow then
          searchRowLbl:SetPoint("TOPLEFT", hideCustomSecEdit, "BOTTOMLEFT", 0, -12)
        else
          searchRowLbl:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -12)
        end
        searchPresetBtns[1]:ClearAllPoints()
        searchPresetBtns[1]:SetPoint("TOPLEFT", searchRowLbl, "BOTTOMLEFT", 0, -6)
        searchPresetBtns[2]:ClearAllPoints()
        searchPresetBtns[2]:SetPoint("LEFT", searchPresetBtns[1], "RIGHT", 8, 0)
        searchPresetBtns[3]:ClearAllPoints()
        searchPresetBtns[3]:SetPoint("TOPLEFT", searchPresetBtns[1], "BOTTOMLEFT", 0, -6)
        searchPresetBtns[4]:ClearAllPoints()
        searchPresetBtns[4]:SetPoint("LEFT", searchPresetBtns[3], "RIGHT", 8, 0)
        searchCustomSecEdit:ClearAllPoints()
        searchCustomSecEdit:SetPoint("TOPLEFT", searchPresetBtns[3], "BOTTOMLEFT", 0, -6)
        searchCustomCountdownBtn:ClearAllPoints()
        searchCustomCountdownBtn:SetPoint("LEFT", searchCustomSecEdit, "RIGHT", 8, 0)
        revealRowLbl:ClearAllPoints()
        -- During SEARCHING the house section is hidden; anchor directly below session buttons.
        if showRevealPhaseRow then
          revealRowLbl:SetPoint("TOPLEFT", endRoundBtn, "BOTTOMLEFT", 0, -12)
        else
          revealRowLbl:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -12)
        end
        revealBtn:ClearAllPoints()
        revealBtn:SetPoint("TOPLEFT", revealRowLbl, "BOTTOMLEFT", 0, -6)
      else
        hideRowLbl:ClearAllPoints()
        if pickSeeker then
          hideRowLbl:SetPoint("TOPLEFT", startRoundBtn, "BOTTOMLEFT", 0, -12)
        elseif pickHouse and State.gameSessionHouseListSource == nil then
          hideRowLbl:SetPoint("TOPLEFT", sessionListGroupBtn, "BOTTOMLEFT", 0, -12)
        else
          hideRowLbl:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -12)
        end
      end
    else
      seekerSelectHdr:ClearAllPoints()
      seekerSelectHdr:SetPoint("TOPLEFT", endRoundBtn, "BOTTOMLEFT", 0, -12)
      candidateSeekerLbl:ClearAllPoints()
      candidateSeekerLbl:SetPoint("TOPLEFT", seekerSelectHdr, "BOTTOMLEFT", 0, -4)
      randSeekerBtn:ClearAllPoints()
      randSeekerBtn:SetPoint("TOPLEFT", candidateSeekerLbl, "BOTTOMLEFT", 0, -8)
      startRoundBtn:ClearAllPoints()
      startRoundBtn:SetPoint("LEFT", randSeekerBtn, "RIGHT", 8, 0)
      hideRowLbl:ClearAllPoints()
      hideRowLbl:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -12)
    end

    -- houseSelectHdr always anchors directly below the session button row (endRoundBtn).
    -- During pickGameMode, gameModeHdr is re-anchored below lockedRoundHouseLbl so
    -- the confirmed house info appears above the game mode buttons.
    houseSelectHdr:ClearAllPoints()
    houseSelectHdr:SetPoint("TOPLEFT", endRoundBtn, "BOTTOMLEFT", 0, -12)

    gameModeHdr:ClearAllPoints()
    if pickGameMode then
      gameModeHdr:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -12)
    else
      gameModeHdr:SetPoint("TOPLEFT", endRoundBtn, "BOTTOMLEFT", 0, -12)
    end

    -- Re-anchor divControlOptions below the lowest visible control element.
    do
      local anchor = sessionToggleBtn
      if sess then
        if inRound then
          -- endRoundBtn is now above the controls; anchor to the lowest visible timer control.
          if showRevealPhaseRow then
            anchor = revealBtn
          elseif showSearchPhaseRow then
            anchor = searchCustomSecEdit
          elseif showHidePhaseRow then
            anchor = hideCustomSecEdit
          else -- Revealing: no timer controls, house section hidden; End Round is the only element.
            anchor = endRoundBtn
          end
        elseif pickGameMode then
          anchor = gameModeRandomBtn
        elseif pickSeeker then
          anchor = startRoundBtn
        elseif pickHouse then
          if State.gameSessionHouseListSource == nil then
            anchor = sessionListGroupBtn
          else
            anchor = confirmGameHouseBtn
          end
        else
          anchor = randSeekerBtn
        end
      end
      divControlOptions:ClearAllPoints()
      divControlOptions:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -8, -10)
    end
    selectSeekerBtn:SetEnabled(pickSeeker and mayAct)
    syncSeekerUiOptionsFromSaved()
    local hlIdx = NeighborhoodHideSeek.SavedHouses.GetSavedPresetIndexForEntry(State.selectedEntry)
    if not hlIdx and State.gameLockedHouseKey then
      hlIdx = NeighborhoodHideSeek.SavedHouses.GetSavedPresetIndexForStableKey(State.gameLockedHouseKey)
    end
    if not hlIdx and State.gameLockedHouseLiveEntry then
      hlIdx = NeighborhoodHideSeek.SavedHouses.GetSavedPresetIndexForEntry(State.gameLockedHouseLiveEntry)
    end
    NeighborhoodHideSeek.SavedHouses.PresetButtonsApplySavedHighlightIdx(hidePresetBtns, searchPresetBtns, hlIdx)
    syncMainFrameHeight()
    B.nhsSessionHudUpdate()
  end

  function UI.RefreshGameRounds()
    refreshGameRounds()
  end

  local function nhsTryCommitSessionHouseListSource(source, label)
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_HOUSE then
      return
    end
    if State.gameSessionHouseListSource ~= nil then
      return
    end
    State.gameSessionHouseListSource = source
    print(("|cff88ccff[NHS]|r Session house list: %s."):format(label))
    B.nhsPersistGameSessionToSaved()
    refreshGameRounds()
  end

  sessionListNeighborhoodBtn:SetScript("OnClick", function()
    if not sessionListNeighborhoodBtn:IsEnabled() then
      return
    end
    nhsTryCommitSessionHouseListSource("neighborhood", "neighborhood")
  end)
  sessionListSavedBtn:SetScript("OnClick", function()
    if not sessionListSavedBtn:IsEnabled() then
      return
    end
    nhsTryCommitSessionHouseListSource("saved", "saved list")
  end)
  sessionListGroupBtn:SetScript("OnClick", function()
    if not sessionListGroupBtn:IsEnabled() then
      return
    end
    nhsTryCommitSessionHouseListSource("group", "group members")
  end)

  for _, b in ipairs(houseSizePresetBtns) do
    b:SetScript("OnClick", function(self)
      if not State.selectedEntry then
        return
      end
      local idx = self._housePresetIdx
      if NeighborhoodHideSeek.SavedHouses.SetSavedPresetForEntry(State.selectedEntry, idx, State.selectedLabel, State.selectedIndex) then
        print(
          ("|cff88ccff[NHS]|r Saved size |cffffffff%s|r for this house."):format(NHS.ROUND_PRESETS[idx].label)
        )
      else
        print(
          "|cffff8800[NHS]|r Could not save — this house row has no stable id (GUID / plot / neighbor)."
        )
      end
      updateMainHouseSizeLine()
      updateHouseListButtonLabels()
      syncHouseSizePickerEnabled()
      refreshSavedHousesPanel()
      if UI.RefreshGameRounds then
        UI.RefreshGameRounds()
      end
    end)
  end

  houseSizeClearBtn:SetScript("OnClick", function()
    if NeighborhoodHideSeek.SavedHouses.ClearSavedPresetForEntry(State.selectedEntry) then
      print("|cff88ccff[NHS]|r Cleared saved size for this house.")
    end
    updateMainHouseSizeLine()
    updateHouseListButtonLabels()
    syncHouseSizePickerEnabled()
    refreshSavedHousesPanel()
    if UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    end
  end)

  savedListBtn:SetScript("OnClick", function()
    refreshSavedHousesPanel()
    shf:Show()
  end)

  function UI.RefreshFound()
    if B.nhsSessionHudUpdate then
      B.nhsSessionHudUpdate()
    end
    syncMainFrameHeight()
  end

  function UI.RefreshAll()
    syncSeekerUiOptionsFromSaved()
    refreshBtn:SetEnabled(true)
    refreshHouseList()
    local canHousing = NeighborhoodHideSeek.HousingApi.Available()
    pinBtn:SetEnabled(canHousing and State.selectedEntry ~= nil)
    sharePinBtn:SetEnabled(canHousing and State.selectedEntry ~= nil)
    housingSelText:SetText(
      State.selectedLabel and ("Selected House: %s"):format(State.selectedLabel)
        or "Selected House: (none)"
    )
    updateMainHouseSizeLine()
    refreshGameRounds()
    if B.nhsSessionHudUpdate then
      B.nhsSessionHudUpdate()
    end
  end

  orphanSessionBtn:SetScript("OnClick", function()
    if not (State.gameSessionActive and IsInGroup() and not B.nhsIsRoundLeader()) then
      return
    end
    B.nhsResetGameSession()
    print("|cff88ccff[NHS]|r Game session ended.")
    refreshGameRounds()
  end)

  sessionToggleBtn:SetScript("OnClick", function()
    if State.gameSessionActive then
      if B.nhsIsRoundLeader() and IsInGroup() then
        B.nhsBroadcastLeaderSync(B.NHS_MSG_GAME_OVER)
      end
      B.nhsResetGameSession()
      print("|cff88ccff[NHS]|r Game session ended.")
      refreshGameRounds()
      return
    end
    if IsInGroup() and not B.nhsIsRoundLeader() then
      return
    end
    State.gameSessionActive = true
    State.phase = Phase.PICK_HOUSE
    State.gameMode = nil
    State.gameSessionHouseListSource = nil
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    wipe(State.gameHouseHistory)
    wipe(State.gameHouseRotationUsed)
    wipe(State.gameCandidateKeys)
    wipe(State.gameLockedSeekerKeys)
    wipe(State.gameSeekerHistory)
    wipe(State.gameRotationUsed)
    wipe(State.pastRounds)
    if NHS.ClearCompletedPastRoundsArchive then
      NHS.ClearCompletedPastRoundsArchive()
    end
    refreshHouseList()
    B.nhsPersistGameSessionToSaved()
    if IsInGroup() and B.nhsIsRoundLeader() then
      B.nhsBroadcastLeaderSync(B.NHS_MSG_SESSION_START)
    end
    print(
      "|cff88ccff[NHS]|r Game session started. Choose a house list and confirm a house, then pick a game mode."
    )
    refreshGameRounds()
  end)

  local function nhsLeaderSelectGameMode(modeId)
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_GAME_MODE then
      return
    end
    if not NHS.IsValidGameMode or not NHS.IsValidGameMode(modeId) then
      return
    end
    State.gameMode = modeId
    State.phase = Phase.PICK_SEEKER
    local label = NHS.GameModeHudLabel and NHS.GameModeHudLabel(modeId) or modeId
    if IsInGroup() and B.nhsIsRoundLeader() then
      B.nhsBroadcastLeaderGameMode(modeId)
    end
    print(("|cff88ccff[NHS]|r Game mode: |cffffffff%s|r — pick a seeker."):format(label))
    B.nhsPersistGameSessionToSaved()
    if NHS.SyncHiddenRangePoll then
      NHS.SyncHiddenRangePoll()
    end
    refreshGameRounds()
  end

  -- Game Mode Selection

  for _, b in ipairs(gameModeButtons) do
    b:SetScript("OnClick", function(self)
      nhsLeaderSelectGameMode(self._gameModeId)
    end)
  end

  gameModeRandomBtn:SetScript("OnClick", function()
    local ids = NHS.GAME_MODE_IDS
    nhsLeaderSelectGameMode(ids[math.random(#ids)])
  end)

  gameplayGroupCatchUpBtn:SetScript("OnClick", function()
    if not B.nhsLeaderBroadcastGameplayCatchUpSync then
      print("|cffff8800[NHS]|r Group sync is not ready yet.")
      return
    end
    local ok, err = B.nhsLeaderBroadcastGameplayCatchUpSync()
    if ok then
      print("|cff88ccff[NHS]|r Group catch-up sync sent to party/raid (addon).")
      if UI.RefreshAll then
        UI.RefreshAll()
      end
    else
      print("|cffff8800[NHS]|r " .. tostring(err))
    end
  end)

  local function nhsOpenSeekerAnimatedRandomPick(hideSeekerListFrame)
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_SEEKER then
      return
    end
    local required = B.nhsGetRequiredSeekerCount and B.nhsGetRequiredSeekerCount() or 1
    -- If the list is already full, clear it so the player can start a fresh pick.
    if #State.gameCandidateKeys >= required then
      wipe(State.gameCandidateKeys)
    end
    local elig, err = B.nhsRandomSeekerEligible()
    if not elig then
      print("|cffff8800[NHS]|r " .. tostring(err))
      return
    end
    if hideSeekerListFrame then
      gsfp:Hide()
    end
    local isHiderMode = NHS.IsHiderMode and NHS.IsHiderMode()
    local slotNum = #State.gameCandidateKeys + 1
    local animTitle
    if isHiderMode then
      animTitle = "Random hider (eligible this rotation)"
    elseif required > 1 then
      animTitle = ("Random seeker %d/%d (eligible this rotation)"):format(slotNum, required)
    else
      animTitle = "Random seeker (eligible this rotation)"
    end
    randomPickAnim.openAnimated("seeker", animTitle, elig, function(winIdx)
      local m = elig[winIdx]
      if not m then
        return
      end
      State.gameCandidateKeys[#State.gameCandidateKeys + 1] = m.key
      local names = {}
      for _, k in ipairs(State.gameCandidateKeys) do
        names[#names + 1] = Ambiguate(k, "short")
      end
      local nameStr = table.concat(names, ", ")
      if required > 1 then
        local remaining = required - #State.gameCandidateKeys
        if remaining > 0 then
          print(
            ("|cff88ccff[NHS]|r Seeker %d/%d: |cffffffff%s|r — pick %d more."):format(
              #State.gameCandidateKeys, required, nameStr, remaining
            )
          )
        else
          print(
            ("|cff88ccff[NHS]|r Seekers (%d/%d): |cffffffff%s|r — Confirm seekers to lock in."):format(
              #State.gameCandidateKeys, required, nameStr
            )
          )
        end
      else
        print(
          ("|cff88ccff[NHS]|r %s pick: |cffffffff%s|r — Confirm %s to lock in (or random again)."):format(
            isHiderMode and "Hider" or "Seeker", m.display, isHiderMode and "hider" or "seeker"
          )
        )
      end
      B.nhsPersistGameSessionToSaved()
      refreshGameRounds()
    end)
  end

  gsfpAnimRandomSeekerBtn:SetScript("OnClick", function()
    nhsOpenSeekerAnimatedRandomPick(true)
  end)

  randGameHouseBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_HOUSE then
      return
    end
    local src = State.gameSessionHouseListSource
    if not src then
      return
    end
    if src == "neighborhood" then
      if not NeighborhoodHideSeek.HousingApi.Available() then
        print("|cffff8800[NHS]|r Housing API not ready — open the neighborhood map or pick a different session list.")
        return
      end
      if #housesCache == 0 then
        refreshHouseList()
      end
    end
    local elig, err = NeighborhoodHideSeek.SavedHouses.GameplayRandomHouseEligible(housesCache, src)
    if not elig then
      print("|cffff8800[NHS]|r " .. tostring(err))
      return
    end
    randomPickAnim.openAnimated("house", "Random house (eligible this rotation)", elig, function(winIdx)
      local pick = elig[winIdx]
      if not pick then
        return
      end
      State.gameHouseCandidateKey = pick.rotKey
      State.gameHouseCandidateDisplay = pick.display
      State.gameLockedHouseLiveEntry = pick.liveEntry
      State.gameLockedHouseLiveIndex = pick.liveIndex
      print(
        ("|cff88ccff[NHS]|r Gameplay house: |cffffffff%s|r — Confirm house when ready."):format(pick.display)
      )
      B.nhsPersistGameSessionToSaved()
      refreshGameRounds()
    end)
  end)

  viewGameHousePickBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_HOUSE then
      return
    end
    local src = State.gameSessionHouseListSource
    if not src then
      return
    end
    if src == "neighborhood" then
      if not NeighborhoodHideSeek.HousingApi.Available() then
        print("|cffff8800[NHS]|r Housing API not ready.")
        return
      end
      refreshHouseList()
    end
    refreshGameplayHousePickList()
    ghfp:Show()
  end)

  confirmGameHouseBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_HOUSE then
      return
    end
    if not State.gameHouseCandidateKey then
      return
    end
    State.gameLockedHouseKey = State.gameHouseCandidateKey
    State.gameLockedHouseDisplay = State.gameHouseCandidateDisplay
    State.gameHouseRotationUsed[State.gameLockedHouseKey] = true
    State.gameHouseHistory[#State.gameHouseHistory + 1] = State.gameLockedHouseDisplay
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.phase = Phase.PICK_GAME_MODE
    if IsInGroup() and B.nhsIsRoundLeader() then
      B.nhsBroadcastHouseLocked(State.gameLockedHouseDisplay)
      B.nhsBroadcastGameplayHousePin(
        State.gameLockedHouseLiveEntry,
        State.gameLockedHouseLiveIndex,
        State.gameLockedHouseDisplay,
        State.gameLockedHouseKey
      )
    end
    print(
      ("|cff88ccff[NHS]|r House locked for this round: |cffffffff%s|r — pick a game mode."):format(
        State.gameLockedHouseDisplay
      )
    )
    B.nhsPersistGameSessionToSaved()
    refreshGameRounds()
  end)

  randSeekerBtn:SetScript("OnClick", function()
    nhsOpenSeekerAnimatedRandomPick(false)
  end)

  selectSeekerBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_SEEKER then
      return
    end
    if #B.nhsGetGroupRoster() == 0 then
      print("|cffff8800[NHS]|r No players in group.")
      return
    end
    local required = B.nhsGetRequiredSeekerCount and B.nhsGetRequiredSeekerCount() or 1
    -- If the list is already full, clear it so the player can start a fresh pick.
    if #State.gameCandidateKeys >= required then
      wipe(State.gameCandidateKeys)
      refreshGameRounds()
    end
    refreshGroupSeekerPickList()
    gsfp:Show()
  end)

  startRoundBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_SEEKER then
      return
    end
    local required = B.nhsGetRequiredSeekerCount and B.nhsGetRequiredSeekerCount() or 1
    if #State.gameCandidateKeys ~= required then
      return
    end
    if not State.gameLockedHouseDisplay then
      print("|cffff8800[NHS]|r Confirm a house first (house selection phase).")
      return
    end
    B.clearFound()
    wipe(State.gameLockedSeekerKeys)
    if NHS.IsHiderMode and NHS.IsHiderMode() then
      -- Hider mode (e.g. Chosen One): candidate is the hider; everyone else in the roster becomes a seeker.
      local hiderKey = State.gameCandidateKeys[1]
      State.gameRotationUsed[hiderKey] = true
      local roster = B.nhsGetGroupRoster()
      for _, m in ipairs(roster) do
        if m.key ~= hiderKey then
          State.gameLockedSeekerKeys[#State.gameLockedSeekerKeys + 1] = m.key
        end
      end
      local hiderName = Ambiguate(hiderKey, "short")
      State.gameSeekerHistory[#State.gameSeekerHistory + 1] = "Hider: " .. hiderName
      wipe(State.gameCandidateKeys)
      State.phase = Phase.PENDING
      local keyStr = table.concat(State.gameLockedSeekerKeys, ",")
      B.nhsBroadcastRoundStart(keyStr, "[NHS] Hider Selected: " .. hiderName)
      print(("|cff88ccff[NHS]|r Round started. |cffffffff%s|r is the hider."):format(hiderName))
    else
      -- Normal mode: lock in all candidates as seekers.
      local names = {}
      for _, k in ipairs(State.gameCandidateKeys) do
        State.gameRotationUsed[k] = true
        State.gameLockedSeekerKeys[#State.gameLockedSeekerKeys + 1] = k
        names[#names + 1] = Ambiguate(k, "short")
      end
      State.gameSeekerHistory[#State.gameSeekerHistory + 1] = table.concat(names, ", ")
      wipe(State.gameCandidateKeys)
      State.phase = Phase.PENDING
      local keyStr = table.concat(State.gameLockedSeekerKeys, ",")
      local nameStr = table.concat(names, ", ")
      B.nhsBroadcastRoundStart(keyStr, "[NHS] Seeker(s) Selected: " .. nameStr)
      if #State.gameLockedSeekerKeys > 1 then
        print(("|cff88ccff[NHS]|r Round started. Seekers: |cffffffff%s|r."):format(nameStr))
      else
        print(("|cff88ccff[NHS]|r Round started. |cffffffff%s|r is the seeker."):format(nameStr))
      end
    end
    B.nhsPersistGameSessionToSaved()
    refreshGameRounds()
  end)

  local function nhsLeaderBroadcastRoundPhase(phase)
    if phase == Phase.HIDING then
      State.phase = Phase.HIDING
      B.nhsBroadcastLeaderSync(B.NHS_MSG_HIDING)
      if NHS.PlayHidingPhaseStartSound then
        NHS.PlayHidingPhaseStartSound()
      end
    elseif phase == Phase.SEARCHING then
      wipe(State.hiderReadySet)
      State.phase = Phase.SEARCHING
      local keyParts = {}
      for _, k in ipairs(State.gameLockedSeekerKeys) do
        if type(k) == "string" and k ~= "" then
          keyParts[#keyParts + 1] = k
        end
      end
      if #keyParts > 0 then
        B.nhsBroadcastLeaderSync(B.NHS_MSG_SEEKING .. table.concat(keyParts, ","))
      else
        B.nhsBroadcastLeaderSync("[NHS] The Seeking Begins!")
      end
      B.nhsLeaderTryPromoteSeekerForRaidWarn()
    elseif phase == Phase.REVEALING then
      State.phase = Phase.REVEALING
      do
        -- Build congratulatory chat message: praise surviving hiders, or the seeker(s) if all found.
        local seekerSet = {}
        for _, k in ipairs(State.gameLockedSeekerKeys) do seekerSet[k] = true end
        local hiderNames = {}
        for _, m in ipairs(B.nhsGetGroupRoster()) do
          if not seekerSet[m.key] and not State.foundSet[m.key] then
            hiderNames[#hiderNames + 1] = Ambiguate(m.key, "short")
          end
        end
        table.sort(hiderNames)
        local function nameList(names)
          local n = #names
          if n == 0 then return "" end
          if n == 1 then return names[1] end
          if n == 2 then return names[1] .. " and " .. names[2] end
          local t = {}
          for i = 1, n - 1 do t[i] = names[i] end
          return table.concat(t, ", ") .. ", and " .. names[n]
        end
        local chatMsg
        if #hiderNames > 0 then
          chatMsg = B.NHS_MSG_REVEALING .. " Congratulations to " .. nameList(hiderNames) .. " for staying hidden!"
        else
          local seekerNames = {}
          for _, k in ipairs(State.gameLockedSeekerKeys) do
            seekerNames[#seekerNames + 1] = Ambiguate(k, "short")
          end
          chatMsg = B.NHS_MSG_REVEALING .. " " .. nameList(seekerNames) .. " found everyone!"
        end
        if B.nhsBroadcastRevealingPhase then
          B.nhsBroadcastRevealingPhase(chatMsg)
        else
          B.nhsBroadcastLeaderSync(B.NHS_MSG_REVEALING)
        end
      end
      B.nhsLeaderDemoteSeekerAssistantIfWePromoted()
      if State.seekerMode and B.setSeekerMode then
        B.setSeekerMode(false)
      end
    end
    if NHS.SyncHiddenRangePoll then
      NHS.SyncHiddenRangePoll()
    end
  end

  local function onPresetCountdownClick(self)
    if not B.nhsMayUseLeaderGameActions() or not (State.gameSessionActive and IsRoundPhase(State.phase)) then
      return
    end
    local sec
    local presetName
    if self._isCustom then
      local eb = self._secEdit
      sec = math.floor(tonumber(eb and eb:GetText() or "") or 0)
      if sec < 1 or sec > 7200 then
        print("|cffff8800[NHS]|r Enter seconds between 1 and 7200 (up to 2 hours).")
        return
      end
      presetName = "Custom"
    else
      local idx = self._presetIdx
      local pr = NHS.ROUND_PRESETS[idx]
      if not pr then
        return
      end
      presetName = pr.label
      if self._kind == "hide" then
        sec = pr.hideSec
        if NHS.GetRoundHideSeconds then
          sec = NHS.GetRoundHideSeconds(pr.hideSec)
        end
      else
        sec = pr.searchSec
        if NHS.GetRoundSearchSeconds then
          sec = NHS.GetRoundSearchSeconds(pr.searchSec)
        end
      end
    end
    -- Phase transition happens unconditionally; the Blizzard countdown is cosmetic only.
    -- Some addons (e.g. BigWigs) hook C_PartyInfo.DoCountdown without passing through its
    -- return value, which would otherwise block the phase from advancing.
    local targetPhase = self._kind == "hide" and Phase.HIDING or Phase.SEARCHING
    local phaseLabel  = self._kind == "hide" and "Hiding" or "Searching"
    nhsLeaderBroadcastRoundPhase(targetPhase)
    if self._kind == "search" then
      State.searchPhaseStartTime = GetTime()
      State.searchPhaseDuration = sec
    end
    print(("|cff88ccff[NHS]|r %s — %s (%d s)."):format(phaseLabel, presetName, sec))
    local ok, err = B.nhsStartBuiltInCountdown(sec)
    if not ok then
      if NHS.debugSync then
        print(("|cffffcc00[NHS] debugsync|r Countdown returned: ok=%s err=%s"):format(tostring(ok), tostring(err)))
      end
    end
    if UI.RefreshAll then
      UI.RefreshAll()
    end
    B.nhsSeekerAutoModeSyncToPhase()
    B.nhsPersistGameSessionToSaved()
  end

  for _, b in ipairs(hidePresetBtns) do
    b:SetScript("OnClick", onPresetCountdownClick)
  end
  for _, b in ipairs(searchPresetBtns) do
    b:SetScript("OnClick", onPresetCountdownClick)
  end
  hideCustomCountdownBtn:SetScript("OnClick", onPresetCountdownClick)
  searchCustomCountdownBtn:SetScript("OnClick", onPresetCountdownClick)

  revealBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or not (State.gameSessionActive and IsRoundPhase(State.phase)) then
      return
    end
    if State.phase ~= Phase.SEARCHING then
      return
    end
    B.nhsStopPartyCountdown()
    nhsLeaderBroadcastRoundPhase(Phase.REVEALING)
    print("|cff88ccff[NHS]|r Revealing phase started — hiders, show yourselves!")
    if UI.RefreshAll then
      UI.RefreshAll()
    end
    B.nhsPersistGameSessionToSaved()
  end)

  local function nhsDoEndRound()
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive
      or State.phase == Phase.PICK_HOUSE then
      return
    end
    B.nhsAppendPastRoundSnapshotIfActiveRound()
    B.nhsLeaderDemoteSeekerAssistantIfWePromoted()
    if NHS.ClearRoundGameMode then
      NHS.ClearRoundGameMode()
    else
      State.gameMode = nil
    end
    State.phase = Phase.PICK_HOUSE
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    wipe(State.gameLockedSeekerKeys)
    wipe(State.gameCandidateKeys)
    B.clearFound()
    B.nhsStopPartyCountdown()
    B.nhsBroadcastLeaderSync(B.NHS_MSG_ROUND_OVER)
    print("|cff88ccff[NHS]|r Round ended. Pick the next house, then a game mode and seeker.")
    B.nhsPersistGameSessionToSaved()
    if State.seekerMode then
      B.setSeekerMode(false)
    end
    refreshGameRounds()
  end

  endRoundBtn:SetScript("OnClick", nhsDoEndRound)

  refreshBtn:SetScript("OnClick", function()
    refreshHouseList()
  end)

  updateSavedListBtn:SetScript("OnClick", function()
    local S = NHS.SavedHouses
    -- Collect matches before modifying NHSV (SetSavedPresetForEntry mutates the table).
    -- Require both stable key (plot ID / GUID) AND label (plot number + character name) to
    -- match so that a different occupant at the same plot ID in another neighborhood is never
    -- treated as the same house.
    local matches = {}
    for i, entry in ipairs(housesCache) do
      local stable = S.StableKeyFromEntry(entry)
      if stable then
        local liveLabel = NHS.LabelFromEntry(entry, i)
        for savedKey in pairs(NHSV.houseSizes) do
          if S.BaseStableKeyFromPersistenceKey(savedKey) == stable then
            local savedLabel = NHSV.houseLabels[savedKey]
            if type(savedLabel) == "string" and savedLabel == liveLabel then
              matches[#matches + 1] = {
                entry = entry,
                index = i,
                savedKey = savedKey,
              }
              break
            end
          end
        end
      end
    end
    local updated = 0
    for _, m in ipairs(matches) do
      if S.MigrateSavedEntryToCurrentContext(m.savedKey, m.entry, m.index) then
        updated = updated + 1
      end
    end
    if updated > 0 then
      print(("|cff88ff88[NHS]|r Updated %d saved house(s) with current neighborhood data."):format(updated))
      updateHouseListButtonLabels()
      refreshSavedHousesPanel()
      if UI.RefreshGameRounds then
        UI.RefreshGameRounds()
      end
    else
      print("|cffff8800[NHS]|r No saved houses matched the current neighborhood.")
    end
  end)

  pinBtn:SetScript("OnClick", function()
    if NeighborhoodHideSeek.HousingApi.TryWaypointForEntry(State.selectedEntry, State.selectedIndex) then
      print("|cff88ff88[NHS]|r Map pin set.")
    else
      local n = 0
      for _ in pairs(NeighborhoodHideSeek.HousingRegistry.plotPinIndex) do
        n = n + 1
      end
      if n == 0 then
        print(
          "|cffff8800[NHS]|r No coordinates on this row and no plot index from map data — open the Housing map, Refresh, or /dump C_HousingNeighborhood.GetNeighborhoodMapData()."
        )
      else
        print(
          ("|cffff8800[NHS]|r No pin for this plot (%d plot positions in map cache). Try Refresh after opening the neighborhood map."):format(
            n
          )
        )
      end
    end
  end)

  sharePinBtn:SetScript("OnClick", function()
    local ok, info = NeighborhoodHideSeek.HousingPinShare.ShareSelectedPinInChat(
      State.selectedEntry,
      State.selectedIndex,
      State.selectedLabel
    )
    if ok then
      print(("|cff88ff88[NHS]|r Pin shared to %s."):format(tostring(info)))
    else
      print("|cffff8800[NHS]|r " .. tostring(info))
    end
  end)

  -- Without at least one SetPoint, the frame often never draws on screen.
  NHS.EnsureSavedVars()
  f:ClearAllPoints()
  if NHSV.framePoint then
    local p = NHSV.framePoint
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  f:SetFrameStrata("DIALOG")
  f:SetFrameLevel(200)
  f:SetToplevel(true)
  f:Hide()

  hf:ClearAllPoints()
  if NHSV.houseListFramePoint then
    local hp = NHSV.houseListFramePoint
    hf:SetPoint(hp[1], UIParent, hp[2], hp[3], hp[4])
  else
    hf:SetPoint("TOPLEFT", f, "TOPRIGHT", 16, 0)
  end
  hf:SetFrameStrata("DIALOG")
  hf:SetFrameLevel(205)
  hf:SetToplevel(true)
  hf:Hide()

  optf:ClearAllPoints()
  if NHSV.optionsFramePoint then
    local op = NHSV.optionsFramePoint
    optf:SetPoint(op[1], UIParent, op[2], op[3], op[4])
  else
    optf:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -12)
  end
  optf:SetFrameStrata("DIALOG")
  optf:SetFrameLevel(204)
  optf:SetToplevel(true)
  optf:Hide()

  psf:ClearAllPoints()
  if NHSV.pastSeekersFramePoint then
    local pp = NHSV.pastSeekersFramePoint
    psf:SetPoint(pp[1], UIParent, pp[2], pp[3], pp[4])
  else
    psf:SetPoint("LEFT", f, "RIGHT", 16, 0)
  end
  psf:SetFrameStrata("DIALOG")
  psf:SetFrameLevel(206)
  psf:SetToplevel(true)

  htpf:ClearAllPoints()
  if NHSV.howToPlayFramePoint then
    local hp = NHSV.howToPlayFramePoint
    htpf:SetPoint(hp[1], UIParent, hp[2], hp[3], hp[4])
  else
    htpf:SetPoint("TOP", f, "TOP", 0, -24)
  end
  htpf:SetFrameStrata("DIALOG")
  htpf:SetFrameLevel(207)
  htpf:SetToplevel(true)

  gmif:ClearAllPoints()
  if NHSV.gameModesInfoFramePoint then
    local hp = NHSV.gameModesInfoFramePoint
    gmif:SetPoint(hp[1], UIParent, hp[2], hp[3], hp[4])
  else
    gmif:SetPoint("TOP", f, "TOP", 0, -24)
  end
  gmif:SetFrameStrata("DIALOG")
  gmif:SetFrameLevel(207)
  gmif:SetToplevel(true)


  shf:ClearAllPoints()
  if NHSV.savedSizesFramePoint then
    local sp = NHSV.savedSizesFramePoint
    shf:SetPoint(sp[1], UIParent, sp[2], sp[3], sp[4])
  else
    shf:SetPoint("TOPLEFT", hf, "TOPRIGHT", 12, 0)
  end
  shf:SetFrameStrata("DIALOG")
  shf:SetFrameLevel(208)
  shf:SetToplevel(true)

  ghfp:ClearAllPoints()
  if NHSV.gameplayHousePickFramePoint then
    local gp = NHSV.gameplayHousePickFramePoint
    ghfp:SetPoint(gp[1], UIParent, gp[2], gp[3], gp[4])
  else
    ghfp:SetPoint("TOPLEFT", f, "TOPRIGHT", 16, 0)
  end
  ghfp:SetFrameStrata("DIALOG")
  ghfp:SetFrameLevel(206)
  ghfp:SetToplevel(true)

  ghpf:ClearAllPoints()
  if NHSV.gameplayPastHousesFramePoint then
    local pp = NHSV.gameplayPastHousesFramePoint
    ghpf:SetPoint(pp[1], UIParent, pp[2], pp[3], pp[4])
  else
    ghpf:SetPoint("LEFT", f, "RIGHT", 16, 0)
  end
  ghpf:SetFrameStrata("DIALOG")
  ghpf:SetFrameLevel(206)
  ghpf:SetToplevel(true)

  pastRoundsFrame:ClearAllPoints()
  if NHSV.pastRoundsFramePoint then
    local pp = NHSV.pastRoundsFramePoint
    pastRoundsFrame:SetPoint(pp[1], UIParent, pp[2], pp[3], pp[4])
  else
    pastRoundsFrame:SetPoint("LEFT", f, "RIGHT", 16, -24)
  end
  pastRoundsFrame:SetFrameStrata("DIALOG")
  pastRoundsFrame:SetFrameLevel(206)
  pastRoundsFrame:SetToplevel(true)

  gsfp:ClearAllPoints()
  if NHSV.gameplaySeekerPickFramePoint then
    local sp = NHSV.gameplaySeekerPickFramePoint
    gsfp:SetPoint(sp[1], UIParent, sp[2], sp[3], sp[4])
  else
    gsfp:SetPoint("TOPLEFT", f, "TOPRIGHT", 16, -40)
  end
  gsfp:SetFrameStrata("DIALOG")
  gsfp:SetFrameLevel(206)
  gsfp:SetToplevel(true)

  randomPickFrame:ClearAllPoints()
  if NHSV.randomPickFramePoint then
    local rp = NHSV.randomPickFramePoint
    randomPickFrame:SetPoint(rp[1], UIParent, rp[2], rp[3], rp[4])
  else
    randomPickFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  randomPickFrame:SetFrameStrata("DIALOG")
  randomPickFrame:SetFrameLevel(210)
  randomPickFrame:SetToplevel(true)

  UI.optionsFrame = optf
  UI.houseListFrame = hf
  UI.pastSeekersFrame = psf
  UI.gameplayHousePickFrame = ghfp
  UI.gameplayPastHousesFrame = ghpf
  UI.gameplayPastRoundsFrame = pastRoundsFrame
  UI.gameplaySeekerPickFrame = gsfp
  UI.gameplayRandomPickFrame = randomPickFrame
  UI.howToPlayFrame = htpf
  UI.gameModesInfoFrame = gmif
  UI.savedSizesFrame = shf
  UI.viewHouseListBtn = viewHouseListBtn
  UI.frame = f
  syncHouseSizePickerEnabled()
  syncHouseListFrameHeight()
  B.nhsSessionHudUpdate()

  if NHS.RegisterEscapeProxyFrameHooks then
    NHS.RegisterEscapeProxyFrameHooks(UI)
  end
end