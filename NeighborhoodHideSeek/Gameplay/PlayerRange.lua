--[[
  Approximate distance to hidden players (UnitPosition + item range fallback).
  Session HUD shows only the closest hidden player's band while seeking; hidden lists are names only.
  Load after GameSession.lua; before SessionHud.lua.
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State
local Phase = NHS.Phase
local IsRoundPhase = NHS.IsRoundPhase

-- Item use-range bands (~yards). Each band lists several item IDs (LibRangeCheck-style);
-- the first ID that returns true wins. 10498 does not work on party/raid units in retail.
local RANGE_BANDS = {
  {
    label = "BURNING", -- ~3–5
    itemIDs = {
      37727, -- Rub Acorn (~3)
    },
  },
  {
    label = "HOT", -- ~10
    itemIDs = {
      32321, -- Sparrowhawk Net
    },
  },
  {
    label = "WARM", -- ~15
    itemIDs = {
      43159, -- Master Summoner's Staff
    },
  },
  {
    label = "COOL", -- ~20
    itemIDs = {
      21519, -- Mistletoe
    },
  },
  {
    label = "COLD", -- ~25
    itemIDs = {
      17202, -- Snowball
    },
  },
}

local RANGE_SORT = {
  BURNING = 1,
  HOT = 2,
  WARM = 3,
  COOL = 4,
  COLD = 5,
  FREEZING = 6,
}

-- |cffRRGGBB…|r for session HUD (heat → cold).
local RANGE_COLORS = {
  BURNING = "ff4400",
  HOT = "ff9900",
  WARM = "ffdd33",
  COOL = "66ccff",
  COLD = "3399ff",
  FREEZING = "333333",
}

function NHS.ColorizeRangeLabel(label)
  if not label or label == "" then
    return "|cff888888—|r"
  end
  if label == "—" then
    return "|cff888888—|r"
  end
  local hex = RANGE_COLORS[label] or "ffffff"
  return ("|cff%s%s|r"):format(hex, label)
end

local function nhsGetGroupRoster()
  local bmf = NHS.BuildMainFrameBridge
  assert(bmf and bmf.nhsGetGroupRoster, "BuildMainFrameBridge.nhsGetGroupRoster missing (load order).")
  return bmf.nhsGetGroupRoster()
end

-- Returns a set (key→true) of all seeker keys to exclude from hidden-player lists.
local function nhsSeekerKeySetForHiddenLists()
  local set = {}
  local function addKeys(list)
    for _, k in ipairs(list) do
      set[k] = true
    end
  end
  if State.remoteSessionActive and IsRoundPhase(State.phase) then
    addKeys(State.remoteSeekerKeys)
  end
  if State.gameSessionActive and IsRoundPhase(State.phase) then
    addKeys(State.gameLockedSeekerKeys)
  end
  if State.gameSessionActive and State.phase == Phase.PICK_SEEKER then
    addKeys(State.gameCandidateKeys)
  end
  return set
end

local function nhsAnyItemInRange(itemIDs, unit)
  if not C_Item or not C_Item.IsItemInRange then
    return nil
  end
  local sawNil = false
  for i = 1, #itemIDs do
    local ok = C_Item.IsItemInRange(itemIDs[i], unit)
    if ok == true then
      return true
    elseif ok == nil then
      sawNil = true
    end
  end
  if sawNil then
    return nil
  end
  return false
end

local DISTANCE_BANDS = {
  { maxYd = 5, label = "BURNING" },
  { maxYd = 10, label = "HOT" },
  { maxYd = 15, label = "WARM" },
  { maxYd = 20, label = "COOL" },
  { maxYd = 25, label = "COLD" },
}

local function nhsDistanceYards(unit)
  if not UnitPosition then
    return nil
  end
  local py, px = UnitPosition("player")
  local uy, ux = UnitPosition(unit)
  if not px or not ux then
    return nil
  end
  local dx = px - ux
  local dy = py - uy
  return math.sqrt(dx * dx + dy * dy)
end

local function nhsRangeFromDistanceYards(d)
  for _, band in ipairs(DISTANCE_BANDS) do
    if d <= band.maxYd then
      return band.label
    end
  end
  return "FREEZING"
end

function NHS.GetApproxRange(unit)
  if not unit or not UnitExists(unit) then
    return nil
  end
  -- Prefer map distance: item checks are coarse (a 10y item is "in range" at 2y, and many 5y
  -- quest items never return true on party/raid units — e.g. item 10498 is not a player target).
  local d = nhsDistanceYards(unit)
  if d then
    return nhsRangeFromDistanceYards(d)
  end
  local anyNil = false
  for _, band in ipairs(RANGE_BANDS) do
    local inBand = nhsAnyItemInRange(band.itemIDs, unit)
    if inBand == true then
      return band.label
    elseif inBand == nil then
      anyNil = true
    end
  end
  if anyNil then
    return nil
  end
  return "FREEZING"
end

local function nhsHiddenPlayerEntries()
  local roleSet = nhsSeekerKeySetForHiddenLists()
  local roster = nhsGetGroupRoster()
  local entries = {}
  for _, m in ipairs(roster) do
    if not roleSet[m.key] and not State.foundSet[m.key] then
      entries[#entries + 1] = m
    end
  end
  return entries
end

function NHS.ShouldShowHiddenPlayerRanges()
  if not NHS.GameModeAllowsHotColdIndicator or not NHS.GameModeAllowsHotColdIndicator() then
    return false
  end
  if State.phase ~= Phase.SEARCHING then
    return false
  end
  if not NHS.LocalPlayerIsDesignatedSeeker then
    return false
  end
  if not NHS.LocalPlayerIsDesignatedSeeker() then
    return false
  end
  -- Normal Plus: hot/cold indicator only activates once exactly 1 hider remains.
  local modeId = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
  if modeId == "normal_plus" then
    return #nhsHiddenPlayerEntries() == 1
  end
  return true
end

-- Returns the roster entry (and distance in yards) of the closest hidden player, or nil.
-- Uses UnitPosition, so only works when the player's position is available via the group API.
function NHS.GetClosestHiddenPlayerEntry()
  local entries = nhsHiddenPlayerEntries()
  if #entries == 0 then
    return nil, nil
  end
  local bestEntry = nil
  local bestDist = math.huge
  for _, m in ipairs(entries) do
    if m.unit then
      local d = nhsDistanceYards(m.unit)
      if d and d < bestDist then
        bestDist = d
        bestEntry = m
      end
    end
  end
  return bestEntry, bestEntry and bestDist or nil
end

function NHS.GetClosestHiddenPlayerRange()
  if not NHS.ShouldShowHiddenPlayerRanges() then
    return nil
  end
  local entries = nhsHiddenPlayerEntries()
  if #entries == 0 then
    return nil
  end
  local bestLabel
  local bestSort = 99
  for _, m in ipairs(entries) do
    local range = NHS.GetApproxRange(m.unit)
    if range then
      local order = RANGE_SORT[range] or 99
      if order < bestSort then
        bestSort = order
        bestLabel = range
      end
    end
  end
  return bestLabel
end

-- Session HUD only: nearest hidden player band (no names). nil when not shown.
function NHS.FormatClosestHiddenRangeLine()
  if not NHS.ShouldShowHiddenPlayerRanges() then
    return nil
  end
  local entries = nhsHiddenPlayerEntries()
  if #entries == 0 then
    return nil
  end
  local label = NHS.GetClosestHiddenPlayerRange() or "—"
  return NHS.ColorizeRangeLabel(label)
end

function NHS.FormatHiddenPlayersLine()
  local entries = nhsHiddenPlayerEntries()
  local n = #entries
  if n == 0 then
    return "Hidden (0): —"
  end
  local parts = {}
  for _, m in ipairs(entries) do
    parts[#parts + 1] = Ambiguate(m.key, "short")
  end
  table.sort(parts)
  local maxShown = 14
  local commaList
  if #parts <= maxShown then
    commaList = table.concat(parts, ", ")
  else
    local shown = {}
    for i = 1, maxShown do
      shown[i] = parts[i]
    end
    commaList = table.concat(shown, ", ") .. (", +" .. tostring(#parts - maxShown) .. " more")
  end
  return ("Hidden (%d): %s"):format(n, commaList)
end

local hiddenRangePoll = CreateFrame("Frame")
hiddenRangePoll:Hide()
hiddenRangePoll._lastFmt = nil

hiddenRangePoll:SetScript("OnUpdate", function(self, elapsed)
  self._acc = (self._acc or 0) + elapsed
  if self._acc < 0.35 then
    return
  end
  self._acc = 0
  if not NHS.ShouldShowHiddenPlayerRanges() then
    self._lastFmt = nil
    self:Hide()
    return
  end
  local fmt = (NHS.FormatClosestHiddenRangeLine() or "") .. "|" .. NHS.FormatHiddenPlayersLine()
  if fmt == self._lastFmt then
    return
  end
  self._lastFmt = fmt
  if NHS.RefreshGameSessionUi then
    NHS.RefreshGameSessionUi()
  elseif NHS.SessionHudUpdate then
    NHS.SessionHudUpdate()
  end
end)

function NHS.SyncHiddenRangePoll()
  if NHS.ShouldShowHiddenPlayerRanges() then
    hiddenRangePoll._lastFmt = nil
    hiddenRangePoll:Show()
  else
    hiddenRangePoll._lastFmt = nil
    hiddenRangePoll:Hide()
  end
  if NHS.SyncNormalPlusNearestPoll then
    NHS.SyncNormalPlusNearestPoll()
  end
end

-- Normal Plus: every 10 s the seeker broadcasts the closest hidden player's key.
-- GroupSync receives this message and triggers DoEmote("WHISTLE") on the named player's client.
local function nhsNormalPlusShouldBroadcast()
  if State.phase ~= Phase.SEARCHING then return false end
  local id = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
  if id ~= "normal_plus" then return false end
  if not NHS.LocalPlayerIsDesignatedSeeker then return false end
  return NHS.LocalPlayerIsDesignatedSeeker()
end

local normalPlusNearestPoll = CreateFrame("Frame")
normalPlusNearestPoll:Hide()

normalPlusNearestPoll:SetScript("OnUpdate", function(self, elapsed)
  self._acc = (self._acc or 0) + elapsed
  if self._acc < 10 then return end
  self._acc = 0
  if not nhsNormalPlusShouldBroadcast() then
    self:Hide()
    return
  end
  local entry = NHS.GetClosestHiddenPlayerEntry()
  if entry and NHS.BroadcastNormalPlusNearest then
    NHS.BroadcastNormalPlusNearest(entry.key)
  end
end)

function NHS.SyncNormalPlusNearestPoll()
  if nhsNormalPlusShouldBroadcast() then
    -- Fire immediately on search start (acc=10), then every 10 s thereafter.
    normalPlusNearestPoll._acc = 10
    normalPlusNearestPoll:Show()
  else
    normalPlusNearestPoll._acc = 0
    normalPlusNearestPoll:Hide()
  end
end

NHS.HiddenRangePoll = hiddenRangePoll

local bmf = NHS.BuildMainFrameBridge
if bmf then
  bmf.nhsFormatHiddenPlayersLine = NHS.FormatHiddenPlayersLine
  bmf.nhsFormatClosestHiddenRangeLine = NHS.FormatClosestHiddenRangeLine
  bmf.nhsSyncHiddenRangePoll = NHS.SyncHiddenRangePoll
end

local gsb = NHS.GroupSyncBridge
if gsb then
  gsb.nhsSyncHiddenRangePoll = NHS.SyncHiddenRangePoll
end

NHS.SyncHiddenRangePoll()
