--[[
  Draggable session summary HUD (phase / house / seeker / hidden / found).
  Expects NeighborhoodHideSeek.State, EnsureSavedVars, SeekerModeBridge.getUI,
  and BuildMainFrameBridge.nhsGetGroupRoster from Gameplay/GameSession.lua
  (load GameSession before this file; see .toc).
]]

local NHS = NeighborhoodHideSeek
local ADDON_NAME = assert(NHS.ADDON_NAME, "NeighborhoodHideSeek.ADDON_NAME missing.")
local State = NHS.State
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
  { label = "Medium", hideSec = 240, searchSec = 360 },
  { label = "Large", hideSec = 300, searchSec = 480 },
  { label = "Oversized", hideSec = 300, searchSec = 600 },
}
NHS.ROUND_PRESETS = ROUND_PRESETS

local function nhsSessionHudIsActive()
  return State.gameSessionActive or State.remoteSessionActive or State.remoteRoundActive
end

local function nhsSessionHudPhaseText()
  if State.gameSessionActive and State.gamePhase == "pick_house" then
    return "House selection"
  end
  if State.gameSessionActive and State.gamePhase == "pick_seeker" then
    return "Seeker selection"
  end
  if State.gamePhase == "round_active" or State.remoteRoundActive then
    if State.roundPhase == "pending" then
      return "Preparing"
    elseif State.roundPhase == "hiding" then
      return "Hiding"
    elseif State.roundPhase == "searching" then
      return "Searching"
    end
    return "Round active"
  end
  if State.remoteSessionActive then
    return "Waiting for round"
  end
  return "—"
end

local function nhsSessionHudHouseText()
  if State.gameSessionActive and State.gamePhase == "pick_house" and State.gameHouseCandidateDisplay then
    return State.gameHouseCandidateDisplay
  end
  if State.gameSessionActive and (State.gamePhase == "pick_seeker" or State.gamePhase == "round_active") then
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
  if State.remoteRoundActive and State.remoteSeekerKey then
    return Ambiguate(State.remoteSeekerKey, "short")
  end
  if State.gamePhase == "round_active" and State.gameLockedSeekerDisplay then
    return State.gameLockedSeekerDisplay
  end
  if State.gamePhase == "pick_seeker" and State.gameCandidateDisplay then
    return State.gameCandidateDisplay
  end
  return "—"
end

local function nhsSessionHudSeekerKeyForLists()
  if State.remoteRoundActive and State.remoteSeekerKey then
    return State.remoteSeekerKey
  end
  if State.gamePhase == "round_active" and State.gameLockedSeekerKey then
    return State.gameLockedSeekerKey
  end
  if State.gamePhase == "pick_seeker" and State.gameCandidateKey then
    return State.gameCandidateKey
  end
  return nil
end

local function nhsSessionHudCommaList(names, maxShown)
  maxShown = maxShown or 14
  if #names == 0 then
    return "(none)"
  end
  table.sort(names)
  if #names <= maxShown then
    return table.concat(names, ", ")
  end
  local parts = {}
  for i = 1, maxShown do
    parts[i] = names[i]
  end
  return table.concat(parts, ", ") .. (", +" .. tostring(#names - maxShown) .. " more")
end

-- Everyone still hiding (not marked found), excluding the designated seeker once that key is known.
local function nhsSessionHudHiddenPlayerNames()
  local sk = nhsSessionHudSeekerKeyForLists()
  local roster = nhsGetGroupRoster()
  local names = {}
  for _, m in ipairs(roster) do
    if (sk == nil or m.key ~= sk) and not State.foundSet[m.key] then
      names[#names + 1] = Ambiguate(m.key, "short")
    end
  end
  table.sort(names)
  return names
end

local function nhsSessionHudHiddenFormatted()
  local names = nhsSessionHudHiddenPlayerNames()
  local n = #names
  if n == 0 then
    return "Hidden (0): —"
  end
  return ("Hidden (%d): %s"):format(n, nhsSessionHudCommaList(names))
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
  table.sort(names)
  return ("Found (%d): %s"):format(n, nhsSessionHudCommaList(names))
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
  hud._houseLine:SetText("House: " .. nhsSessionHudHouseText())
  hud._seekerLine:SetText("Seeker: " .. nhsSessionHudSeekerText())
  hud._foundLine:SetText(nhsSessionHudFoundFormatted())
  hud._hiddenLine:SetText(nhsSessionHudHiddenFormatted())
  local padBottom = 14
  local hTitle = hud._title:GetStringHeight() or 12
  local hPhase = hud._phaseLine:GetStringHeight() or 12
  local hHouse = hud._houseLine:GetStringHeight() or 12
  local hSeek = hud._seekerLine:GetStringHeight() or 12
  local hHid = hud._hiddenLine:GetStringHeight() or 12
  local hFound = hud._foundLine:GetStringHeight() or 12
  local totalH = 12 + hTitle + 10 + hPhase + 4 + hHouse + 4 + hSeek + 8 + hHid + 6 + hFound + padBottom
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
  local title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText("Hide & Seek")
  hud._title = title
  local phaseLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  phaseLine:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  phaseLine:SetWidth(contentW)
  phaseLine:SetJustifyH("LEFT")
  phaseLine:SetSpacing(2)
  local houseLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  houseLine:SetPoint("TOPLEFT", phaseLine, "BOTTOMLEFT", 0, -4)
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
  local foundLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  foundLine:SetPoint("TOPLEFT", hiddenLine, "BOTTOMLEFT", 0, -6)
  foundLine:SetWidth(contentW)
  foundLine:SetJustifyH("LEFT")
  foundLine:SetSpacing(2)
  hud._phaseLine = phaseLine
  hud._houseLine = houseLine
  hud._seekerLine = seekerLine
  hud._foundLine = foundLine
  hud._hiddenLine = hiddenLine
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
