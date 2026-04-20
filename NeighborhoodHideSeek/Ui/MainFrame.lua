--[[
  Main window (game rounds strip, house list wiring, random pick). Satellite popups live in Ui/*.lua;
  Core.lua seeds BuildMainFrameBridge; Gameplay/* modules add keys before Ui/MainFrame.lua runs.
]]

function NeighborhoodHideSeek.BuildMainFrame(UI)
  local NHS = NeighborhoodHideSeek
  local State = NHS.State
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
  gameplayGroupCatchUpBtn:Hide()

  local houseSelectHdr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  houseSelectHdr:SetPoint("TOPLEFT", sessionToggleBtn, "BOTTOMLEFT", 0, -12)
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

  local ctrlSectionSpacer = CreateFrame("Frame", nil, f)
  ctrlSectionSpacer:SetSize(308, 16)
  ctrlSectionSpacer:SetPoint("TOPLEFT", searchCustomSecEdit, "BOTTOMLEFT", 0, -10)

  local endRoundBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  endRoundBtn:SetSize(308, 24)
  endRoundBtn:SetText("End Round")
  endRoundBtn:SetPoint("TOPLEFT", ctrlSectionSpacer, "BOTTOMLEFT", 0, 0)

  local divControlGameplay = f:CreateTexture(nil, "ARTWORK", nil, 1)
  divControlGameplay:SetColorTexture(1, 1, 1, 0.12)
  divControlGameplay:SetSize(312, 1)
  divControlGameplay:SetPoint("TOPLEFT", endRoundBtn, "BOTTOMLEFT", -8, -10)

  local orphanSessionBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  orphanSessionBtn:SetSize(308, 24)
  orphanSessionBtn:SetText("End Game Session")
  orphanSessionBtn:Hide()

  local roundPhaseLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  roundPhaseLabel:SetWidth(328)
  roundPhaseLabel:SetJustifyH("LEFT")
  roundPhaseLabel:SetSpacing(2)
  roundPhaseLabel:SetPoint("TOPLEFT", divControlGameplay, "BOTTOMLEFT", 8, -8)

  local gameplayHouseLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gameplayHouseLbl:SetWidth(328)
  gameplayHouseLbl:SetJustifyH("LEFT")
  gameplayHouseLbl:SetPoint("TOPLEFT", roundPhaseLabel, "BOTTOMLEFT", 0, -6)
  gameplayHouseLbl:SetText("House: —")

  local gameplaySeekerLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gameplaySeekerLbl:SetWidth(328)
  gameplaySeekerLbl:SetJustifyH("LEFT")
  gameplaySeekerLbl:SetPoint("TOPLEFT", gameplayHouseLbl, "BOTTOMLEFT", 0, -6)
  gameplaySeekerLbl:SetText("Seeker: —")

  local hiddenList = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hiddenList:SetWidth(328)
  hiddenList:SetJustifyH("LEFT")
  hiddenList:SetSpacing(2)
  hiddenList:SetPoint("TOPLEFT", gameplaySeekerLbl, "BOTTOMLEFT", 0, -8)
  hiddenList:SetText("Hidden (0): —")

  local foundList = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  foundList:SetWidth(328)
  foundList:SetJustifyH("LEFT")
  foundList:SetSpacing(2)
  foundList:SetPoint("TOPLEFT", hiddenList, "BOTTOMLEFT", 0, -6)
  foundList:SetText("Found (0): —")

  local viewPastGameHousesBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewPastGameHousesBtn:SetSize(150, 22)
  viewPastGameHousesBtn:SetText("Previous Houses")
  viewPastGameHousesBtn:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", 0, -8)

  local viewPastSeekersBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewPastSeekersBtn:SetSize(150, 22)
  viewPastSeekersBtn:SetText("Previous Seekers")
  viewPastSeekersBtn:SetPoint("LEFT", viewPastGameHousesBtn, "RIGHT", 8, 0)

  local pastRoundsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  pastRoundsBtn:SetSize(308, 22)
  pastRoundsBtn:SetText("Previous Rounds")
  pastRoundsBtn:Hide()

  viewPastGameHousesBtn:Hide()
  viewPastSeekersBtn:Hide()

  local roundHintText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  roundHintText:SetWidth(328)
  roundHintText:SetJustifyH("LEFT")
  roundHintText:SetSpacing(2)
  roundHintText:Hide()

  local divGameplayHouse = f:CreateTexture(nil, "ARTWORK", nil, 1)
  divGameplayHouse:SetColorTexture(1, 1, 1, 0.12)
  divGameplayHouse:SetSize(312, 1)
  divGameplayHouse:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", -8, -12)

  -- House list / pin / saved size: separate House list window. Bottom row: How to play, View house list, Options.
  local howToPlayBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  howToPlayBtn:SetSize(308, 26)
  howToPlayBtn:SetText("How To Play")
  howToPlayBtn:SetPoint("TOPLEFT", divGameplayHouse, "BOTTOMLEFT", 8, -8)

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

  local function refreshFoundList()
    hiddenList:SetText(B.nhsSessionHudHiddenFormatted())
    foundList:SetText(B.nhsSessionHudFoundFormatted())
  end

  local function syncGameplayHouseSeekerLabels()
    gameplayHouseLbl:SetText("House: " .. B.nhsSessionHudHouseText())
    gameplaySeekerLbl:SetText("Seeker: " .. B.nhsSessionHudSeekerText())
  end

  -- Same source as the draggable session HUD so leader and follower gameplay blocks stay aligned.
  local function gameplayPhaseLine()
    if B.nhsSessionHudIsActive and B.nhsSessionHudIsActive() and B.nhsSessionHudPhaseText then
      return ("Phase: %s"):format(B.nhsSessionHudPhaseText())
    end
    return nil
  end

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
    local vhlBottom = viewHouseListBtn and viewHouseListBtn:GetBottom()
    if vhlBottom then
      lowest = math.min(lowest, vhlBottom)
    end
    local htpBottom = howToPlayBtn and howToPlayBtn:GetBottom()
    if htpBottom then
      lowest = math.min(lowest, htpBottom)
    end
    if roundHintText:IsShown() then
      local hb = roundHintText:GetBottom()
      if hb then
        lowest = math.min(lowest, hb)
      end
    end
    if versionLabel then
      local vb = versionLabel:GetBottom()
      if vb then
        lowest = math.min(lowest, vb)
      end
    end
    if sessionListGroupBtn and sessionListGroupBtn:IsShown() then
      local sb = sessionListGroupBtn:GetBottom()
      if sb then
        lowest = math.min(lowest, sb)
      end
    end
    local pad = 22
    local h = topEdge - lowest + pad
    h = math.max(260, math.min(1000, h))
    f:SetHeight(h)
  end

  local function setControlSectionVisible(show)
    if not show then
      nhsHideSessionHouseListPickUi()
    end
    sessionToggleBtn:SetShown(show)
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
    ctrlSectionSpacer:SetShown(show)
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
    endRoundBtn:SetShown(show)
  end

  local function layoutGameplayBlock(topAnchor, xOff, yOff, forLeaderUi)
    forLeaderUi = forLeaderUi ~= false
    if forLeaderUi then
      divControlGameplay:ClearAllPoints()
      divControlGameplay:Show()
      if topAnchor == f then
        divControlGameplay:SetPoint("TOPLEFT", f, "TOPLEFT", xOff, yOff)
      else
        divControlGameplay:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", xOff - 8, yOff + 6)
      end
    else
      divControlGameplay:Hide()
    end

    local phaseAnchor
    local phasePoint
    local phaseRel
    local phaseX
    local phaseY

    if orphanSessionBtn:IsShown() then
      orphanSessionBtn:ClearAllPoints()
      if forLeaderUi then
        orphanSessionBtn:SetPoint("TOPLEFT", divControlGameplay, "BOTTOMLEFT", 8, -8)
      else
        orphanSessionBtn:SetPoint("TOPLEFT", f, "TOPLEFT", xOff, yOff)
      end
      phaseAnchor = orphanSessionBtn
      phasePoint = "BOTTOMLEFT"
      phaseRel = "TOPLEFT"
      phaseX = 0
      phaseY = -8
    elseif forLeaderUi then
      phaseAnchor = divControlGameplay
      phasePoint = "BOTTOMLEFT"
      phaseRel = "TOPLEFT"
      phaseX = 8
      phaseY = -8
    else
      phaseAnchor = f
      phasePoint = "TOPLEFT"
      phaseRel = "TOPLEFT"
      phaseX = xOff
      phaseY = yOff
    end

    roundPhaseLabel:ClearAllPoints()
    roundPhaseLabel:SetPoint(phaseRel, phaseAnchor, phasePoint, phaseX, phaseY)
    gameplayHouseLbl:ClearAllPoints()
    gameplayHouseLbl:SetPoint("TOPLEFT", roundPhaseLabel, "BOTTOMLEFT", 0, -6)
    gameplaySeekerLbl:ClearAllPoints()
    gameplaySeekerLbl:SetPoint("TOPLEFT", gameplayHouseLbl, "BOTTOMLEFT", 0, -6)
    hiddenList:ClearAllPoints()
    hiddenList:SetPoint("TOPLEFT", gameplaySeekerLbl, "BOTTOMLEFT", 0, -8)
    foundList:ClearAllPoints()
    foundList:SetPoint("TOPLEFT", hiddenList, "BOTTOMLEFT", 0, -6)
  end

  -- Past session lists + divider below phase / house / seeker / hidden / found.
  -- "Previous Houses/Seekers" only while session HUD is active; "Previous Rounds" also after session
  -- ends when there is saved history for the last completed session.
  local function layoutGameplayDetailsFooter()
    local hud = B.nhsSessionHudIsActive and B.nhsSessionHudIsActive()
    local roundsOnly = not hud and #State.pastRounds > 0
    viewPastGameHousesBtn:ClearAllPoints()
    viewPastSeekersBtn:ClearAllPoints()
    pastRoundsBtn:ClearAllPoints()
    divGameplayHouse:ClearAllPoints()
    if hud then
      viewPastGameHousesBtn:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", 0, -8)
      viewPastSeekersBtn:SetPoint("LEFT", viewPastGameHousesBtn, "RIGHT", 8, 0)
      pastRoundsBtn:SetPoint("TOPLEFT", viewPastGameHousesBtn, "BOTTOMLEFT", 0, -8)
      viewPastGameHousesBtn:Show()
      viewPastSeekersBtn:Show()
      pastRoundsBtn:Show()
      divGameplayHouse:SetPoint("TOPLEFT", pastRoundsBtn, "BOTTOMLEFT", -8, -10)
    elseif roundsOnly then
      viewPastGameHousesBtn:Hide()
      viewPastSeekersBtn:Hide()
      pastRoundsBtn:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", 0, -8)
      pastRoundsBtn:Show()
      divGameplayHouse:SetPoint("TOPLEFT", pastRoundsBtn, "BOTTOMLEFT", -8, -10)
    else
      viewPastGameHousesBtn:Hide()
      viewPastSeekersBtn:Hide()
      pastRoundsBtn:Hide()
      divGameplayHouse:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", -8, -12)
    end
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
    local pickHouse = sess and State.gamePhase == "pick_house"
    local pickSeeker = sess and State.gamePhase == "pick_seeker"
    local inRound = sess and State.gamePhase == "round_active"
    local roundPhase = State.roundPhase
    local showOrphanEnd = sess and ingroup and not leader

    randomPickAnim.syncPhase(
      sess,
      pickHouse and State.gameSessionHouseListSource ~= nil,
      pickSeeker,
      useLeaderUi
    )

    if ingroup and leader then
      State.remoteRoundActive = false
      State.remoteSeekerKey = nil
    end

    roundHintText:Hide()

    if not useLeaderUi then
      setControlSectionVisible(false)
      sessionToggleBtn:Hide()
      gameplayGroupCatchUpBtn:Hide()
      orphanSessionBtn:SetShown(showOrphanEnd)
      roundsHint:Show()
      if State.gameSessionActive then
        roundsHint:SetText(
          "Party/raid data may be unavailable briefly during travel or loading. "
            .. "Session is kept in memory and saved — it will not be deleted automatically."
        )
        layoutGameplayBlock(f, 16, -72, false)
        layoutGameplayDetailsFooter()
        roundPhaseLabel:Hide()
        syncGameplayHouseSeekerLabels()
        roundHintText:ClearAllPoints()
        roundHintText:SetPoint("TOPLEFT", divGameplayHouse, "BOTTOMLEFT", 8, -10)
        roundHintText:SetWidth(328)
        roundHintText:Show()
        roundHintText:SetText(
          "Game control is hidden until you are party/raid leader again. "
            .. "Use End game session below to clear saved state."
        )
        viewPastGameHousesBtn:SetEnabled(#State.gameHouseHistory > 0)
        viewPastSeekersBtn:SetEnabled(#State.gameSeekerHistory > 0)
        pastRoundsBtn:SetEnabled(#State.pastRounds > 0)
        refreshFoundList()
        syncSeekerUiOptionsFromSaved()
        syncMainFrameHeight()
        if B.nhsSessionHudUpdate then
          B.nhsSessionHudUpdate()
        end
        return
      end
      if ingroup and State.remoteRoundActive then
        roundsHint:SetText("Group sync (addon); party/raid lines when out of combat")
        orphanSessionBtn:Hide()
        layoutGameplayBlock(f, 16, -40, false)
        layoutGameplayDetailsFooter()
        local phaseLineFollower = gameplayPhaseLine()
        if phaseLineFollower then
          roundPhaseLabel:SetWidth(328)
          roundPhaseLabel:SetText(phaseLineFollower)
          roundPhaseLabel:Show()
        else
          roundPhaseLabel:Hide()
        end
        syncGameplayHouseSeekerLabels()
        roundHintText:ClearAllPoints()
        roundHintText:SetPoint("TOPLEFT", divGameplayHouse, "BOTTOMLEFT", 8, -10)
        roundHintText:SetWidth(328)
        roundHintText:Show()
        local ph = (B.nhsSessionHudPhaseText and B.nhsSessionHudPhaseText()) or ""
        if ph == "Searching" then
          roundHintText:SetText(
            "If you are the seeker, use Options → Enter seeker mode if needed, then target party/raid members to mark them found."
          )
        elseif ph == "Hiding" then
          roundHintText:SetText(
            "Hiding — the leader can start a searching countdown when ready."
          )
        elseif ph == "Preparing" then
          roundHintText:SetText(
            "Preparing — the leader will start a hiding countdown when ready."
          )
        else
          roundHintText:SetText(
            "Round in progress — follow the phase line above or the leader’s party messages."
          )
        end
        viewPastGameHousesBtn:SetEnabled(#State.gameHouseHistory > 0)
        viewPastSeekersBtn:SetEnabled(#State.gameSeekerHistory > 0)
        pastRoundsBtn:SetEnabled(#State.pastRounds > 0)
        refreshFoundList()
        syncSeekerUiOptionsFromSaved()
        syncMainFrameHeight()
        if B.nhsSessionHudUpdate then
          B.nhsSessionHudUpdate()
        end
        gameplayGroupCatchUpBtn:Hide()
        return
      end
      orphanSessionBtn:Hide()
      roundsHint:SetText(
        not ingroup and "Join a party or raid to sync game rounds with the leader."
          or "Only the party/raid leader can run game control."
      )
      roundsHint:Show()
      layoutGameplayBlock(f, 16, -64, false)
      layoutGameplayDetailsFooter()
      local phaseLineWait = gameplayPhaseLine()
      if phaseLineWait then
        roundPhaseLabel:SetWidth(328)
        roundPhaseLabel:SetText(phaseLineWait)
        roundPhaseLabel:Show()
      else
        roundPhaseLabel:Hide()
      end
      syncGameplayHouseSeekerLabels()
      viewPastGameHousesBtn:SetEnabled(#State.gameHouseHistory > 0)
      viewPastSeekersBtn:SetEnabled(#State.gameSeekerHistory > 0)
      pastRoundsBtn:SetEnabled(#State.pastRounds > 0)
      refreshFoundList()
      syncSeekerUiOptionsFromSaved()
      syncMainFrameHeight()
      if B.nhsSessionHudUpdate then
        B.nhsSessionHudUpdate()
      end
      gameplayGroupCatchUpBtn:Hide()
      return
    end

    -- Leader or solo (not in group): show full control strip
    setControlSectionVisible(true)
    roundsHint:Hide()
    sessionToggleBtn:Show()
    orphanSessionBtn:Hide()

    sessionToggleBtn:SetText(sess and "End Game Session" or "Start Game Session")
    sessionToggleBtn:SetEnabled(mayAct)
    gameplayGroupCatchUpBtn:SetShown(sess and ingroup and mayAct)
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
      houseSelectHdr:Show()
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
      lockedRoundHouseLbl:SetShown(pickSeeker or inRound)
      seekerSelectHdr:SetShown(pickSeeker)
      candidateSeekerLbl:SetShown(pickSeeker)
      randSeekerBtn:SetShown(pickSeeker)
      selectSeekerBtn:SetShown(pickSeeker)
      startRoundBtn:SetShown(pickSeeker)
    end

    local showRoundTimers = sess and inRound
    local showHidePhaseRow = showRoundTimers and roundPhase == "pending"
    local showSearchPhaseRow = showRoundTimers and roundPhase == "hiding"

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

    ctrlSectionSpacer:SetShown(showRoundTimers)
    endRoundBtn:SetShown(showRoundTimers)

    if State.gameCandidateDisplay then
      candidateSeekerLbl:SetText(
        ("Current seeker (not locked in): %s"):format(State.gameCandidateDisplay)
      )
    else
      candidateSeekerLbl:SetText("Current seeker (not locked in): —")
    end

    for i, b in ipairs(hidePresetBtns) do
      local pr = NHS.ROUND_PRESETS[i]
      b:SetText(nhsPresetButtonCaptionWithDuration(pr.label, pr.hideSec))
    end
    for i, b in ipairs(searchPresetBtns) do
      local pr = NHS.ROUND_PRESETS[i]
      b:SetText(nhsPresetButtonCaptionWithDuration(pr.label, pr.searchSec))
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
      endRoundBtn:SetEnabled(false)
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
      endRoundBtn:SetEnabled(false)
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
      startRoundBtn:SetEnabled(
        mayAct and State.gameCandidateKey ~= nil and State.gameLockedHouseDisplay ~= nil
      )
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      endRoundBtn:SetEnabled(false)
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
      local rp = State.roundPhase
      local hideOn = mayAct and rp == "pending"
      local searchOn = mayAct and rp == "hiding"
      local endOn = mayAct and (rp == "pending" or rp == "hiding" or rp == "searching")
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(hideOn)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(searchOn)
      end
      endRoundBtn:SetEnabled(endOn)
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
      endRoundBtn:SetEnabled(false)
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
        ctrlSectionSpacer:ClearAllPoints()
        if showSearchPhaseRow then
          ctrlSectionSpacer:SetPoint("TOPLEFT", searchCustomSecEdit, "BOTTOMLEFT", 0, -10)
        elseif showHidePhaseRow then
          ctrlSectionSpacer:SetPoint("TOPLEFT", hideCustomSecEdit, "BOTTOMLEFT", 0, -10)
        else
          ctrlSectionSpacer:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -12)
        end
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
      seekerSelectHdr:SetPoint("TOPLEFT", sessionToggleBtn, "BOTTOMLEFT", 0, -12)
      candidateSeekerLbl:ClearAllPoints()
      candidateSeekerLbl:SetPoint("TOPLEFT", seekerSelectHdr, "BOTTOMLEFT", 0, -4)
      randSeekerBtn:ClearAllPoints()
      randSeekerBtn:SetPoint("TOPLEFT", candidateSeekerLbl, "BOTTOMLEFT", 0, -8)
      startRoundBtn:ClearAllPoints()
      startRoundBtn:SetPoint("LEFT", randSeekerBtn, "RIGHT", 8, 0)
      hideRowLbl:ClearAllPoints()
      hideRowLbl:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -12)
    end

    -- Anchor the divider + “rest of UI” to the left column so housing/options stay aligned with the panel edge.
    local layoutAnchor = sessionToggleBtn
    if sess then
      if inRound then
        layoutAnchor = endRoundBtn
      elseif pickSeeker then
        layoutAnchor = startRoundBtn
      elseif pickHouse then
        if State.gameSessionHouseListSource == nil then
          layoutAnchor = sessionListGroupBtn
        else
          layoutAnchor = confirmGameHouseBtn
        end
      else
        layoutAnchor = randSeekerBtn
      end
    end
    layoutGameplayBlock(layoutAnchor, 0, -16, true)
    layoutGameplayDetailsFooter()

    local phaseLine = gameplayPhaseLine()
    if phaseLine then
      roundPhaseLabel:SetWidth(328)
      roundPhaseLabel:SetText(phaseLine)
      roundPhaseLabel:Show()
    else
      roundPhaseLabel:Hide()
    end
    syncGameplayHouseSeekerLabels()
    refreshFoundList()

    selectSeekerBtn:SetEnabled(pickSeeker and mayAct)
    viewPastGameHousesBtn:SetEnabled(sess and #State.gameHouseHistory > 0)
    viewPastSeekersBtn:SetEnabled(sess and #State.gameSeekerHistory > 0)
    pastRoundsBtn:SetEnabled(#State.pastRounds > 0)
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
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_house" then
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
    refreshFoundList()
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
    refreshFoundList()
    refreshGameRounds()
    if B.nhsSessionHudUpdate then
      B.nhsSessionHudUpdate()
    end
  end

  viewPastSeekersBtn:SetScript("OnClick", function()
    refreshPastSeekersPanel()
    psf:Show()
  end)

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
    State.gamePhase = "pick_house"
    State.gameSessionHouseListSource = nil
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    wipe(State.gameHouseHistory)
    wipe(State.gameHouseRotationUsed)
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.gameLockedSeekerKey = nil
    State.gameLockedSeekerDisplay = nil
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
      "|cff88ccff[NHS]|r Game session started. Choose Neighborhood, Saved list, or Group for houses, then pick and confirm a house."
    )
    refreshGameRounds()
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
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_seeker" then
      return
    end
    local elig, err = B.nhsRandomSeekerEligible()
    if not elig then
      print("|cffff8800[NHS]|r " .. tostring(err))
      return
    end
    if hideSeekerListFrame then
      gsfp:Hide()
    end
    randomPickAnim.openAnimated("seeker", "Random seeker (eligible this rotation)", elig, function(winIdx)
      local m = elig[winIdx]
      if not m then
        return
      end
      State.gameCandidateKey = m.key
      State.gameCandidateDisplay = m.display
      print(
        ("|cff88ccff[NHS]|r Seeker pick: |cffffffff%s|r — Confirm seeker to lock in (or random again)."):format(
          m.display
        )
      )
      B.nhsPersistGameSessionToSaved()
      refreshGameRounds()
    end)
  end

  gsfpAnimRandomSeekerBtn:SetScript("OnClick", function()
    nhsOpenSeekerAnimatedRandomPick(true)
  end)

  randGameHouseBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_house" then
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
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_house" then
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
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_house" then
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
    State.gamePhase = "pick_seeker"
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
      ("|cff88ccff[NHS]|r House locked for this round: |cffffffff%s|r — pick a seeker."):format(
        State.gameLockedHouseDisplay
      )
    )
    B.nhsPersistGameSessionToSaved()
    refreshGameRounds()
  end)

  viewPastGameHousesBtn:SetScript("OnClick", function()
    refreshGameplayPastHousesPanel()
    ghpf:Show()
  end)

  pastRoundsBtn:SetScript("OnClick", function()
    refreshPastRoundsPanel()
    pastRoundsFrame:Show()
  end)

  randSeekerBtn:SetScript("OnClick", function()
    nhsOpenSeekerAnimatedRandomPick(false)
  end)

  selectSeekerBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_seeker" then
      return
    end
    if #B.nhsGetGroupRoster() == 0 then
      print("|cffff8800[NHS]|r No players in group.")
      return
    end
    refreshGroupSeekerPickList()
    gsfp:Show()
  end)

  startRoundBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_seeker" then
      return
    end
    if not State.gameCandidateKey then
      return
    end
    if not State.gameLockedHouseDisplay then
      print("|cffff8800[NHS]|r Confirm a house first (house selection phase).")
      return
    end
    B.clearFound()
    State.gameRotationUsed[State.gameCandidateKey] = true
    State.gameSeekerHistory[#State.gameSeekerHistory + 1] = State.gameCandidateDisplay
    State.gameLockedSeekerKey = State.gameCandidateKey
    State.gameLockedSeekerDisplay = State.gameCandidateDisplay
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.gamePhase = "round_active"
    State.roundPhase = "pending"
    B.nhsBroadcastLeaderSync(B.NHS_MSG_ROUND_START .. tostring(State.gameLockedSeekerKey))
    print(
      ("|cff88ccff[NHS]|r Round started. |cffffffff%s|r is the seeker."):format(State.gameLockedSeekerDisplay)
    )
    B.nhsPersistGameSessionToSaved()
    refreshGameRounds()
  end)

  local function nhsLeaderBroadcastRoundPhase(phase)
    if phase == "hiding" then
      State.roundPhase = "hiding"
      B.nhsBroadcastLeaderSync(B.NHS_MSG_HIDING)
      if NHS.PlayHidingPhaseStartSound then
        NHS.PlayHidingPhaseStartSound()
      end
    elseif phase == "searching" then
      State.roundPhase = "searching"
      if State.gameLockedSeekerKey and State.gameLockedSeekerKey ~= "" then
        B.nhsBroadcastLeaderSync(B.NHS_MSG_SEEKING .. State.gameLockedSeekerKey)
      else
        B.nhsBroadcastLeaderSync("[NHS] The Seeking Begins!")
      end
      B.nhsLeaderTryPromoteSeekerForRaidWarn()
    end
  end

  local function onPresetCountdownClick(self)
    if not B.nhsMayUseLeaderGameActions() or State.gamePhase ~= "round_active" then
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
      sec = (self._kind == "hide") and pr.hideSec or pr.searchSec
    end
    local ok, err = B.nhsStartBuiltInCountdown(sec)
    if ok then
      local phaseLabel = (self._kind == "hide") and "Hiding" or "Searching"
      nhsLeaderBroadcastRoundPhase(self._kind == "hide" and "hiding" or "searching")
      print(
        ("|cff88ccff[NHS]|r %s — %s (%d s)."):format(phaseLabel, presetName, sec)
      )
      if UI.RefreshAll then
        UI.RefreshAll()
      end
      B.nhsSeekerAutoModeSyncToPhase()
      B.nhsPersistGameSessionToSaved()
    else
      print("|cffff8800[NHS]|r " .. tostring(err))
    end
  end

  for _, b in ipairs(hidePresetBtns) do
    b:SetScript("OnClick", onPresetCountdownClick)
  end
  for _, b in ipairs(searchPresetBtns) do
    b:SetScript("OnClick", onPresetCountdownClick)
  end
  hideCustomCountdownBtn:SetScript("OnClick", onPresetCountdownClick)
  searchCustomCountdownBtn:SetScript("OnClick", onPresetCountdownClick)

  endRoundBtn:SetScript("OnClick", function()
    if not B.nhsMayUseLeaderGameActions() or State.gamePhase ~= "round_active" then
      return
    end
    B.nhsAppendPastRoundSnapshotIfActiveRound()
    B.nhsLeaderDemoteSeekerAssistantIfWePromoted()
    State.gamePhase = "pick_house"
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    State.gameLockedSeekerKey = nil
    State.gameLockedSeekerDisplay = nil
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.roundPhase = "none"
    B.clearFound()
    B.nhsStopPartyCountdown()
    B.nhsBroadcastLeaderSync(B.NHS_MSG_ROUND_OVER)
    print("|cff88ccff[NHS]|r Round ended. Pick the next house, then the next seeker.")
    B.nhsPersistGameSessionToSaved()
    if State.seekerMode then
      B.setSeekerMode(false)
    end
    refreshGameRounds()
  end)

  refreshBtn:SetScript("OnClick", function()
    refreshHouseList()
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

