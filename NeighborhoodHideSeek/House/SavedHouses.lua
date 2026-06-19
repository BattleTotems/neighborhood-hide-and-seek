--[[
  Saved house sizes / labels / pin coords (NHSV) and gameplay house pools.
  Expects NeighborhoodHideSeek hooks from House/Housing.lua (loaded before this file).
]]

local NHS = NeighborhoodHideSeek

local function ensureSaved()
  if NHS.EnsureSavedVars then
    NHS.EnsureSavedVars()
  end
end

local function presets()
  return NHS.ROUND_PRESETS
end

local function neighborIDFromEntry(entry)
  local f = NHS.NeighborIDFromEntry
  return f and f(entry) or nil
end

local function getPinCoords(entry, rowIndex)
  local f = NHS.GetPinCoordsForHouseEntry
  if f then
    return f(entry, rowIndex)
  end
  return nil, nil, nil
end

local function plotSortKeyFromSavedLabelOrKey(label, stableKey)
  local f = NHS.PlotSortKeyFromSavedLabelOrKey
  return f and f(label, stableKey) or stableKey
end

local function sortHouseListInPlace(list)
  local f = NHS.SortHouseListInPlace
  if f then
    f(list)
  end
end

local function labelFromEntry(entry, fallbackIndex)
  local f = NHS.LabelFromEntry
  return f and f(entry, fallbackIndex) or "?"
end

local S = {}
NHS.SavedHouses = S

-- Disambiguate same plot/GUID across neighborhoods (and subdivisions) in SavedVariables.
local NHS_PERSIST_KEY_SEP = "\1"
-- Inside the persistence tail (after first SOH): neighborhood .. STX .. subdivision .. ETX .. player.
local NHS_TAIL_PAIR_SEP = "\2"
local NHS_TAIL_PLAYER_SEP = "\3"

-- Builds the tail appended after NHS_PERSIST_KEY_SEP. All three components are optional;
-- pass nil to omit. Format: hood[\2sub][\3player]
local function persistenceTailFromHoodAndSub(neighborhoodName, subdivisionName, playerName)
  local h = type(neighborhoodName) == "string" and neighborhoodName:match("^%s*(.-)%s*$") or ""
  local s = type(subdivisionName) == "string" and subdivisionName:match("^%s*(.-)%s*$") or ""
  local p = type(playerName) == "string" and playerName:match("^%s*(.-)%s*$") or ""
  if h ~= "" and s ~= "" then
    return h .. NHS_TAIL_PAIR_SEP .. s .. (p ~= "" and (NHS_TAIL_PLAYER_SEP .. p) or "")
  end
  if h ~= "" then
    return h .. (p ~= "" and (NHS_TAIL_PLAYER_SEP .. p) or "")
  end
  if s ~= "" then
    return s  -- legacy fallback: sub without hood, no player appended
  end
  return ""
end

-- Returns just the hood portion of a tail, stripping subdivision and player.
local function persistenceTailHoodOnly(tail)
  if type(tail) ~= "string" then
    return ""
  end
  local pos2 = tail:find(NHS_TAIL_PAIR_SEP, 1, true)
  local pos3 = tail:find(NHS_TAIL_PLAYER_SEP, 1, true)
  local cut = nil
  if pos2 and pos2 > 1 then cut = pos2 end
  if pos3 and pos3 > 1 and (not cut or pos3 < cut) then cut = pos3 end
  return cut and tail:sub(1, cut - 1) or tail
end

-- Returns the tail with the player component removed (hood[\2sub] only).
local function persistenceTailWithoutPlayer(tail)
  if type(tail) ~= "string" then
    return ""
  end
  local pos = tail:find(NHS_TAIL_PLAYER_SEP, 1, true)
  return pos and tail:sub(1, pos - 1) or tail
end

