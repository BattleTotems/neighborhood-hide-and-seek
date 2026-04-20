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
  gamePhase = "none", -- none | pick_house | pick_seeker | round_active
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
  gameCandidateKey = nil,
  gameCandidateDisplay = nil,
  gameLockedSeekerKey = nil,
  gameLockedSeekerDisplay = nil,
  gameSeekerHistory = {},
  gameRotationUsed = {},
  -- Follower: last house line from leader addon sync (same text may appear in party/raid when out of combat).
  remoteHouseDisplay = nil,
  -- Round flow: leader/seeker addon messages; optional party/raid chat for players when not in combat lockdown.
  roundPhase = "none", -- none | pending (preparing) | hiding | searching
  remoteRoundActive = false,
  remoteSeekerKey = nil,
  -- Follower: leader sent "[NHS] Game session started" (stays true until Game Over chat).
  remoteSessionActive = false,
  -- Follower: mirrors leader gamePhase during setup (pick_house | pick_seeker) and round_active; none when idle.
  remoteLeaderGamePhase = "none",
  -- Raid leader: we PromoteToAssistant'd the seeker for RAID_WARNING; demote on round/session end.
  nhsSeekerPromotedAsAssistantKey = nil,
  -- Completed rounds for the current or last-ended session (house+size / seeker / hidden / found).
  -- Cleared when a new game session starts. After a session ends, data stays in memory and is
  -- written to NHSV.lastCompletedPastRounds for /reload; hydrate loads that when no active
  -- NHSV.gameRounds session exists (see GameSession.lua).
  pastRounds = {},
}

NeighborhoodHideSeek.State = State

local function clearFound()
  wipe(State.foundOrder)
  wipe(State.foundSet)
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
-- tear down group session + seeker mode when the local player actually leaves a group (not
-- for solo-only game session / seeker preview, which never had wasInGroup = true).
local wasInGroup = false

local function nhsSyncGroupLeaveCleanup()
  local NHS = NeighborhoodHideSeek
  local inGroup = IsInGroup()

  if wasInGroup and not inGroup then
    local B = NHS.BuildMainFrameBridge
    if B and B.nhsResetGameSession then
      B.nhsResetGameSession()
    else
      if NHS.GroupSync and NHS.GroupSync.ClearRemoteRound and State.remoteRoundActive then
        NHS.GroupSync.ClearRemoteRound()
      end
      if State.seekerMode and NHS.SetSeekerMode then
        NHS.SetSeekerMode(false)
      end
    end
  end

  if not inGroup and State.remoteRoundActive and NHS.GroupSync and NHS.GroupSync.ClearRemoteRound then
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
