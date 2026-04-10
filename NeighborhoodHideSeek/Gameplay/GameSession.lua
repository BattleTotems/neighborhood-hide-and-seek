--[[
  Party/raid roster, leader checks, Blizzard party countdown, NHSV.gameRounds persistence,
  and past-round snapshot helpers. Patches BuildMainFrameBridge + GroupSyncBridge.
  Load after Core.lua and before SessionHud.lua (roster must exist on the bridge).
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State
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

-- Raid leader only: temporary assistant so the seeker can send RAID_WARNING for [NHS] Found lines.
local function nhsLeaderTryPromoteSeekerForRaidWarn()
  if not nhsIsRoundLeader() or not IsInRaid() or not State.gameLockedSeekerKey then
    return
  end
  local key = State.gameLockedSeekerKey
  local unit = nhsFindGroupUnitForSortKey(key)
  if not unit or not UnitExists(unit) then
    return
  end
  if UnitIsGroupLeader(unit) or (UnitIsRaidOfficer and UnitIsRaidOfficer(unit)) then
    return
  end
  if PromoteToAssistant then
    pcall(PromoteToAssistant, unit)
  end
  if UnitIsRaidOfficer and UnitIsRaidOfficer(unit) and not UnitIsGroupLeader(unit) then
    State.nhsSeekerPromotedAsAssistantKey = key
  end
end

local function nhsLeaderDemoteSeekerAssistantIfWePromoted()
  if not State.nhsSeekerPromotedAsAssistantKey then
    return
  end
  local key = State.nhsSeekerPromotedAsAssistantKey
  State.nhsSeekerPromotedAsAssistantKey = nil
  if nhsIsRoundLeader() and IsInRaid() then
    local unit = nhsFindGroupUnitForSortKey(key)
    if unit and UnitExists(unit) and not UnitIsGroupLeader(unit) then
      if UnitIsRaidOfficer and UnitIsRaidOfficer(unit) and DemoteAssistant then
        pcall(DemoteAssistant, unit)
      end
    end
  end
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

local function nhsStopPartyCountdown()
  if C_PartyInfo and C_PartyInfo.DoCountdown then
    pcall(C_PartyInfo.DoCountdown, 0)
  end
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
        seeker = pr.seeker or "",
        hidden = pr.hidden or "",
        found = pr.found or "",
      }
    end
  end
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
    NHSV.gameRounds = {
      sessionActive = true,
      clientMode = "leader",
      phase = State.gamePhase,
      houseCandidateKey = State.gameHouseCandidateKey,
      houseCandidateDisplay = State.gameHouseCandidateDisplay,
      houseLockedKey = State.gameLockedHouseKey,
      houseLockedDisplay = State.gameLockedHouseDisplay,
      houseRotationKeys = houseRotKeys,
      houseHistory = houseHist,
      candidateKey = State.gameCandidateKey,
      candidateDisplay = State.gameCandidateDisplay,
      lockedKey = State.gameLockedSeekerKey,
      lockedDisplay = State.gameLockedSeekerDisplay,
      seekerHistory = hist,
      rotationKeys = rotKeys,
      foundOrder = foundSnap,
      pastRounds = pastSnap,
    }
    return
  end
  if State.remoteSessionActive or State.remoteRoundActive then
    local houseHist = {}
    for i = 1, #State.gameHouseHistory do
      houseHist[i] = State.gameHouseHistory[i]
    end
    local seekHist = {}
    for i = 1, #State.gameSeekerHistory do
      seekHist[i] = State.gameSeekerHistory[i]
    end
    NHSV.gameRounds = {
      sessionActive = true,
      clientMode = "follower",
      remoteSessionActive = State.remoteSessionActive and true or false,
      remoteRoundActive = State.remoteRoundActive and true or false,
      remoteSeekerKey = State.remoteSeekerKey,
      remoteHouseDisplay = State.remoteHouseDisplay,
      roundPhase = State.roundPhase,
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
    State.remoteRoundActive = s.remoteRoundActive and true or false
    State.remoteSeekerKey = s.remoteSeekerKey
    State.remoteHouseDisplay = s.remoteHouseDisplay
    State.roundPhase = (type(s.roundPhase) == "string" and s.roundPhase ~= "") and s.roundPhase or "none"
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
    State.gamePhase = "none"
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    wipe(State.gameHouseRotationUsed)
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.gameLockedSeekerKey = nil
    State.gameLockedSeekerDisplay = nil
    wipe(State.gameRotationUsed)
    NHS.SessionHudUpdate()
    return
  end
  if State.gameSessionActive then
    NHS.SessionHudUpdate()
    return
  end
  State.gameSessionActive = true
  local ph = s.phase
  if ph == "round_active" or ph == "pick_seeker" or ph == "pick_house" then
    State.gamePhase = ph
  else
    State.gamePhase = "pick_house"
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
  if State.gamePhase == "pick_seeker" and not (State.gameLockedHouseKey or State.gameLockedHouseDisplay) then
    State.gamePhase = "pick_house"
  end
  if State.gamePhase == "round_active" and not (State.gameLockedHouseKey or State.gameLockedHouseDisplay) then
    State.gamePhase = "pick_house"
    State.roundPhase = "none"
  end
  State.gameCandidateKey = s.candidateKey
  State.gameCandidateDisplay = s.candidateDisplay
  State.gameLockedSeekerKey = s.lockedKey
  State.gameLockedSeekerDisplay = s.lockedDisplay
  wipe(State.gameSeekerHistory)
  for i, v in ipairs(s.seekerHistory or {}) do
    State.gameSeekerHistory[i] = v
  end
  wipe(State.gameRotationUsed)
  for _, k in ipairs(s.rotationKeys or {}) do
    State.gameRotationUsed[k] = true
  end
  if State.gamePhase == "round_active" then
    State.roundPhase = "pending"
  else
    State.roundPhase = "none"
  end
  nhsRestoreFoundFromSnapshot(s.foundOrder)
  nhsRestorePastRoundsFromSave(s.pastRounds)
  NHS.SessionHudUpdate()
end

local function nhsResetGameSession()
  nhsStopPartyCountdown()
  nhsLeaderDemoteSeekerAssistantIfWePromoted()
  State.gameSessionActive = false
  State.gamePhase = "none"
  State.gameHouseCandidateKey = nil
  State.gameHouseCandidateDisplay = nil
  State.gameLockedHouseKey = nil
  State.gameLockedHouseDisplay = nil
  State.gameLockedHouseLiveEntry = nil
  State.gameLockedHouseLiveIndex = nil
  wipe(State.gameHouseHistory)
  wipe(State.gameHouseRotationUsed)
  State.remoteHouseDisplay = nil
  State.gameCandidateKey = nil
  State.gameCandidateDisplay = nil
  State.gameLockedSeekerKey = nil
  State.gameLockedSeekerDisplay = nil
  wipe(State.gameSeekerHistory)
  wipe(State.gameRotationUsed)
  State.roundPhase = "none"
  State.remoteRoundActive = false
  State.remoteSeekerKey = nil
  State.remoteSessionActive = false
  wipe(State.pastRounds)
  clearFound()
  ensureSavedVars()
  NHSV.gameRounds = nil
  NHS.SessionHudUpdate()
end

local function nhsRandomSeekerEligible()
  local roster = nhsGetGroupRoster()
  if #roster == 0 then
    return nil, "No players in group."
  end
  local eligible = {}
  for _, m in ipairs(roster) do
    if not State.gameRotationUsed[m.key] then
      eligible[#eligible + 1] = m
    end
  end
  if #eligible == 0 then
    wipe(State.gameRotationUsed)
    eligible = roster
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

-- Who may send "mark found" sync: leader uses locked seeker key; followers use remote seeker key.
local function nhsGetDesignatedSeekerKey()
  -- Follower: prefer remoteRoundActive; also allow searching phase if round flag desynced briefly.
  if State.remoteSeekerKey then
    if State.remoteRoundActive
      or (State.remoteSessionActive and State.roundPhase == "searching") then
      return State.remoteSeekerKey
    end
  end
  if State.gameSessionActive and State.gamePhase == "round_active" and State.gameLockedSeekerKey then
    if not IsInGroup() or nhsIsRoundLeader() then
      return State.gameLockedSeekerKey
    end
  end
  return nil
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
  local dsk = nhsGetDesignatedSeekerKey()
  if not dsk then
    return false
  end
  return nhsRosterIdentityEqual(me, dsk)
end

local function nhsChatSenderIsDesignatedSeeker(senderName)
  local seeker = nhsGetDesignatedSeekerKey()
  if not seeker then
    return false
  end
  if type(senderName) ~= "string" or senderName == "" then
    return false
  end
  local sk = Ambiguate(nhsTrimStr(senderName), "none")
  if sk == "" then
    return false
  end
  return nhsRosterIdentityEqual(sk, seeker)
end

local function nhsPastRoundHiddenSnapshotString(seekerKey)
  seekerKey = seekerKey or nhsGetDesignatedSeekerKey()
  local roster = nhsGetGroupRoster()
  local names = {}
  for _, m in ipairs(roster) do
    if (seekerKey == nil or m.key ~= seekerKey) and not State.foundSet[m.key] then
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
  table.sort(names)
  local n = #names
  if n == 0 then
    return "Found (0): —"
  end
  return ("Found (%d): %s"):format(n, NHS.SessionHudCommaList(names))
end

local function nhsPastRoundSeekerDisplay()
  if State.remoteRoundActive and State.remoteSeekerKey then
    return Ambiguate(State.remoteSeekerKey, "short")
  end
  if State.gameSessionActive and State.gamePhase == "round_active" and State.gameLockedSeekerDisplay then
    return State.gameLockedSeekerDisplay
  end
  return "—"
end

local function nhsPastRoundHouseAndKey()
  if State.gameSessionActive and State.gamePhase == "round_active" then
    return State.gameLockedHouseDisplay, State.gameLockedHouseKey
  end
  if State.remoteRoundActive and State.remoteHouseDisplay and State.remoteHouseDisplay ~= "" then
    return State.remoteHouseDisplay, nil
  end
  return nil, nil
end

-- Call before clearing round state (leader End round, follower Round is over! sync).
local function nhsAppendPastRoundSnapshotIfActiveRound()
  if not NHS.SessionHudIsActive() then
    return
  end
  local inLeaderRound = State.gameSessionActive and State.gamePhase == "round_active"
  local inFollowerRound = State.remoteRoundActive
  if not inLeaderRound and not inFollowerRound then
    return
  end
  local houseDisp = nhsPastRoundHouseAndKey()
  if not houseDisp or houseDisp == "" then
    houseDisp = "—"
  end
  local seekerKey = nhsGetDesignatedSeekerKey()
  State.pastRounds[#State.pastRounds + 1] = {
    house = ("House: %s"):format(houseDisp),
    seeker = ("Seeker: %s"):format(nhsPastRoundSeekerDisplay()),
    hidden = nhsPastRoundHiddenSnapshotString(seekerKey),
    found = nhsPastRoundFoundSnapshotString(),
  }
end

NHS.UnitSortKey = nhsUnitSortKey
NHS.UnitIsInGroupRoster = nhsUnitIsInGroupRoster
NHS.LocalPlayerSortKey = nhsLocalPlayerSortKey
NHS.GetDesignatedSeekerKey = nhsGetDesignatedSeekerKey
NHS.LocalPlayerIsDesignatedSeeker = nhsLocalPlayerIsDesignatedSeeker
NHS.GroupSortKeysEquivalent = nhsGroupSortKeysEquivalent
NHS.CanonicalGroupSortKey = nhsCanonicalGroupSortKey
NHS.RosterIdentityEqual = nhsRosterIdentityEqual
NHS.HydrateGameSessionFromSaved = nhsHydrateGameSessionFromSaved
NHS.PersistGameSessionToSaved = nhsPersistGameSessionToSaved
NHS.PickRandomSeekerMember = nhsPickRandomSeekerMember

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
  gsb.nhsStopPartyCountdown = nhsStopPartyCountdown
end
