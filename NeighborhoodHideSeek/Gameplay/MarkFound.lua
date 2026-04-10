--[[
  Designated seeker: mark target found (manual + auto on PLAYER_TARGET_CHANGED).
  Expects GameSession exports, GroupSync.BroadcastSeekerFound, SeekerModeBridge.getUI.
  Load after GroupSync.lua (see .toc).

  Non-leader seeker: we update this client's found list first (foundSet / foundOrder), then
  BroadcastSeekerFound, then NHS.RefreshGameSessionUi (main frame if built, else session HUD only).
  Debug: /nhs debugfound — prints roster + keys when a step is blocked (debugFoundSync on).
]]

local NHS = NeighborhoodHideSeek
local B = assert(NHS.SeekerModeBridge, "NeighborhoodHideSeek.SeekerModeBridge missing (load order).")
local State = NHS.State

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
  if State.roundPhase ~= "searching" then
    if not quiet then
      print("|cffff8800[NHS]|r Mark found is only available during the searching phase.")
    end
    return
  end
  if not NHS.LocalPlayerIsDesignatedSeeker() then
    if NHS.debugFoundSync and NHS.DebugDumpFoundSyncState then
      NHS.DebugDumpFoundSyncState("Mark found blocked: LocalPlayerIsDesignatedSeeker is false")
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
  local dsk = NHS.GetDesignatedSeekerKey()
  if dsk and NHS.GroupSortKeysEquivalent(key, dsk) then
    if not quiet then
      print("|cffff8800[NHS]|r You cannot mark the seeker as found.")
    end
    return
  end
  if State.foundSet[key] then
    return
  end
  local disp = UnitName("target") or Ambiguate(key, "short")
  State.foundSet[key] = true
  State.foundOrder[#State.foundOrder + 1] = key
  print(("|cff88ff88[NHS]|r Marked found: %s"):format(disp))
  NHS.GroupSync.BroadcastSeekerFound(key)
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
  if not State.seekerMode or State.roundPhase ~= "searching" then
    return
  end
  if not NHS.LocalPlayerIsDesignatedSeeker() then
    if NHS.debugFoundSync and NHS.DebugDumpFoundSyncState then
      NHS.DebugDumpFoundSyncState("Auto mark (target change) blocked: not designated seeker")
    end
    return
  end
  markTargetFound({ quiet = true })
end)
