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
  bloodhound = {
    id = "bloodhound",
    label = "Bloodhound",
    hudLabel = "Bloodhound",
    hotColdIndicator = false,
    searchSecChange = 0,
    hideSecOverride = nil,
    seekers = 1,
    description = "hiders must keep moving. After an initial grace period, the seeker receives a directional arrow pointing to whichever hider has been stationary the longest. The arrow updates every 6 seconds and its color shifts from blue to red as the seeker closes in.",
    tooltip = "Hiders must keep moving. Every 6s the seeker gets an arrow to the longest-stationary hider. Arrow color shows distance: blue is far, red is close.",
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
  chosen_one = {
    id = "chosen_one",
    label = "Chosen One",
    hudLabel = "Chosen One",
    hotColdIndicator = false,
    searchSecChange = -30,
    searchSecChangePerSeeker = -15,
    hideSecOverride = nil,
    seekers = 0, -- one hider, others seekers
    description = "one hider, the rest are seekers. The search time is reduced by 15 seconds per seeker.",
    tooltip = "One player hides while everyone else seeks. Search time is reduced by 15 seconds per seeker.",
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
  sardines = {
    id = "sardines",
    label = "Sardines",
    hudLabel = "Sardines",
    hotColdIndicator = false,
    searchSecChange = 0,
    hideSecOverride = nil,
    seekers = 0,
    description = "one player hides (the sardine). When a seeker finds the sardine they squeeze in and hide too. The round ends when all seekers have joined, or time runs out.",
    tooltip = "One player hides. Seekers who find them join the pile until no seekers remain.",
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
    searchSecChangePerHider = 10,
    searchSecPerFind = 45,
    hideSecOverride = 60,
    searchSecOverride = 60,
    seekers = 1,
    description = "hiders get 60 seconds to hide. Seekers start with 60 seconds to search plus 10 seconds per hider, and each player found adds 45 seconds back to the clock.",
    tooltip = "60s to hide, 60s + 10s per hider to seek. Each player found adds 45s back to the clock.",
  },
  toy_and_seek = {
    id = "toy_and_seek",
    label = "Toying Around",
    hudLabel = "Toying Around",
    hotColdIndicator = false,
    searchSecChange = 0,
    hideSecOverride = nil,
    seekers = 1,
    description = "hiders get a button (30-second cooldown) that uses a random toy from the group's common pool and sends a random hindrance to the seeker. Requires all group members to own at least one toy in common.",
    tooltip = "Hiders use toys to disguise themselves and prank the seeker. Common toy pool required.",
  },
  hot_potato = {
    id = "hot_potato",
    label = "Hot Potato",
    hudLabel = "Hot Potato",
    hotColdIndicator = false,
    searchSecChange = 0,
    hideSecOverride = 60,
    seekers = 1,
    description = "hiders get 60 seconds to hide. When the seeker finds a hider they swap roles — no tagbacks. Whoever is still the seeker when time runs out loses.",
    tooltip = "Seeker and found hider swap roles. No tagbacks. Last seeker when time runs out loses.",
  },
}

NHS.GAME_MODES = GAME_MODES
NHS.GAME_MODE_IDS = { "normal", "normal_plus", "hot_cold", "bloodhound", "paired", "chosen_one", "conquer", "sardines", "lightning", "overtime", "toy_and_seek", "hot_potato" }

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

function NHS.IsSardinesMode()
  return NHS.GetEffectiveGameModeId() == "sardines"
end

function NHS.IsHotPotatoMode()
  return NHS.GetEffectiveGameModeId() == "hot_potato"
end

local MIN_SEARCH_SECONDS = 120

function NHS.GetRoundSearchSeconds(baseSec)
  baseSec = math.floor(tonumber(baseSec) or 0)
  if baseSec < 1 then
    return baseSec
  end
  local id = NHS.GetEffectiveGameModeId()
  local def = id and GAME_MODES[id]
  local groupSize = IsInGroup() and GetNumGroupMembers() or 1
  local change = (def and def.searchSecChange) or 0
  if def and def.searchSecChangePerSeeker then
    -- Hider mode (seekers=0): one player hides, everyone else seeks.
    local seekerCount = (def.seekers == 0) and math.max(0, groupSize - 1) or def.seekers
    change = change + def.searchSecChangePerSeeker * seekerCount
  end
  if def and def.searchSecChangePerHider then
    -- Hider mode (seekers=0): exactly one hider.
    local hiderCount = (def.seekers == 0) and 1 or math.max(0, groupSize - def.seekers)
    change = change + def.searchSecChangePerHider * hiderCount
  end
  if def and def.searchSecOverride then
    -- Override sets an absolute base; per-seeker/hider changes still apply on top.
    -- MIN_SEARCH_SECONDS does not apply — the override is intentional.
    return math.max(1, math.floor(def.searchSecOverride) + change)
  end
  -- Floor is min(baseSec, MIN_SEARCH_SECONDS) so we never inadvertently raise a
  -- sub-120 baseSec, but large groups with per-seeker/hider changes always get at least 120s.
  local floor = math.min(baseSec, MIN_SEARCH_SECONDS)
  return math.max(floor, baseSec + change)
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

-- Leader-only: called on each find. Adds searchSecPerFind seconds to the running clock
-- for any mode that defines that field.
function NHS.OvertimeOnFound()
  local id = NHS.GetEffectiveGameModeId()
  local def = id and GAME_MODES[id]
  local bonus = def and def.searchSecPerFind
  if not bonus or bonus <= 0 then return end
  local bmf = NHS.BuildMainFrameBridge
  if not bmf or not bmf.nhsIsRoundLeader or not bmf.nhsIsRoundLeader() then return end
  if State.phase ~= NHS.Phase.SEARCHING then return end
  if not State.searchPhaseStartTime or not State.searchPhaseDuration then return end

  local elapsed = GetTime() - State.searchPhaseStartTime
  local remaining = math.max(0, State.searchPhaseDuration - elapsed)
  local newDur = math.floor(remaining + bonus)
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
    bmf.nhsBroadcastLeaderSync(("[NHS] +%ds — %s remaining"):format(bonus, timeStr))
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