-- Extracts the player name from a house display string.
-- Handles three formats:
--   "PlayerName"                    (group legacy / group display)
--   "Plot - PlayerName"             (neighborhood mode)
--   "Plot - PlayerName — ..."       (saved-list display with neighborhood info)
local function playerFromDisplay(display)
  if type(display) ~= "string" or display == "" then return nil end
  local remainder
  local dashPos = display:find(" - ", 1, true)
  if dashPos then
    remainder = display:sub(dashPos + 3)
  else
    remainder = display
  end
  -- Strip " — ..." suffix (em dash U+2014, UTF-8: \xE2\x80\x94)
  local emdashPos = remainder:find(" \226\128\148 ", 1, true)
  if emdashPos then
    remainder = remainder:sub(1, emdashPos - 1)
  end
  remainder = remainder:match("^%s*(.-)%s*$") or ""
  return remainder ~= "" and remainder or nil
end

-- Returns the trimmed player name from a live entry, or nil if unavailable/fallback.
local function trimmedPlayerNameFromEntry(entry, fallbackIndex)
  if not (NHS.EntryHasOwnerDisplay and NHS.EntryHasOwnerDisplay(entry)) then
    return nil
  end
  local f = NHS.HouseNameFromEntry
  if not f then return nil end
  local n = f(entry, fallbackIndex or 1)
  if type(n) ~= "string" then return nil end
  n = n:match("^%s*(.-)%s*$") or ""
  return n ~= "" and n or nil
end

function S.PersistenceKeyFromStableNeighborhoodSubdivision(stableKey, neighborhoodName, subdivisionName)
  if type(stableKey) ~= "string" or stableKey == "" then
    return nil
  end
  local tail = persistenceTailFromHoodAndSub(neighborhoodName, subdivisionName)
  if tail == "" then
    return stableKey
  end
  return stableKey .. NHS_PERSIST_KEY_SEP .. tail
end

function S.PersistenceKeyFromStableKeyAndNeighborhood(stableKey, neighborhoodName)
  return S.PersistenceKeyFromStableNeighborhoodSubdivision(stableKey, neighborhoodName, nil)
end

function S.BaseStableKeyFromPersistenceKey(persistenceKey)
  if type(persistenceKey) ~= "string" then
    return persistenceKey
  end
  local pos = persistenceKey:find(NHS_PERSIST_KEY_SEP, 1, true)
  if pos and pos > 1 then
    return persistenceKey:sub(1, pos - 1)
  end
  return persistenceKey
end

-- Returns (neighborhoodName, subdivisionName) parsed from a persistence key's tail.
-- Either value may be nil when not encoded in the key.
-- Used to detect neighborhood/subdivision changes between rounds for the group callout.
function S.NeighborhoodAndSubFromKey(persistenceKey)
  if type(persistenceKey) ~= "string" then
    return nil, nil
  end
  local sep = persistenceKey:find(NHS_PERSIST_KEY_SEP, 1, true)
  if not sep or sep >= #persistenceKey then
    return nil, nil
  end
  local tail = persistenceKey:sub(sep + 1)
  -- Strip the player component (\3...) if present.
  local playerSep = tail:find(NHS_TAIL_PLAYER_SEP, 1, true)
  if playerSep then
    tail = tail:sub(1, playerSep - 1)
  end
  -- Split into neighborhood and subdivision at the pair separator (\2).
  local pairSep = tail:find(NHS_TAIL_PAIR_SEP, 1, true)
  if pairSep then
    local hood = tail:sub(1, pairSep - 1)
    local sub  = tail:sub(pairSep + 1)
    return hood ~= "" and hood or nil, sub ~= "" and sub or nil
  end
  -- No pair separator: tail is the neighborhood name only.
  return tail ~= "" and tail or nil, nil
end

local function trimmedNeighborhoodName()
  local hood = NHS.GetNeighborhoodDisplayName and NHS.GetNeighborhoodDisplayName() or nil
  if type(hood) ~= "string" then
    return nil
  end
  hood = hood:match("^%s*(.-)%s*$") or ""
  if hood == "" then
    return nil
  end
  return hood
end

-- User-entered subdivision on the house list (replaces unreliable housing API / GUID slice ids).
local function trimmedManualSubdivisionForSave()
  ensureSaved()
  local sub = NHSV.savedHouseListSubdivision
  if type(sub) ~= "string" then
    return nil
  end
  sub = sub:match("^%s*(.-)%s*$") or ""
  if sub == "" then
    return nil
  end
  return sub
end

