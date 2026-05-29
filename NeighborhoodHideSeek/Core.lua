--[[
  Neighborhood Hide & Seek — prototype (Retail Midnight housing neighborhoods).
  Target live client: 12.0.1 (TOC interface 120001). Verify with /dump select(4, GetBuildInfo()).
  Uses C_HousingNeighborhood / C_Housing for map/roster data; C_Map for waypoints/hyperlinks.
]]

-- Must match your AddOns folder name (used for ADDON_LOADED and SavedVariables).
local ADDON_NAME = "NeighborhoodHideSeek"
NeighborhoodHideSeek = NeighborhoodHideSeek or {}
NeighborhoodHideSeek.ADDON_NAME = ADDON_NAME

do
  local function readAddonVersionFromMetadata()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
      local v = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
      if type(v) == "string" and strtrim(v) ~= "" then
        return strtrim(v)
      end
    end
    if type(GetAddOnMetadata) == "function" then
      local v = GetAddOnMetadata(ADDON_NAME, "Version")
      if type(v) == "string" and strtrim(v) ~= "" then
        return strtrim(v)
      end
    end
    return nil
  end
  local v = readAddonVersionFromMetadata()
  NeighborhoodHideSeek.ADDON_VERSION = v
  NeighborhoodHideSeek.ADDON_VERSION_DISPLAY = v and ("Version " .. v) or "Version —"
end

-- Unified phase enumeration (string values for saved-variable compatibility).
-- Setup phases: PICK_HOUSE → PICK_GAME_MODE → PICK_SEEKER.
-- Round phases: PENDING → HIDING → SEARCHING → REVEALING (see IsRoundPhase).
NeighborhoodHideSeek.Phase = {
  NONE           = "none",
  PICK_GAME_MODE = "pick_game_mode",
  PICK_HOUSE     = "pick_house",
  PICK_SEEKER    = "pick_seeker",
  PENDING        = "pending",
  HIDING         = "hiding",
  SEARCHING      = "searching",
  REVEALING      = "revealing",
}

local Phase = NeighborhoodHideSeek.Phase

local function nhsIsRoundPhase(phase)
  return phase == Phase.PENDING or phase == Phase.HIDING
    or phase == Phase.SEARCHING or phase == Phase.REVEALING
end
NeighborhoodHideSeek.IsRoundPhase = nhsIsRoundPhase

-- Ephemeral session state (not saved between sessions).
local State = {
  seekerMode = false,
  savedNameplateCVars = nil,
  -- Discovery order (keys = Ambiguate(..., "none")); foundSet avoids duplicates.
  foundOrder = {},
  foundSet = {},
  selectedNeighborID = nil,
  selectedLabel = nil,
  selectedEntry = nil,
  selectedIndex = nil,
  -- Leader-only game rounds (ephemeral; lost on reload)
  gameSessionActive = false,
  phase = Phase.NONE, -- unified phase: setup (pick_game_mode/house/seeker) or round (pending/hiding/searching/revealing)
  gameMode = nil, -- normal | hot_cold (leader; cleared each round until re-picked)
  remoteGameMode = nil, -- follower mirror of leader's mode for current round
  -- Leader: once per session — neighborhood | saved | group (nil = not chosen yet).
  gameSessionHouseListSource = nil,
  gameHouseCandidateKey = nil,
  gameHouseCandidateDisplay = nil,
  gameLockedHouseKey = nil,
  gameLockedHouseDisplay = nil,
  gameLockedHouseLiveEntry = nil,
  gameLockedHouseLiveIndex = nil,
  gameHouseRotationUsed = {},
  gameHouseHistory = {},
  gameCandidateKeys = {},    -- list of seeker candidates being built (not yet confirmed)
  gameLockedSeekerKeys = {}, -- confirmed seeker keys for the current round
  gameSeekerHistory = {},
  gameRotationUsed = {},
  -- Follower: last house line from leader addon sync (same text may appear in party/raid when out of combat).
  remoteHouseDisplay = nil,
  -- Round flow: leader/seeker addon messages; optional party/raid chat for players when not in combat lockdown.
  remoteSeekerKeys = {},     -- follower mirror of leader's seeker key list for this round
  -- Follower: leader sent "[NHS] Game session started" (stays true until Game Over chat).
  remoteSessionActive = false,
  -- Raid leader: we PromoteToAssistant'd seekers for RAID_WARNING; demote on round/session end.
  nhsSeekerPromotedAsAssistantKeys = {},
  -- Completed rounds for the current or last-ended session (house+size / seeker / hidden / found).
  -- Cleared when a new game session starts. After a session ends, data stays in memory and is
  -- written to NHSV.lastCompletedPastRounds for /reload; hydrate loads that when no active
  -- NHSV.gameRounds session exists (see GameSession.lua).
  pastRounds = {},
  -- Time Trial: leader tracks when the search phase started and its duration so +60s on find works.
  searchPhaseStartTime = nil,
  searchPhaseDuration = nil,
  -- Hiders who clicked "I'm Hidden!" during the hiding phase (keys = Ambiguate(..., "none")).
  hiderReadySet = {},
}

NeighborhoodHideSeek.State = State

local function clearFound()
  wipe(State.foundOrder)
  wipe(State.foundSet)
  wipe(State.hiderReadySet)
