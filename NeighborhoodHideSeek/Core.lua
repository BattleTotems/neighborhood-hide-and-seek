--[[
  Neighborhood Hide & Seek — prototype (Retail Midnight housing neighborhoods).
  Target live client: 12.0.1 (TOC interface 120001). Verify with /dump select(4, GetBuildInfo()).
  Uses C_HousingNeighborhood / C_Housing for map/roster data; C_Map for waypoints/hyperlinks.
]]

-- Must match your AddOns folder name (used for ADDON_LOADED and SavedVariables).
local ADDON_NAME = "NeighborhoodHideSeek"
NeighborhoodHideSeek = NeighborhoodHideSeek or {}
NeighborhoodHideSeek.ADDON_NAME = ADDON_NAME

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
  -- Follower: last house line from leader chat sync.
  remoteHouseDisplay = nil,
  -- Round flow for leader + party/raid sync (followers listen to leader chat)
  roundPhase = "none", -- none | pending (preparing) | hiding | searching
  remoteRoundActive = false,
  remoteSeekerKey = nil,
  -- Follower: leader sent "[NHS] Game session started" (stays true until Game Over chat).
  remoteSessionActive = false,
  -- Raid leader: we PromoteToAssistant'd the seeker for RAID_WARNING; demote on round/session end.
  nhsSeekerPromotedAsAssistantKey = nil,
  -- Completed rounds this session (house+size / seeker / hidden / found); cleared on new session or game over.
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
    NeighborhoodHideSeek.InitMinimapButton()
    print(
      "|cff88ccff[NHS]|r Loaded. Minimap stealth icon or |cffffffff/nhs|r toggles the window. |cffffffff/nhs visitinfo|r explains Visit attempts. |cffffffff/run NHS_Toggle()|r if slash fails."
    )
  elseif event == "PLAYER_ENTERING_WORLD" then
    NeighborhoodHideSeek.EnsureSavedVars()
    NeighborhoodHideSeek.InitSessionHud()
    NeighborhoodHideSeek.InitMinimapButton()
    NeighborhoodHideSeek.HydrateGameSessionFromSaved()
    NeighborhoodHideSeek.PersistGameSessionToSaved()
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
    if not IsInGroup() and State.remoteRoundActive then
      NeighborhoodHideSeek.GroupSync.ClearRemoteRound()
    end
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