local function persistenceKeysForLookup(stable, player)
  local hood = trimmedNeighborhoodName()
  local sub = trimmedManualSubdivisionForSave()
  local seen = {}
  local keys = {}
  local function add(tail)
    local k = tail ~= "" and (stable .. NHS_PERSIST_KEY_SEP .. tail) or stable
    if not seen[k] then
      seen[k] = true
      keys[#keys + 1] = k
    end
  end
  -- Most specific to least specific; each level tried with and without player for compat.
  add(persistenceTailFromHoodAndSub(hood, sub, player))
  add(persistenceTailFromHoodAndSub(hood, sub))
  add(persistenceTailFromHoodAndSub(hood, nil, player))
  add(persistenceTailFromHoodAndSub(hood, nil))
  add("")  -- bare stable key
  return keys
end

local function normalizeNeighborhoodDedup(s)
  if type(s) ~= "string" then
    return ""
  end
  local t = s:match("^%s*(.-)%s*$") or ""
  return string.lower(t)
end

-- Neighborhood string for a SavedVariables key (suffix after SOH, else stored name for legacy keys).
local function neighborhoodLabelFromSavedKey(k)
  if type(k) ~= "string" then
    return ""
  end
  local pos = k:find(NHS_PERSIST_KEY_SEP, 1, true)
  if pos and pos < #k then
    return k:sub(pos + 1)
  end
  ensureSaved()
  local t = type(NHSV.houseNeighborhoodNames) == "table" and NHSV.houseNeighborhoodNames[k]
  if type(t) == "string" then
    return t
  end
  return ""
end

local function nhsRemoveSavedHouseKey(k)
  NHSV.houseSizes[k] = nil
  NHSV.houseLabels[k] = nil
  NHSV.housePinCoords[k] = nil
  if type(NHSV.houseNeighborhoodNames) == "table" then
    NHSV.houseNeighborhoodNames[k] = nil
  end
  if type(NHSV.houseSubdivisionNames) == "table" then
    NHSV.houseSubdivisionNames[k] = nil
  end
end

-- Before writing targetKey: drop legacy base-only row and same-slot rows superseded by the new tail
-- (neighborhood ± subdivision), without removing a different subdivision under the same neighborhood name.
local function wipePersistentKeysSupersededBySave(stable, tailWant, targetKey)
  ensureSaved()
  if not stable or not targetKey then
    return
  end
  local tw = tailWant or ""
  local wantFull = normalizeNeighborhoodDedup(tw)
  if wantFull == "" then
    return
  end
  local wantHasSub = tw:find(NHS_TAIL_PAIR_SEP, 1, true)
  local wantHasPlayer = tw:find(NHS_TAIL_PLAYER_SEP, 1, true)
  local wantHoodNorm = normalizeNeighborhoodDedup(persistenceTailHoodOnly(tw))
  local wantNoPlayerNorm = normalizeNeighborhoodDedup(persistenceTailWithoutPlayer(tw))
  local toWipe = {}
  for k in pairs(NHSV.houseSizes) do
    if k ~= targetKey and S.BaseStableKeyFromPersistenceKey(k) == stable then
      local kTail = neighborhoodLabelFromSavedKey(k)
      local kNorm = normalizeNeighborhoodDedup(kTail)
      local kHasSub = kTail:find(NHS_TAIL_PAIR_SEP, 1, true)
      local kHasPlayer = kTail:find(NHS_TAIL_PLAYER_SEP, 1, true)
      local wipe = false
      if k == stable then
        wipe = true
      elseif kNorm == wantFull then
        -- Exact match — replace.
        wipe = true
      elseif wantHasSub and not kHasSub and wantHoodNorm ~= "" and normalizeNeighborhoodDedup(persistenceTailHoodOnly(kTail)) == wantHoodNorm then
        -- New key adds subdivision over a hood-only (or hood+player) entry for the same hood.
        wipe = true
      elseif wantHasPlayer and not kHasPlayer and wantNoPlayerNorm ~= "" and kNorm == wantNoPlayerNorm then
        -- New key adds player name over an otherwise identical entry (same hood+sub, no player).
        wipe = true
      end
      if wipe then
        toWipe[#toWipe + 1] = k
      end
    end
  end
  for _, k in ipairs(toWipe) do
    nhsRemoveSavedHouseKey(k)
  end
end

function S.StableKeyFromEntry(entry)
  if type(entry) == "number" then
    return "n:" .. tostring(entry)
  end
  if type(entry) ~= "table" then
    return nil
  end
  local g = entry.houseGuid or entry.houseGUID or entry.characterGUID or entry.guid
  if type(g) == "string" and g ~= "" then
    return "g:" .. g
  end
  local pid = entry.plotID
  if pid == nil then
    pid = entry.plotId
  end
  if pid ~= nil then
    return "p:" .. tostring(tonumber(pid) or pid)
  end
  local lid = entry.lotID
  if lid == nil then
    lid = entry.lotId
  end
  if lid ~= nil then
    return "l:" .. tostring(tonumber(lid) or lid)
  end
  local slot = entry.plotIndex
    or entry.lotIndex
    or entry.LotIndex
    or entry.plotNumber
    or entry.lotNumber
    or entry.slotIndex
    or entry.index
  if slot ~= nil then
    return "slot:" .. tostring(tonumber(slot) or slot)
  end
  local nid = neighborIDFromEntry(entry)
  if nid ~= nil then
    return "n:" .. tostring(nid)
  end
  return nil
end

function S.GetSavedPresetIndexForEntry(entry)
  ensureSaved()
  local stable = S.StableKeyFromEntry(entry)
  if not stable then
    return nil
  end
  local pr = presets()
  local player = trimmedPlayerNameFromEntry(entry)
  for _, key in ipairs(persistenceKeysForLookup(stable, player)) do
    local idx = tonumber(NHSV.houseSizes[key])
    if idx and idx >= 1 and idx <= #pr then
      return idx
    end
  end
  return nil
end

function S.SetSavedPresetForEntry(entry, presetIdx, displayLabel, listRowIndex)
  if not (NHS.EntryHasOwnerDisplay and NHS.EntryHasOwnerDisplay(entry)) then
    return false
  end
  presetIdx = tonumber(presetIdx)
  local pr = presets()
  if not presetIdx or presetIdx < 1 or presetIdx > #pr then
    return false
  end
  local stable = S.StableKeyFromEntry(entry)
  if not stable then
    return false
  end
  local hood = trimmedNeighborhoodName()
  local sub = trimmedManualSubdivisionForSave()
  local player = trimmedPlayerNameFromEntry(entry, listRowIndex)
  local tail = persistenceTailFromHoodAndSub(hood, sub, player)
  local key = tail ~= "" and (stable .. NHS_PERSIST_KEY_SEP .. tail) or stable
  ensureSaved()
  wipePersistentKeysSupersededBySave(stable, tail, key)
  NHSV.houseSizes[key] = presetIdx
  if type(displayLabel) == "string" and displayLabel ~= "" then
    NHSV.houseLabels[key] = displayLabel
  end
  if hood then
    if type(NHSV.houseNeighborhoodNames) ~= "table" then
      NHSV.houseNeighborhoodNames = {}
    end
    NHSV.houseNeighborhoodNames[key] = hood
  end
  if type(NHSV.houseSubdivisionNames) ~= "table" then
    NHSV.houseSubdivisionNames = {}
  end
  if sub then
    NHSV.houseSubdivisionNames[key] = sub
  else
    NHSV.houseSubdivisionNames[key] = nil
  end
  local mapID, x, y = getPinCoords(entry, listRowIndex or 1)
  if mapID and mapID ~= 0 and x ~= nil and y ~= nil then
    NHSV.housePinCoords[key] = { mapID = mapID, x = x, y = y }
  else
    NHSV.housePinCoords[key] = nil
  end
  return true
end

-- Migrate a specific saved key to the current neighborhood/subdivision context.
-- Writes the new key first, then removes the old one, so no data is lost on failure.
-- Does not touch any other saved keys for the same stable slot.
function S.MigrateSavedEntryToCurrentContext(savedKey, entry, listRowIndex)
  ensureSaved()
  local presetIdx = tonumber(NHSV.houseSizes[savedKey])
  local pr = presets()
  if not presetIdx or presetIdx < 1 or presetIdx > #pr then
    return false
  end
  local stable = S.StableKeyFromEntry(entry)
  if not stable then
    return false
  end
  local hood = trimmedNeighborhoodName()
  -- Guard against cross-neighborhood overwrites: if the saved key already has a
  -- neighborhood tail, it must match the current neighborhood. Only legacy keys
  -- (no tail) are allowed to migrate into any neighborhood context.
  local sepPos = savedKey:find(NHS_PERSIST_KEY_SEP, 1, true)
  if sepPos then
    local savedHoodNorm = normalizeNeighborhoodDedup(persistenceTailHoodOnly(savedKey:sub(sepPos + 1)))
    local currentHoodNorm = normalizeNeighborhoodDedup(hood or "")
    if savedHoodNorm == "" or currentHoodNorm == "" or savedHoodNorm ~= currentHoodNorm then
      return false
    end
  end
  local sub = trimmedManualSubdivisionForSave()
  local player = trimmedPlayerNameFromEntry(entry, listRowIndex)
  -- If the edit box has no subdivision but the saved key already encodes one, keep it so
  -- that two entries at the same plot in different subdivisions don't collapse to the same key.
  if not sub and sepPos then
    local pairPos = savedKey:find(NHS_TAIL_PAIR_SEP, sepPos + 1, true)
    if pairPos then
      local playerPos = savedKey:find(NHS_TAIL_PLAYER_SEP, pairPos + 1, true)
      sub = playerPos and savedKey:sub(pairPos + 1, playerPos - 1) or savedKey:sub(pairPos + 1)
    end
  end
  local newTail = persistenceTailFromHoodAndSub(hood, sub, player)
  local newKey = newTail ~= "" and (stable .. NHS_PERSIST_KEY_SEP .. newTail) or stable
  local mapID, x, y = getPinCoords(entry, listRowIndex or 1)
  if newKey == savedKey then
    -- Key unchanged — just refresh the pin coords from the live entry.
    if mapID and mapID ~= 0 and x ~= nil and y ~= nil then
      NHSV.housePinCoords[newKey] = { mapID = mapID, x = x, y = y }
    end
    return true
  end
  -- Write new key first so data is never absent, then delete old key.
  local displayLabel = NHSV.houseLabels[savedKey]
  NHSV.houseSizes[newKey] = presetIdx
  if type(displayLabel) == "string" and displayLabel ~= "" then
    NHSV.houseLabels[newKey] = displayLabel
  end
  if type(NHSV.houseNeighborhoodNames) ~= "table" then
    NHSV.houseNeighborhoodNames = {}
  end
  if hood then
    NHSV.houseNeighborhoodNames[newKey] = hood
  end
  if type(NHSV.houseSubdivisionNames) ~= "table" then
    NHSV.houseSubdivisionNames = {}
  end
  if sub then
    NHSV.houseSubdivisionNames[newKey] = sub
  else
    NHSV.houseSubdivisionNames[newKey] = nil
  end
  if mapID and mapID ~= 0 and x ~= nil and y ~= nil then
    NHSV.housePinCoords[newKey] = { mapID = mapID, x = x, y = y }
  else
    NHSV.housePinCoords[newKey] = nil
  end
  nhsRemoveSavedHouseKey(savedKey)
  return true
end

function S.ClearSavedPresetForEntry(entry)
  local stable = S.StableKeyFromEntry(entry)
  if not stable then
    return false
  end
  ensureSaved()
  local player = trimmedPlayerNameFromEntry(entry)
  local key
  for _, k in ipairs(persistenceKeysForLookup(stable, player)) do
    if NHSV.houseSizes[k] ~= nil then
      key = k
      break
    end
  end
  if not key then
    return false
  end
  nhsRemoveSavedHouseKey(key)
  return true
end

function S.GetSavedHousePinCoords(stableKey)
  if type(stableKey) ~= "string" or stableKey == "" then
    return nil, nil, nil
  end
  ensureSaved()
  local t = NHSV.housePinCoords[stableKey]
  if type(t) ~= "table" then
    return nil, nil, nil
  end
  local mapID = tonumber(t.mapID) or t.mapID
  local x = tonumber(t.x)
  local y = tonumber(t.y)
  if not mapID or mapID == 0 or x == nil or y == nil then
    return nil, nil, nil
  end
  return mapID, x, y
end

function S.SavedSizeSuffixForEntry(entry)
  local idx = S.GetSavedPresetIndexForEntry(entry)
  if not idx then
    return ""
  end
  local pr = presets()
  return (" [%s]"):format(pr[idx].label)
end

function S.CountSavedHouseSizes()
  ensureSaved()
  local n = 0
  for _ in pairs(NHSV.houseSizes) do
    n = n + 1
  end
  return n
end

function S.PresetButtonsApplySavedHighlight(hideBtns, searchBtns, entry)
  local idx = S.GetSavedPresetIndexForEntry(entry)
  local function setHL(b, on)
    local fs = b:GetFontString()
    if fs then
      if on then
        fs:SetTextColor(0.35, 1, 0.45)
      else
        fs:SetTextColor(1, 1, 1)
      end
    end
  end
  if type(hideBtns) == "table" then
    for i, b in ipairs(hideBtns) do
      setHL(b, idx == i)
    end
  end
  if type(searchBtns) == "table" then
    for i, b in ipairs(searchBtns) do
      setHL(b, idx == i)
    end
  end
end

function S.GetSavedPresetIndexForStableKey(stableKey)
  if type(stableKey) ~= "string" or stableKey == "" then
    return nil
  end
  ensureSaved()
  local pr = presets()
  local idx = tonumber(NHSV.houseSizes[stableKey])
  if not idx or idx < 1 or idx > #pr then
    return nil
  end
  return idx
end

function S.PresetButtonsApplySavedHighlightIdx(hideBtns, searchBtns, idx)
  local function setHL(b, on)
    local fs = b:GetFontString()
    if fs then
      if on then
        fs:SetTextColor(0.35, 1, 0.45)
      else
        fs:SetTextColor(1, 1, 1)
      end
    end
  end
  if type(hideBtns) == "table" then
    for i, b in ipairs(hideBtns) do
      setHL(b, idx == i)
    end
  end
  if type(searchBtns) == "table" then
    for i, b in ipairs(searchBtns) do
      setHL(b, idx == i)
    end
  end
end

-- Extract Housing-… slice id from persistence key tail (after first SOH; optional STX before guid).
local function housingGuidFromPersistenceKey(key)
  if type(key) ~= "string" then
    return nil
  end
  local p1 = string.char(1)
  local i1 = key:find(p1, 1, true)
  if not i1 or i1 >= #key then
    return nil
  end
  local tail = key:sub(i1 + 1)
  local p2 = string.char(2)
  local lastPos = nil
  local start = 1
  while true do
    local j = tail:find(p2, start, true)
    if not j then
      break
    end
    lastPos = j
    start = j + 1
  end
  local g = lastPos and tail:sub(lastPos + 1) or tail
  if type(g) == "string" and (g:match("^Housing%-") or g:match("^%x+$")) then
    return g
  end
  return nil
end

local function sliceDisplayLabelForSavedKey(key)
  local sub = type(NHSV.houseSubdivisionNames) == "table" and NHSV.houseSubdivisionNames[key]
  if type(sub) == "string" then
    sub = sub:match("^%s*(.-)%s*$") or ""
    if sub ~= "" then
      return sub
    end
  end
  local gid = housingGuidFromPersistenceKey(key)
  if gid and type(NHSV.neighborhoodSliceLabels) == "table" then
    local lab = NHSV.neighborhoodSliceLabels[gid]
    if type(lab) == "string" then
      lab = lab:match("^%s*(.-)%s*$") or ""
      if lab ~= "" then
        return lab
      end
    end
  end
  return nil
end

function S.SliceDisplayLabelForSavedKey(key)
  ensureSaved()
  return sliceDisplayLabelForSavedKey(key)
end

local function gameplaySavedHousePoolEntries()
  ensureSaved()
  local pr = presets()
  local wrapped = {}
  for key, idx in pairs(NHSV.houseSizes) do
    idx = tonumber(idx)
    if idx and idx >= 1 and idx <= #pr then
      local baseLabel = NHSV.houseLabels[key] or key
      local hood = type(NHSV.houseNeighborhoodNames) == "table" and NHSV.houseNeighborhoodNames[key]
      if type(hood) ~= "string" or hood == "" then
        hood = nil
      end
      local sub = sliceDisplayLabelForSavedKey(key)
      local dispLabel = baseLabel
      if hood then
        dispLabel = ("%s — %s"):format(dispLabel, hood)
      end
      if sub then
        dispLabel = ("%s — %s"):format(dispLabel, sub)
      end
      local disp = ("%s [%s]"):format(dispLabel, pr[idx].label)
      wrapped[#wrapped + 1] = {
        k = plotSortKeyFromSavedLabelOrKey(baseLabel, S.BaseStableKeyFromPersistenceKey(key)),
        ord = #wrapped + 1,
        row = {
          rotKey = key,
          display = disp,
          liveEntry = nil,
          liveIndex = nil,
        },
      }
    end
  end
  table.sort(wrapped, function(a, b)
    local ka, kb = a.k, b.k
    if type(ka) == "number" and type(kb) == "number" and ka ~= kb then
      return ka < kb
    end
    local na, nb = tonumber(tostring(ka)), tonumber(tostring(kb))
    if na and nb and na ~= nb then
      return na < nb
    end
    local sa, sb = tostring(ka), tostring(kb)
    if sa ~= sb then
      return sa < sb
    end
    return a.ord < b.ord
  end)
  local pool = {}
  for i = 1, #wrapped do
    pool[i] = wrapped[i].row
  end
  return pool
end

local function gameplayCurrentHousePoolEntries(rows)
  local list = {}
  for _, entry in ipairs(rows or {}) do
    if NHS.EntryHasOwnerDisplay and NHS.EntryHasOwnerDisplay(entry) then
      list[#list + 1] = entry
    end
  end
  sortHouseListInPlace(list)
  local pool = {}
  for i, entry in ipairs(list) do
    local rk = S.StableKeyFromEntry(entry)
    if not rk then
      rk = "__idx:" .. tostring(i)
    end
    pool[#pool + 1] = {
      rotKey = rk,
      display = labelFromEntry(entry, i),
      liveEntry = entry,
      liveIndex = i,
    }
  end
  return pool
end

local function gameplayGroupHousePoolEntries()
  local B = NHS.BuildMainFrameBridge
  local getRoster = B and B.nhsGetGroupRoster
  if not getRoster then
    return {}
  end
  local roster = getRoster()
  local pool = {}
  for _, m in ipairs(roster) do
    pool[#pool + 1] = {
      rotKey = "group:" .. tostring(m.key),
      display = m.display,
      liveEntry = nil,
      liveIndex = nil,
    }
  end
  return pool
end

--- @param listSource "neighborhood"|"saved"|"group"|nil
function S.BuildGameplayHousePickPool(housesCache, listSource)
  ensureSaved()
  if listSource == "saved" then
    return gameplaySavedHousePoolEntries()
  end
  if listSource == "group" then
    return gameplayGroupHousePoolEntries()
  end
  return gameplayCurrentHousePoolEntries(housesCache)
end

function S.GameplayRandomHouseEligible(housesCache, listSource)
  local pool = S.BuildGameplayHousePickPool(housesCache, listSource)
  if #pool == 0 then
    local nhMsg
    if listSource == "saved" then
      nhMsg = "No saved houses with sizes. Add sizes in the house list (Saved Sizes), or pick another session list."
    elseif listSource == "group" then
      nhMsg = "No group members in the roster."
    elseif housesCache and #housesCache > 0 then
      nhMsg =
        "No occupied plots in the neighborhood — empty lots are excluded. Refresh the house list or pick another session list."
    else
      nhMsg = "No houses in the neighborhood list — open View house list and refresh, or pick another session list."
    end
    return nil, nhMsg
  end
  local st = NHS.State
  local elig = {}
  for _, p in ipairs(pool) do
    if not st.gameHouseRotationUsed[p.rotKey] then
      elig[#elig + 1] = p
    end
  end
  if #elig == 0 then
    wipe(st.gameHouseRotationUsed)
    elig = pool
  end
  return elig, nil
end

function S.PickRandomGameplayHouse(housesCache, listSource)
  local elig, err = S.GameplayRandomHouseEligible(housesCache, listSource)
  if not elig then
    return nil, err
  end
  return elig[math.random(1, #elig)]
end

-- ---------------------------------------------------------------------------
-- Canonical house stat keys  (player-centric; survives plot / neighborhood changes)
-- ---------------------------------------------------------------------------

-- Extracts the player name encoded after \3 in a persistence key's tail.
-- Returns nil if no player component is present.
function S.PlayerFromPersistenceKey(key)
  if type(key) ~= "string" then return nil end
  local pos = key:find(NHS_TAIL_PLAYER_SEP, 1, true)
  if not pos or pos >= #key then return nil end
  local p = key:sub(pos + 1):match("^%s*(.-)%s*$") or ""
  return p ~= "" and p or nil
end

-- Normalizes a player name to a fully-qualified "Name-Realm" key.
-- If the name has no "-Realm" suffix, the current realm is appended via GetRealmName().
-- Returns the name unchanged (without realm) if GetRealmName() is unavailable.
function S.NormalizePlayerKey(name)
  if type(name) ~= "string" then return nil end
  name = name:match("^%s*(.-)%s*$") or ""
  if name == "" then return nil end
  if name:find("-", 1, true) then
    return name  -- realm suffix already present
  end
  local realm = GetRealmName and GetRealmName()
  if type(realm) == "string" then
    realm = realm:match("^%s*(.-)%s*$") or ""
  end
  if realm and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end

-- Returns a canonical stat key of the form "player:Name-Realm" for a gameplay
-- session's house.  Returns nil if no player name can be determined.
-- Sources tried in order:
--   1. "group:<key>" prefix on houseKey  (group-mode roster key)
--   2. \3 player component in a full persistence key  (saved-list / any key with player tail)
--   3. Player name parsed from houseDisplay  (neighborhood bare stable key, or legacy group)
function S.CanonicalHouseStatKey(houseKey, houseDisplay)
  local playerName
  if type(houseKey) == "string" and houseKey ~= "" then
    local groupPart = houseKey:match("^group:(.+)$")
    if groupPart then
      playerName = groupPart
    else
      playerName = S.PlayerFromPersistenceKey(houseKey)
    end
  end
  if not playerName then
    playerName = playerFromDisplay(houseDisplay)
  end
  local normalized = playerName and S.NormalizePlayerKey(playerName)
  if not normalized then return nil end
  return "player:" .. normalized
end

-- Migrates all houseCounts entries from legacy key formats (persistence keys, bare stable
-- keys, "group:" keys, plain display names) to the canonical "player:Name-Realm" format.
-- Merges duplicates, keeping the richest (longest) display label.  Safe to call multiple times.
-- Only migrates when GetRealmName() is populated; returns false otherwise so the caller
-- can retry later.
function S.MigrateHouseCountsToPlayerKeys(houseCounts)
  if type(houseCounts) ~= "table" then return false end
  local realm = GetRealmName and GetRealmName()
  if type(realm) ~= "string" or realm:match("^%s*$") then return false end
  local migrations = {}
  for oldKey, hc in pairs(houseCounts) do
    if type(oldKey) == "string" then
      -- Skip correctly-formed canonical keys ("player:Name-Realm" with no spaces after the prefix).
      -- Process everything else: legacy keys AND bugged "player:Plot - Name" keys from a prior run.
      local isClean = oldKey:match("^player:") and not oldKey:find(" ", 8, true)
      if not isClean then
        local disp = type(hc) == "table" and hc.display or nil
        local canonical = S.CanonicalHouseStatKey(oldKey, disp or oldKey)
        if canonical and canonical ~= oldKey then
          local count = type(hc) == "table" and (hc.count or 0) or (tonumber(hc) or 0)
          migrations[#migrations + 1] = { old = oldKey, new = canonical, count = count, display = disp }
        end
      end
    end
  end
  for _, m in ipairs(migrations) do
    local existing = houseCounts[m.new]
    if existing then
      existing.count = (existing.count or 0) + m.count
      if type(m.display) == "string" and #m.display > #(existing.display or "") then
        existing.display = m.display
      end
    else
      houseCounts[m.new] = { display = m.display or m.new, count = m.count }
    end
    houseCounts[m.old] = nil
  end
  return true
end
