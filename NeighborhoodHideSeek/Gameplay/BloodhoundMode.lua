--[[
  Bloodhound mode: polls hider positions every 2s to track movement.
  Every 10s, picks whichever hider has been stationary longest as the current target.
  A custom rotating arrow always points toward that target regardless of distance or map.
  Load after PlayerRange.lua.
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State
local Phase = NHS.Phase

local MOVE_THRESHOLD_YARDS = 3
local POSITION_POLL_SEC    = 2
local WAYPOINT_POLL_SEC    = 10

local lastPos          = {}   -- key → { x, y }
local lastMovedTime    = {}   -- key → GetTime() when last moved >= threshold
local currentTargetKey = nil  -- key of the hider the arrow currently points at

local function nhsBloodhoundShouldRun()
  if State.phase ~= Phase.SEARCHING then return false end
  local id = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
  if id ~= "bloodhound" then return false end
  if not NHS.LocalPlayerIsDesignatedSeeker then return false end
  return NHS.LocalPlayerIsDesignatedSeeker()
end

local function nhsBloodhoundReset()
  lastPos          = {}
  lastMovedTime    = {}
  currentTargetKey = nil
end

-- Arrow frame: updates every frame, rotates to face currentTargetKey.
local arrowFrame = CreateFrame("Frame", nil, UIParent)
arrowFrame:SetSize(64, 64)
arrowFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
arrowFrame:SetFrameStrata("HIGH")
arrowFrame:Hide()

local arrowTex = arrowFrame:CreateTexture(nil, "OVERLAY")
arrowTex:SetAllPoints()
arrowTex:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPARROW")

arrowFrame:SetScript("OnUpdate", function(self)
  if not currentTargetKey then return end
  local target = lastPos[currentTargetKey]
  if not target then return end
  local py, px = UnitPosition("player")
  if not px or not py then return end
  local dx = target.x - px
  local dy = target.y - py
  -- bearing from north, clockwise-positive (WoW y increases northward)
  local bearing = math.atan2(dx, dy)
  arrowTex:SetRotation(bearing - GetPlayerFacing())
end)

-- 2s position poll: snapshot hider positions and update movement timestamps.
local bloodhoundPosPoll = CreateFrame("Frame")
bloodhoundPosPoll:Hide()

bloodhoundPosPoll:SetScript("OnUpdate", function(self, elapsed)
  self._acc = (self._acc or 0) + elapsed
  if self._acc < POSITION_POLL_SEC then return end
  self._acc = 0
  if not nhsBloodhoundShouldRun() then
    self:Hide()
    return
  end
  local now = GetTime()
  local entries = NHS.GetHiddenPlayerEntries and NHS.GetHiddenPlayerEntries() or {}
  for _, m in ipairs(entries) do
    if m.unit then
      local uy, ux = UnitPosition(m.unit)
      if ux and uy then
        local prev = lastPos[m.key]
        if prev then
          local dx = ux - prev.x
          local dy = uy - prev.y
          if math.sqrt(dx * dx + dy * dy) >= MOVE_THRESHOLD_YARDS then
            lastMovedTime[m.key] = now
          end
        else
          lastMovedTime[m.key] = now
        end
        lastPos[m.key] = { x = ux, y = uy }
      end
    end
  end
end)

-- 10s target poll: find the longest-stationary hider and point the arrow at them.
local bloodhoundTargetPoll = CreateFrame("Frame")
bloodhoundTargetPoll:Hide()

bloodhoundTargetPoll:SetScript("OnUpdate", function(self, elapsed)
  self._acc = (self._acc or 0) + elapsed
  if self._acc < WAYPOINT_POLL_SEC then return end
  self._acc = 0
  if not nhsBloodhoundShouldRun() then
    self:Hide()
    arrowFrame:Hide()
    return
  end
  local entries = NHS.GetHiddenPlayerEntries and NHS.GetHiddenPlayerEntries() or {}
  if #entries == 0 then
    currentTargetKey = nil
    arrowFrame:Hide()
    return
  end
  local bestKey   = nil
  local oldestTime = math.huge
  for _, m in ipairs(entries) do
    local t = lastMovedTime[m.key] or 0
    if t < oldestTime then
      oldestTime = t
      bestKey    = m.key
    end
  end
  currentTargetKey = bestKey
  arrowFrame:Show()
end)

function NHS.SyncBloodhoundPolls()
  if nhsBloodhoundShouldRun() then
    bloodhoundPosPoll._acc  = POSITION_POLL_SEC  -- fire first position snapshot immediately
    bloodhoundTargetPoll._acc = 0                -- first target selection after 10s
    bloodhoundPosPoll:Show()
    bloodhoundTargetPoll:Show()
  else
    bloodhoundPosPoll:Hide()
    bloodhoundTargetPoll:Hide()
    arrowFrame:Hide()
    nhsBloodhoundReset()
  end
end

local bmf = NHS.BuildMainFrameBridge
if bmf then
  bmf.nhsSyncBloodhoundPolls = NHS.SyncBloodhoundPolls
end

local gsb = NHS.GroupSyncBridge
if gsb then
  gsb.nhsSyncBloodhoundPolls = NHS.SyncBloodhoundPolls
end

NHS.SyncBloodhoundPolls()
