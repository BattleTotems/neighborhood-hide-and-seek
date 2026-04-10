--[[
  Seeker mode: nameplate CVars, party/minimap suppression poll; may-enter rules and phase auto-sync.
  Expects NeighborhoodHideSeek.SeekerModeBridge from Core; LocalPlayerIsDesignatedSeeker from GameSession
  at runtime (GameSession loads after this file).
]]

local NHS = NeighborhoodHideSeek
local B = assert(NHS.SeekerModeBridge, "NeighborhoodHideSeek.SeekerModeBridge missing (load order).")
local State = NHS.State

--[[
  Nameplate-related CVars snapshotted in seeker mode (Names / Nameplates options).
  Midnight (12.x) removed nameplateShowFriends; friendly *player* plates are driven
  largely by nameplatePlayerMaxDistance — set to 0 in seeker mode when present.
  We still SetCVar nameplateShowFriends for older clients (pcall, no GetCVar guard).
]]
local NAMEPLATE_CVARS = {
  "nameplateShowAll",
  "nameplateShowEnemies",
  "nameplateShowFriends",
  "nameplateShowSelf",
  "nameplateShowFriendlyNPCs",
  "nameplateShowEnemyMinus",
  "nameplateShowEnemyMinions",
  "nameplateShowFriendlyMinions",
  "nameplateShowEnemyPets",
  "nameplateShowFriendlyPets",
  "nameplateShowEnemyGuardians",
  "nameplateShowFriendlyGuardians",
  "nameplateShowEnemyTotems",
  "nameplateShowFriendlyTotems",
  "nameplateShowOnlyNames",
  "nameplatePlayerMaxDistance",
  "nameplateGameObjectMaxDistance",
  "nameplateMaxDistance",
  "nameplateTargetRadialPosition",
  "nameplateTargetBehindMaxDistance",
  "NameplatePersonalShowAlways",
  "NameplatePersonalShowInCombat",
  "NameplatePersonalShowWithTarget",
  "UnitNameFriendlyPlayerName",
}

local function snapshotNameplates()
  local t = {}
  for _, key in ipairs(NAMEPLATE_CVARS) do
    local v = C_CVar.GetCVar(key)
    if v ~= nil then
      t[key] = v
    end
  end
  return t
end

local function applyNameplateSnapshot(t)
  if not t then
    return
  end
  for k, v in pairs(t) do
    if v ~= nil then
      pcall(C_CVar.SetCVar, k, v)
    end
  end
end

-- Seeker mode: force everything off.
local function hideAllNameplates()
  for _, key in ipairs(NAMEPLATE_CVARS) do
    pcall(C_CVar.SetCVar, key, "0")
  end
end

-- While seeker: keep default party/raid (and optionally minimap) hidden — Blizz re-shows often, so we poll.
local SEEKER_UI_HIDE_FRAMES = {
  "PartyFrame",
  "CompactPartyFrame",
  "CompactRaidFrameContainer",
  "CompactRaidFrameManager",
}

local seekerUiPoll = CreateFrame("Frame")
seekerUiPoll:Hide()
seekerUiPoll:SetScript("OnUpdate", function(self, elapsed)
  self._acc = (self._acc or 0) + elapsed
  if self._acc < 0.35 then
    return
  end
  self._acc = 0
  if not State.seekerMode then
    return
  end
  NHS.EnsureSavedVars()
  if NHSV.hideGroupFramesInSeeker then
    for _, fname in ipairs(SEEKER_UI_HIDE_FRAMES) do
      local fr = _G[fname]
      if fr and fr.IsShown and fr:IsShown() then
        fr:Hide()
      end
    end
  end
  if NHSV.hideMinimapInSeeker then
    local mc = _G.MinimapCluster
    if mc and mc.IsShown and mc:IsShown() then
      mc:Hide()
    end
  end
end)

