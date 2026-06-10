--[[
  Leader-only: when the revealing phase starts, mark every still-hidden player with a
  raid icon so the seeker can easily locate them in the housing zone.  Icons are cleared
  automatically when the round/session ends.

  Requires SetRaidTarget permission (party/raid leader or assistant).
  Load after Gameplay/MarkFound.lua and before Ui/MainFrame.lua (see .toc).

  Hook surface:
    NHS.OnLeaderRevealPhaseStart — called by nhsLeaderBroadcastRoundPhase(REVEALING) in GameSession.
    NHS.ClearRevealMarkers       — called by nhsResetGameSession in GameSession.
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State

-- Raid icon indices to assign, most eye-catching first.
-- WoW has 8 icons: 1=Star 2=Circle 3=Diamond 4=Triangle 5=Moon 6=Square 7=Cross 8=Skull.
local REVEAL_ICONS = { 8, 7, 6, 5, 4, 3, 2, 1 }

-- Unit IDs we marked this reveal phase, so we only clear our own icons.
local markedUnits = {}

local function nhsClearRevealMarkers()
  for _, unit in ipairs(markedUnits) do
    if UnitExists(unit) then
      pcall(SetRaidTarget, unit, 0)
    end
  end
  wipe(markedUnits)
end

local function nhsMarkUnfoundHiders()
  if not IsInGroup() then return end
  if not UnitIsGroupLeader("player") then return end

  -- Clear any icons left from a previous reveal before (re-)marking.
  nhsClearRevealMarkers()

  local seekerSet = {}
  for _, k in ipairs(State.gameLockedSeekerKeys) do
    seekerSet[k] = true
  end

  local roster = NHS.GetGroupRoster and NHS.GetGroupRoster() or {}
  local iconSlot = 1

  for _, m in ipairs(roster) do
    if not seekerSet[m.key] and not State.foundSet[m.key] then
      local icon = REVEAL_ICONS[iconSlot]
      if not icon then break end  -- more than 8 hidden players; no icons left
      local ok = pcall(SetRaidTarget, m.unit, icon)
      if ok then
        markedUnits[#markedUnits + 1] = m.unit
        iconSlot = iconSlot + 1
      end
    end
  end
end

NHS.OnLeaderRevealPhaseStart = nhsMarkUnfoundHiders
NHS.ClearRevealMarkers = nhsClearRevealMarkers
