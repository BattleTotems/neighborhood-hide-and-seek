--[[
  Party/raid roster, leader checks, Blizzard party countdown, NHSV.gameRounds persistence,
  and past-round snapshot helpers. Patches BuildMainFrameBridge + GroupSyncBridge.
  Load after Core.lua and before SessionHud.lua (roster must exist on the bridge).
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State
local Phase = NHS.Phase
local IsRoundPhase = NHS.IsRoundPhase
local B = assert(NHS.SeekerModeBridge, "NeighborhoodHideSeek.SeekerModeBridge missing (load order).")

local function ensureSavedVars()
  NHS.EnsureSavedVars()
end

local function clearFound()
  B.clearFound()
end

local function nhsUnitSortKey(unit)
  if not UnitExists(unit) then
    return nil
  end
  local name, realm = UnitFullName(unit)
  if not name then
    return nil
  end
  local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
  return Ambiguate(full, "none")
end

local function nhsUnitDisplay(unit)
  return UnitName(unit) or "?"
end

local function nhsGetGroupRoster()
  local list = {}
  if not IsInGroup() then
    local unit = "player"
    if UnitExists(unit) and UnitIsPlayer(unit) then
      local key = nhsUnitSortKey(unit)
      if key then
        list[#list + 1] = { unit = unit, key = key, display = nhsUnitDisplay(unit) }
      end
    end
    return list
  end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitExists(unit) and UnitIsPlayer(unit) then
        local key = nhsUnitSortKey(unit)
        if key then
          list[#list + 1] = { unit = unit, key = key, display = nhsUnitDisplay(unit) }
        end
      end
    end
  elseif IsInGroup() then
    do
      local unit = "player"
      local key = nhsUnitSortKey(unit)
      if key then
        list[#list + 1] = { unit = unit, key = key, display = nhsUnitDisplay(unit) }
      end
    end
    for i = 1, GetNumGroupMembers() - 1 do
      local unit = "party" .. i
      if UnitExists(unit) and UnitIsPlayer(unit) then
        local key = nhsUnitSortKey(unit)
        if key then
          list[#list + 1] = { unit = unit, key = key, display = nhsUnitDisplay(unit) }
        end
      end
    end
  end
  return list
end

local function nhsUnitIsInGroupRoster(unit)
  if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
    return false
  end
  local tk = nhsUnitSortKey(unit)
  if not tk then
    return false
  end
  for _, m in ipairs(nhsGetGroupRoster()) do
    if m.key == tk then
      return true
    end
  end
  return false
end

local function nhsFindGroupUnitForSortKey(wantKey)
  if not wantKey then
    return nil
  end
  for _, m in ipairs(nhsGetGroupRoster()) do
    if m.key == wantKey then
      return m.unit
    end
  end
  return nil
end

local function nhsIsRoundLeader()
  return IsInGroup() and UnitIsGroupLeader("player")
end

-- How many seekers the active game mode requires (minimum 1).
local function nhsGetRequiredSeekerCount()
  local id = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
  if not id then return 1 end
  local def = NHS.GameModeDefinition and NHS.GameModeDefinition(id)
  if not def or type(def.seekers) ~= "number" or def.seekers < 1 then return 1 end
  return def.seekers
end

-- Raid leader only: temporary assistant so seekers can send RAID_WARNING for [NHS] Found lines.
local function nhsLeaderTryPromoteSeekerForRaidWarn()
  if not nhsIsRoundLeader() or not IsInRaid() or #State.gameLockedSeekerKeys == 0 then
    return
  end
  for _, key in ipairs(State.gameLockedSeekerKeys) do
    local unit = nhsFindGroupUnitForSortKey(key)
    if unit and UnitExists(unit) then
      if not UnitIsGroupLeader(unit) and not (UnitIsRaidOfficer and UnitIsRaidOfficer(unit)) then
        if PromoteToAssistant then
          pcall(PromoteToAssistant, unit)
        end
        if UnitIsRaidOfficer and UnitIsRaidOfficer(unit) and not UnitIsGroupLeader(unit) then
          local alreadyTracked = false
          for _, k in ipairs(State.nhsSeekerPromotedAsAssistantKeys) do
            if k == key then alreadyTracked = true; break end
          end
          if not alreadyTracked then
            State.nhsSeekerPromotedAsAssistantKeys[#State.nhsSeekerPromotedAsAssistantKeys + 1] = key
          end
        end
      end
    end
  end
end

local function nhsLeaderDemoteSeekerAssistantIfWePromoted()
  if #State.nhsSeekerPromotedAsAssistantKeys == 0 then
    return
  end
  if nhsIsRoundLeader() and IsInRaid() then
    for _, key in ipairs(State.nhsSeekerPromotedAsAssistantKeys) do
      local unit = nhsFindGroupUnitForSortKey(key)
      if unit and UnitExists(unit) and not UnitIsGroupLeader(unit) then
        if UnitIsRaidOfficer and UnitIsRaidOfficer(unit) and DemoteAssistant then
          pcall(DemoteAssistant, unit)
        end
      end
    end
  end
  wipe(State.nhsSeekerPromotedAsAssistantKeys)
end

-- Solo (not in a group) may use game controls; in a group only the leader may.
local function nhsMayUseLeaderGameActions()
  if not IsInGroup() then
    return true
  end
  return nhsIsRoundLeader()
end

-- Blizzard party/raid countdown (same system as /cd in many setups); not an addon timer.
local function nhsStartBuiltInCountdown(seconds)
  seconds = math.floor(tonumber(seconds) or 0)
  if seconds < 1 then
    return false, "Invalid duration."
  end
  if C_PartyInfo and C_PartyInfo.DoCountdown then
    local ok, success = pcall(C_PartyInfo.DoCountdown, seconds)
    if NHS.debugSync then
      print(("|cffffcc00[NHS] debugsync|r DoCountdown(%d): pcall_ok=%s success=%s"):format(
        seconds, tostring(ok), tostring(success)))
    end
    if ok and success then
      return true
    end
    if ok and success == false then
      return false, "Countdown failed — try in a party/raid or instance."
    end
    return false, "Could not start countdown."
  end
  return false, "C_PartyInfo.DoCountdown not available on this client."
end

-- Only the party/raid leader should cancel (DoCountdown(0) spams group chat if every member calls it).
local function nhsStopPartyCountdown()
  if IsInGroup() and not nhsIsRoundLeader() then
    return
  end
  if C_PartyInfo and C_PartyInfo.DoCountdown then
    pcall(C_PartyInfo.DoCountdown, 0)
  end
end

-- Master toggle for addon gameplay SFX (Options → Gameplay).
local function nhsGameplaySoundsEnabled()
  ensureSavedVars()
  return NHSV.gameplaySoundsEnabled ~= false
end

-- Karazhan Opera (Big Bad Wolf): HoodWolf transform / "Run away little girl!" (Wowhead sound kit 9278).
-- Hiders only: the designated seeker skips (cue is for people hiding).
local function nhsPlayHidingPhaseStartSound()
  if not nhsGameplaySoundsEnabled() then
    return
  end
  if NHS.LocalPlayerIsDesignatedSeeker and NHS.LocalPlayerIsDesignatedSeeker() then
    return
  end
  pcall(PlaySound, 9278, "Master")
end

-- Saved to NHSV.gameRounds so sessions survive /reload and match in-memory state after travel.
local function nhsFoundOrderSnapshot()
  local t = {}
  for i = 1, #State.foundOrder do
    t[i] = State.foundOrder[i]
  end
  return t
end

local function nhsRestoreFoundFromSnapshot(list)
  clearFound()
  if type(list) ~= "table" then
    return
  end
  -- Hot Potato adds passers to foundOrder but never to foundSet during live play.
  -- Restoring foundSet from foundOrder would incorrectly block tags and empty the
  -- hidden list after a /reload, so skip it for hot_potato.
  local isHotPotato = (State.gameMode == "hot_potato") or (State.remoteGameMode == "hot_potato")
  local seen = isHotPotato and {} or nil
  for _, k in ipairs(list) do
    if type(k) == "string" and k ~= "" then
      if isHotPotato then
        if not seen[k] then
          seen[k] = true
          State.foundOrder[#State.foundOrder + 1] = k
        end
      elseif not State.foundSet[k] then
        State.foundSet[k] = true
        State.foundOrder[#State.foundOrder + 1] = k
      end
    end
  end
end

local function nhsPastRoundsSnapshotForSave()
  local out = {}
  for i = 1, #State.pastRounds do
    local r = State.pastRounds[i]
    if type(r) == "table" then
      out[#out + 1] = {
        house = r.house or "",
        mode = r.mode or "",
        seeker = r.seeker or "",
        hidden = r.hidden or "",
        found = r.found or "",
      }
    end
  end
  return out
end

local function nhsRestorePastRoundsFromSave(list)
  wipe(State.pastRounds)
  if type(list) ~= "table" then
    return
  end
  for _, pr in ipairs(list) do
    if type(pr) == "table" then
      State.pastRounds[#State.pastRounds + 1] = {
        house = pr.house or "",
        mode = pr.mode or "",
        seeker = pr.seeker or "",
        hidden = pr.hidden or "",
        found = pr.found or "",
      }
    end
  end
end

-- When no live session is saved in NHSV.gameRounds, completed rounds from the last ended session
-- are restored from NHSV.lastCompletedPastRounds (see nhsResetGameSession / follower game over).
local function nhsArchiveCompletedPastRoundsForReload()
  ensureSavedVars()
  NHSV.lastCompletedPastRounds = nhsPastRoundsSnapshotForSave()
end

local function nhsClearCompletedPastRoundsArchive()
  ensureSavedVars()
  NHSV.lastCompletedPastRounds = nil
end

local function nhsPersistGameSessionToSaved()
  ensureSavedVars()
  local foundSnap = nhsFoundOrderSnapshot()
  local pastSnap = nhsPastRoundsSnapshotForSave()
  if State.gameSessionActive then
    local rotKeys = {}
    for k in pairs(State.gameRotationUsed) do
      rotKeys[#rotKeys + 1] = k
    end
    local hist = {}
    for i = 1, #State.gameSeekerHistory do
      hist[i] = State.gameSeekerHistory[i]
    end
    local houseRotKeys = {}
    for k in pairs(State.gameHouseRotationUsed) do
      houseRotKeys[#houseRotKeys + 1] = k
    end
    local houseHist = {}
    for i = 1, #State.gameHouseHistory do
      houseHist[i] = State.gameHouseHistory[i]
    end
    local candidateKeySnap = {}
    for i, k in ipairs(State.gameCandidateKeys) do candidateKeySnap[i] = k end
    local lockedKeySnap = {}
    for i, k in ipairs(State.gameLockedSeekerKeys) do lockedKeySnap[i] = k end
    local recentSnap = {}
    for i, v in ipairs(State.recentlyPlayedModes) do recentSnap[i] = v end
    NHSV.gameRounds = {
      sessionActive = true,
      clientMode = "leader",
      phase = State.phase,
      gameMode = State.gameMode,
      houseListSource = State.gameSessionHouseListSource or "pending",
      houseCandidateKey = State.gameHouseCandidateKey,
      houseCandidateDisplay = State.gameHouseCandidateDisplay,
      houseLockedKey = State.gameLockedHouseKey,
      houseLockedDisplay = State.gameLockedHouseDisplay,
      houseRotationKeys = houseRotKeys,
      houseHistory = houseHist,
      candidateKeys = candidateKeySnap,
      lockedKeys = lockedKeySnap,
      lockedHiderKey = State.gameLockedHiderKey,
      seekerHistory = hist,
      rotationKeys = rotKeys,
      foundOrder = foundSnap,
      pastRounds = pastSnap,
      hotPotatoTaggedBy = State.hotPotatoTaggedBy or nil,
      recentlyPlayedModes = recentSnap,
    }
    return
  end
  if State.remoteSessionActive then
    local houseHist = {}
    for i = 1, #State.gameHouseHistory do
      houseHist[i] = State.gameHouseHistory[i]
    end
    local seekHist = {}
    for i = 1, #State.gameSeekerHistory do
      seekHist[i] = State.gameSeekerHistory[i]
    end
    local remoteSeekerKeySnap = {}
    for i, k in ipairs(State.remoteSeekerKeys) do remoteSeekerKeySnap[i] = k end
    NHSV.gameRounds = {
      sessionActive = true,
      clientMode = "follower",
      remoteSessionActive = State.remoteSessionActive and true or false,
      phase = State.phase,
      remoteSeekerKeys = remoteSeekerKeySnap,
      remoteHouseDisplay = State.remoteHouseDisplay,
      remoteGameMode = State.remoteGameMode,
      houseHistory = houseHist,
      seekerHistory = seekHist,
      foundOrder = foundSnap,
      pastRounds = pastSnap,
      hotPotatoTaggedBy = State.hotPotatoTaggedBy or nil,
    }
    return
  end
  NHSV.gameRounds = nil
end

local function nhsHydrateGameSessionFromSaved()
  ensureSavedVars()
  local s = NHSV.gameRounds
  if not s or not s.sessionActive then
    nhsRestorePastRoundsFromSave(NHSV.lastCompletedPastRounds)
    NHS.SessionHudUpdate()
    return
  end
  local mode = s.clientMode or "leader"
  if mode == "follower" then
    if State.gameSessionActive then
      NHS.SessionHudUpdate()
      return
    end
    State.gameSessionActive = false
    State.remoteSessionActive = s.remoteSessionActive and true or false
    -- Restore remoteSeekerKeys: new format is a list; legacy is a single string remoteSeekerKey.
    wipe(State.remoteSeekerKeys)
    if type(s.remoteSeekerKeys) == "table" then
      for _, k in ipairs(s.remoteSeekerKeys) do
        if type(k) == "string" and k ~= "" then
          State.remoteSeekerKeys[#State.remoteSeekerKeys + 1] = k
        end
      end
    elseif type(s.remoteSeekerKey) == "string" and s.remoteSeekerKey ~= "" then
      State.remoteSeekerKeys[1] = s.remoteSeekerKey
    end
    State.remoteHouseDisplay = s.remoteHouseDisplay
    -- Determine phase: new saves store s.phase; legacy saves use remoteLeaderGamePhase + roundPhase + remoteRoundActive.
    local ph = s.phase
    if type(ph) == "string" and (ph == Phase.PICK_GAME_MODE or ph == Phase.PICK_HOUSE or ph == Phase.PICK_SEEKER or IsRoundPhase(ph)) then
      State.phase = ph
    elseif type(ph) == "string" and ph == "round_active" then
      local rp = s.roundPhase
      State.phase = IsRoundPhase(rp) and rp or Phase.PENDING
    else
      -- Legacy migration
      local rra = s.remoteRoundActive
      local rlgp = s.remoteLeaderGamePhase
      local rph = s.roundPhase
      if rra then
        State.phase = IsRoundPhase(rph) and rph or Phase.PENDING
      elseif rlgp == Phase.PICK_SEEKER or rlgp == Phase.PICK_HOUSE or rlgp == Phase.PICK_GAME_MODE then
        State.phase = rlgp
      elseif State.remoteHouseDisplay and State.remoteHouseDisplay ~= "" then
        State.phase = Phase.PICK_GAME_MODE  -- house known from old save; best guess is game mode step
      elseif State.remoteSessionActive then
        State.phase = Phase.PICK_HOUSE
      else
        State.phase = Phase.NONE
      end
    end
    if type(s.remoteGameMode) == "string" and NHS.IsValidGameMode and NHS.IsValidGameMode(s.remoteGameMode) then
      State.remoteGameMode = s.remoteGameMode
    else
      State.remoteGameMode = nil
    end
    wipe(State.gameHouseHistory)
    for i, v in ipairs(s.houseHistory or {}) do
      State.gameHouseHistory[i] = v
    end
    wipe(State.gameSeekerHistory)
    for i, v in ipairs(s.seekerHistory or {}) do
      State.gameSeekerHistory[i] = v
    end
    nhsRestoreFoundFromSnapshot(s.foundOrder)
    nhsRestorePastRoundsFromSave(s.pastRounds)
    State.hotPotatoTaggedBy = (type(s.hotPotatoTaggedBy) == "string" and s.hotPotatoTaggedBy ~= "") and s.hotPotatoTaggedBy or nil
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    wipe(State.gameHouseRotationUsed)
    wipe(State.gameCandidateKeys)
    wipe(State.gameLockedSeekerKeys)
    wipe(State.gameRotationUsed)
    NHS.SessionHudUpdate()
    return
  end
  if State.gameSessionActive then
    NHS.SessionHudUpdate()
    return
  end
  State.gameSessionActive = true
  local src = s.houseListSource
  if src == "neighborhood" or src == "saved" or src == "group" then
    State.gameSessionHouseListSource = src
  elseif src == "pending" then
    State.gameSessionHouseListSource = nil
  else
    -- Legacy saves had no houseListSource; honor old Options toggle once.
    ensureSavedVars()
    if NHSV.selectHouseFromSavedList == false then
      State.gameSessionHouseListSource = "neighborhood"
    else
      State.gameSessionHouseListSource = "saved"
    end
  end
  -- Determine phase: new saves store unified phase; legacy saves use phase="round_active" + separate roundPhase.
  do
    local ph = s.phase
    if ph == "round_active" then
      -- Legacy: promote roundPhase to unified phase
      local rp = s.roundPhase
      State.phase = IsRoundPhase(rp) and rp or Phase.PENDING
    elseif ph == Phase.PICK_SEEKER or ph == Phase.PICK_HOUSE or ph == Phase.PICK_GAME_MODE then
      State.phase = ph
    elseif IsRoundPhase(ph) then
      State.phase = ph
    else
      State.phase = Phase.PICK_HOUSE
    end
  end
  if type(s.gameMode) == "string" and NHS.IsValidGameMode and NHS.IsValidGameMode(s.gameMode) then
    State.gameMode = s.gameMode
  else
    State.gameMode = nil
  end
  -- PICK_GAME_MODE (second phase) requires a confirmed house.
  if State.phase == Phase.PICK_GAME_MODE and not (State.gameLockedHouseKey or State.gameLockedHouseDisplay) then
    State.phase = Phase.PICK_HOUSE
  end
  State.gameHouseCandidateKey = s.houseCandidateKey
  State.gameHouseCandidateDisplay = s.houseCandidateDisplay
  State.gameLockedHouseKey = s.houseLockedKey
  State.gameLockedHouseDisplay = s.houseLockedDisplay
  wipe(State.gameHouseHistory)
  for i, v in ipairs(s.houseHistory or {}) do
    State.gameHouseHistory[i] = v
  end
  wipe(State.gameHouseRotationUsed)
  for _, k in ipairs(s.houseRotationKeys or {}) do
    State.gameHouseRotationUsed[k] = true
  end
  State.gameLockedHouseLiveEntry = nil
  State.gameLockedHouseLiveIndex = nil
  if State.phase == Phase.PICK_SEEKER and not (State.gameLockedHouseKey or State.gameLockedHouseDisplay) then
    State.phase = Phase.PICK_HOUSE
  end
  -- PICK_SEEKER (third phase) requires a game mode too.
  if State.phase == Phase.PICK_SEEKER and not State.gameMode then
    State.phase = Phase.PICK_GAME_MODE
  end
  if IsRoundPhase(State.phase) and not (State.gameLockedHouseKey or State.gameLockedHouseDisplay) then
    State.phase = Phase.PICK_HOUSE
  end
  -- Restore gameCandidateKeys: new format is a list; legacy was a single candidateKey string.
  wipe(State.gameCandidateKeys)
  if type(s.candidateKeys) == "table" then
    for _, k in ipairs(s.candidateKeys) do
      if type(k) == "string" and k ~= "" then
        State.gameCandidateKeys[#State.gameCandidateKeys + 1] = k
      end
    end
  elseif type(s.candidateKey) == "string" and s.candidateKey ~= "" then
    State.gameCandidateKeys[1] = s.candidateKey
  end
  -- Restore gameLockedSeekerKeys: new format is a list; legacy was a single lockedKey string.
  wipe(State.gameLockedSeekerKeys)
  if type(s.lockedKeys) == "table" then
    for _, k in ipairs(s.lockedKeys) do
      if type(k) == "string" and k ~= "" then
        State.gameLockedSeekerKeys[#State.gameLockedSeekerKeys + 1] = k
      end
    end
  elseif type(s.lockedKey) == "string" and s.lockedKey ~= "" then
    State.gameLockedSeekerKeys[1] = s.lockedKey
  end
  wipe(State.gameSeekerHistory)
  for i, v in ipairs(s.seekerHistory or {}) do
    State.gameSeekerHistory[i] = v
  end
  wipe(State.gameRotationUsed)
  for _, k in ipairs(s.rotationKeys or {}) do
    State.gameRotationUsed[k] = true
  end
  State.gameLockedHiderKey = (type(s.lockedHiderKey) == "string" and s.lockedHiderKey ~= "") and s.lockedHiderKey or nil
  State.hotPotatoTaggedBy = (type(s.hotPotatoTaggedBy) == "string" and s.hotPotatoTaggedBy ~= "") and s.hotPotatoTaggedBy or nil
  wipe(State.recentlyPlayedModes)
  for i, v in ipairs(s.recentlyPlayedModes or {}) do
    State.recentlyPlayedModes[i] = v
  end
  nhsRestoreFoundFromSnapshot(s.foundOrder)
  nhsRestorePastRoundsFromSave(s.pastRounds)
  NHS.SessionHudUpdate()
  if NHS.SyncHiddenRangePoll then
    NHS.SyncHiddenRangePoll()
  end
end

local function nhsResetGameSession()
  State.statsPhaseStartTime = nil  -- nhsEndPhaseClock() already flushed before this is called
  if NHS.ClearRevealMarkers then
    NHS.ClearRevealMarkers()
  end
  nhsStopPartyCountdown()
  nhsLeaderDemoteSeekerAssistantIfWePromoted()
  State.gameSessionActive = false
  State.phase = Phase.NONE
  State.gameSessionHouseListSource = nil
  State.gameHouseCandidateKey = nil
  State.gameHouseCandidateDisplay = nil
  State.gameLockedHouseKey = nil
  State.gameLockedHouseDisplay = nil
  State.gameLastRoundHouseKey = nil
  State.gameLockedHouseLiveEntry = nil
  State.gameLockedHouseLiveIndex = nil
  wipe(State.gameHouseHistory)
  wipe(State.gameHouseRotationUsed)
  State.remoteHouseDisplay = nil
  State.remoteHouseKey = nil
  wipe(State.gameRoundInitialSeekerKeys)
  State.followerSearchPhaseStartTime = nil
  State.searchPhaseOriginalStartTime = nil
  wipe(State.gameCandidateKeys)
  wipe(State.gameLockedSeekerKeys)
  State.gameLockedHiderKey = nil
  wipe(State.gameSeekerHistory)
  wipe(State.gameRotationUsed)
  wipe(State.remoteSeekerKeys)
  wipe(State.recentlyPlayedModes)
  State.remoteSessionActive = false
  if NHS.ClearRoundGameMode then
    NHS.ClearRoundGameMode()
  else
    State.gameMode = nil
    State.remoteGameMode = nil
  end
  clearFound()
  if State.seekerMode and NHS.SetSeekerMode then
    NHS.SetSeekerMode(false)
  end
  nhsArchiveCompletedPastRoundsForReload()
  NHSV.gameRounds = nil
  NHS.SessionHudUpdate()
  if NHS.SyncHiddenRangePoll then
    NHS.SyncHiddenRangePoll()
  end
end

local function nhsRandomSeekerEligible()
  local roster = nhsGetGroupRoster()
  if #roster == 0 then
    return nil, "No players in group."
  end
  -- Build a set of already-picked candidates so they are excluded from this pick.
  local pickedSet = {}
  for _, k in ipairs(State.gameCandidateKeys) do
    pickedSet[k] = true
  end
  -- Hider mode (e.g. Chosen One): the seeker rotation is irrelevant — anyone in the
  -- group can be the hider regardless of who sought in previous rounds.
  if NHS.IsHiderMode and NHS.IsHiderMode() then
    local eligible = {}
    for _, m in ipairs(roster) do
      if not pickedSet[m.key] then
        eligible[#eligible + 1] = m
      end
    end
    if #eligible == 0 then
      return nil, "No eligible players (group is empty)."
    end
    return eligible, nil
  end
  -- Normal mode: honour the seeker rotation so everyone gets a turn.
  local eligible = {}
  for _, m in ipairs(roster) do
    if not State.gameRotationUsed[m.key] and not pickedSet[m.key] then
      eligible[#eligible + 1] = m
    end
  end
  if #eligible == 0 then
    -- Reset rotation but still exclude already-picked candidates.
    wipe(State.gameRotationUsed)
    eligible = {}
    for _, m in ipairs(roster) do
      if not pickedSet[m.key] then
        eligible[#eligible + 1] = m
      end
    end
  end
  if #eligible == 0 then
    return nil, "No eligible players (all picked for this round or group is empty)."
  end
  return eligible, nil
end

local function nhsPickRandomSeekerMember()
  local elig, err = nhsRandomSeekerEligible()
  if not elig then
    return nil, err
  end
  return elig[math.random(1, #elig)]
end

local function nhsLocalPlayerSortKey()
  return nhsUnitSortKey("player")
end

-- Returns the full list of designated seeker keys for the active round (empty table if none).
local function nhsGetDesignatedSeekerKeys()
  if State.remoteSessionActive and IsRoundPhase(State.phase) and #State.remoteSeekerKeys > 0 then
    return State.remoteSeekerKeys
  end
  if State.gameSessionActive and IsRoundPhase(State.phase) and #State.gameLockedSeekerKeys > 0 then
    if not IsInGroup() or nhsIsRoundLeader() then
      return State.gameLockedSeekerKeys
    end
  end
  return {}
end

-- Convenience: returns the first (primary) seeker key, or nil. Used for single-seeker paths and legacy sync.
local function nhsGetDesignatedSeekerKey()
  local keys = nhsGetDesignatedSeekerKeys()
  return keys[1] or nil
end

-- Chat sender (and sometimes local sort key) can differ from sync/roster keys: same-realm short
-- name vs Name-Realm, etc. Resolve wantKey to a group unit when possible.
local function nhsTrimStr(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function nhsChatSenderMatchesSortKey(senderName, wantKey)
  if not wantKey or type(senderName) ~= "string" or senderName == "" then
    return false
  end
  local sk = Ambiguate(nhsTrimStr(senderName), "none")
  if sk == wantKey then
    return true
  end
  local unit = nhsFindGroupUnitForSortKey(wantKey)
  if not unit or not UnitExists(unit) then
    return false
  end
  local uk = nhsUnitSortKey(unit)
  if sk == uk then
    return true
  end
  local name, realm = UnitFullName(unit)
  if not name then
    return false
  end
  local withRealm = (realm and realm ~= "") and (name .. "-" .. realm) or name
  if sk == Ambiguate(withRealm, "none") then
    return true
  end
  if sk == Ambiguate(name, "none") then
    return true
  end
  return false
end

local function nhsGroupSortKeysEquivalent(a, b)
  if not a or not b then
    return false
  end
  if a == b then
    return true
  end
  return nhsChatSenderMatchesSortKey(a, b) or nhsChatSenderMatchesSortKey(b, a)
end

-- Map a sort key from chat/sync to this client's roster m.key so foundSet[m.key] and HUD stay consistent.
local function nhsCanonicalGroupSortKey(key)
  if type(key) ~= "string" or key == "" then
    return key
  end
  if not IsInGroup() then
    return key
  end
  for _, m in ipairs(nhsGetGroupRoster()) do
    if nhsGroupSortKeysEquivalent(m.key, key) then
      return m.key
    end
  end
  return key
end

-- True if two strings refer to the same group member on this client (chat name, sync key, or m.key).
-- GroupSortKeysEquivalent alone fails when e.g. chat gives "Name" but roster has only "Name-Realm"
-- and FindGroupUnitForSortKey("Name") returns nil — canonicalize both sides to m.key first.
local function nhsRosterIdentityEqual(a, b)
  if not a or not b or a == "" or b == "" then
    return false
  end
  if a == b then
    return true
  end
  if not IsInGroup() then
    return nhsGroupSortKeysEquivalent(a, b)
  end
  local ca = nhsCanonicalGroupSortKey(a)
  local cb = nhsCanonicalGroupSortKey(b)
  if ca == cb then
    return true
  end
  return nhsGroupSortKeysEquivalent(a, b)
end

local function nhsLocalPlayerIsDesignatedSeeker()
  local me = nhsLocalPlayerSortKey()
  if not me then
    return false
  end
  local keys = nhsGetDesignatedSeekerKeys()
  for _, sk in ipairs(keys) do
    if nhsRosterIdentityEqual(me, sk) then
      return true
    end
  end
  return false
end

local function nhsChatSenderIsDesignatedSeeker(senderName)
  if type(senderName) ~= "string" or senderName == "" then
    return false
  end
  local sk = Ambiguate(nhsTrimStr(senderName), "none")
  if sk == "" then
    return false
  end
  local keys = nhsGetDesignatedSeekerKeys()
  for _, k in ipairs(keys) do
    if nhsRosterIdentityEqual(sk, k) then
      return true
    end
  end
  return false
end

local function nhsPastRoundHiddenSnapshotString(roleKeys)
  roleKeys = roleKeys or nhsGetDesignatedSeekerKeys()
  local roleSet = {}
  for _, k in ipairs(roleKeys) do
    roleSet[k] = true
  end
  local roster = nhsGetGroupRoster()
  local names = {}
  for _, m in ipairs(roster) do
    if not roleSet[m.key] and not State.foundSet[m.key] then
      names[#names + 1] = Ambiguate(m.key, "short")
    end
  end
  table.sort(names)
  local n = #names
  if n == 0 then
    return "Hidden (0): —"
  end
  return ("Hidden (%d): %s"):format(n, NHS.SessionHudCommaList(names))
end

local function nhsPastRoundFoundSnapshotString()
  local names = {}
  for i = 1, #State.foundOrder do
    names[#names + 1] = Ambiguate(State.foundOrder[i], "short")
  end
  local n = #names
  if n == 0 then
    return "Found (0): —"
  end
  return ("Found (%d): %s"):format(n, NHS.SessionHudCommaList(names, 14, false))
end

local function nhsPastRoundSeekerDisplay()
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
  return "—"
end

local function nhsPastRoundHouseAndKey()
  if State.gameSessionActive and IsRoundPhase(State.phase) then
    return State.gameLockedHouseDisplay, State.gameLockedHouseKey
  end
  if State.remoteSessionActive and IsRoundPhase(State.phase) and State.remoteHouseDisplay and State.remoteHouseDisplay ~= "" then
    return State.remoteHouseDisplay, State.remoteHouseKey
  end
  return nil, nil
end

-- Call before clearing round state (leader End round, follower Round is over! sync).
local function nhsAppendPastRoundSnapshotIfActiveRound()
  if not NHS.SessionHudIsActive() then
    return
  end
  if not IsRoundPhase(State.phase) or State.phase == Phase.PENDING then
    return
  end
  if not State.gameSessionActive and not State.remoteSessionActive then
    return
  end
  NHS.AccumulateRoundStats()
  local houseDisp = nhsPastRoundHouseAndKey()
  if not houseDisp or houseDisp == "" then
    houseDisp = "—"
  end
  local seekerKeys = nhsGetDesignatedSeekerKeys()
  local modeLine = "Mode: —"
  if NHS.PastRoundModeSnapshotString then
    modeLine = NHS.PastRoundModeSnapshotString()
  end
  local roleLabel = "Seeker"
  State.pastRounds[#State.pastRounds + 1] = {
    house = ("House: %s"):format(houseDisp),
    mode = modeLine,
    seeker = ("%s: %s"):format(roleLabel, nhsPastRoundSeekerDisplay()),
    hidden = nhsPastRoundHiddenSnapshotString(seekerKeys),
    found = nhsPastRoundFoundSnapshotString(),
  }
  if NHS.LiveRefreshIfOpen then
    NHS.LiveRefreshIfOpen("rounds")
    NHS.LiveRefreshIfOpen("stats")
  end
end

-- Toggle with /nhs debugfound or /run NeighborhoodHideSeek.debugFoundSync=true
local function nhsDebugFoundSyncDump(reason, extra)
  local me = nhsLocalPlayerSortKey()
  local dsk = nhsGetDesignatedSeekerKey()
  local ca = me and nhsCanonicalGroupSortKey(me) or nil
  local cb = dsk and nhsCanonicalGroupSortKey(dsk) or nil
  local ideq = nhsLocalPlayerIsDesignatedSeeker()
  print("|cffffcc00[NHS] Found-sync debug|r " .. tostring(reason or "?"))
  if extra and extra ~= "" then
    print("|cffffcc00[NHS]|r  extra: " .. tostring(extra))
  end
  print("|cffffcc00[NHS]|r  isLeader=" .. tostring(nhsIsRoundLeader()) .. " inGroup=" .. tostring(IsInGroup()))
  print("|cffffcc00[NHS]|r  localPlayerKey=" .. tostring(me))
  print("|cffffcc00[NHS]|r  designatedSeekerKey(primary)=" .. tostring(dsk))
  print("|cffffcc00[NHS]|r  canonical(local)=" .. tostring(ca) .. " | canonical(designated)=" .. tostring(cb))
  print("|cffffcc00[NHS]|r  LocalPlayerIsDesignatedSeeker=" .. tostring(ideq))
  print(
    "|cffffcc00[NHS]|r  remoteSession="
      .. tostring(State.remoteSessionActive)
      .. " phase="
      .. tostring(State.phase)
  )
  do
    local rsk = {}
    for _, k in ipairs(State.remoteSeekerKeys) do rsk[#rsk + 1] = tostring(k) end
    print("|cffffcc00[NHS]|r  State.remoteSeekerKeys=" .. (#rsk > 0 and table.concat(rsk, ", ") or "(none)"))
  end
  do
    local lsk = {}
    for _, k in ipairs(State.gameLockedSeekerKeys) do lsk[#lsk + 1] = tostring(k) end
    print(
      "|cffffcc00[NHS]|r  gameSession="
        .. tostring(State.gameSessionActive)
        .. " lockedSeekerKeys=" .. (#lsk > 0 and table.concat(lsk, ", ") or "(none)")
    )
  end
  print("|cffffcc00[NHS]|r  Group roster (list we match keys against):")
  local roster = nhsGetGroupRoster()
  if #roster == 0 then
    print("|cffffcc00[NHS]|r    (empty)")
  else
    for i, m in ipairs(roster) do
      print(
        ("|cffffcc00[NHS]|r    [%d] m.key=%q  display=%q"):format(i, tostring(m.key), tostring(m.display))
      )
    end
  end
  local fo = {}
  for i = 1, #State.foundOrder do
    fo[#fo + 1] = tostring(State.foundOrder[i])
  end
  print("|cffffcc00[NHS]|r  foundOrder keys: " .. (#fo > 0 and table.concat(fo, ", ") or "(none)"))
end

if NHS.debugFoundSync == nil then
  NHS.debugFoundSync = false
end
if NHS.debugSync == nil then
  NHS.debugSync = false
end
NHS.DebugDumpFoundSyncState = nhsDebugFoundSyncDump

-- Leader end-round action extracted from MainFrame so it can be triggered without the window open.
-- onRefreshUI is an optional callback for the UI layer (pass refreshGameRounds from MainFrame, or nil).
local function nhsLeaderPerformEndRound(onRefreshUI)
  local bmf = NHS.BuildMainFrameBridge
  if not bmf or not nhsMayUseLeaderGameActions() then
    return
  end
  if not State.gameSessionActive or State.phase == Phase.PICK_HOUSE then
    return
  end
  nhsAppendPastRoundSnapshotIfActiveRound()
  nhsLeaderDemoteSeekerAssistantIfWePromoted()
  if NHS.ClearRoundGameMode then
    NHS.ClearRoundGameMode()
  else
    State.gameMode = nil
  end
  NHS.FlushPhaseClock()
  State.phase = Phase.PICK_HOUSE
  State.gameHouseCandidateKey = nil
  State.gameHouseCandidateDisplay = nil
  State.gameLastRoundHouseKey = State.gameLockedHouseKey  -- preserve for subdivision-change callout on next house pick
  State.gameLockedHouseKey = nil
  State.gameLockedHouseDisplay = nil
  State.gameLockedHouseLiveEntry = nil
  State.gameLockedHouseLiveIndex = nil
  wipe(State.gameLockedSeekerKeys)
  State.gameLockedHiderKey = nil
  wipe(State.gameCandidateKeys)
  clearFound()
  nhsStopPartyCountdown()
  if bmf.nhsBroadcastLeaderSync and bmf.NHS_MSG_ROUND_OVER then
    bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_ROUND_OVER)
  end
  print("|cff88ccff[NHS]|r Round ended. Pick the next house, then a game mode and seeker.")
  nhsPersistGameSessionToSaved()
  if State.seekerMode and NHS.SetSeekerMode then
    NHS.SetSeekerMode(false)
  end
  if onRefreshUI then
    onRefreshUI()
  else
    NHS.SessionHudUpdate()
  end
end

-- Best-effort full UI refresh: calls RefreshGameRounds if the main window has been built, else HUD only.
local function nhsRefreshGameUi()
  local ui = B.getUI()
  if ui.RefreshGameRounds then
    ui.RefreshGameRounds()
  else
    NHS.SessionHudUpdate()
  end
end

-- Revealing phase: restart the round with the same house, game mode, and seeker(s)/hider without
-- going back through setup. Broadcasts ROUND_OVER first so followers correctly snapshot and reset
-- before receiving the new round's sync messages.
local function nhsLeaderPlayAgain(onRefreshUI)
  local bmf = NHS.BuildMainFrameBridge
  if not bmf or not nhsMayUseLeaderGameActions() then return end
  if not State.gameSessionActive or State.phase ~= Phase.REVEALING then return end

  -- Capture reuse values before clearing anything.
  local houseKey     = State.gameLockedHouseKey
  local houseDisplay = State.gameLockedHouseDisplay
  local modeId       = State.gameMode
  local isHiderMode  = NHS.IsHiderMode and NHS.IsHiderMode()
  local hiderKey     = State.gameLockedHiderKey

  -- For seeker modes, determine which keys to carry forward.
  -- Conquer expands gameLockedSeekerKeys as hiders are found; [1] is always the original seeker.
  -- Hot Potato swaps to the final/losing seeker; [1] is that loser.
  -- Paired starts with two seekers; both are originals and the list is unchanged.
  local carrySeekersOver = {}
  if not isHiderMode then
    if modeId == "conquer" then
      if State.gameLockedSeekerKeys[1] then
        carrySeekersOver[1] = State.gameLockedSeekerKeys[1]
      end
    else
      for _, k in ipairs(State.gameLockedSeekerKeys) do
        carrySeekersOver[#carrySeekersOver + 1] = k
      end
    end
  end

  if not houseDisplay or houseDisplay == "" then return end
  if not modeId or not (NHS.IsValidGameMode and NHS.IsValidGameMode(modeId)) then return end
  if isHiderMode and not hiderKey then return end
  if not isHiderMode and #carrySeekersOver == 0 then return end

  -- Snapshot and cleanly end the current round on all clients before starting the new one.
  -- ROUND_OVER must fire first: without it, followers in the same round phase with the same
  -- seeker key would treat the incoming Round Start as a re-sync and skip clearFound().
  nhsAppendPastRoundSnapshotIfActiveRound()
  nhsLeaderDemoteSeekerAssistantIfWePromoted()
  nhsStopPartyCountdown()
  if bmf.nhsBroadcastLeaderSync and bmf.NHS_MSG_ROUND_OVER then
    bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_ROUND_OVER)
  end

  -- Reset round-specific state while keeping the session and house history alive.
  clearFound()
  wipe(State.gameCandidateKeys)
  wipe(State.gameLockedSeekerKeys)
  State.gameLockedHiderKey     = nil
  State.gameLockedHouseLiveEntry = nil
  State.gameLockedHouseLiveIndex = nil

  -- Re-lock house and mode.
  State.gameLockedHouseKey     = houseKey
  State.gameLockedHouseDisplay = houseDisplay
  State.gameMode               = modeId

  -- Re-lock seeker(s) or rebuild the seeker list for hider modes.
  -- Rebuilding from the roster ensures late-joiners and Sardines mid-round shrinkage are handled.
  if isHiderMode then
    State.gameLockedHiderKey = hiderKey
    for _, m in ipairs(nhsGetGroupRoster()) do
      if m.key ~= hiderKey then
        State.gameLockedSeekerKeys[#State.gameLockedSeekerKeys + 1] = m.key
      end
    end
  else
    for _, k in ipairs(carrySeekersOver) do
      State.gameLockedSeekerKeys[#State.gameLockedSeekerKeys + 1] = k
    end
  end

  NHS.FlushPhaseClock()
  State.phase = Phase.PENDING

  -- Sync followers through the setup phases they're skipping.
  -- House: sendChat=false — the house was already announced this session.
  if bmf.nhsBroadcastHouseLocked then
    bmf.nhsBroadcastHouseLocked(houseDisplay, false, houseKey)
  end
  -- Game mode: always announces to chat so players see the reminder.
  if bmf.nhsBroadcastLeaderGameMode then
    bmf.nhsBroadcastLeaderGameMode(modeId)
  end
  -- Round Start: puts followers into PENDING with the correct seeker keys.
  if bmf.nhsBroadcastRoundStart then
    local keyStr = table.concat(State.gameLockedSeekerKeys, ",")
    local chatLabel
    if isHiderMode then
      chatLabel = "[NHS] Hider Selected: " .. Ambiguate(hiderKey, "short")
    else
      local names = {}
      for _, k in ipairs(State.gameLockedSeekerKeys) do
        names[#names + 1] = Ambiguate(k, "short")
      end
      chatLabel = "[NHS] Seeker(s) Selected: " .. table.concat(names, ", ")
    end
    bmf.nhsBroadcastRoundStart(keyStr, chatLabel)
  end

  if State.seekerMode and NHS.SetSeekerMode then
    NHS.SetSeekerMode(false)
  end

  local modeLabel = NHS.GameModeHudLabel and NHS.GameModeHudLabel(modeId) or modeId
  print(("|cff88ccff[NHS]|r Playing again — |cffffffff%s|r. Set up hiding when ready."):format(modeLabel))
  nhsPersistGameSessionToSaved()
  if onRefreshUI then
    onRefreshUI()
  else
    nhsRefreshGameUi()
  end
end

-- Phase transition (HIDING / SEARCHING / REVEALING): commits rotation/history, broadcasts sync messages,
-- builds the congratulatory reveal chat line. Extracted from MainFrame so auto-reveal and countdown
-- triggers work correctly after /reload without the main window having been opened first.
local function nhsLeaderBroadcastRoundPhase(phase)
  local bmf = NHS.BuildMainFrameBridge
  if not bmf then return end
  if phase == Phase.HIDING then
    -- Commit house and seeker rotation/history now that the round is actually underway.
    if State.gameLockedHouseKey then
      State.gameHouseRotationUsed[State.gameLockedHouseKey] = true
      State.gameHouseHistory[#State.gameHouseHistory + 1] = State.gameLockedHouseDisplay
    end
    if NHS.IsHiderMode and NHS.IsHiderMode() then
      if State.gameLockedHiderKey then
        State.gameRotationUsed[State.gameLockedHiderKey] = true
        local hiderLabel = (NHS.IsSardinesMode and NHS.IsSardinesMode()) and "Sardine" or "Hider"
        State.gameSeekerHistory[#State.gameSeekerHistory + 1] = hiderLabel .. ": " .. Ambiguate(State.gameLockedHiderKey, "short")
      end
    else
      local names = {}
      for _, k in ipairs(State.gameLockedSeekerKeys) do
        State.gameRotationUsed[k] = true
        names[#names + 1] = Ambiguate(k, "short")
      end
      if #names > 0 then
        State.gameSeekerHistory[#State.gameSeekerHistory + 1] = table.concat(names, ", ")
      end
    end
    if NHS.LiveRefreshIfOpen then
      NHS.LiveRefreshIfOpen("houses")
      NHS.LiveRefreshIfOpen("seekers")
    end
    -- Step 1 of 2: capture initial seeker keys for stats. Overwritten at SEARCHING to pick up late-joiners.
    wipe(State.gameRoundInitialSeekerKeys)
    for _, k in ipairs(State.gameLockedSeekerKeys) do
      State.gameRoundInitialSeekerKeys[#State.gameRoundInitialSeekerKeys + 1] = k
    end
    NHS.FlushPhaseClock()
    State.phase = Phase.HIDING
    if bmf.nhsBroadcastLeaderSync then bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_HIDING) end
    nhsPlayHidingPhaseStartSound()
  elseif phase == Phase.SEARCHING then
    wipe(State.hiderReadySet)
    -- Step 2 of 2: overwrite to pick up any players who joined during the hiding phase and were
    -- added as seekers by nhsLeaderHiderModeAddLateJoiners. Conquer/Hot Potato swaps haven't
    -- happened yet so this is still the correct "initial" seeker set for stats purposes.
    wipe(State.gameRoundInitialSeekerKeys)
    for _, k in ipairs(State.gameLockedSeekerKeys) do
      State.gameRoundInitialSeekerKeys[#State.gameRoundInitialSeekerKeys + 1] = k
    end
    NHS.FlushPhaseClock()
    State.phase = Phase.SEARCHING
    local keyParts = {}
    for _, k in ipairs(State.gameLockedSeekerKeys) do
      if type(k) == "string" and k ~= "" then
        keyParts[#keyParts + 1] = k
      end
    end
    if bmf.nhsBroadcastLeaderSync then
      if #keyParts > 0 then
        bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_SEEKING .. table.concat(keyParts, ","))
      else
        bmf.nhsBroadcastLeaderSync("[NHS] The Seeking Begins!")
      end
    end
    nhsLeaderTryPromoteSeekerForRaidWarn()
  elseif phase == Phase.REVEALING then
    NHS.FlushPhaseClock()
    State.phase = Phase.REVEALING
    do
      -- Build congratulatory chat message: praise surviving hiders, or the seeker(s) if all found.
      local seekerSet = {}
      for _, k in ipairs(State.gameLockedSeekerKeys) do seekerSet[k] = true end
      local hiderNames = {}
      for _, m in ipairs(nhsGetGroupRoster()) do
        if not seekerSet[m.key] and not State.foundSet[m.key] then
          hiderNames[#hiderNames + 1] = Ambiguate(m.key, "short")
        end
      end
      table.sort(hiderNames)
      local function nameList(names)
        local n = #names
        if n == 0 then return "" end
        if n == 1 then return names[1] end
        if n == 2 then return names[1] .. " and " .. names[2] end
        local t = {}
        for i = 1, n - 1 do t[i] = names[i] end
        return table.concat(t, ", ") .. ", and " .. names[n]
      end
      local chatMsg
      local revealModeId = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
      if revealModeId == "hot_potato" and #State.gameLockedSeekerKeys > 0 then
        local loserName = Ambiguate(State.gameLockedSeekerKeys[1], "short")
        chatMsg = (bmf.NHS_MSG_REVEALING or "") .. " " .. loserName .. " is holding the Hot Potato!"
      elseif revealModeId == "sardines" then
        local sardineName = State.gameLockedHiderKey and Ambiguate(State.gameLockedHiderKey, "short") or "the sardine"
        if #State.gameLockedSeekerKeys == 0 then
          -- All seekers found and joined the sardine pile.
          chatMsg = (bmf.NHS_MSG_REVEALING or "") .. " Everyone squeezed in with " .. sardineName .. "!"
        else
          -- Time ran out; some seekers never found the sardine.
          chatMsg = (bmf.NHS_MSG_REVEALING or "") .. " Congratulations to " .. sardineName .. " for staying hidden!"
        end
      elseif #hiderNames > 0 then
        chatMsg = (bmf.NHS_MSG_REVEALING or "") .. " Congratulations to " .. nameList(hiderNames) .. " for staying hidden!"
      else
        local seekerNames = {}
        for _, k in ipairs(State.gameLockedSeekerKeys) do
          seekerNames[#seekerNames + 1] = Ambiguate(k, "short")
        end
        chatMsg = (bmf.NHS_MSG_REVEALING or "") .. " " .. nameList(seekerNames) .. " found everyone!"
      end
      if bmf.nhsBroadcastRevealingPhase then
        bmf.nhsBroadcastRevealingPhase(chatMsg)
      elseif bmf.nhsBroadcastLeaderSync then
        bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_REVEALING)
      end
    end
    nhsLeaderDemoteSeekerAssistantIfWePromoted()
    if State.seekerMode and NHS.SetSeekerMode then NHS.SetSeekerMode(false) end
    if NHS.OnLeaderRevealPhaseStart then NHS.OnLeaderRevealPhaseStart() end
  end
  if NHS.SyncHiddenRangePoll then NHS.SyncHiddenRangePoll() end
end

-- Auto-advance to revealing when the seeker marks the last hider found. Called from GroupSync
-- and MarkFound without the main window open — must be defined at addon load, not in BuildMainFrame.
local function nhsTryLeaderAutoReveal()
  if not State.gameSessionActive or not nhsIsRoundLeader() then return end
  if State.phase ~= Phase.SEARCHING then return end
  -- Hot Potato ends only when the timer runs out, not when a hider is found.
  if NHS.IsHotPotatoMode and NHS.IsHotPotatoMode() then return end
  -- Sardines: reveal when every seeker has joined the sardine (seeker list empties).
  if NHS.IsSardinesMode and NHS.IsSardinesMode() then
    if #State.gameLockedSeekerKeys == 0 then
      nhsStopPartyCountdown()
      nhsLeaderBroadcastRoundPhase(Phase.REVEALING)
      print("|cff88ccff[NHS]|r All seekers joined the sardine!")
      nhsPersistGameSessionToSaved()
      nhsRefreshGameUi()
    end
    return
  end
  local seekerSet = {}
  for _, k in ipairs(State.gameLockedSeekerKeys) do seekerSet[k] = true end
  local hiderCount, unfoundCount = 0, 0
  for _, m in ipairs(nhsGetGroupRoster()) do
    if not seekerSet[m.key] then
      hiderCount = hiderCount + 1
      if not State.foundSet[m.key] then unfoundCount = unfoundCount + 1 end
    end
  end
  if hiderCount == 0 or unfoundCount > 0 then return end
  nhsStopPartyCountdown()
  nhsLeaderBroadcastRoundPhase(Phase.REVEALING)
  print("|cff88ccff[NHS]|r All hiders found — moving to the revealing phase!")
  nhsPersistGameSessionToSaved()
  nhsRefreshGameUi()
end

-- End the current game session (broadcasts game-over then resets state).
local function nhsLeaderEndSession(onRefreshUI)
  local bmf = NHS.BuildMainFrameBridge
  -- Snapshot the round before resetting so sessions ended during a round phase
  -- (e.g. End Session while still in Revealing) don't lose the last round's data.
  nhsAppendPastRoundSnapshotIfActiveRound()
  if IsInGroup() and nhsIsRoundLeader() and bmf and bmf.nhsBroadcastLeaderSync then
    bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_GAME_OVER)
  end
  NHS.EndPhaseClock()
  nhsResetGameSession()
  print("|cff88ccff[NHS]|r Game session ended.")
  if onRefreshUI then onRefreshUI() else nhsRefreshGameUi() end
end

-- Start a new game session. onAfterStart is optional; the UI layer can pass refreshHouseList + refreshGameRounds.
local function nhsLeaderStartSession(onAfterStart)
  if IsInGroup() and not nhsIsRoundLeader() then return end
  local bmf = NHS.BuildMainFrameBridge
  State.gameSessionActive = true
  State.phase = Phase.PICK_HOUSE
  State.gameMode = nil
  State.gameSessionHouseListSource = nil
  State.gameHouseCandidateKey = nil
  State.gameHouseCandidateDisplay = nil
  State.gameLockedHouseKey = nil
  State.gameLockedHouseDisplay = nil
  State.gameLastRoundHouseKey = nil
  State.gameLockedHouseLiveEntry = nil
  State.gameLockedHouseLiveIndex = nil
  wipe(State.gameHouseHistory)
  wipe(State.gameHouseRotationUsed)
  wipe(State.gameCandidateKeys)
  wipe(State.gameLockedSeekerKeys)
  State.gameLockedHiderKey = nil
  wipe(State.gameSeekerHistory)
  wipe(State.gameRotationUsed)
  wipe(State.pastRounds)
  wipe(State.recentlyPlayedModes)
  nhsClearCompletedPastRoundsArchive()
  NHS.RecordSessionStart()
  nhsPersistGameSessionToSaved()
  if IsInGroup() and nhsIsRoundLeader() and bmf and bmf.nhsBroadcastLeaderSync then
    bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_SESSION_START)
  end
  if IsInGroup() and nhsIsRoundLeader() and NHS.VersionCheck and NHS.VersionCheck.TriggerCheck then
    NHS.VersionCheck.TriggerCheck()
  end
  print("|cff88ccff[NHS]|r Game session started. Choose a house list and confirm a house, then pick a game mode.")
  if onAfterStart then onAfterStart() else nhsRefreshGameUi() end
end

-- Select a game mode for the current round.
local function nhsLeaderSelectGameMode(modeId, onRefreshUI)
  local bmf = NHS.BuildMainFrameBridge
  if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_GAME_MODE then
    return
  end
  if not NHS.IsValidGameMode or not NHS.IsValidGameMode(modeId) then return end
  State.gameMode = modeId
  NHS.FlushPhaseClock()
  State.phase = Phase.PICK_SEEKER
  -- Track last 2 modes played this session (used to default their checkboxes off next round).
  for i = #State.recentlyPlayedModes, 1, -1 do
    if State.recentlyPlayedModes[i] == modeId then table.remove(State.recentlyPlayedModes, i) end
  end
  table.insert(State.recentlyPlayedModes, 1, modeId)
  if #State.recentlyPlayedModes > 2 then table.remove(State.recentlyPlayedModes) end
  local label = NHS.GameModeHudLabel and NHS.GameModeHudLabel(modeId) or modeId
  if IsInGroup() and nhsIsRoundLeader() and bmf and bmf.nhsBroadcastLeaderGameMode then
    bmf.nhsBroadcastLeaderGameMode(modeId)
  end
  print(("|cff88ccff[NHS]|r Game mode: |cffffffff%s|r — pick a seeker."):format(label))
  nhsPersistGameSessionToSaved()
  if NHS.SyncHiddenRangePoll then NHS.SyncHiddenRangePoll() end
  if onRefreshUI then onRefreshUI() else nhsRefreshGameUi() end
end

-- Lock in the selected seeker(s)/hider and advance to PENDING phase.
local function nhsLeaderConfirmSeeker(onRefreshUI)
  local bmf = NHS.BuildMainFrameBridge
  if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.phase ~= Phase.PICK_SEEKER then
    return
  end
  local required = nhsGetRequiredSeekerCount()
  if #State.gameCandidateKeys ~= required then return end
  if not State.gameLockedHouseDisplay then
    print("|cffff8800[NHS]|r Confirm a house first (house selection phase).")
    return
  end
  clearFound()
  wipe(State.gameLockedSeekerKeys)
  if NHS.IsHiderMode and NHS.IsHiderMode() then
    -- Hider mode: candidate is the hider; everyone else in the roster becomes a seeker.
    local hiderKey = State.gameCandidateKeys[1]
    State.gameLockedHiderKey = hiderKey
    for _, m in ipairs(nhsGetGroupRoster()) do
      if m.key ~= hiderKey then
        State.gameLockedSeekerKeys[#State.gameLockedSeekerKeys + 1] = m.key
      end
    end
    local hiderName = Ambiguate(hiderKey, "short")
    wipe(State.gameCandidateKeys)
    NHS.FlushPhaseClock()
    State.phase = Phase.PENDING
    if bmf and bmf.nhsBroadcastRoundStart then
      bmf.nhsBroadcastRoundStart(table.concat(State.gameLockedSeekerKeys, ","), "[NHS] Hider Selected: " .. hiderName)
    end
    print(("|cff88ccff[NHS]|r Round started. |cffffffff%s|r is the hider."):format(hiderName))
  else
    -- Normal mode: lock in all candidates as seekers.
    local names = {}
    for _, k in ipairs(State.gameCandidateKeys) do
      State.gameLockedSeekerKeys[#State.gameLockedSeekerKeys + 1] = k
      names[#names + 1] = Ambiguate(k, "short")
    end
    -- gameRotationUsed and gameSeekerHistory committed when hide timer starts (HIDING phase).
    wipe(State.gameCandidateKeys)
    NHS.FlushPhaseClock()
    State.phase = Phase.PENDING
    local nameStr = table.concat(names, ", ")
    if bmf and bmf.nhsBroadcastRoundStart then
      bmf.nhsBroadcastRoundStart(table.concat(State.gameLockedSeekerKeys, ","), "[NHS] Seeker(s) Selected: " .. nameStr)
    end
    if #State.gameLockedSeekerKeys > 1 then
      print(("|cff88ccff[NHS]|r Round started. Seekers: |cffffffff%s|r."):format(nameStr))
    else
      print(("|cff88ccff[NHS]|r Round started. |cffffffff%s|r is the seeker."):format(names[1] or "?"))
    end
  end
  nhsPersistGameSessionToSaved()
  if onRefreshUI then onRefreshUI() else nhsRefreshGameUi() end
end

-- Advance to HIDING or SEARCHING phase and fire the Blizzard party countdown.
-- phase: Phase.HIDING or Phase.SEARCHING. sec: duration. presetName: label for the print line.
local function nhsLeaderStartPhaseCountdown(phase, sec, presetName, onRefreshUI)
  if not nhsMayUseLeaderGameActions() or not (State.gameSessionActive and IsRoundPhase(State.phase)) then
    return
  end
  local bmf = NHS.BuildMainFrameBridge
  nhsLeaderBroadcastRoundPhase(phase)
  if phase == Phase.SEARCHING then
    State.searchPhaseStartTime = GetTime()
    State.searchPhaseOriginalStartTime = GetTime()
    State.searchPhaseDuration = sec
  end
  local phaseLabel = phase == Phase.HIDING and "Hiding" or "Searching"
  print(("|cff88ccff[NHS]|r %s — %s (%d s)."):format(phaseLabel, presetName or "Custom", sec))
  local ok, err = nhsStartBuiltInCountdown(sec)
  if not ok and NHS.debugSync then
    print(("|cffffcc00[NHS] debugsync|r Countdown returned: ok=%s err=%s"):format(tostring(ok), tostring(err)))
  end
  nhsPersistGameSessionToSaved()
  if bmf and bmf.nhsSeekerAutoModeSyncToPhase then bmf.nhsSeekerAutoModeSyncToPhase() end
  if onRefreshUI then onRefreshUI() else nhsRefreshGameUi() end
end

-- Manual "Begin Revealing" action.
local function nhsLeaderReveal(onRefreshUI)
  if not nhsMayUseLeaderGameActions() or not (State.gameSessionActive and IsRoundPhase(State.phase)) then
    return
  end
  if State.phase ~= Phase.SEARCHING then return end
  nhsStopPartyCountdown()
  nhsLeaderBroadcastRoundPhase(Phase.REVEALING)
  print("|cff88ccff[NHS]|r Revealing phase started — hiders, show yourselves!")
  nhsPersistGameSessionToSaved()
  if onRefreshUI then onRefreshUI() else nhsRefreshGameUi() end
end

-- Back-navigation: revert one setup step (PICK_GAME_MODE → PICK_HOUSE, PICK_SEEKER → PICK_GAME_MODE, PENDING → PICK_SEEKER).
local function nhsLeaderBack(onRefreshUI)
  local bmf = NHS.BuildMainFrameBridge
  if not nhsMayUseLeaderGameActions() or not State.gameSessionActive then return end
  if State.phase == Phase.PICK_GAME_MODE then
    State.gameHouseCandidateKey = State.gameLockedHouseKey
    State.gameHouseCandidateDisplay = State.gameLockedHouseDisplay
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    NHS.FlushPhaseClock()
    State.phase = Phase.PICK_HOUSE
    if bmf and bmf.nhsBroadcastLeaderSync then bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_ROUND_OVER, false) end
    print("|cff88ccff[NHS]|r Back to house selection.")
  elseif State.phase == Phase.PICK_SEEKER then
    if NHS.ClearRoundGameMode then NHS.ClearRoundGameMode() else State.gameMode = nil end
    wipe(State.gameCandidateKeys)
    NHS.FlushPhaseClock()
    State.phase = Phase.PICK_GAME_MODE
    if bmf and bmf.nhsBroadcastHouseLocked then bmf.nhsBroadcastHouseLocked(State.gameLockedHouseDisplay, false, State.gameLockedHouseKey) end
    print("|cff88ccff[NHS]|r Back to game mode selection.")
  elseif State.phase == Phase.PENDING then
    if NHS.IsHiderMode and NHS.IsHiderMode() then
      if State.gameLockedHiderKey then State.gameCandidateKeys[1] = State.gameLockedHiderKey end
      State.gameLockedHiderKey = nil
    else
      for _, k in ipairs(State.gameLockedSeekerKeys) do
        State.gameCandidateKeys[#State.gameCandidateKeys + 1] = k
      end
    end
    wipe(State.gameLockedSeekerKeys)
    clearFound()
    nhsStopPartyCountdown()
    if State.seekerMode and NHS.SetSeekerMode then NHS.SetSeekerMode(false) end
    NHS.FlushPhaseClock()
    State.phase = Phase.PICK_SEEKER
    if bmf and bmf.nhsBroadcastLeaderSync then
      bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_ROUND_OVER, false)
      bmf.nhsBroadcastHouseLocked(State.gameLockedHouseDisplay, false, State.gameLockedHouseKey)
      if State.gameMode then bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_GAME_MODE .. State.gameMode, false) end
    end
    print("|cff88ccff[NHS]|r Back to seeker selection.")
  else
    return
  end
  nhsPersistGameSessionToSaved()
  if onRefreshUI then onRefreshUI() else nhsRefreshGameUi() end
end

-- Chosen One: on GROUP_ROSTER_UPDATE, add any new group member as a seeker.
-- Guards make this a no-op in every other mode/phase/role.
local function nhsLeaderHiderModeAddLateJoiners()
  if not nhsMayUseLeaderGameActions() then return end
  if not State.gameSessionActive then return end
  if not IsRoundPhase(State.phase) then return end
  if not (NHS.IsHiderMode and NHS.IsHiderMode()) then return end
  if not State.gameLockedHiderKey then return end

  local seekerSet = {}
  for _, k in ipairs(State.gameLockedSeekerKeys) do
    seekerSet[k] = true
  end

  local added = {}
  for _, m in ipairs(nhsGetGroupRoster()) do
    if m.key ~= State.gameLockedHiderKey and not seekerSet[m.key] then
      State.gameLockedSeekerKeys[#State.gameLockedSeekerKeys + 1] = m.key
      added[#added + 1] = m.display
    end
  end

  if #added == 0 then return end

  local bmf = NHS.BuildMainFrameBridge
  if bmf and bmf.nhsBroadcastLeaderSync and bmf.NHS_MSG_ROUND_START then
    local keyStr = table.concat(State.gameLockedSeekerKeys, ",")
    if keyStr ~= "" then
      bmf.nhsBroadcastLeaderSync(bmf.NHS_MSG_ROUND_START .. keyStr, false)
    end
  end

  print(("|cff88ccff[NHS]|r %s joined and %s added as %s (Chosen One)."):format(
    table.concat(added, ", "),
    #added == 1 and "was" or "were",
    #added == 1 and "a seeker" or "seekers"
  ))

  nhsPersistGameSessionToSaved()
  nhsRefreshGameUi()
end

NHS.GetGroupRoster = nhsGetGroupRoster
NHS.UnitSortKey = nhsUnitSortKey
NHS.UnitIsInGroupRoster = nhsUnitIsInGroupRoster
NHS.LocalPlayerSortKey = nhsLocalPlayerSortKey
NHS.GetDesignatedSeekerKey = nhsGetDesignatedSeekerKey
NHS.GetDesignatedSeekerKeys = nhsGetDesignatedSeekerKeys
NHS.GetRequiredSeekerCount = nhsGetRequiredSeekerCount
NHS.LocalPlayerIsDesignatedSeeker = nhsLocalPlayerIsDesignatedSeeker
NHS.GroupSortKeysEquivalent = nhsGroupSortKeysEquivalent
NHS.CanonicalGroupSortKey = nhsCanonicalGroupSortKey
NHS.RosterIdentityEqual = nhsRosterIdentityEqual
NHS.HydrateGameSessionFromSaved = nhsHydrateGameSessionFromSaved
NHS.PersistGameSessionToSaved = nhsPersistGameSessionToSaved
NHS.ArchiveCompletedPastRoundsForReload = nhsArchiveCompletedPastRoundsForReload
NHS.ClearCompletedPastRoundsArchive = nhsClearCompletedPastRoundsArchive
NHS.PickRandomSeekerMember = nhsPickRandomSeekerMember
NHS.PlayHidingPhaseStartSound = nhsPlayHidingPhaseStartSound
NHS.GameplaySoundsEnabled = nhsGameplaySoundsEnabled
NHS.LeaderPerformEndRound = nhsLeaderPerformEndRound
NHS.LeaderBroadcastRoundPhase = nhsLeaderBroadcastRoundPhase
NHS.TryLeaderAutoReveal = nhsTryLeaderAutoReveal
NHS.LeaderEndSession = nhsLeaderEndSession
NHS.LeaderStartSession = nhsLeaderStartSession
NHS.LeaderSelectGameMode = nhsLeaderSelectGameMode
NHS.LeaderConfirmSeeker = nhsLeaderConfirmSeeker
NHS.LeaderStartPhaseCountdown = nhsLeaderStartPhaseCountdown
NHS.LeaderReveal = nhsLeaderReveal
NHS.LeaderBack = nhsLeaderBack
NHS.LeaderPlayAgain = nhsLeaderPlayAgain
NHS.LeaderHiderModeAddLateJoiners = nhsLeaderHiderModeAddLateJoiners

local bmf = NHS.BuildMainFrameBridge
if bmf then
  bmf.nhsPersistGameSessionToSaved = nhsPersistGameSessionToSaved
  bmf.nhsGetGroupRoster = nhsGetGroupRoster
  bmf.nhsMayUseLeaderGameActions = nhsMayUseLeaderGameActions
  bmf.nhsIsRoundLeader = nhsIsRoundLeader
  bmf.nhsResetGameSession = nhsResetGameSession
  bmf.nhsStartBuiltInCountdown = nhsStartBuiltInCountdown
  bmf.nhsStopPartyCountdown = nhsStopPartyCountdown
  bmf.nhsLeaderTryPromoteSeekerForRaidWarn = nhsLeaderTryPromoteSeekerForRaidWarn
  bmf.nhsLeaderDemoteSeekerAssistantIfWePromoted = nhsLeaderDemoteSeekerAssistantIfWePromoted
  bmf.nhsAppendPastRoundSnapshotIfActiveRound = nhsAppendPastRoundSnapshotIfActiveRound
  bmf.nhsLeaderPerformEndRound = nhsLeaderPerformEndRound
  bmf.nhsLeaderPlayAgain = nhsLeaderPlayAgain
  bmf.nhsRandomSeekerEligible = nhsRandomSeekerEligible
  bmf.nhsGetRequiredSeekerCount = nhsGetRequiredSeekerCount
end

local gsb = NHS.GroupSyncBridge
if gsb then
  gsb.nhsUnitSortKey = nhsUnitSortKey
  gsb.nhsGetGroupRoster = nhsGetGroupRoster
  gsb.nhsLocalPlayerSortKey = nhsLocalPlayerSortKey
  gsb.nhsGetDesignatedSeekerKey = nhsGetDesignatedSeekerKey
  gsb.nhsLocalPlayerIsDesignatedSeeker = nhsLocalPlayerIsDesignatedSeeker
  gsb.nhsChatSenderIsDesignatedSeeker = nhsChatSenderIsDesignatedSeeker
  gsb.nhsCanonicalGroupSortKey = nhsCanonicalGroupSortKey
  gsb.nhsRosterIdentityEqual = nhsRosterIdentityEqual
  gsb.nhsIsRoundLeader = nhsIsRoundLeader
  gsb.nhsPersistGameSessionToSaved = nhsPersistGameSessionToSaved
  gsb.nhsAppendPastRoundSnapshotIfActiveRound = nhsAppendPastRoundSnapshotIfActiveRound
end