local function seekerUiSuppressActive()
  NHS.EnsureSavedVars()
  return State.seekerMode and (NHSV.hideGroupFramesInSeeker or NHSV.hideMinimapInSeeker)
end

local function seekerUiSuppressStart()
  if seekerUiSuppressActive() then
    seekerUiPoll:Show()
  end
end

local function seekerUiSuppressStop()
  seekerUiPoll:Hide()
  for _, fname in ipairs(SEEKER_UI_HIDE_FRAMES) do
    local fr = _G[fname]
    if fr and fr.Show then
      pcall(fr.Show, fr)
    end
  end
  local mc = _G.MinimapCluster
  if mc and mc.Show then
    pcall(mc.Show, mc)
  end
end

local function refreshMainUi()
  local ui = B.getUI()
  if ui and ui.RefreshAll then
    ui.RefreshAll()
  elseif NHS.RefreshGameSessionUi then
    NHS.RefreshGameSessionUi()
  elseif NHS.SessionHudUpdate then
    NHS.SessionHudUpdate()
  end
end

local function setSeekerMode(enabled)
  State.seekerMode = enabled and true or false
  if State.seekerMode then
    if not State.savedNameplateCVars then
      State.savedNameplateCVars = snapshotNameplates()
    end
    hideAllNameplates()
    seekerUiSuppressStart()
  else
    seekerUiSuppressStop()
    applyNameplateSnapshot(State.savedNameplateCVars)
    State.savedNameplateCVars = nil
    B.clearFound()
    State.selectedNeighborID = nil
    State.selectedLabel = nil
    State.selectedEntry = nil
    State.selectedIndex = nil
  end
  refreshMainUi()
end

NHS.SetSeekerMode = setSeekerMode
NHS.SeekerUiPoll = seekerUiPoll
NHS.SeekerUiSuppressStop = seekerUiSuppressStop
NHS.ApplyNameplateSnapshot = applyNameplateSnapshot

function NHS.OnPlayerLogoutSeekerCleanup()
  seekerUiSuppressStop()
  if State.seekerMode and State.savedNameplateCVars then
    applyNameplateSnapshot(State.savedNameplateCVars)
  end
end

-- Enter seeker mode: with no session/synced round, allow (preview nameplate/UI options). During a
-- session, only the designated seeker may enter, and only in Hiding or Searching (not pick-seeker,
-- preparing/pending, etc.).
local function nhsMayEnterSeekerMode()
  if not State.gameSessionActive and not State.remoteSessionActive and not State.remoteRoundActive then
    return true
  end
  if (State.gameSessionActive and (State.gamePhase == "pick_house" or State.gamePhase == "pick_seeker"))
    or (State.remoteSessionActive and not State.remoteRoundActive) then
    return false
  end
  if not NHS.LocalPlayerIsDesignatedSeeker() then
    return false
  end
  return State.roundPhase == "hiding" or State.roundPhase == "searching"
end

NHS.MayEnterSeekerMode = nhsMayEnterSeekerMode

-- After SetSeekerMode exists: auto-enable seeker mode in Hiding / Searching for the designated seeker.
local function nhsSeekerAutoModeSyncToPhase()
  if State.roundPhase ~= "hiding" and State.roundPhase ~= "searching" then
    return
  end
  if not NHS.LocalPlayerIsDesignatedSeeker() or not nhsMayEnterSeekerMode() then
    return
  end
  if State.seekerMode then
    return
  end
  setSeekerMode(true)
  print("|cff88ccff[NHS]|r Seeker mode enabled automatically for this phase.")
end

local bmf = NHS.BuildMainFrameBridge
if bmf then
  bmf.setSeekerMode = setSeekerMode
  bmf.nhsSeekerAutoModeSyncToPhase = nhsSeekerAutoModeSyncToPhase
end

local gsb = NHS.GroupSyncBridge
if gsb then
  gsb.nhsSeekerAutoModeSyncToPhase = nhsSeekerAutoModeSyncToPhase
end
