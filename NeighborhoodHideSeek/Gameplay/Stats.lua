--[[
  Per-character lifetime stats: schema init/migration, phase clock, session and round accumulation.
  Load after Core.lua and SavedVarsDefaults.lua; before GameSession.lua and GroupSync.lua.
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------

local function nhsEnsureCharStats(charKey)
  if not charKey then return nil end
  NHS.EnsureSavedVars()
  NHSV.charStats = NHSV.charStats or {}
  if not NHSV.charStats[charKey] then
    NHSV.charStats[charKey] = { statsVersion = 1 }
  end
  local s = NHSV.charStats[charKey]
  s.statsVersion        = s.statsVersion        or 1
  s.roundsPlayed        = s.roundsPlayed        or 0
  s.roundsAsSeeker      = s.roundsAsSeeker      or 0
  s.roundsAsHider       = s.roundsAsHider       or 0
  s.seekerWins          = s.seekerWins          or 0
  s.hiderSurvivals      = s.hiderSurvivals      or 0
  s.timesFirstFound     = s.timesFirstFound     or 0
  s.timesLastFound      = s.timesLastFound      or 0
  s.hotPotatoLosses     = s.hotPotatoLosses     or 0
  s.hotPotatoWins       = s.hotPotatoWins       or 0
  s.secondsSearching    = s.secondsSearching    or 0
  s.secondsHiding       = s.secondsHiding       or 0
  s.totalSessionSeconds = s.totalSessionSeconds or 0
  -- Migrate from old separate sessionsStarted/sessionsCompleted to a single sessionsPlayed.
  if not s.sessionsPlayed then
    s.sessionsPlayed = s.sessionsStarted or 0
  end
  s.sessionsPlayed     = s.sessionsPlayed     or 0
  s.totalRoundCount    = s.totalRoundCount    or 0
  s.houseCounts        = type(s.houseCounts)        == "table" and s.houseCounts        or {}
  -- Migrate legacy house stat keys to canonical "player:Name-Realm" format (statsVersion → 3).
  -- v1→3: first-time migration of persistence keys, bare stable keys, group: keys, display names.
  -- v2→3: fixes bugged "player:Plot - Name" keys produced by an earlier run with a search bug.
  if (s.statsVersion or 1) < 3 then
    local S = NHS.SavedHouses
    if S and S.MigrateHouseCountsToPlayerKeys and S.MigrateHouseCountsToPlayerKeys(s.houseCounts) then
      s.statsVersion = 3
    end
  end
  s.modeCounts         = type(s.modeCounts)         == "table" and s.modeCounts         or {}
  s.modeSeekerWins     = type(s.modeSeekerWins)     == "table" and s.modeSeekerWins     or {}
  s.modeHiderSurvivals = type(s.modeHiderSurvivals) == "table" and s.modeHiderSurvivals or {}
  s.modeSeekerRounds   = type(s.modeSeekerRounds)   == "table" and s.modeSeekerRounds   or {}
  s.modeHiderRounds    = type(s.modeHiderRounds)     == "table" and s.modeHiderRounds    or {}
  s.playerEncounters   = type(s.playerEncounters)   == "table" and s.playerEncounters   or {}
  return s
end

-- ---------------------------------------------------------------------------
-- Phase clock  (flushed at every phase transition; lost on logout = at most one phase of data)
-- ---------------------------------------------------------------------------

local function nhsFlushPhaseClock()
  local now = time()
  if State.statsPhaseStartTime then
    local charKey = NHS.LocalCharacterKey
    if charKey then
      local elapsed = math.max(0, now - State.statsPhaseStartTime)
      if elapsed > 0 then
        local s = nhsEnsureCharStats(charKey)
        if s then s.totalSessionSeconds = s.totalSessionSeconds + elapsed end
      end
    end
    State.statsPhaseStartTime = nil
  end
  if IsInGroup() then
    State.statsPhaseStartTime = now
  end
end

local function nhsStartPhaseClock()
  if not IsInGroup() then return end
  State.statsPhaseStartTime = time()
end

local function nhsEndPhaseClock()
  if not State.statsPhaseStartTime then return end
  local charKey = NHS.LocalCharacterKey
  if charKey then
    local elapsed = math.max(0, time() - State.statsPhaseStartTime)
    if elapsed > 0 then
      local s = nhsEnsureCharStats(charKey)
      if s then s.totalSessionSeconds = s.totalSessionSeconds + elapsed end
    end
  end
  State.statsPhaseStartTime = nil
end

-- ---------------------------------------------------------------------------
-- Session start  (clock + sessionsPlayed in one call)
-- ---------------------------------------------------------------------------

local function nhsRecordSessionStart()
  if not IsInGroup() then return end
  nhsStartPhaseClock()
  local charKey = NHS.LocalCharacterKey
  if not charKey then return end
  local s = nhsEnsureCharStats(charKey)
  if s then s.sessionsPlayed = s.sessionsPlayed + 1 end
end

-- ---------------------------------------------------------------------------
-- Round accumulation
-- ---------------------------------------------------------------------------

local function nhsAccumulateRoundStats()
  if not IsInGroup() then return end
  local charKey = NHS.LocalCharacterKey
  if not charKey then return end

  local s = nhsEnsureCharStats(charKey)
  if not s then return end

  local modeId      = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
  local isSardines  = NHS.IsSardinesMode  and NHS.IsSardinesMode()
  local isHotPotato = NHS.IsHotPotatoMode and NHS.IsHotPotatoMode()

  local myKey = NHS.LocalPlayerSortKey and NHS.LocalPlayerSortKey()
  if not myKey then return end

  -- Initial seeker keys for this round (captured at HIDING/SEARCHING for leader; at Round Start for follower).
  local initSeekers = State.gameRoundInitialSeekerKeys
  if not initSeekers or #initSeekers == 0 then
    initSeekers = State.gameSessionActive and State.gameLockedSeekerKeys or State.remoteSeekerKeys
  end
  initSeekers = initSeekers or {}

  local iWasSeeker = false
  for _, k in ipairs(initSeekers) do
    if NHS.RosterIdentityEqual and NHS.RosterIdentityEqual(myKey, k) then
      iWasSeeker = true
      break
    end
  end
  local iWasHider = not iWasSeeker

  local iWasFound = false
  if iWasHider then
    for _, k in ipairs(State.foundOrder) do
      if NHS.RosterIdentityEqual and NHS.RosterIdentityEqual(myKey, k) then
        iWasFound = true
        break
      end
    end
  end

  local roster = NHS.GetGroupRoster and NHS.GetGroupRoster() or {}
  local allHidersFound = false
  if not isHotPotato and not isSardines and #initSeekers > 0 then
    local seekerSet = {}
    for _, k in ipairs(initSeekers) do seekerSet[k] = true end
    local anyHider, anyUnfound = false, false
    for _, m in ipairs(roster) do
      if not seekerSet[m.key] then
        anyHider = true
        if not State.foundSet[m.key] then anyUnfound = true; break end
      end
    end
    allHidersFound = anyHider and not anyUnfound
  end

  -- Round counts
  s.roundsPlayed    = s.roundsPlayed    + 1
  s.totalRoundCount = s.totalRoundCount + 1
  if iWasSeeker then s.roundsAsSeeker = s.roundsAsSeeker + 1 end
  if iWasHider  then s.roundsAsHider  = s.roundsAsHider  + 1 end
  if modeId then
    s.modeCounts[modeId] = (s.modeCounts[modeId] or 0) + 1
    if iWasSeeker then s.modeSeekerRounds[modeId] = (s.modeSeekerRounds[modeId] or 0) + 1 end
    if iWasHider  then s.modeHiderRounds[modeId]  = (s.modeHiderRounds[modeId]  or 0) + 1 end
  end

  -- Performance stats (win conditions per game mode)
  if isHotPotato then
    -- Hot Potato: final seeker at reveal = loss; everyone else = win.
    -- Does not contribute to generic seekerWins/hiderSurvivals.
    local currentSeekers = State.gameSessionActive and State.gameLockedSeekerKeys or State.remoteSeekerKeys
    local finalSeeker = currentSeekers and currentSeekers[1]
    if finalSeeker then
      if NHS.RosterIdentityEqual and NHS.RosterIdentityEqual(myKey, finalSeeker) then
        s.hotPotatoLosses = s.hotPotatoLosses + 1
      else
        s.hotPotatoWins = s.hotPotatoWins + 1
      end
    end
  elseif isSardines then
    -- Sardines: seekers win as a team when all seekers have joined the sardine pile.
    -- Sardine (hider) wins = time ran out before all seekers joined.
    local allSeekersJoined = #initSeekers > 0
    if allSeekersJoined then
      for _, k in ipairs(initSeekers) do
        if not State.foundSet[k] then allSeekersJoined = false; break end
      end
    end
    if iWasHider then
      if not allSeekersJoined then
        s.hiderSurvivals = s.hiderSurvivals + 1
        if modeId then s.modeHiderSurvivals[modeId] = (s.modeHiderSurvivals[modeId] or 0) + 1 end
      end
    else
      if allSeekersJoined then
        s.seekerWins = s.seekerWins + 1
        if modeId then s.modeSeekerWins[modeId] = (s.modeSeekerWins[modeId] or 0) + 1 end
      end
    end
  else
    -- Standard modes (Normal, Normal Plus, Hot & Cold, Bloodhound, Paired, Conquer,
    -- Chosen One, Lightning, Overtime, Toying Around):
    -- Seeker wins = all hiders found; hider survives = not found at reveal.
    if iWasSeeker then
      if allHidersFound then
        s.seekerWins = s.seekerWins + 1
        if modeId then s.modeSeekerWins[modeId] = (s.modeSeekerWins[modeId] or 0) + 1 end
      end
    else
      if not iWasFound then
        s.hiderSurvivals = s.hiderSurvivals + 1
        if modeId then s.modeHiderSurvivals[modeId] = (s.modeHiderSurvivals[modeId] or 0) + 1 end
      end
      if #State.foundOrder > 0 then
        if NHS.RosterIdentityEqual and NHS.RosterIdentityEqual(myKey, State.foundOrder[1]) then
          s.timesFirstFound = s.timesFirstFound + 1
        end
        if NHS.RosterIdentityEqual and NHS.RosterIdentityEqual(myKey, State.foundOrder[#State.foundOrder]) and allHidersFound then
          s.timesLastFound = s.timesLastFound + 1
        end
      end
    end
  end

  -- Search-phase time (uses original start time to survive Overtime resets).
  local elapsed = 0
  if State.gameSessionActive then
    local t = State.searchPhaseOriginalStartTime or State.searchPhaseStartTime
    if t then elapsed = math.max(0, math.floor(GetTime() - t)) end
  elseif State.remoteSessionActive and State.followerSearchPhaseStartTime then
    elapsed = math.max(0, math.floor(GetTime() - State.followerSearchPhaseStartTime))
  end
  if elapsed > 0 then
    if iWasSeeker then
      s.secondsSearching = s.secondsSearching + elapsed
    else
      s.secondsHiding = s.secondsHiding + elapsed
    end
  end

  -- House stats
  local houseKey, houseDisplay
  if State.gameSessionActive then
    houseKey     = State.gameLockedHouseKey
    houseDisplay = State.gameLockedHouseDisplay
  else
    houseKey     = State.remoteHouseKey
    houseDisplay = State.remoteHouseDisplay
  end
  local houseStatKey
  local SH = NHS.SavedHouses
  if SH and SH.CanonicalHouseStatKey then
    houseStatKey = SH.CanonicalHouseStatKey(houseKey, houseDisplay)
  end
  houseStatKey = houseStatKey or (houseKey ~= "" and houseKey) or houseDisplay
  if houseStatKey and houseStatKey ~= "" then
    local hc = s.houseCounts[houseStatKey] or { display = houseDisplay or houseStatKey, count = 0 }
    hc.count = hc.count + 1
    -- Keep the richest display seen so far rather than always overwriting.
    if houseDisplay and houseDisplay ~= "" and #houseDisplay > #(hc.display or "") then
      hc.display = houseDisplay
    end
    s.houseCounts[houseStatKey] = hc
  end
  -- Player encounters
  for _, m in ipairs(roster) do
    if NHS.RosterIdentityEqual and not NHS.RosterIdentityEqual(myKey, m.key) then
      local pe = s.playerEncounters[m.key]
      if not pe then
        pe = { display = m.display, count = 0 }
        s.playerEncounters[m.key] = pe
      end
      pe.count   = pe.count + 1
      pe.display = m.display
    end
  end
end

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

NHS.EnsureCharStats      = nhsEnsureCharStats
NHS.FlushPhaseClock      = nhsFlushPhaseClock
NHS.StartPhaseClock      = nhsStartPhaseClock
NHS.EndPhaseClock        = nhsEndPhaseClock
NHS.RecordSessionStart   = nhsRecordSessionStart
NHS.AccumulateRoundStats = nhsAccumulateRoundStats
