--[[
  Party/raid [NHS] chat lines and addon comm (CHAT_MSG_ADDON + visible party/raid).
  Core.lua assigns GroupSyncBridge; Gameplay/GameSession.lua patches roster/persist/sync fields;
  Gameplay/SessionHud.lua patches nhsSessionHudUpdate — load GameSession and SessionHud before
  this file (see .toc).
]]

local NHS = NeighborhoodHideSeek
local C = assert(NHS.GroupSyncBridge, "NeighborhoodHideSeek.GroupSyncBridge missing (load order).")

local NHS_CHAT_TAG = "[NHS]"
local NHS_MSG_ROUND_START = "[NHS] Round Start: "
local NHS_MSG_SESSION_START = "[NHS] Game session started"
local NHS_MSG_HOUSE = "[NHS] House: "
local NHS_MSG_HIDING = "[NHS] Hiding Starts Now: "
local NHS_MSG_SEEKING = "[NHS] The Seeking Begins!: "
local NHS_MSG_ROUND_OVER = "[NHS] Round is over!"
local NHS_MSG_GAME_OVER = "[NHS] Game Over! Thanks for playing!"
local NHS_MSG_FOUND_PREFIX = "[NHS] Found: "

-- Addon comm: same human-readable NHS line as payload (max 255 bytes).
local NHS_ADDON_PREFIX = "NeighborhoodHS"

NHS.AddonMessagePrefix = NHS_ADDON_PREFIX

local function nhsSeekerFoundSyncChannel()
  if IsInRaid() then
    if UnitIsGroupLeader("player") or (UnitIsRaidOfficer and UnitIsRaidOfficer("player")) then
      return "RAID_WARNING"
    end
    return "RAID"
  end
  return "PARTY"
end

-- PARTY reaches party members in open world and in most instances; RAIDs use RAID.
local function nhsAddonSyncChatType()
  return IsInRaid() and "RAID" or "PARTY"
end

local function nhsSendAddonSyncPayload(message)
  if not message or message == "" or #message > 255 then
    return
  end
  if not IsInGroup() then
    return
  end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
    return
  end
  pcall(C_ChatInfo.SendAddonMessage, NHS_ADDON_PREFIX, message, nhsAddonSyncChatType())
end

local function nhsChatSenderIsGroupLeader(senderName)
  if not senderName or senderName == "" then
    return false
  end
  local sk = Ambiguate(senderName, "none")
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local u = "raid" .. i
      if UnitExists(u) and UnitIsGroupLeader(u) then
        local k = C.nhsUnitSortKey(u)
        if k and k == sk then
          return true
        end
      end
    end
  elseif IsInGroup() then
    if UnitExists("player") and UnitIsGroupLeader("player") then
      local k = C.nhsUnitSortKey("player")
      if k and k == sk then
        return true
      end
    end
    for i = 1, GetNumGroupMembers() - 1 do
      local u = "party" .. i
      if UnitExists(u) and UnitIsGroupLeader(u) then
        local k = C.nhsUnitSortKey(u)
        if k and k == sk then
          return true
        end
      end
    end
  end
  return false
end

-- Party: normal party chat. Raid: raid warning (center screen) so [NHS] sync stands out.
local function nhsGroupSyncChannel()
  return IsInRaid() and "RAID_WARNING" or "PARTY"
end

local function nhsBroadcastLeaderSync(message)
  if not IsInGroup() or not C.nhsIsRoundLeader() or not message or message == "" then
    return
  end
  if #message > 255 then
    return
  end
  pcall(SendChatMessage, message, nhsGroupSyncChannel())
  nhsSendAddonSyncPayload(message)
end

