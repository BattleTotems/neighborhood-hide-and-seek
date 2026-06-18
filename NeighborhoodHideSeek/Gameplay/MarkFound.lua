--[[
  Designated seeker: mark target found (manual + auto on PLAYER_TARGET_CHANGED).
  Expects GameSession exports, GroupSync.BroadcastSeekerFound, SeekerModeBridge.getUI.
  Load after GroupSync.lua (see .toc).

  Non-leader seeker: we update this client's found list first (foundSet / foundOrder), then
  BroadcastSeekerFound, then NHS.RefreshGameSessionUi (main frame if built, else session HUD only).
  Debug: /nhs debugfound — prints roster + keys when a step is blocked (debugFoundSync on).
  Debug: /nhs debugsync  — traces DoCountdown return values, addon messages sent/received, and phase sync.
]]

local NHS = NeighborhoodHideSeek
local B = assert(NHS.SeekerModeBridge, "NeighborhoodHideSeek.SeekerModeBridge missing (load order).")
local State = NHS.State
local Phase = NHS.Phase

-- opts.quiet: no prints on failure (used when auto-marking on target change).
local function markTargetFound(opts)
  opts = opts or {}
  local quiet = opts.quiet == true
  if not State.seekerMode then
    if not quiet then
      print("|cffff8800[NHS]|r Enter seeker mode first.")
    end
    return
  end
  if State.phase ~= Phase.SEARCHING then
    if not quiet then
      print("|cffff8800[NHS]|r Mark found is only available during the searching phase.")
    end
    return
  end
  if not NHS.LocalPlayerIsDesignatedSeeker() then
    if NHS.debugFoundSync and NHS.DebugDumpFoundSyncState then
      NHS.DebugDumpFoundSyncState("Mark found blocked: not designated seeker")
    end
    if not quiet then
      print("|cffff8800[NHS]|r Only the designated seeker can mark players found.")
    end
    return
  end
  if not UnitExists("target") then
    if not quiet then
      print("|cffff8800[NHS]|r No target.")
    end
    return
  end
  if not UnitIsPlayer("target") then
    if not quiet then
      print("|cffff8800[NHS]|r Target a player in your party or raid.")
    end
    return
  end
  if UnitIsUnit("target", "player") then
    if not quiet then
      print("|cffff8800[NHS]|r Pick another group member (not yourself).")
    end
    return
  end
  local key = NHS.UnitSortKey("target")
  if not key then
    local name = UnitName("target")
    if not name then
      return
    end
    key = Ambiguate(name, "none")
  end
  if not NHS.UnitIsInGroupRoster("target") then
    if not quiet then
      print("|cffff8800[NHS]|r Target must be in your party or raid.")
    end
    return
  end
  if NHS.CanonicalGroupSortKey then
    key = NHS.CanonicalGroupSortKey(key)
  end
  -- Prevent marking any of the designated seekers as found.
  local dskKeys = NHS.GetDesignatedSeekerKeys and NHS.GetDesignatedSeekerKeys() or {}
  for _, dsk in ipairs(dskKeys) do
    if NHS.GroupSortKeysEquivalent(key, dsk) then
      if not quiet then
        print("|cffff8800[NHS]|r You cannot mark a seeker as found.")
      end
      return
    end
  end
  local modeId = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
  local disp = UnitName("target") or Ambiguate(key, "short")

  -- Sardines mode: seeker joins the sardine rather than marking the hider found.
  -- The dskKeys loop above already blocks targeting current seekers. Any group member who
  -- passed that check is either the sardine or a seeker who already joined and was removed
  -- from the seeker list — both are valid targets, so no further validity check is needed.
  if modeId == "sardines" then
    local myKey = NHS.LocalPlayerSortKey()
    if not myKey then return end
    if State.foundSet[myKey] then return end
    -- Broadcast before modifying state so the seeker check in the broadcast still passes.
    if NHS.GroupSync and NHS.GroupSync.BroadcastSardineJoined then
      NHS.GroupSync.BroadcastSardineJoined()
    end
    State.foundSet[myKey] = true
    State.foundOrder[#State.foundOrder + 1] = myKey
    for i = #State.gameLockedSeekerKeys, 1, -1 do
      if NHS.GroupSortKeysEquivalent(State.gameLockedSeekerKeys[i], myKey) then
        table.remove(State.gameLockedSeekerKeys, i)
        break
      end
    end
    for i = #State.remoteSeekerKeys, 1, -1 do
      if NHS.GroupSortKeysEquivalent(State.remoteSeekerKeys[i], myKey) then
        table.remove(State.remoteSeekerKeys, i)
        break
      end
    end
    if State.seekerMode and NHS.SetSeekerMode then NHS.SetSeekerMode(false) end
    print(("|cff88ff88[NHS]|r Joined the sardine with %s!"):format(disp))
    if NHS.TryLeaderAutoReveal then NHS.TryLeaderAutoReveal() end
    if NHS.SyncHiddenRangePoll then NHS.SyncHiddenRangePoll() end
    if NHS.RefreshGameSessionUi then
      NHS.RefreshGameSessionUi()
    else
      local UI = B.getUI()
      if UI.RefreshFound then UI.RefreshFound() elseif NHS.SessionHudUpdate then NHS.SessionHudUpdate() end
    end
    NHS.PersistGameSessionToSaved()
    return
  end

  if State.foundSet[key] then
    return
  end

  -- Hot Potato mode: seeker and found hider swap roles.
  if modeId == "hot_potato" then
    local isNoTagback = State.hotPotatoTaggedBy and (
      (NHS.RosterIdentityEqual and NHS.RosterIdentityEqual(key, State.hotPotatoTaggedBy))
      or key == State.hotPotatoTaggedBy
    )
    if isNoTagback then
      if not quiet then
        print("|cffff8800[NHS]|r No tagbacks! Find someone else.")
      end
      return
    end
    local myKey = NHS.LocalPlayerSortKey()
    if not myKey then return end
    -- Broadcast before wiping seekerKeys so the seeker check in the broadcast still passes.
    if NHS.GroupSync and NHS.GroupSync.BroadcastHotPotatoSwap then
      NHS.GroupSync.BroadcastHotPotatoSwap(key)
    end
    State.foundOrder[#State.foundOrder + 1] = myKey
    wipe(State.gameLockedSeekerKeys)
    State.gameLockedSeekerKeys[1] = key
    State.hotPotatoTaggedBy = myKey
    -- All players stay in seeker mode throughout Hot Potato; no transition needed here.
    print(("|cff88ff88[NHS]|r Hot Potato! %s is now the seeker."):format(disp))
    if NHS.SyncHiddenRangePoll then NHS.SyncHiddenRangePoll() end
    if NHS.RefreshGameSessionUi then
      NHS.RefreshGameSessionUi()
    else
      local UI = B.getUI()
      if UI.RefreshFound then UI.RefreshFound() elseif NHS.SessionHudUpdate then NHS.SessionHudUpdate() end
    end
    NHS.PersistGameSessionToSaved()
    return
  end

  State.foundSet[key] = true
  State.foundOrder[#State.foundOrder + 1] = key
  -- Conquer mode: add the found player to the seeker list so they can broadcast finds.
  -- NOTE: only gameLockedSeekerKeys is extended here — gameRotationUsed is intentionally
  -- NOT updated. Conquer-conscripted seekers must remain eligible for future rounds;
  -- only the originally-confirmed seeker(s) (marked in nhsDoConfirmSeeker) count toward
  -- the per-player seeker rotation.
  if NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId() == "conquer" then
    local alreadySeeker = false
    for _, k in ipairs(dskKeys) do
      if NHS.GroupSortKeysEquivalent(k, key) then alreadySeeker = true; break end
    end
    if not alreadySeeker then
      if State.gameSessionActive then
        State.gameLockedSeekerKeys[#State.gameLockedSeekerKeys + 1] = key
      elseif State.remoteSessionActive then
        State.remoteSeekerKeys[#State.remoteSeekerKeys + 1] = key
      end
    end
  end
  print(("|cff88ff88[NHS]|r Marked found: %s"):format(disp))
  NHS.GroupSync.BroadcastSeekerFound(key)
  if NHS.TryLeaderAutoReveal then
    NHS.TryLeaderAutoReveal()
  end
  if NHS.OvertimeOnFound then
    NHS.OvertimeOnFound()
  end
  if NHS.SyncHiddenRangePoll then
    NHS.SyncHiddenRangePoll()
  end
  if NHS.RefreshGameSessionUi then
    NHS.RefreshGameSessionUi()
  else
    local UI = B.getUI()
    if UI.RefreshFound then
      UI.RefreshFound()
    elseif NHS.SessionHudUpdate then
      NHS.SessionHudUpdate()
    end
  end
  NHS.PersistGameSessionToSaved()
end

NHS.MarkTargetFound = markTargetFound

local nhsSeekerAutoMarkFrame = CreateFrame("Frame")
nhsSeekerAutoMarkFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
nhsSeekerAutoMarkFrame:SetScript("OnEvent", function()
  if not State.seekerMode or State.phase ~= Phase.SEARCHING then
    return
  end
  if not NHS.LocalPlayerIsDesignatedSeeker() then
    return
  end
  markTargetFound({ quiet = true })
end)
