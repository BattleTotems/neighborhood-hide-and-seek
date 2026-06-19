--[[
  Draggable session summary HUD (phase / house / seeker / hidden / found).
  Expects NeighborhoodHideSeek.State, EnsureSavedVars, SeekerModeBridge.getUI,
  and BuildMainFrameBridge.nhsGetGroupRoster from Gameplay/GameSession.lua
  (load GameSession before this file; see .toc).
]]

local NHS = NeighborhoodHideSeek
local ADDON_NAME = assert(NHS.ADDON_NAME, "NeighborhoodHideSeek.ADDON_NAME missing.")
local State = NHS.State
local Phase = NHS.Phase
local IsRoundPhase = NHS.IsRoundPhase
local B = assert(NHS.SeekerModeBridge, "NeighborhoodHideSeek.SeekerModeBridge missing (load order).")

local function ensureSavedVars()
  NHS.EnsureSavedVars()
end

local function getUI()
  return B.getUI()
end

local function nhsGetGroupRoster()
  local bmf = NHS.BuildMainFrameBridge
  assert(bmf and bmf.nhsGetGroupRoster, "BuildMainFrameBridge.nhsGetGroupRoster missing (load order).")
  return bmf.nhsGetGroupRoster()
end

local ROUND_PRESETS = {
  { label = "Small", hideSec = 180, searchSec = 240 },
  { label = "Medium", hideSec = 240, searchSec = 330 },
  { label = "Large", hideSec = 300, searchSec = 420 }, 
  { label = "Oversized", hideSec = 300, searchSec = 510 },
}
NHS.ROUND_PRESETS = ROUND_PRESETS

local function nhsSessionHudIsActive()
  return State.gameSessionActive or State.remoteSessionActive
end

local function nhsSessionHudPhaseText()
  local p = State.phase
  if p == Phase.PICK_GAME_MODE then return "Game Mode Selection" end
  if p == Phase.PICK_HOUSE then return "House Selection" end
  if p == Phase.PICK_SEEKER then
    return (NHS.IsHiderMode and NHS.IsHiderMode()) and "Hider Selection" or "Seeker Selection"
  end
  if p == Phase.PENDING then return "Preparing" end
  if p == Phase.HIDING then return "Hiding" end
  if p == Phase.SEARCHING then return "Searching" end
  if p == Phase.REVEALING then return "Revealing" end
  return "—"
end

local function nhsSessionHudGameModeText()
  if not nhsSessionHudIsActive() then
    return nil
  end
  local id = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
  if id and NHS.GameModeHudLabel then
    return "Mode: " .. NHS.GameModeHudLabel(id)
  end
  return "Mode: —"
end

local function nhsSessionHudHouseText()
  if State.gameSessionActive and State.phase == Phase.PICK_HOUSE and State.gameHouseCandidateDisplay then
    return State.gameHouseCandidateDisplay
  end
  if State.gameSessionActive and (State.phase == Phase.PICK_GAME_MODE or State.phase == Phase.PICK_SEEKER or IsRoundPhase(State.phase)) then
    if State.gameLockedHouseDisplay then
      return State.gameLockedHouseDisplay
    end
  end
  if State.remoteHouseDisplay and State.remoteHouseDisplay ~= "" then
    return State.remoteHouseDisplay
  end
  return "—"
end

