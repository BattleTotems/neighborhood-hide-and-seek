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
  for _, k in ipairs(list) do
    if type(k) == "string" and k ~= "" and not State.foundSet[k] then
      State.foundSet[k] = true
      State.foundOrder[#State.foundOrder + 1] = k
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
      seekerHistory = hist,
      rotationKeys = rotKeys,
      foundOrder = foundSnap,
      pastRounds = pastSnap,
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
  nhsRestoreFoundFromSnapshot(s.foundOrder)
  nhsRestorePastRoundsFromSave(s.pastRounds)
  NHS.SessionHudUpdate()
  if NHS.SyncHiddenRangePoll then
    NHS.SyncHiddenRangePoll()
  end
end

local function nhsResetGameSession()
  nhsStopPartyCountdown()
  nhsLeaderDemoteSeekerAssistantIfWePromoted()
  State.gameSessionActive = false
  State.phase = Phase.NONE
  State.gameSessionHouseListSource = nil
  State.gameHouseCandidateKey = nil
  State.gameHouseCandidateDisplay = nil
  State.gameLockedHouseKey = nil
  State.gameLockedHouseDisplay = nil
  State.gameLockedHouseLiveEntry = nil
  State.gameLockedHouseLiveIndex = nil
  wipe(State.gameHouseHistory)
  wipe(State.gameHouseRotationUsed)
  State.remoteHouseDisplay = nil
  wipe(State.gameCandidateKeys)
  wipe(State.gameLockedSeekerKeys)
  wipe(State.gameSeekerHistory)
  wipe(State.gameRotationUsed)
  wipe(State.remoteSeekerKeys)
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
    return State.remoteHouseDisplay, nil
  end
  return nil, nil
end

-- Call before clearing round state (leader End round, follower Round is over! sync).
local function nhsAppendPastRoundSnapshotIfActiveRound()
  if not NHS.SessionHudIsActive() then
    return
  end
  if not IsRoundPhase(State.phase) then
    return
  end
  if not State.gameSessionActive and not State.remoteSessionActive then
    return
  end
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
NHS.DebugDumpFoundSyncState = nhsDebugFoundSyncDump

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