local function nhsBroadcastHouseLocked(display)
  if type(display) ~= "string" or display == "" then
    return
  end
  local safe = NHS.HousingPinShare.SanitizeForChat(display)
  local msg = NHS_MSG_HOUSE .. safe
  if #msg > 250 then
    msg = NHS_MSG_HOUSE .. safe:sub(1, math.max(1, 250 - #NHS_MSG_HOUSE - 1)) .. "…"
  end
  nhsBroadcastLeaderSync(msg)
end

-- Second line after [NHS] House: … — waypoint link or coordinate text (not an [NHS] tag line).
local function nhsBroadcastGameplayHousePin(entry, rowIndex, labelText, stableKey)
  if not IsInGroup() or not C.nhsIsRoundLeader() then
    return
  end
  local mapID, x, y
  if entry ~= nil and rowIndex ~= nil then
    mapID, x, y = NHS.GetPinCoordsForHouseEntry(entry, rowIndex)
  end
  if (not mapID or mapID == 0 or x == nil or y == nil) and type(stableKey) == "string" and stableKey ~= "" then
    mapID, x, y = NHS.SavedHouses.GetSavedHousePinCoords(stableKey)
  end
  if not mapID or mapID == 0 or x == nil or y == nil then
    return
  end
  local link = NHS.HousingPinShare.BuildWaypointHyperlink(mapID, x, y)
  if link and #link <= 255 then
    local ok = pcall(SendChatMessage, link, nhsGroupSyncChannel())
    if ok then
      return
    end
  end
  local fb = NHS.HousingPinShare.CoordinateMessage(mapID, x, y, labelText)
  fb = NHS.HousingPinShare.SanitizeForChat(fb)
  if fb ~= "" and #fb <= 255 then
    pcall(SendChatMessage, fb, nhsGroupSyncChannel())
  end
end

local function nhsClearRemoteRoundSync()
  C.State.remoteRoundActive = false
  C.State.remoteSeekerKey = nil
  C.State.roundPhase = "none"
  C.clearFound()
end

local function nhsRemoteFollowerSyncRoundState(key, phase)
  if type(key) ~= "string" or key == "" then
    return
  end
  key = Ambiguate(key:match("^%s*(.-)%s*$") or key, "none")
  if key == "" then
    return
  end
  C.State.remoteSessionActive = true
  local newRound = not C.State.remoteRoundActive or C.State.remoteSeekerKey ~= key
  if newRound then
    C.clearFound()
  end
  C.State.remoteRoundActive = true
  C.State.remoteSeekerKey = key
  C.State.roundPhase = phase
end

-- Returns true if this was an [NHS] Found: line (handled or ignored); false otherwise.
local function nhsApplyFoundSyncFromChat(senderName, text)
  local body = text:match("^%[NHS%]%s*Found:%s*(.+)%s*$")
  if not body then
    return false
  end
  if not IsInGroup() then
    return true
  end
  if not C.nhsIsRoundLeader() and not C.nhsGetDesignatedSeekerKey() then
    local senderKey = Ambiguate(type(senderName) == "string" and senderName or "", "none")
    if senderKey and senderKey ~= "" then
      for _, m in ipairs(C.nhsGetGroupRoster()) do
        if C.nhsRosterIdentityEqual and C.nhsRosterIdentityEqual(senderKey, m.key) then
          C.State.remoteSessionActive = true
          C.State.remoteRoundActive = true
          C.State.remoteSeekerKey = m.key
          C.State.roundPhase = "searching"
          break
        end
      end
    end
  end
  if not C.nhsChatSenderIsDesignatedSeeker(senderName) then
    if NHS.debugFoundSync and NHS.DebugDumpFoundSyncState then
      NHS.DebugDumpFoundSyncState(
        "Incoming [NHS] Found ignored: sender is not designated seeker",
        ("chatSender=%q"):format(tostring(senderName))
      )
    end
    C.nhsPersistGameSessionToSaved()
    return true
  end
  if C.State.roundPhase ~= "searching" then
    if NHS.debugFoundSync and NHS.DebugDumpFoundSyncState then
      NHS.DebugDumpFoundSyncState(
        "Incoming [NHS] Found ignored: roundPhase is not searching",
        ("roundPhase=%q"):format(tostring(C.State.roundPhase))
      )
    end
    C.nhsPersistGameSessionToSaved()
    return true
  end
  local foundKey = Ambiguate(body:match("^%s*(.-)%s*$") or body, "none")
  if not foundKey or foundKey == "" then
    C.nhsPersistGameSessionToSaved()
    return true
  end
  if C.nhsCanonicalGroupSortKey then
    foundKey = C.nhsCanonicalGroupSortKey(foundKey)
  end
  if C.State.foundSet[foundKey] then
    C.nhsPersistGameSessionToSaved()
    return true
  end
  C.State.foundSet[foundKey] = true
  C.State.foundOrder[#C.State.foundOrder + 1] = foundKey
  if NHS.RefreshGameSessionUi then
    NHS.RefreshGameSessionUi()
  elseif C.UI.RefreshFound then
    C.UI.RefreshFound()
  elseif C.UI.RefreshAll then
    C.UI.RefreshAll()
  elseif C.nhsSessionHudUpdate then
    C.nhsSessionHudUpdate()
  end
  C.nhsPersistGameSessionToSaved()
  return true
end

local function nhsBroadcastSeekerFound(foundKey)
  if not IsInGroup() or type(foundKey) ~= "string" or foundKey == "" then
    return
  end
  if not C.nhsLocalPlayerIsDesignatedSeeker or not C.nhsLocalPlayerIsDesignatedSeeker() then
    if NHS.debugFoundSync and NHS.DebugDumpFoundSyncState then
      NHS.DebugDumpFoundSyncState("BroadcastSeekerFound skipped: LocalPlayerIsDesignatedSeeker is false")
    end
    return
  end
  local msg = NHS_MSG_FOUND_PREFIX .. foundKey
  if #msg > 255 then
    return
  end
  pcall(SendChatMessage, msg, nhsSeekerFoundSyncChannel())
  nhsSendAddonSyncPayload(msg)
end

local function nhsApplyGroupSyncFromLeader(senderName, text)
  if C.nhsIsRoundLeader() or not IsInGroup() then
    return
  end
  if not nhsChatSenderIsGroupLeader(senderName) then
    return
  end
  if type(text) ~= "string" or text:sub(1, #NHS_CHAT_TAG) ~= NHS_CHAT_TAG then
    return
  end
  local myKey = C.nhsLocalPlayerSortKey()
  local senderKey = Ambiguate(senderName, "none")
  if myKey and senderKey == myKey then
    return
  end
  local seekerPart = text:match("^%[NHS%]%s*Round Start:%s*(.+)%s*$")
  if seekerPart and seekerPart ~= "" then
    local key = Ambiguate(seekerPart:match("^%s*(.-)%s*$") or seekerPart, "none")
    if key and key ~= "" then
      C.clearFound()
      C.State.remoteSessionActive = true
      C.State.remoteRoundActive = true
      C.State.remoteSeekerKey = key
      C.State.roundPhase = "pending"
      C.State.gameSeekerHistory[#C.State.gameSeekerHistory + 1] = Ambiguate(key, "short")
    end
  elseif text:match("^%[NHS%]%s*Game session started%s*$") then
    C.State.remoteSessionActive = true
    wipe(C.State.gameSeekerHistory)
    wipe(C.State.gameHouseHistory)
    wipe(C.State.pastRounds)
    C.State.remoteHouseDisplay = nil
  elseif text:match("^%[NHS%]%s*House:%s*.+") then
    local housePart = text:match("^%[NHS%]%s*House:%s*(.+)%s*$")
    if housePart then
      C.State.remoteSessionActive = true
      local disp = housePart:match("^%s*(.-)%s*$") or housePart
      C.State.remoteHouseDisplay = disp
      C.State.gameHouseHistory[#C.State.gameHouseHistory + 1] = disp
    end
  elseif text:match("^%[NHS%]%s*Round is over!%s*$") then
    C.nhsAppendPastRoundSnapshotIfActiveRound()
    nhsClearRemoteRoundSync()
    C.State.remoteHouseDisplay = nil
    if C.State.seekerMode and NHS.SetSeekerMode then
      NHS.SetSeekerMode(false)
    end
  elseif text:match("^%[NHS%]%s*Game Over! Thanks for playing!%s*$") then
    C.nhsStopPartyCountdown()
    C.State.remoteSessionActive = false
    wipe(C.State.gameSeekerHistory)
    wipe(C.State.gameHouseHistory)
    wipe(C.State.pastRounds)
    C.State.remoteHouseDisplay = nil
    nhsClearRemoteRoundSync()
    if C.State.seekerMode and NHS.SetSeekerMode then
      NHS.SetSeekerMode(false)
    end
  else
    local hideKey = text:match("^%[NHS%]%s*Hiding Starts Now:%s*(.+)%s*$")
    if hideKey then
      nhsRemoteFollowerSyncRoundState(hideKey, "hiding")
    elseif text:match("^%[NHS%]%s*Hiding Starts Now%s*$") then
      C.State.remoteSessionActive = true
      if C.State.remoteRoundActive then
        C.State.roundPhase = "hiding"
      end
    else
      local seekKey = text:match("^%[NHS%]%s*The Seeking Begins!:%s*(.+)%s*$")
      if seekKey then
        nhsRemoteFollowerSyncRoundState(seekKey, "searching")
      elseif text:match("^%[NHS%]%s*The Seeking Begins!%s*$") then
        C.State.remoteSessionActive = true
        if C.State.remoteRoundActive then
          C.State.roundPhase = "searching"
        end
      end
    end
  end
  C.nhsSeekerAutoModeSyncToPhase()
  if C.UI.RefreshAll then
    C.UI.RefreshAll()
  elseif C.UI.RefreshGameRounds then
    C.UI.RefreshGameRounds()
  end
  C.nhsPersistGameSessionToSaved()
  C.nhsSessionHudUpdate()
end

NHS.GroupSync = {
  BroadcastSeekerFound = nhsBroadcastSeekerFound,
  ClearRemoteRound = nhsClearRemoteRoundSync,
}

local B = NHS.BuildMainFrameBridge
B.nhsBroadcastLeaderSync = nhsBroadcastLeaderSync
B.NHS_MSG_ROUND_START = NHS_MSG_ROUND_START
B.NHS_MSG_SESSION_START = NHS_MSG_SESSION_START
B.NHS_MSG_HIDING = NHS_MSG_HIDING
B.NHS_MSG_SEEKING = NHS_MSG_SEEKING
B.NHS_MSG_ROUND_OVER = NHS_MSG_ROUND_OVER
B.NHS_MSG_GAME_OVER = NHS_MSG_GAME_OVER
B.nhsBroadcastHouseLocked = nhsBroadcastHouseLocked
B.nhsBroadcastGameplayHousePin = nhsBroadcastGameplayHousePin

-- Dedupe when the same NHS line arrives via addon comm and visible chat in the same tick (or twice).
local nhsSyncDedupeAt, nhsSyncDedupeKey = 0, nil
local function nhsGroupSyncLineRecentlyHandled(senderName, text)
  local sk = type(senderName) == "string" and Ambiguate(senderName, "none") or ""
  local key = sk .. "\0" .. text
  local now = GetTime()
  if nhsSyncDedupeKey == key and (now - nhsSyncDedupeAt) < 0.35 then
    return true
  end
  nhsSyncDedupeKey = key
  nhsSyncDedupeAt = now
  return false
end

local function nhsNormalizeSyncSender(senderName)
  if type(senderName) ~= "string" then
    return ""
  end
  return (senderName:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function nhsDispatchGroupNhsLine(senderName, text)
  senderName = nhsNormalizeSyncSender(senderName)
  if nhsGroupSyncLineRecentlyHandled(senderName, text) then
    return
  end
  if nhsApplyFoundSyncFromChat(senderName, text) then
    return
  end
  nhsApplyGroupSyncFromLeader(senderName, text)
end

local function nhsAddonCommChannelAllowed(channel)
  if type(channel) ~= "string" or channel == "" then
    return false
  end
  local c = strupper(channel)
  return c == "PARTY" or c == "RAID" or c == "INSTANCE_CHAT"
end

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(NHS_ADDON_PREFIX)
end

local nhsSyncChatFrame = CreateFrame("Frame")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_ADDON")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_PARTY")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_RAID")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_RAID_WARNING")
nhsSyncChatFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    if prefix ~= NHS_ADDON_PREFIX then
      return
    end
    if not nhsAddonCommChannelAllowed(channel) then
      return
    end
    if type(msg) ~= "string" or msg:sub(1, #NHS_CHAT_TAG) ~= NHS_CHAT_TAG then
      return
    end
    nhsDispatchGroupNhsLine(sender, msg)
    return
  end
  if InCombatLockdown() then
    return
  end
  local text, sender = ...
  if type(text) ~= "string" or text:sub(1, #NHS_CHAT_TAG) ~= NHS_CHAT_TAG then
    return
  end
  nhsDispatchGroupNhsLine(sender, text)
end)