local function nhsSessionHudSeekerText()
  if State.remoteSessionActive and IsRoundPhase(State.phase) and #State.remoteSeekerKeys > 0 then
    local names = {}
    for _, k in ipairs(State.remoteSeekerKeys) do
      names[#names + 1] = Ambiguate(k, "short")
    end
    return table.concat(names, ", ")
  end
  if State.gameSessionActive and IsRoundPhase(State.phase) and #State.gameLockedSeekerKeys > 0 then
    local names = {}
    for _, k in ipairs(State.gameLockedSeekerKeys) do
      names[#names + 1] = Ambiguate(k, "short")
    end
    return table.concat(names, ", ")
  end
  if State.gameSessionActive and State.phase == Phase.PICK_SEEKER and #State.gameCandidateKeys > 0 then
    local names = {}
    for _, k in ipairs(State.gameCandidateKeys) do
      names[#names + 1] = Ambiguate(k, "short")
    end
    return table.concat(names, ", ")
  end
  return "—"
end

local function nhsSessionHudSeekerKeyForLists()
  -- Returns first seeker key only (fallback for single-seeker hidden-player list).
  if State.remoteSessionActive and IsRoundPhase(State.phase) and #State.remoteSeekerKeys > 0 then
    return State.remoteSeekerKeys[1]
  end
  if State.gameSessionActive and IsRoundPhase(State.phase) and #State.gameLockedSeekerKeys > 0 then
    return State.gameLockedSeekerKeys[1]
  end
  if State.gameSessionActive and State.phase == Phase.PICK_SEEKER and #State.gameCandidateKeys > 0 then
    return State.gameCandidateKeys[1]
  end
  return nil
end

local function nhsSessionHudCommaList(names, maxShown, sortAlphabetically)
  maxShown = maxShown or 14
  if #names == 0 then
    return "(none)"
  end
  if sortAlphabetically ~= false then
    table.sort(names)
  end
  if #names <= maxShown then
    return table.concat(names, ", ")
  end
  local parts = {}
  for i = 1, maxShown do
    parts[i] = names[i]
  end
  return table.concat(parts, ", ") .. (", +" .. tostring(#names - maxShown) .. " more")
end

-- Returns whether the local player is a hider (not a seeker) during the hiding phase.
local function nhsLocalPlayerIsHider()
  if State.phase ~= Phase.HIDING then return false end
  local seekerKeys = State.gameSessionActive and State.gameLockedSeekerKeys
    or (State.remoteSessionActive and State.remoteSeekerKeys)
    or {}
  local myKey = NHS.LocalPlayerSortKey and NHS.LocalPlayerSortKey()
  if not myKey then return false end
  for _, k in ipairs(seekerKeys) do
    if NHS.GroupSortKeysEquivalent and NHS.GroupSortKeysEquivalent(myKey, k) then
      return false
    end
  end
  return true
end

-- Everyone still hiding (not marked found), with ready status.
-- Returns sorted list of { name, ready } entries.
-- Uses fuzzy key matching (GroupSortKeysEquivalent) so realm-format differences
-- between how the leader broadcasts their key vs how they appear in the roster
-- don't cause a seeker to slip into the hidden list.
local function nhsSessionHudHiddenPlayerEntries()
  local roleKeys = {}
  if State.remoteSessionActive and IsRoundPhase(State.phase) then
    for _, k in ipairs(State.remoteSeekerKeys) do roleKeys[#roleKeys + 1] = k end
  end
  if State.gameSessionActive and IsRoundPhase(State.phase) then
    for _, k in ipairs(State.gameLockedSeekerKeys) do roleKeys[#roleKeys + 1] = k end
  end
  if State.gameSessionActive and State.phase == Phase.PICK_SEEKER then
    for _, k in ipairs(State.gameCandidateKeys) do roleKeys[#roleKeys + 1] = k end
  end
  local roster = nhsGetGroupRoster()
  local entries = {}
  for _, m in ipairs(roster) do
    local inRoleKeys = false
    for _, k in ipairs(roleKeys) do
      if m.key == k or (NHS.GroupSortKeysEquivalent and NHS.GroupSortKeysEquivalent(m.key, k)) then
        inRoleKeys = true
        break
      end
    end
    if not inRoleKeys and not State.foundSet[m.key] then
      entries[#entries + 1] = {
        name = Ambiguate(m.key, "short"),
        ready = State.hiderReadySet[m.key] == true,
        key = m.key,
      }
    end
  end
  table.sort(entries, function(a, b) return a.name < b.name end)
  return entries
end

-- Everyone still hiding (not marked found), excluding designated seekers.
local function nhsSessionHudHiddenPlayerNames()
  local entries = nhsSessionHudHiddenPlayerEntries()
  local names = {}
  for _, e in ipairs(entries) do
    names[#names + 1] = e.name
  end
  return names
end

local function nhsSessionHudHiddenFormatted()
  local entries = nhsSessionHudHiddenPlayerEntries()
  local n = #entries
  if n == 0 then
    return "Hidden (0): —"
  end
  -- During hiding phase, show ready players in green.
  local showReady = State.phase == Phase.HIDING
  local maxShown = 14
  local parts = {}
  for i = 1, math.min(n, maxShown) do
    local e = entries[i]
    if showReady and e.ready then
      parts[#parts + 1] = "|cff00dd00" .. e.name .. "|r"
    else
      parts[#parts + 1] = e.name
    end
  end
  local list = table.concat(parts, ", ")
  if n > maxShown then
    list = list .. ", +" .. tostring(n - maxShown) .. " more"
  end
  return ("Hidden (%d): %s"):format(n, list)
end

local function nhsSessionHudClosestRangeText()
  if NHS.FormatClosestHiddenRangeLine then
    return NHS.FormatClosestHiddenRangeLine()
  end
  return nil
end

local function nhsSessionHudFoundFormatted()
  local names = {}
  for i = 1, #State.foundOrder do
    names[#names + 1] = Ambiguate(State.foundOrder[i], "short")
  end
  local n = #names
  if n == 0 then
    return "Found (0): —"
  end
  return ("Found (%d): %s"):format(n, nhsSessionHudCommaList(names, 14, false))
end

local function nhsSessionHudUpdate()
  local UI = getUI()
  local hud = UI.sessionHud
  if not hud then
    return
  end
  if not nhsSessionHudIsActive() then
    hud:Hide()
    return
  end
  hud:Show()
  hud._phaseLine:SetText("Phase: " .. nhsSessionHudPhaseText())
  if hud._gameModeLine then
    hud._gameModeLine:SetText(nhsSessionHudGameModeText())
  end
  hud._houseLine:SetText("House: " .. nhsSessionHudHouseText())
  -- Show "Hider" only during the picking phase; once the round runs, all locked keys are seekers.
  local seekerRoleLabel = (NHS.IsHiderMode and NHS.IsHiderMode() and State.phase == Phase.PICK_SEEKER) and "Hider" or "Seeker"
  hud._seekerLine:SetText(seekerRoleLabel .. ": " .. nhsSessionHudSeekerText())
  hud._hiddenLine:SetText(nhsSessionHudHiddenFormatted())
  local closestRange = nhsSessionHudClosestRangeText()
  if closestRange then
    hud._closestRangeLine:SetText(closestRange)
    hud._closestRangeLine:Show()
    hud._foundLine:SetPoint("TOPLEFT", hud._closestRangeLine, "BOTTOMLEFT", 0, -6)
  else
    hud._closestRangeLine:Hide()
    hud._foundLine:SetPoint("TOPLEFT", hud._hiddenLine, "BOTTOMLEFT", 0, -6)
  end
  hud._foundLine:SetText(nhsSessionHudFoundFormatted())
  local showSeekerBtn = hud._seekerModeBtn
    and (State.phase == Phase.HIDING or State.phase == Phase.SEARCHING)
    and NHS.MayEnterSeekerMode and NHS.MayEnterSeekerMode()
    and not State.seekerMode
  if hud._seekerModeBtn then
    if showSeekerBtn then
      hud._seekerModeBtn:ClearAllPoints()
      hud._seekerModeBtn:SetPoint("TOPLEFT", hud._foundLine, "BOTTOMLEFT", 0, -8)
      hud._seekerModeBtn:Show()
    else
      hud._seekerModeBtn:Hide()
    end
  end
  -- Ready button: visible for hiders during hiding phase only, hidden once they've clicked it.
  local myKey = NHS.LocalPlayerSortKey and NHS.LocalPlayerSortKey()
  local alreadyReady = myKey and State.hiderReadySet[myKey] == true
  local showReadyBtn = hud._readyBtn
    and nhsLocalPlayerIsHider()
    and not alreadyReady
  if hud._readyBtn then
    if showReadyBtn then
      local anchorAbove = showSeekerBtn and hud._seekerModeBtn or hud._foundLine
      hud._readyBtn:ClearAllPoints()
      hud._readyBtn:SetPoint("TOPLEFT", anchorAbove, "BOTTOMLEFT", 0, -8)
      hud._readyBtn:Show()
    else
      hud._readyBtn:Hide()
    end
  end
  -- Toy button: visible for Toy & Seek hiders during the searching phase only.
  -- Position is fixed at creation time (BOTTOMLEFT of hud + 12, 14) — never
  -- reposition from here, because ClearAllPoints/SetPoint on a
  -- SecureActionButtonTemplate from tainted Lua silently fails in modern WoW.
  local showToyBtn = hud._toyBtn
    and (NHS.ToyAndSeek and NHS.ToyAndSeek.IsHider and NHS.ToyAndSeek.IsHider())
  if hud._toyBtn then
    if showToyBtn then
      hud._toyBtn:Show()
    else
      hud._toyBtn:Hide()
    end
  end
  local padBottom = 14
  local hTitle = hud._title:GetStringHeight() or 12
  local hPhase = hud._phaseLine:GetStringHeight() or 12
  local hMode = (hud._gameModeLine and hud._gameModeLine:GetStringHeight()) or 12
  local hHouse = hud._houseLine:GetStringHeight() or 12
  local hSeek = hud._seekerLine:GetStringHeight() or 12
  local hHid = hud._hiddenLine:GetStringHeight() or 12
  local hClosest = closestRange and (hud._closestRangeLine:GetStringHeight() or 12) or 0
  local hFound = hud._foundLine:GetStringHeight() or 12
  local gapClosest = closestRange and 6 or 0
  local hBtn = (showSeekerBtn and 32 or 0) + (showReadyBtn and 32 or 0) + (showToyBtn and 32 or 0)
  local totalH = 12 + hTitle + 10 + hPhase + 4 + hMode + 4 + hHouse + 4 + hSeek + 8 + hHid + gapClosest + hClosest + 6 + hFound + hBtn + padBottom
  hud:SetHeight(math.max(130, math.min(360, totalH)))
end

-- Main window is lazy-built (BuildMainFrame on first toggle); until then UI.RefreshFound is nil.
-- Always refresh the draggable session HUD when found/hidden/session state changes.
local function nhsRefreshGameSessionUi()
  local ui = B.getUI()
  if ui.RefreshFound then
    ui.RefreshFound()
  else
    nhsSessionHudUpdate()
  end
end

local function nhsInitSessionHud()
  local UI = getUI()
  if UI.sessionHud then
    return
  end
  ensureSavedVars()
  local hud = CreateFrame("Frame", ADDON_NAME .. "SessionHud", UIParent, "BackdropTemplate")
  local contentW = 216
  hud._contentW = contentW
  hud:SetSize(240, 160)
  hud:SetClampedToScreen(true)
  hud:SetMovable(true)
  hud:SetFrameStrata("MEDIUM")
  hud:SetFrameLevel(25)
  hud:EnableMouse(true)
  hud:RegisterForDrag("LeftButton")
  hud:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.sessionHudPoint = { p, rp or "UIParent", x, y }
  end)
  hud:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  hud:SetBackdropColor(0, 0, 0, 0.85)
  if NHSV.sessionHudPoint then
    local hp = NHSV.sessionHudPoint
    hud:SetPoint(hp[1], UIParent, hp[2], hp[3], hp[4])
  else
    hud:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -160)
  end
  local openBtn = CreateFrame("Button", nil, hud)
  openBtn:SetSize(20, 20)
  openBtn:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -34, -10)
  openBtn:SetNormalTexture("Interface\\Common\\help-i")
  openBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  openBtn:SetScript("OnClick", function()
    if NHS.ToggleMainWindow then
      NHS.ToggleMainWindow()
    end
  end)
  openBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Hide & Seek", 1, 1, 1)
    GameTooltip:AddLine("Click to open the main window.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  openBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  local statsBtn = CreateFrame("Button", nil, hud)
  statsBtn:SetSize(20, 20)
  statsBtn:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -10, -10)
  statsBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_09")
  statsBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  statsBtn:SetScript("OnClick", function()
    NHS.EnsureMainFrameCreated()
    local UI = getUI()
    if UI and UI.statsFrame then
      if UI.statsFrame:IsShown() then
        UI.statsFrame:Hide()
      else
        if UI.refreshStatsPanel then
          UI.refreshStatsPanel()
        end
        UI.statsFrame:Show()
      end
    end
  end)
  statsBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Game Stats", 1, 1, 1)
    GameTooltip:AddLine("Click to view game statistics.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  statsBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  local title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText("Hide & Seek")
  hud._title = title
  local phaseLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  phaseLine:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  phaseLine:SetWidth(contentW)
  phaseLine:SetJustifyH("LEFT")
  phaseLine:SetSpacing(2)
  local gameModeLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gameModeLine:SetPoint("TOPLEFT", phaseLine, "BOTTOMLEFT", 0, -4)
  gameModeLine:SetWidth(contentW)
  gameModeLine:SetJustifyH("LEFT")
  gameModeLine:SetSpacing(2)
  local houseLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  houseLine:SetPoint("TOPLEFT", gameModeLine, "BOTTOMLEFT", 0, -4)
  houseLine:SetWidth(contentW)
  houseLine:SetJustifyH("LEFT")
  houseLine:SetSpacing(2)
  local seekerLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  seekerLine:SetPoint("TOPLEFT", houseLine, "BOTTOMLEFT", 0, -4)
  seekerLine:SetWidth(contentW)
  seekerLine:SetJustifyH("LEFT")
  seekerLine:SetSpacing(2)
  local hiddenLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hiddenLine:SetPoint("TOPLEFT", seekerLine, "BOTTOMLEFT", 0, -8)
  hiddenLine:SetWidth(contentW)
  hiddenLine:SetJustifyH("LEFT")
  hiddenLine:SetSpacing(2)
  local closestRangeLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  closestRangeLine:SetPoint("TOPLEFT", hiddenLine, "BOTTOMLEFT", 0, -6)
  closestRangeLine:SetWidth(contentW)
  closestRangeLine:SetJustifyH("LEFT")
  closestRangeLine:Hide()
  local foundLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  foundLine:SetPoint("TOPLEFT", hiddenLine, "BOTTOMLEFT", 0, -6)
  foundLine:SetWidth(contentW)
  foundLine:SetJustifyH("LEFT")
  foundLine:SetSpacing(2)
  local seekerModeBtn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
  seekerModeBtn:SetSize(160, 24)
  seekerModeBtn:SetText("Enter Seeker Mode")
  seekerModeBtn:SetScript("OnClick", function()
    if NHS.SetSeekerMode then
      NHS.SetSeekerMode(true)
    end
  end)
  seekerModeBtn:Hide()
  local readyBtn = CreateFrame("Button", nil, hud, "UIPanelButtonTemplate")
  readyBtn:SetSize(160, 24)
  readyBtn:SetText("I'm Hidden!")
  readyBtn:SetScript("OnClick", function()
    if NHS.BroadcastHiderReady then
      NHS.BroadcastHiderReady()
    end
    nhsSessionHudUpdate()
  end)
  readyBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("I'm Hidden!", 1, 1, 1)
    GameTooltip:AddLine("Let the leader know you're in your hiding spot.", nil, nil, nil, true)
    GameTooltip:Show()
  end)
  readyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  readyBtn:Hide()
  -- Toy & Seek hider button (SecureActionButtonTemplate).  Must be a child of this
  -- frame so it moves with it and the player's click is treated as a hardware event.
  if NHS.ToyAndSeek and NHS.ToyAndSeek.InitHudButton then
    NHS.ToyAndSeek.InitHudButton(hud)
  end
  hud._phaseLine = phaseLine
  hud._gameModeLine = gameModeLine
  hud._houseLine = houseLine
  hud._seekerLine = seekerLine
  hud._foundLine = foundLine
  hud._hiddenLine = hiddenLine
  hud._closestRangeLine = closestRangeLine
  hud._seekerModeBtn = seekerModeBtn
  hud._readyBtn = readyBtn
  UI.sessionHud = hud
  nhsSessionHudUpdate()
end

NHS.SessionHudCommaList = nhsSessionHudCommaList
NHS.SessionHudIsActive = nhsSessionHudIsActive
NHS.SessionHudUpdate = nhsSessionHudUpdate
NHS.RefreshGameSessionUi = nhsRefreshGameSessionUi
NHS.InitSessionHud = nhsInitSessionHud

local bmf = NHS.BuildMainFrameBridge
if bmf then
  bmf.nhsSessionHudUpdate = nhsSessionHudUpdate
  bmf.nhsSessionHudIsActive = nhsSessionHudIsActive
  bmf.nhsSessionHudPhaseText = nhsSessionHudPhaseText
  bmf.nhsSessionHudGameModeText = nhsSessionHudGameModeText
  bmf.nhsSessionHudHiddenFormatted = nhsSessionHudHiddenFormatted
  bmf.nhsSessionHudFoundFormatted = nhsSessionHudFoundFormatted
  bmf.nhsSessionHudHouseText = nhsSessionHudHouseText
  bmf.nhsSessionHudSeekerText = nhsSessionHudSeekerText
end

local gsb = NHS.GroupSyncBridge
if gsb then
  gsb.nhsSessionHudUpdate = nhsSessionHudUpdate
  gsb.nhsRefreshGameSessionUi = nhsRefreshGameSessionUi
end
