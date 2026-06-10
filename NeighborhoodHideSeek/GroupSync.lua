--[[
  Group sync: CHAT_MSG_ADDON only (no party/raid chat listeners — avoids combat/instance limits).
  Leaders/seekers still SendChatMessage the same lines for humans when not InCombatLockdown();
  addon payload always sent so followers stay in sync.
  Core.lua assigns GroupSyncBridge; Gameplay/GameSession.lua patches roster/persist/sync fields;
  Gameplay/SessionHud.lua patches nhsSessionHudUpdate — load GameSession and SessionHud before
  this file (see .toc).
]]

local NHS = NeighborhoodHideSeek
local C = assert(NHS.GroupSyncBridge, "NeighborhoodHideSeek.GroupSyncBridge missing (load order).")
local Phase = NHS.Phase
local IsRoundPhase = NHS.IsRoundPhase

local NHS_CHAT_TAG = "[NHS]"
local NHS_MSG_ROUND_START = "[NHS] Round Start: "
local NHS_MSG_SESSION_START = "[NHS] Game session started"
local NHS_MSG_HOUSE = "[NHS] House: "
-- Addon + visible chat line (no seeker suffix; roster key comes from Round Start / saved state).
local NHS_MSG_HIDING = "[NHS] Hiding Starts Now"
local NHS_MSG_SEEKING = "[NHS] The Seeking Begins!: "
local NHS_MSG_ROUND_OVER = "[NHS] Round is over!"
local NHS_MSG_GAME_OVER = "[NHS] Game Over! Thanks for playing!"
local NHS_MSG_GAME_MODE = "[NHS] Game mode: "
local NHS_MSG_FOUND_PREFIX = "[NHS] Found: "
local NHS_MSG_REVEALING = "[NHS] The Revealing Begins!"
local NHS_MSG_NP_NEAREST = "[NHS] NP Nearest: "
local NHS_MSG_HIDER_READY = "[NHS] Hider Ready: "
local NHS_MSG_SARDINE_JOIN = "[NHS] Sardine: "
local NHS_MSG_HP_SWAP = "[NHS] HP Swap: "
-- Separator embedded in the addon-only house payload to carry both key and display in one message.
-- \31 (unit separator) is safe in addon messages and never appears in house names or persistence keys.
local NHS_HOUSE_KEY_SEP = "\31"

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

-- PARTY for open-world groups; RAID for raids; INSTANCE_CHAT for LFG/instance squads (PARTY/RAID
-- addon delivery can fail there — followers would stay on "Preparing" if phase lines never arrive).
local function nhsAddonSyncChatType()
  if IsInRaid() then
    return "RAID"
  end
  local inst = LE_PARTY_CATEGORY_INSTANCE or 2
  if IsInGroup(inst) then
    return "INSTANCE_CHAT"
  end
  return "PARTY"
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
  local ch = nhsAddonSyncChatType()
  if NHS.debugSync then
    print(("|cffffcc00[NHS] debugsync|r SendAddonMessage prefix=%s ch=%s msg=%s"):format(
      NHS_ADDON_PREFIX, tostring(ch), tostring(message)))
  end
  local ok, err = pcall(C_ChatInfo.SendAddonMessage, NHS_ADDON_PREFIX, message, ch)
  if NHS.debugSync and not ok then
    print(("|cffffcc00[NHS] debugsync|r SendAddonMessage ERROR: %s"):format(tostring(err)))
  end
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

-- Party: normal party chat. Raid: raid warning (center screen) so [NHS] lines stand out in chat.
local function nhsGroupSyncChannel()
  return IsInRaid() and "RAID_WARNING" or "PARTY"
end

-- Visible chat for players; Blizzard can block or error this in combat — skip and rely on addon sync.
local function nhsGameplaySendChatIfOutOfCombat(text, channel)
  if not text or text == "" or not channel then
    return
  end
  if InCombatLockdown() then
    return
  end
  pcall(SendChatMessage, text, channel)
end

local function nhsBroadcastLeaderSync(message, sendChat)
  if not IsInGroup() or not C.nhsIsRoundLeader() or not message or message == "" then
    return
  end
  if #message > 255 then
    return
  end
  if sendChat ~= false then
    nhsGameplaySendChatIfOutOfCombat(message, nhsGroupSyncChannel())
  end
  nhsSendAddonSyncPayload(message)
end

