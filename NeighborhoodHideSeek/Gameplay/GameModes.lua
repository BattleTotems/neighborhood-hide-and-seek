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
  },
}

NHS.GAME_MODES = GAME_MODES
NHS.GAME_MODE_IDS = { "normal", "normal_plus", "hot_cold", "paired", "conquer", "chosen_one", "lightning" }

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
