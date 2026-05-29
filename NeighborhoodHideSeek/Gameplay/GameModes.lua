--[[
  Round game modes (leader picks each round before house selection).
  Load after GameSession.lua; before PlayerRange.lua.
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State

local GAME_MODES = {
  normal = {
    id = "normal",
    label = "Normal",
    hudLabel = "Normal",
    hotColdIndicator = false,
    searchSecChange = 0,
    hideSecOverride = nil,
    seekers = 1,
    description = "the default game mode.",
    tooltip = "Standard hide and seek. No special rules.",
  },
  normal_plus = {
    id = "normal_plus",
    label = "Normal Plus",
    hudLabel = "Normal Plus",
    hotColdIndicator = true,  -- activates dynamically: only once 1 hider remains (see PlayerRange.lua)
    searchSecChange = 0,
    hideSecOverride = nil,
    seekers = 1,
    description = "like normal, but every 10 seconds the closest player to the seeker will roar. Also, once there is one hider left, the seeker will be given hot and cold information to where the last hider is.",
    warning = "Warning: Best to play this mode in a humanoid form. This game mode may cause your character to suddenly stand up — be prepared!",
    tooltip = "Like Normal, but the closest hider roars every 10s. When one hider remains, the seeker gets hot/cold distance hints.",
  },
  hot_cold = {
    id = "hot_cold",
    label = "Hot and Cold",
    hudLabel = "Hot and Cold",
    hotColdIndicator = true,
    searchSecChange = -90,
    hideSecOverride = nil,
    seekers = 1,
    description = "the seeker gets hot and cold information on how close they are to a hider. The search times are reduced.",
    tooltip = "The seeker always sees hot/cold distance hints. Shorter search time.",
  },
  paired = {
    id = "paired",
    label = "Paired",
    hudLabel = "Paired",
    hotColdIndicator = false,
    searchSecChange = -90,
    hideSecOverride = nil,
    seekers = 2,
    description = "the seeker is paired with another seeker. The search times are reduced.",
    tooltip = "Two seekers hunt together. Shorter search time.",
  },
  conquer = {
    id = "conquer",
    label = "Conquer",
    hudLabel = "Conquer",
    hotColdIndicator = false,
    searchSecChange = -60,
    hideSecOverride = nil,
    seekers = 1,
    description = "as the seeker finds players, those players become seekers. The search times are reduced.",
    tooltip = "Found players join the seeker team. Shorter search time.",
  },
  chosen_one = {
    id = "chosen_one",
    label = "Chosen One",
    hudLabel = "Chosen One",
    hotColdIndicator = false,
    searchSecChange = -90,
    hideSecOverride = nil,
    seekers = 0, -- one hider, others seekers
    description = "one hider, the rest are seekers. The search times are reduced.",
    tooltip = "One player hides while everyone else seeks. Shorter search time.",
  },
  lightning = {
    id = "lightning",
    label = "Lightning",
    hudLabel = "Lightning",
    hotColdIndicator = false,
    searchSecChange = -60,
    hideSecOverride = 30,
    seekers = 1,
    description = "hiders only get 30 seconds to hide. The search times are reduced.",
    tooltip = "Only 30 seconds to hide. Shorter search time.",
  },
  overtime = {
    id = "overtime",
    label = "Overtime",
    hudLabel = "Overtime",
    hotColdIndicator = false,
    searchSecChange = 0,
    hideSecOverride = 60,
    searchSecOverride = 90,
    seekers = 1,
    description = "hiders get 60 seconds to hide. Seekers start with 90 seconds to search, but each player found adds 30 seconds back to the clock.",
    tooltip = "60s to hide, 90s to seek. Each player found adds 30s back to the clock.",
  },
}

NHS.GAME_MODES = GAME_MODES
NHS.GAME_MODE_IDS = { "normal", "normal_plus", "hot_cold", "paired", "conquer", "chosen_one", "lightning", "overtime" }

function NHS.IsValidGameMode(modeId)
  return type(modeId) == "string" and GAME_MODES[modeId] ~= nil
end

function NHS.GameModeDefinition(modeId)
  if NHS.IsValidGameMode(modeId) then
    return GAME_MODES[modeId]
  end
  return nil
end

function NHS.GameModeHudLabel(modeId)
  local def = NHS.GameModeDefinition(modeId)
  return def and def.hudLabel or nil
end

-- Reverse lookup: human-readable label → mode ID (case-insensitive).
-- Used so group-sync messages can carry the readable label and still be parsed.
function NHS.GameModeIdFromHudLabel(labelStr)
  if type(labelStr) ~= "string" or labelStr == "" then
    return nil
  end
  local lower = labelStr:lower()
  for id, def in pairs(GAME_MODES) do
    if def.hudLabel and def.hudLabel:lower() == lower then
      return id
    end
  end
  return nil
end

-- Leader: State.gameMode. Follower: State.remoteGameMode.
function NHS.GetEffectiveGameModeId()
  if State.gameSessionActive and State.gameMode then
    return State.gameMode
  end
  if State.remoteGameMode and NHS.IsValidGameMode(State.remoteGameMode) then
    return State.remoteGameMode
  end
  return nil
end

-- Returns the description string for a mode, or nil if none.
function NHS.GameModeDescription(modeId)
  local def = NHS.GameModeDefinition(modeId)
  return def and def.description or nil
end

-- Returns the warning string for a mode, or nil if none.
function NHS.GameModeWarning(modeId)
  local def = NHS.GameModeDefinition(modeId)
  return def and def.warning or nil
end

function NHS.GameModeAllowsHotColdIndicator()
  local id = NHS.GetEffectiveGameModeId()
  local def = id and GAME_MODES[id]
  return def and def.hotColdIndicator == true
end

-- True when the active mode uses seekers=0: one hider is picked, everyone else seeks.
function NHS.IsHiderMode()
  local id = NHS.GetEffectiveGameModeId()
  local def = id and GAME_MODES[id]
  return def ~= nil and def.seekers == 0
end

function NHS.GetRoundSearchSeconds(baseSec)
  baseSec = math.floor(tonumber(baseSec) or 0)
  if baseSec < 1 then
    return baseSec
  end
  local id = NHS.GetEffectiveGameModeId()
  local def = id and GAME_MODES[id]
  if def and def.searchSecOverride then
    return math.max(1, math.floor(def.searchSecOverride))
  end
  local change = (def and def.searchSecChange) or 0
  return math.max(1, baseSec + change)
end

function NHS.GetRoundHideSeconds(baseSec)
  baseSec = math.floor(tonumber(baseSec) or 0)
  if baseSec < 1 then
    return baseSec
  end
  local id = NHS.GetEffectiveGameModeId()
  local def = id and GAME_MODES[id]
  if def and def.hideSecOverride then
    return math.max(1, math.floor(def.hideSecOverride))
  end
  return baseSec
end

function NHS.IsOvertime()
  return NHS.GetEffectiveGameModeId() == "overtime"
end

-- Leader-only: called after each found in Overtime mode to add 30 s to the running clock.
function NHS.OvertimeOnFound()
  if not NHS.IsOvertime() then return end
  local bmf = NHS.BuildMainFrameBridge
  if not bmf or not bmf.nhsIsRoundLeader or not bmf.nhsIsRoundLeader() then return end
  if State.phase ~= NHS.Phase.SEARCHING then return end
  if not State.searchPhaseStartTime or not State.searchPhaseDuration then return end

  local elapsed = GetTime() - State.searchPhaseStartTime
  local remaining = math.max(0, State.searchPhaseDuration - elapsed)
  local newDur = math.floor(remaining + 30)
  if newDur < 1 then return end

  State.searchPhaseStartTime = GetTime()
  State.searchPhaseDuration = newDur

  if bmf.nhsStartBuiltInCountdown then
    bmf.nhsStartBuiltInCountdown(newDur)
  end

  if bmf.nhsBroadcastLeaderSync then
    local mins = math.floor(newDur / 60)
    local secs = newDur % 60
    local timeStr = mins > 0 and ("%dm %ds"):format(mins, secs) or ("%ds"):format(secs)
    bmf.nhsBroadcastLeaderSync(("[NHS] Overtime: +30s — %s remaining"):format(timeStr))
  end
end

function NHS.ClearRoundGameMode()
  State.gameMode = nil
  State.remoteGameMode = nil
end

function NHS.PastRoundModeSnapshotString()
  local id = NHS.GetEffectiveGameModeId()
  if id then
    return ("Mode: %s"):format(NHS.GameModeHudLabel(id) or id)
  end
  return "Mode: —"
end

local bmf = NHS.BuildMainFrameBridge
if bmf then
  bmf.nhsClearRoundGameMode = NHS.ClearRoundGameMode
end

local gsb = NHS.GroupSyncBridge
if gsb then
  gsb.nhsClearRoundGameMode = NHS.ClearRoundGameMode
end