-- Sends Round Start to addon sync (backwards-compatible) but a custom string to visible chat.
local function nhsBroadcastRoundStart(keyStr, chatMsg)
  if not IsInGroup() or not C.nhsIsRoundLeader() or not keyStr or keyStr == "" then
    return
  end
  local addonMsg = NHS_MSG_ROUND_START .. keyStr
  if #addonMsg > 255 then
    return
  end
  nhsSendAddonSyncPayload(addonMsg)
  local msg = (type(chatMsg) == "string" and chatMsg ~= "" and #chatMsg <= 255) and chatMsg or addonMsg
  nhsGameplaySendChatIfOutOfCombat(msg, nhsGroupSyncChannel())
end

-- key (optional): the house persistence key. When provided, the addon payload carries
-- "<key>\31<display>" so followers can store the stable key for stats while still displaying
-- the human-readable name. Chat always receives the plain display name (unchanged for humans).
-- Old clients receive the combined addon payload and store it verbatim as remoteHouseDisplay
-- (garbled, accepted trade-off). New clients split on NHS_HOUSE_KEY_SEP to extract both.
local function nhsBroadcastHouseLocked(display, sendChat, key)
  if type(display) ~= "string" or display == "" then
    return
  end
  local safe = NHS.HousingPinShare.SanitizeForChat(display)
  -- Chat: always the human-readable display name (behaviour unchanged).
  local chatMsg = NHS_MSG_HOUSE .. safe
  if #chatMsg > 250 then
    chatMsg = NHS_MSG_HOUSE .. safe:sub(1, math.max(1, 250 - #NHS_MSG_HOUSE - 1)) .. "…"
  end
  if sendChat ~= false then
    nhsGameplaySendChatIfOutOfCombat(chatMsg, nhsGroupSyncChannel())
  end
  -- Addon: persistence key embedded before separator so followers can use it for stats.
  local addonMsg
  if type(key) == "string" and key ~= "" then
    local combined = NHS_MSG_HOUSE .. key .. NHS_HOUSE_KEY_SEP .. safe
    if #combined <= 255 then
      addonMsg = combined
    else
      -- Combined too long: key only. Follower won't get a clean display from this message.
      local keyOnly = NHS_MSG_HOUSE .. key
      addonMsg = #keyOnly <= 255 and keyOnly or chatMsg
    end
  else
    addonMsg = chatMsg
  end
  nhsSendAddonSyncPayload(addonMsg)
end

-- After [NHS] House: … — waypoint link in chat for players (when out of combat) + [NHS] coords on addon for sync.
local function nhsBroadcastGameplayHousePin(entry, rowIndex, labelText, stableKey)
  if not IsInGroup() or not C.nhsIsRoundLeader() then
    return false
  end
  local mapID, x, y
  if entry ~= nil and rowIndex ~= nil then
    mapID, x, y = NHS.GetPinCoordsForHouseEntry(entry, rowIndex)
  end
  if (not mapID or mapID == 0 or x == nil or y == nil) and type(stableKey) == "string" and stableKey ~= "" then
    mapID, x, y = NHS.SavedHouses.GetSavedHousePinCoords(stableKey)
  end
  if not mapID or mapID == 0 or x == nil or y == nil then
    return false
  end
  local ch = nhsGroupSyncChannel()
  local fb = NHS.HousingPinShare.CoordinateMessage(mapID, x, y, labelText)
  fb = NHS.HousingPinShare.SanitizeForChat(fb)
  local sentAddon = false
  if fb ~= "" and #fb <= 255 then
    nhsSendAddonSyncPayload(fb)
    sentAddon = true
  end
  local link = NHS.HousingPinShare.BuildWaypointHyperlink(mapID, x, y)
  if link and #link <= 255 then
    nhsGameplaySendChatIfOutOfCombat(link, ch)
    return true
  end
  if fb ~= "" and #fb <= 255 then
    nhsGameplaySendChatIfOutOfCombat(fb, ch)
    return true
  end
  return sentAddon
end

local function nhsClearRemoteRoundSync()
  wipe(C.State.remoteSeekerKeys)
  wipe(C.State.hiderReadySet)
  C.clearFound()
  if NHS.SyncHiddenRangePoll then
    NHS.SyncHiddenRangePoll()
  end
end

-- Parse a comma-separated seeker key string into a list, sanitising each part.
local function nhsParseSeekersString(keysStr)
  local keys = {}
  for part in keysStr:gmatch("[^,]+") do
    local k = Ambiguate((part:match("^%s*(.-)%s*$") or part), "none")
    if k ~= "" then
      keys[#keys + 1] = k
    end
  end
  return keys
end

local function nhsRemoteFollowerSyncRoundState(keysStr, phase)
  if type(keysStr) ~= "string" or keysStr == "" then
    return
  end
  local keys = nhsParseSeekersString(keysStr)
  if #keys == 0 then
    return
  end
  C.State.remoteSessionActive = true
  -- Determine whether this is a new round by comparing the first key.
  local firstNew = keys[1]
  local firstOld = C.State.remoteSeekerKeys[1]
  local newRound = not IsRoundPhase(C.State.phase)
  if not newRound then
    if C.nhsRosterIdentityEqual then
      newRound = not C.nhsRosterIdentityEqual(firstOld or "", firstNew)
    else
      newRound = firstOld ~= firstNew
    end
  end
  if newRound then
    C.clearFound()
  end
  wipe(C.State.remoteSeekerKeys)
  for _, k in ipairs(keys) do
    C.State.remoteSeekerKeys[#C.State.remoteSeekerKeys + 1] = k
  end
  C.State.phase = phase
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
          wipe(C.State.remoteSeekerKeys)
          C.State.remoteSeekerKeys[1] = m.key
          C.State.phase = Phase.SEARCHING
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
  if C.State.phase ~= Phase.SEARCHING then
    if NHS.debugFoundSync and NHS.DebugDumpFoundSyncState then
      NHS.DebugDumpFoundSyncState(
        "Incoming [NHS] Found ignored: phase is not searching",
        ("phase=%q"):format(tostring(C.State.phase))
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
  if NHS.OvertimeOnFound then
    NHS.OvertimeOnFound()
  end
  -- Conquer mode: found players join the seeker team so they can broadcast finds.
  -- NOTE: only the seeker key list is extended here — gameRotationUsed is intentionally
  -- NOT updated. Conquer-conscripted seekers must remain eligible for future rounds;
  -- only the originally-confirmed seeker(s) count toward the per-player seeker rotation.
  if NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId() == "conquer" and IsRoundPhase(C.State.phase) then
    local alreadyIn = false
    local targetList = C.State.gameSessionActive and C.State.gameLockedSeekerKeys
      or (C.State.remoteSessionActive and C.State.remoteSeekerKeys)
    if targetList then
      for _, k in ipairs(targetList) do
        if k == foundKey or (C.nhsRosterIdentityEqual and C.nhsRosterIdentityEqual(k, foundKey)) then
          alreadyIn = true
          break
        end
      end
      if not alreadyIn then
        targetList[#targetList + 1] = foundKey
      end
    end
  end
  if NHS.RefreshGameSessionUi then
    NHS.RefreshGameSessionUi()
  elseif C.UI.RefreshFound then
    C.UI.RefreshFound()
  elseif C.UI.RefreshAll then
    C.UI.RefreshAll()
  elseif C.nhsSessionHudUpdate then
    C.nhsSessionHudUpdate()
  end
  -- If this client's player was just found, hide the Toy & Seek hider HUD immediately.
  if NHS.SyncToyAndSeekMode then
    NHS.SyncToyAndSeekMode()
  end
  if NHS.TryLeaderAutoReveal then
    NHS.TryLeaderAutoReveal()
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
  nhsGameplaySendChatIfOutOfCombat(msg, nhsSeekerFoundSyncChannel())
  nhsSendAddonSyncPayload(msg)
end

-- Normal Plus: seeker broadcasts the closest hidden player's key (addon-only) every 10 s.
-- The named player's client receives this and performs a roar emote.
local function nhsBroadcastNormalPlusNearest(playerKey)
  if not IsInGroup() then return end
  if type(playerKey) ~= "string" or playerKey == "" then return end
  if not C.nhsLocalPlayerIsDesignatedSeeker or not C.nhsLocalPlayerIsDesignatedSeeker() then return end
  local msg = NHS_MSG_NP_NEAREST .. playerKey
  if #msg > 255 then return end
  nhsSendAddonSyncPayload(msg)
end
NHS.BroadcastNormalPlusNearest = nhsBroadcastNormalPlusNearest

-- Any hider: broadcast "[NHS] Hider Ready: <playerKey>" to the group during the hiding phase.
local function nhsBroadcastHiderReady()
  if not IsInGroup() then return end
  local myKey = C.nhsLocalPlayerSortKey and C.nhsLocalPlayerSortKey()
  if not myKey or myKey == "" then return end
  local msg = NHS_MSG_HIDER_READY .. myKey
  if #msg > 255 then return end
  C.State.hiderReadySet[myKey] = true
  nhsSendAddonSyncPayload(msg)
  if NHS.RefreshGameSessionUi then
    NHS.RefreshGameSessionUi()
  elseif C.nhsSessionHudUpdate then
    C.nhsSessionHudUpdate()
  end
end
NHS.BroadcastHiderReady = nhsBroadcastHiderReady

-- Sardines mode: seeker broadcasts their own key when they find and join the sardine's hiding spot.
local function nhsBroadcastSardineJoined()
  if not IsInGroup() then return end
  if not C.nhsLocalPlayerIsDesignatedSeeker or not C.nhsLocalPlayerIsDesignatedSeeker() then return end
  local myKey = C.nhsLocalPlayerSortKey and C.nhsLocalPlayerSortKey()
  if not myKey or myKey == "" then return end
  local msg = NHS_MSG_SARDINE_JOIN .. myKey
  if #msg > 255 then return end
  nhsGameplaySendChatIfOutOfCombat(msg, nhsSeekerFoundSyncChannel())
  nhsSendAddonSyncPayload(msg)
end
NHS.BroadcastSardineJoined = nhsBroadcastSardineJoined

-- Hot Potato mode: current seeker broadcasts when they tag a hider (newSeekerKey becomes the seeker).
-- MarkFound.lua validates seeker status before calling; no redundant check here.
local function nhsBroadcastHotPotatoSwap(newSeekerKey)
  if not IsInGroup() then return end
  if type(newSeekerKey) ~= "string" or newSeekerKey == "" then return end
  local msg = NHS_MSG_HP_SWAP .. newSeekerKey
  if #msg > 255 then return end
  nhsGameplaySendChatIfOutOfCombat(msg, nhsSeekerFoundSyncChannel())
  nhsSendAddonSyncPayload(msg)
end
NHS.BroadcastHotPotatoSwap = nhsBroadcastHotPotatoSwap

-- Returns true if this was an [NHS] Hider Ready: line (handled or ignored); false otherwise.
local function nhsApplyHiderReady(senderName, text)
  local body = text:match("^%[NHS%]%s*Hider Ready:%s*(.+)%s*$")
  if not body then return false end
  if C.State.phase ~= Phase.HIDING then return true end
  local readyKey = Ambiguate((body:match("^%s*(.-)%s*$") or body), "none")
  if not readyKey or readyKey == "" then return true end
  -- Validate the sender key matches the claimed player key (prevents spoofing).
  local senderKey = Ambiguate(type(senderName) == "string" and senderName or "", "none")
  if senderKey == "" then return true end
  if not C.nhsRosterIdentityEqual or not C.nhsRosterIdentityEqual(senderKey, readyKey) then
    return true
  end
  if C.nhsCanonicalGroupSortKey then
    readyKey = C.nhsCanonicalGroupSortKey(readyKey)
  end
  C.State.hiderReadySet[readyKey] = true
  if NHS.RefreshGameSessionUi then
    NHS.RefreshGameSessionUi()
  elseif C.nhsSessionHudUpdate then
    C.nhsSessionHudUpdate()
  end
  return true
end

-- Sardines: seeker joined the sardine's hiding spot.
local function nhsApplySardineJoined(senderName, text)
  local body = text:match("^%[NHS%] Sardine:%s*(.+)%s*$")
  if not body then return false end
  if C.State.phase ~= Phase.SEARCHING then return true end
  if not C.nhsChatSenderIsDesignatedSeeker(senderName) then return true end
  local joinedKey = Ambiguate((body:match("^%s*(.-)%s*$") or body), "none")
  if not joinedKey or joinedKey == "" then return true end
  if C.nhsCanonicalGroupSortKey then joinedKey = C.nhsCanonicalGroupSortKey(joinedKey) end
  -- Dedup: MarkFound already applied this locally on the sender's client.
  if C.State.foundSet[joinedKey] then
    C.nhsPersistGameSessionToSaved()
    return true
  end
  C.State.foundSet[joinedKey] = true
  C.State.foundOrder[#C.State.foundOrder + 1] = joinedKey
  -- Remove the joined seeker from the seeker list.
  local targetList = C.State.gameSessionActive and C.State.gameLockedSeekerKeys
    or (C.State.remoteSessionActive and C.State.remoteSeekerKeys)
  if targetList then
    for i = #targetList, 1, -1 do
      local k = targetList[i]
      if k == joinedKey or (C.nhsRosterIdentityEqual and C.nhsRosterIdentityEqual(k, joinedKey)) then
        table.remove(targetList, i)
        break
      end
    end
  end
  -- The joining player exits seeker mode on their own client.
  local myKey = C.nhsLocalPlayerSortKey and C.nhsLocalPlayerSortKey()
  if myKey and C.nhsRosterIdentityEqual and C.nhsRosterIdentityEqual(myKey, joinedKey) then
    if C.State.seekerMode and NHS.SetSeekerMode then NHS.SetSeekerMode(false) end
  end
  if NHS.RefreshGameSessionUi then
    NHS.RefreshGameSessionUi()
  elseif C.nhsSessionHudUpdate then
    C.nhsSessionHudUpdate()
  end
  if NHS.TryLeaderAutoReveal then NHS.TryLeaderAutoReveal() end
  if NHS.SyncHiddenRangePoll then NHS.SyncHiddenRangePoll() end
  C.nhsPersistGameSessionToSaved()
  return true
end

-- Hot Potato: seeker tagged a hider, they swap roles.
local function nhsApplyHotPotatoSwap(senderName, text)
  local body = text:match("^%[NHS%] HP Swap:%s*(.+)%s*$")
  if not body then return false end
  if C.State.phase ~= Phase.SEARCHING then return true end
  if not C.nhsChatSenderIsDesignatedSeeker(senderName) then return true end
  local newSeekerKey = Ambiguate((body:match("^%s*(.-)%s*$") or body), "none")
  if not newSeekerKey or newSeekerKey == "" then return true end
  if C.nhsCanonicalGroupSortKey then newSeekerKey = C.nhsCanonicalGroupSortKey(newSeekerKey) end
  local targetList = C.State.gameSessionActive and C.State.gameLockedSeekerKeys
    or (C.State.remoteSessionActive and C.State.remoteSeekerKeys)
  if not targetList or #targetList == 0 then return true end
  local oldSeekerKey = targetList[1]
  -- Dedup: MarkFound already applied this swap on the sender's client.
  if C.nhsRosterIdentityEqual and C.nhsRosterIdentityEqual(oldSeekerKey or "", newSeekerKey) then
    return true
  end
  -- Record who passed the potato (the old seeker) in the round history.
  C.State.foundOrder[#C.State.foundOrder + 1] = oldSeekerKey
  -- Swap: wipe and set new seeker.
  wipe(targetList)
  targetList[1] = newSeekerKey
  -- No-tagback: the new seeker cannot immediately tag back the old seeker.
  C.State.hotPotatoTaggedBy = oldSeekerKey
  -- All players stay in seeker mode throughout Hot Potato; no transitions needed here.
  if NHS.RefreshGameSessionUi then
    NHS.RefreshGameSessionUi()
  elseif C.nhsSessionHudUpdate then
    C.nhsSessionHudUpdate()
  end
  if NHS.SyncHiddenRangePoll then NHS.SyncHiddenRangePoll() end
  C.nhsPersistGameSessionToSaved()
  return true
end

-- Revealing phase: addon sync always uses the standard [NHS] line (followers key off it);
-- visible chat carries a custom congratulatory message built by the leader.
local function nhsBroadcastRevealingPhase(chatMsg)
  if not IsInGroup() or not C.nhsIsRoundLeader() then return end
  nhsSendAddonSyncPayload(NHS_MSG_REVEALING)
  local msg = (type(chatMsg) == "string" and chatMsg ~= "" and #chatMsg <= 255)
    and chatMsg or NHS_MSG_REVEALING
  nhsGameplaySendChatIfOutOfCombat(msg, nhsGroupSyncChannel())
end

local function nhsApplyGroupSyncFromLeader(senderName, text)
  if C.nhsIsRoundLeader() or not IsInGroup() then
    if NHS.debugSync then
      print(("|cffffcc00[NHS] debugsync|r ApplyFromLeader skipped: isLeader=%s inGroup=%s"):format(
        tostring(C.nhsIsRoundLeader()), tostring(IsInGroup())))
    end
    return
  end
  if not nhsChatSenderIsGroupLeader(senderName) then
    if NHS.debugSync then
      print(("|cffffcc00[NHS] debugsync|r ApplyFromLeader rejected: sender=%s not group leader"):format(tostring(senderName)))
    end
    return
  end
  if NHS.debugSync then
    print(("|cffffcc00[NHS] debugsync|r ApplyFromLeader accepted: sender=%s msg=%s"):format(tostring(senderName), tostring(text)))
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
    local keys = nhsParseSeekersString(seekerPart)
    if #keys > 0 then
      local firstNew = keys[1]
      local firstOld = C.State.remoteSeekerKeys[1]
      local sameRound = false
      if IsRoundPhase(C.State.phase) and firstOld then
        if C.nhsRosterIdentityEqual then
          sameRound = C.nhsRosterIdentityEqual(firstOld, firstNew)
        else
          sameRound = firstOld == firstNew
        end
      end
      if sameRound then
        C.State.remoteSessionActive = true
      else
        C.clearFound()
        C.State.remoteSessionActive = true
        wipe(C.State.remoteSeekerKeys)
        for _, k in ipairs(keys) do
          C.State.remoteSeekerKeys[#C.State.remoteSeekerKeys + 1] = k
        end
        C.State.phase = Phase.PENDING
        local seekerDisplayNames = {}
        for _, k in ipairs(keys) do
          seekerDisplayNames[#seekerDisplayNames + 1] = Ambiguate(k, "short")
        end
        C.State.gameSeekerHistory[#C.State.gameSeekerHistory + 1] = table.concat(seekerDisplayNames, ", ")
      end
    end
  elseif text:match("^%[NHS%]%s*Game mode:%s*.+") then
    local modePart = text:match("^%[NHS%]%s*Game mode:%s*(.+)%s*$")
    if modePart then
      local modeId = (modePart:match("^%s*(.-)%s*$") or modePart):lower()
      if NHS.IsValidGameMode and NHS.IsValidGameMode(modeId) then
        C.State.remoteSessionActive = true
        C.State.remoteGameMode = modeId
        C.State.phase = Phase.PICK_SEEKER
        -- Toy & Seek: follower triggers ownership broadcast so pool can be computed.
        if modeId == "toy_and_seek" and C.nhsTASOnModeSelected then
          C.nhsTASOnModeSelected()
        end
      end
    end
  elseif text:match("^%[NHS%]%s*Game session started%s*$") then
    C.State.remoteSessionActive = true
    C.State.phase = Phase.PICK_HOUSE
    C.State.remoteGameMode = nil
    wipe(C.State.gameSeekerHistory)
    wipe(C.State.gameHouseHistory)
    wipe(C.State.pastRounds)
    if NHS.ClearCompletedPastRoundsArchive then
      NHS.ClearCompletedPastRoundsArchive()
    end
    C.State.remoteHouseDisplay = nil
    C.State.remoteHouseKey = nil
  elseif text:match("^%[NHS%]%s*House:%s*.+") then
    local housePart = text:match("^%[NHS%]%s*House:%s*(.+)%s*$")
    if housePart then
      C.State.remoteSessionActive = true
      C.State.phase = Phase.PICK_GAME_MODE
      C.State.remoteGameMode = nil
      -- New format: "<key>\31<display>". Old format: plain display string.
      local sepPos = housePart:find(NHS_HOUSE_KEY_SEP, 1, true)
      local disp
      if sepPos and sepPos > 1 then
        C.State.remoteHouseKey = housePart:sub(1, sepPos - 1)
        local rawDisp = housePart:sub(sepPos + 1)
        disp = rawDisp:match("^%s*(.-)%s*$") or rawDisp
        if disp == "" then disp = C.State.remoteHouseKey end
      else
        C.State.remoteHouseKey = nil
        disp = housePart:match("^%s*(.-)%s*$") or housePart
      end
      C.State.remoteHouseDisplay = disp
      if C.State.gameHouseHistory[#C.State.gameHouseHistory] ~= disp then
        C.State.gameHouseHistory[#C.State.gameHouseHistory + 1] = disp
        if NHS.LiveRefreshIfOpen then NHS.LiveRefreshIfOpen("houses") end
      end
    end
  elseif text:match("^%[NHS%]%s*Round is over!%s*$") then
    C.nhsAppendPastRoundSnapshotIfActiveRound()
    nhsClearRemoteRoundSync()
    C.State.remoteHouseDisplay = nil
    C.State.remoteHouseKey = nil
    C.State.phase = Phase.PICK_HOUSE
    C.State.remoteGameMode = nil
    if C.State.seekerMode and NHS.SetSeekerMode then
      NHS.SetSeekerMode(false)
    end
  elseif text:match("^%[NHS%]%s*Game Over! Thanks for playing!%s*$") then
    if NHS.ArchiveCompletedPastRoundsForReload then
      NHS.ArchiveCompletedPastRoundsForReload()
    end
    C.State.remoteSessionActive = false
    C.State.phase = Phase.NONE
    wipe(C.State.gameSeekerHistory)
    wipe(C.State.gameHouseHistory)
    C.State.remoteHouseDisplay = nil
    C.State.remoteHouseKey = nil
    C.State.remoteGameMode = nil
    nhsClearRemoteRoundSync()
    if C.State.seekerMode and NHS.SetSeekerMode then
      NHS.SetSeekerMode(false)
    end
  else
    -- Legacy (pre–no-suffix): seeker after colon; still accepted from older clients.
    local hideKey = text:match("^%[NHS%]%s*Hiding Starts Now:%s*(.+)%s*$")
    if hideKey then
      nhsRemoteFollowerSyncRoundState(hideKey, Phase.HIDING)
      if NHS.PlayHidingPhaseStartSound then
        NHS.PlayHidingPhaseStartSound()
      end
    elseif text:match("^%[NHS%]%s*Hiding Starts Now%s*$") then
      C.State.remoteSessionActive = true
      if IsRoundPhase(C.State.phase) then
        C.State.phase = Phase.HIDING
        if NHS.PlayHidingPhaseStartSound then
          NHS.PlayHidingPhaseStartSound()
        end
      end
    else
      local seekKey = text:match("^%[NHS%]%s*The Seeking Begins!:%s*(.+)%s*$")
      if seekKey then
        wipe(C.State.hiderReadySet)
        nhsRemoteFollowerSyncRoundState(seekKey, Phase.SEARCHING)
      elseif text:match("^%[NHS%]%s*The Seeking Begins!%s*$") then
        C.State.remoteSessionActive = true
        if IsRoundPhase(C.State.phase) then
          wipe(C.State.hiderReadySet)
          C.State.phase = Phase.SEARCHING
        end
      elseif text:match("^%[NHS%]%s*The Revealing Begins!%s*$") then
        C.State.remoteSessionActive = true
        if IsRoundPhase(C.State.phase) then
          C.State.phase = Phase.REVEALING
          if C.State.seekerMode and NHS.SetSeekerMode then
            NHS.SetSeekerMode(false)
          end
        end
      end
    end
  end
  if C.nhsSeekerAutoModeSyncToPhase then
    C.nhsSeekerAutoModeSyncToPhase()
  end
  if NHS.SyncHiddenRangePoll then
    NHS.SyncHiddenRangePoll()
  end
  if C.UI.RefreshAll then
    C.UI.RefreshAll()
  elseif C.UI.RefreshGameRounds then
    C.UI.RefreshGameRounds()
  end
  C.nhsPersistGameSessionToSaved()
  if C.nhsSessionHudUpdate then
    C.nhsSessionHudUpdate()
  end
end

-- After /reload or zoning: followers may still show "Preparing" if they missed HIDING/SEEKING addon
-- lines. Addon-only (no party/raid chat): live phase transitions already posted chat; repeating
-- RAID_WARNING on every PEW was noisy. Pick-house / pick-seeker never hit this path.
local function nhsLeaderRebroadcastActiveRoundPhaseIfNeeded()
  if not IsInGroup() or not C.nhsIsRoundLeader or not C.nhsIsRoundLeader() then
    return
  end
  if not C.State.gameSessionActive or not IsRoundPhase(C.State.phase) then
    return
  end
  local rp = C.State.phase
  if rp == Phase.PENDING then
    return
  end
  if rp == Phase.HIDING then
    nhsSendAddonSyncPayload(NHS_MSG_HIDING)
  elseif rp == Phase.SEARCHING then
    local keys = C.State.gameLockedSeekerKeys
    local keyParts = {}
    for _, k in ipairs(keys) do
      if type(k) == "string" and k ~= "" then
        keyParts[#keyParts + 1] = k
      end
    end
    if #keyParts > 0 then
      nhsSendAddonSyncPayload(NHS_MSG_SEEKING .. table.concat(keyParts, ","))
    else
      nhsSendAddonSyncPayload("[NHS] The Seeking Begins!")
    end
  elseif rp == Phase.REVEALING then
    nhsSendAddonSyncPayload(NHS_MSG_REVEALING)
  end
end

-- Leader-only: replay the same addon lines a new joiner would need, in order, so the group
-- converges on the leader’s current phase (safe duplicates: House history dedupes; Round Start
-- no-ops when the same seeker round is already active).
local function nhsLeaderBroadcastGameplayCatchUpSync()
  if not IsInGroup() then
    return false, "Join a party or raid to sync with other players."
  end
  if not C.nhsIsRoundLeader or not C.nhsIsRoundLeader() then
    return false, "Only the party/raid leader can send group catch-up sync."
  end
  if not C.State.gameSessionActive then
    return false, "Start a game session first."
  end

  local sent = false
  local function mark()
    sent = true
  end

  local gp = C.State.phase

  if gp == Phase.PICK_HOUSE then
    -- New first phase: session started, no house or game mode selected yet.
    nhsBroadcastLeaderSync(NHS_MSG_SESSION_START)
    mark()
  elseif gp == Phase.PICK_GAME_MODE then
    -- New second phase: house confirmed, game mode not yet selected.
    nhsBroadcastLeaderSync(NHS_MSG_SESSION_START)
    mark()
    if C.State.gameLockedHouseDisplay and C.State.gameLockedHouseDisplay ~= "" then
      nhsBroadcastHouseLocked(C.State.gameLockedHouseDisplay, nil, C.State.gameLockedHouseKey)
      mark()
      if C.State.gameLockedHouseKey then
        nhsBroadcastGameplayHousePin(
          C.State.gameLockedHouseLiveEntry,
          C.State.gameLockedHouseLiveIndex,
          C.State.gameLockedHouseDisplay,
          C.State.gameLockedHouseKey
        )
      end
    end
  elseif gp == Phase.PICK_SEEKER then
    -- New third phase: house and game mode both confirmed.
    if not (C.State.gameLockedHouseDisplay and C.State.gameLockedHouseDisplay ~= "") then
      return false, "Confirm a house first so group sync can re-send it."
    end
    nhsBroadcastHouseLocked(C.State.gameLockedHouseDisplay, nil, C.State.gameLockedHouseKey)
    mark()
    if C.State.gameLockedHouseKey then
      nhsBroadcastGameplayHousePin(
        C.State.gameLockedHouseLiveEntry,
        C.State.gameLockedHouseLiveIndex,
        C.State.gameLockedHouseDisplay,
        C.State.gameLockedHouseKey
      )
    end
    if C.State.gameMode and NHS.IsValidGameMode and NHS.IsValidGameMode(C.State.gameMode) then
      local addonMsg = NHS_MSG_GAME_MODE .. C.State.gameMode
      if #addonMsg <= 255 then
        nhsSendAddonSyncPayload(addonMsg)
        mark()
      end
    end
  elseif IsRoundPhase(gp) then
    if C.State.gameLockedHouseDisplay and C.State.gameLockedHouseDisplay ~= "" and C.State.gameLockedHouseKey then
      nhsBroadcastHouseLocked(C.State.gameLockedHouseDisplay, nil, C.State.gameLockedHouseKey)
      mark()
      nhsBroadcastGameplayHousePin(
        C.State.gameLockedHouseLiveEntry,
        C.State.gameLockedHouseLiveIndex,
        C.State.gameLockedHouseDisplay,
        C.State.gameLockedHouseKey
      )
    end
    -- Game mode must arrive before Round Start so the follower's phase transitions correctly.
    if C.State.gameMode and NHS.IsValidGameMode and NHS.IsValidGameMode(C.State.gameMode) then
      local addonMsg = NHS_MSG_GAME_MODE .. C.State.gameMode
      if #addonMsg <= 255 then
        nhsSendAddonSyncPayload(addonMsg)
        mark()
      end
    end
    local keyParts = {}
    for _, k in ipairs(C.State.gameLockedSeekerKeys) do
      if type(k) == "string" and k ~= "" then
        keyParts[#keyParts + 1] = k
      end
    end
    if #keyParts > 0 then
      nhsBroadcastLeaderSync(NHS_MSG_ROUND_START .. table.concat(keyParts, ","))
      mark()
    end
    if gp == Phase.HIDING or gp == Phase.SEARCHING or gp == Phase.REVEALING then
      nhsLeaderRebroadcastActiveRoundPhaseIfNeeded()
      mark()
    end
  end

  if not sent then
    return false, "Nothing to sync — start a round (lock a seeker) so re-send can include round lines."
  end
  return true
end

-- Game-mode sync: addon payload carries the stable ID; visible party/raid chat carries the human label.
-- This keeps the protocol stable across renames and future localisation.
local function nhsBroadcastLeaderGameMode(modeId)
  if not IsInGroup() or not C.nhsIsRoundLeader() then
    return
  end
  if not (NHS.IsValidGameMode and NHS.IsValidGameMode(modeId)) then
    return
  end
  local addonMsg = NHS_MSG_GAME_MODE .. modeId
  if #addonMsg <= 255 then
    nhsSendAddonSyncPayload(addonMsg)
  end
  local label = (NHS.GameModeHudLabel and NHS.GameModeHudLabel(modeId)) or modeId
  local chatMsg = NHS_MSG_GAME_MODE .. label
  if #chatMsg <= 255 then
    nhsGameplaySendChatIfOutOfCombat(chatMsg, nhsGroupSyncChannel())
  end
  local warning = NHS.GameModeWarning and NHS.GameModeWarning(modeId)
  if warning and #warning <= 255 then
    nhsGameplaySendChatIfOutOfCombat(warning, nhsGroupSyncChannel())
  end
  -- Toy & Seek: leader triggers ownership broadcast on their own client immediately.
  if modeId == "toy_and_seek" then
    local bmf = NHS.BuildMainFrameBridge
    if bmf and bmf.nhsTASOnModeSelected then
      bmf.nhsTASOnModeSelected()
    end
  end
end

NHS.GroupSync = {
  BroadcastSeekerFound = nhsBroadcastSeekerFound,
  BroadcastSardineJoined = nhsBroadcastSardineJoined,
  BroadcastHotPotatoSwap = nhsBroadcastHotPotatoSwap,
  ClearRemoteRound = nhsClearRemoteRoundSync,
  LeaderRebroadcastActiveRoundPhaseIfNeeded = nhsLeaderRebroadcastActiveRoundPhaseIfNeeded,
  LeaderBroadcastGameplayCatchUpSync = nhsLeaderBroadcastGameplayCatchUpSync,
}

local B = NHS.BuildMainFrameBridge
B.nhsBroadcastLeaderSync = nhsBroadcastLeaderSync
B.nhsBroadcastRoundStart = nhsBroadcastRoundStart
B.NHS_MSG_ROUND_START = NHS_MSG_ROUND_START
B.NHS_MSG_SESSION_START = NHS_MSG_SESSION_START
B.NHS_MSG_HIDING = NHS_MSG_HIDING
B.NHS_MSG_SEEKING = NHS_MSG_SEEKING
B.NHS_MSG_REVEALING = NHS_MSG_REVEALING
B.NHS_MSG_ROUND_OVER = NHS_MSG_ROUND_OVER
B.NHS_MSG_GAME_OVER = NHS_MSG_GAME_OVER
B.NHS_MSG_GAME_MODE = NHS_MSG_GAME_MODE
B.nhsBroadcastHouseLocked = nhsBroadcastHouseLocked
B.nhsBroadcastGameplayHousePin = nhsBroadcastGameplayHousePin
B.nhsLeaderBroadcastGameplayCatchUpSync = nhsLeaderBroadcastGameplayCatchUpSync
B.nhsBroadcastLeaderGameMode = nhsBroadcastLeaderGameMode
B.nhsBroadcastRevealingPhase = nhsBroadcastRevealingPhase

-- Dedupe duplicate addon lines in the same tick (or rapid resends).
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

-- Returns true if this was an [NHS] NP Nearest: line (handled or ignored); false otherwise.
-- If the local player is the named nearest hider, signals them with an emote.
-- STAND is called first to break sleep, sit, or any other blocking emote state.
-- Uses ROAR in shapeshift forms (works in cat/bear/etc.), WHISTLE otherwise.
local function nhsApplyNormalPlusNearest(senderName, text)
  local body = text:match("^%[NHS%]%s*NP Nearest:%s*(.+)%s*$")
  if not body then return false end
  if C.State.phase ~= Phase.SEARCHING then return true end
  if not C.nhsChatSenderIsDesignatedSeeker(senderName) then return true end
  local nearestKey = Ambiguate((body:match("^%s*(.-)%s*$") or body), "none")
  if not nearestKey or nearestKey == "" then return true end
  local myKey = C.nhsLocalPlayerSortKey and C.nhsLocalPlayerSortKey()
  if not myKey then return true end
  if C.nhsRosterIdentityEqual and C.nhsRosterIdentityEqual(myKey, nearestKey) then
    if not InCombatLockdown() then
      local formID = GetShapeshiftFormID and GetShapeshiftFormID()
      local emote = (formID and formID ~= 0) and "ROAR" or "WHISTLE"
      -- STAND first to break sleep or any other blocking emote state, then a short
      -- delay so the stand animation clears before the audio emote fires.
      pcall(DoEmote, "STAND")
      C_Timer.After(0.5, function()
        pcall(DoEmote, emote)
      end)
    end
  end
  return true
end

local function nhsDispatchGroupNhsLine(senderName, text)
  senderName = nhsNormalizeSyncSender(senderName)
  if nhsGroupSyncLineRecentlyHandled(senderName, text) then
    if NHS.debugSync then
      print(("|cffffcc00[NHS] debugsync|r Deduped (within 0.35s): sender=%s"):format(tostring(senderName)))
    end
    return
  end
  if nhsApplySardineJoined(senderName, text) then
    return
  end
  if nhsApplyHotPotatoSwap(senderName, text) then
    return
  end
  if nhsApplyFoundSyncFromChat(senderName, text) then
    return
  end
  if nhsApplyNormalPlusNearest(senderName, text) then
    return
  end
  if nhsApplyHiderReady(senderName, text) then
    return
  end
  if C.nhsTASApplyStrike and C.nhsTASApplyStrike(senderName, text) then
    return
  end
  if NHS.VersionCheck and NHS.VersionCheck.ApplyVersionQuery(senderName, text) then return end
  if NHS.VersionCheck and NHS.VersionCheck.ApplyVersionReply(senderName, text) then return end
  nhsApplyGroupSyncFromLeader(senderName, text)
end

-- Route through the client error handler so a bad line does not silently break sync (and BugSack can capture it).
local function nhsDispatchGroupNhsLineSafe(senderName, text)
  local ok, err = pcall(nhsDispatchGroupNhsLine, senderName, text)
  if ok then
    return
  end
  local fn = geterrorhandler and geterrorhandler()
  if fn then
    fn(err)
  else
    print("|cffff4444[NHS]|r Group sync: " .. tostring(err))
  end
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
nhsSyncChatFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
nhsSyncChatFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    -- Re-register after zone transitions; housing zone boundaries can reset
    -- server-side prefix registration, silently dropping all incoming addon messages.
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      C_ChatInfo.RegisterAddonMessagePrefix(NHS_ADDON_PREFIX)
    end
    return
  end
  if event ~= "CHAT_MSG_ADDON" then
    return
  end
  local prefix, msg, channel, sender = ...
  if prefix ~= NHS_ADDON_PREFIX then
    return
  end
  if NHS.debugSync then
    print(("|cffffcc00[NHS] debugsync|r CHAT_MSG_ADDON prefix=%s ch=%s sender=%s msg=%s"):format(
      tostring(prefix), tostring(channel), tostring(sender), tostring(msg)))
  end
  if not nhsAddonCommChannelAllowed(channel) then
    if NHS.debugSync then
      print(("|cffffcc00[NHS] debugsync|r Dropped: channel %s not allowed"):format(tostring(channel)))
    end
    return
  end
  if type(msg) ~= "string" or msg:sub(1, #NHS_CHAT_TAG) ~= NHS_CHAT_TAG then
    if NHS.debugSync then
      print(("|cffffcc00[NHS] debugsync|r Dropped: msg missing [NHS] tag"  ))
    end
    return
  end
  nhsDispatchGroupNhsLineSafe(sender, msg)
end)