end

-- --- Game rounds (party/raid leader) ----------------------------------------
-- UI table exists early for GROUP_ROSTER_UPDATE / PARTY_LEADER_CHANGED refresh hooks.
local UI = {}
NeighborhoodHideSeek.SeekerModeBridge = {
  clearFound = clearFound,
  getUI = function()
    return UI
  end,
}

-- SavedVarsDefaults.lua → EnsureSavedVars; Gameplay/* and Ui/MainFrameToggle.lua patch bridges.
NeighborhoodHideSeek.BuildMainFrameBridge = {
  clearFound = clearFound,
}

NeighborhoodHideSeek.GroupSyncBridge = {
  State = State,
  UI = UI,
  clearFound = clearFound,
}

-- Used with GROUP_ROSTER_UPDATE / PARTY_LEADER_CHANGED / PLAYER_ENTERING_WORLD so we only
-- tear down an active game session when the local player actually leaves a group (not when
-- leaving an unrelated party, and not for solo-only session / seeker preview).
local wasInGroup = false

local function nhsSyncGroupLeaveCleanup()
  local NHS = NeighborhoodHideSeek
  local inGroup = IsInGroup()

  if wasInGroup and not inGroup then
    local hadSession = State.gameSessionActive or State.remoteSessionActive
    if hadSession then
      local B = NHS.BuildMainFrameBridge
      if B and B.nhsResetGameSession then
        B.nhsResetGameSession()
      else
        if NHS.GroupSync and NHS.GroupSync.ClearRemoteRound and nhsIsRoundPhase(State.phase) then
          NHS.GroupSync.ClearRemoteRound()
        end
        if State.seekerMode and NHS.SetSeekerMode then
          NHS.SetSeekerMode(false)
        end
      end
    end
  end

  if not inGroup and State.remoteSessionActive and nhsIsRoundPhase(State.phase) and NHS.GroupSync and NHS.GroupSync.ClearRemoteRound then
    NHS.GroupSync.ClearRemoteRound()
  end

  wasInGroup = inGroup
end

local loader = CreateFrame("Frame")
local didPewImport
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_LOGOUT")
loader:RegisterEvent("GROUP_ROSTER_UPDATE")
loader:RegisterEvent("PARTY_LEADER_CHANGED")
loader:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON_NAME then
    NeighborhoodHideSeek.EnsureSavedVars()
    NeighborhoodHideSeek.InitSessionHud()
    NeighborhoodHideSeek.HydrateGameSessionFromSaved()
    NeighborhoodHideSeek.PersistGameSessionToSaved()
    if NeighborhoodHideSeek.GroupSync and NeighborhoodHideSeek.GroupSync.LeaderRebroadcastActiveRoundPhaseIfNeeded then
      NeighborhoodHideSeek.GroupSync.LeaderRebroadcastActiveRoundPhaseIfNeeded()
    end
    NeighborhoodHideSeek.InitMinimapButton()
    C_Timer.After(0, function()
      if NeighborhoodHideSeek.InitBlizzardSettingsAboutOnly then
        NeighborhoodHideSeek.InitBlizzardSettingsAboutOnly()
      end
    end)
    print(
      "|cff88ccff[NHS]|r Loaded. Minimap stealth icon or |cffffffff/nhs|r toggles the window. |cffffffff/nhs visitinfo|r explains Visit attempts. |cffffffff/run NHS_Toggle()|r if slash fails."
    )
    wasInGroup = IsInGroup()
  elseif event == "PLAYER_ENTERING_WORLD" then
    NeighborhoodHideSeek.EnsureSavedVars()
    NeighborhoodHideSeek.InitSessionHud()
    NeighborhoodHideSeek.InitMinimapButton()
    NeighborhoodHideSeek.HydrateGameSessionFromSaved()
    NeighborhoodHideSeek.PersistGameSessionToSaved()
    if NeighborhoodHideSeek.GroupSync and NeighborhoodHideSeek.GroupSync.LeaderRebroadcastActiveRoundPhaseIfNeeded then
      NeighborhoodHideSeek.GroupSync.LeaderRebroadcastActiveRoundPhaseIfNeeded()
    end
    nhsSyncGroupLeaveCleanup()
    if UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    end
    NeighborhoodHideSeek.SessionHudUpdate()
    if not didPewImport then
      didPewImport = true
      NeighborhoodHideSeek.HousingApi.Invalidate()
      if NeighborhoodHideSeek.ChatImportSlashCommands then
        NeighborhoodHideSeek.ChatImportSlashCommands()
      end
    end
  elseif event == "PLAYER_LOGOUT" then
    NeighborhoodHideSeek.PersistGameSessionToSaved()
    if NeighborhoodHideSeek.OnPlayerLogoutSeekerCleanup then
      NeighborhoodHideSeek.OnPlayerLogoutSeekerCleanup()
    end
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
    nhsSyncGroupLeaveCleanup()
    if UI.RefreshAll then
      UI.RefreshAll()
    elseif UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    elseif NeighborhoodHideSeek.RefreshGameSessionUi then
      NeighborhoodHideSeek.RefreshGameSessionUi()
    elseif NeighborhoodHideSeek.SessionHudUpdate then
      NeighborhoodHideSeek.SessionHudUpdate()
    end
  end
end)
