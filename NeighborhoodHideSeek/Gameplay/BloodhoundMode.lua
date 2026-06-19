--[[
  Bloodhound mode: polls hider positions every 1s, building a rolling history.
  "Stationary seconds" for a hider = how long they have stayed within
  MOVE_THRESHOLD_YARDS of their current position, measured by walking backwards
  through their history until a position falls outside that radius.
  Every 6s (after a 20s grace period at round start), the seeker's arrow locks
  onto whichever hider has been stationary the longest — provided they have been
  still for at least MIN_STATIONARY_SEC. Arrow color shifts blue → yellow → red
  as the seeker closes in on the target.
  Load after PlayerRange.lua.
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State
local Phase = NHS.Phase

local MOVE_THRESHOLD_YARDS = 5
local POSITION_POLL_SEC    = 1
local WAYPOINT_POLL_SEC    = 6
local MIN_STATIONARY_SEC   = 7
local GRACE_PERIOD_SEC     = 20
local MAX_HISTORY          = 120   -- 2 minutes at 1s polling

local posHistory       = {}   -- key → array of { t, x, y }, newest last
local currentTargetKey = nil
local searchStartTime  = nil

local function nhsBloodhoundShouldRun()
  if State.phase ~= Phase.SEARCHING then return false end
  local id = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
  if id ~= "bloodhound" then return false end
  if not NHS.LocalPlayerIsDesignatedSeeker then return false end
  return NHS.LocalPlayerIsDesignatedSeeker()
end

local function nhsBloodhoundReset()
  posHistory       = {}
  currentTargetKey = nil
  searchStartTime  = nil
end

-- Returns how many seconds the given hider has been within MOVE_THRESHOLD_YARDS
-- of their current position, by walking backwards through their position history.
local function getStationarySeconds(key)
  local hist = posHistory[key]
  if not hist or #hist < 2 then return 0 end
  local current = hist[#hist]
  for i = #hist - 1, 1, -1 do
    local entry = hist[i]
    local dx = entry.x - current.x
    local dy = entry.y - current.y
    if math.sqrt(dx * dx + dy * dy) >= MOVE_THRESHOLD_YARDS then
      return current.t - entry.t
    end
  end
  -- All history within threshold — stationary for the entire recorded window.
  return current.t - hist[1].t
end

-- Arrow color: blue (cold/far) → yellow (warm/mid) → red (hot/close).
local function getArrowColor(dist)
  if dist >= 40 then
    return 0.3, 0.6, 1.0
  elseif dist >= 20 then
    local t = (40 - dist) / 20   -- 0 at 40y, 1 at 20y
    return 0.3 + 0.7 * t,
           0.6 + 0.2 * t,
           1.0 - 0.8 * t
  else
    local t = (20 - dist) / 20   -- 0 at 20y, 1 at 0y
    return 1.0,
           0.8 - 0.6 * t,
           0.2
  end
end

-- Arrow frame: updates every frame, rotates toward currentTargetKey and
-- tints by distance.
local arrowFrame = CreateFrame("Frame", nil, UIParent)
arrowFrame:SetSize(128, 128)
arrowFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
arrowFrame:SetFrameStrata("HIGH")
arrowFrame:Hide()

local arrowTex = arrowFrame:CreateTexture(nil, "OVERLAY")
arrowTex:SetAllPoints()
arrowTex:SetTexture("Interface\\Minimap\\ROTATING-MINIMAPARROW")

arrowFrame:SetScript("OnUpdate", function(self)
  if not currentTargetKey then return end
  local hist = posHistory[currentTargetKey]
  if not hist or #hist == 0 then return end
  local target = hist[#hist]
  local py, px = UnitPosition("player")
  if not px or not py then return end
  local dx = target.x - px
  local dy = target.y - py
  local dist = math.sqrt(dx * dx + dy * dy)
  local bearing = math.atan2(dx, dy)
  arrowTex:SetRotation(bearing - GetPlayerFacing())
  arrowTex:SetVertexColor(getArrowColor(dist))
end)

-- 1s position poll: append each hider's current position to their history.
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
        local hist = posHistory[m.key]
        if not hist then
          hist = {}
          posHistory[m.key] = hist
        end
        hist[#hist + 1] = { t = now, x = ux, y = uy }
        if #hist > MAX_HISTORY then
          table.remove(hist, 1)
        end
      end
    end
  end
end)

-- 6s target poll: pick the longest-stationary qualifying hider.
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
  -- Suppress targeting during the opening grace period.
  if not searchStartTime or (GetTime() - searchStartTime) < GRACE_PERIOD_SEC then
    currentTargetKey = nil
    arrowFrame:Hide()
    return
  end
  local entries = NHS.GetHiddenPlayerEntries and NHS.GetHiddenPlayerEntries() or {}
  if #entries == 0 then
    currentTargetKey = nil
    arrowFrame:Hide()
    return
  end
  local bestKey = nil
  local bestSec = 0
  for _, m in ipairs(entries) do
    local s = getStationarySeconds(m.key)
    if s >= MIN_STATIONARY_SEC and s > bestSec then
      bestSec = s
      bestKey  = m.key
    end
  end
  currentTargetKey = bestKey
  if currentTargetKey then
    arrowFrame:Show()
  else
    arrowFrame:Hide()
  end
end)

function NHS.SyncBloodhoundPolls()
  if nhsBloodhoundShouldRun() then
    if not searchStartTime then
      searchStartTime = GetTime()
    end
    bloodhoundPosPoll._acc    = POSITION_POLL_SEC   -- fire first snapshot immediately
    bloodhoundTargetPoll._acc = 0                   -- first target selection after 6s
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
