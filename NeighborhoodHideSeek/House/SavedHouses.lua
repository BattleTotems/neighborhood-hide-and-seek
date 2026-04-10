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
  local key = S.StableKeyFromEntry(entry)
  if not key then
    return nil
  end
  local pr = presets()
  local idx = tonumber(NHSV.houseSizes[key])
  if not idx or idx < 1 or idx > #pr then
    return nil
  end
  return idx
end

function S.SetSavedPresetForEntry(entry, presetIdx, displayLabel, listRowIndex)
  presetIdx = tonumber(presetIdx)
  local pr = presets()
  if not presetIdx or presetIdx < 1 or presetIdx > #pr then
    return false
  end
  local key = S.StableKeyFromEntry(entry)
  if not key then
    return false
  end
  ensureSaved()
  NHSV.houseSizes[key] = presetIdx
  if type(displayLabel) == "string" and displayLabel ~= "" then
    NHSV.houseLabels[key] = displayLabel
  end
  local mapID, x, y = getPinCoords(entry, listRowIndex or 1)
  if mapID and mapID ~= 0 and x ~= nil and y ~= nil then
    NHSV.housePinCoords[key] = { mapID = mapID, x = x, y = y }
  else
    NHSV.housePinCoords[key] = nil
  end
  return true
end

function S.ClearSavedPresetForEntry(entry)
  local key = S.StableKeyFromEntry(entry)
  if not key then
    return false
  end
  ensureSaved()
  NHSV.houseSizes[key] = nil
  NHSV.houseLabels[key] = nil
  NHSV.housePinCoords[key] = nil
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

local function gameplaySavedHousePoolEntries()
  ensureSaved()
  local pr = presets()
  local wrapped = {}
  for key, idx in pairs(NHSV.houseSizes) do
    idx = tonumber(idx)
    if idx and idx >= 1 and idx <= #pr then
      local label = NHSV.houseLabels[key] or key
      local disp = ("%s [%s]"):format(label, pr[idx].label)
      wrapped[#wrapped + 1] = {
        k = plotSortKeyFromSavedLabelOrKey(label, key),
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
  for i, entry in ipairs(rows or {}) do
    list[i] = entry
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

function S.BuildGameplayHousePickPool(housesCache)
  ensureSaved()
  if NHSV.selectHouseFromSavedList ~= false then
    return gameplaySavedHousePoolEntries()
  end
  return gameplayCurrentHousePoolEntries(housesCache)
end

function S.GameplayRandomHouseEligible(housesCache)
  local pool = S.BuildGameplayHousePickPool(housesCache)
  if #pool == 0 then
    return nil,
      (NHSV.selectHouseFromSavedList ~= false)
          and "No saved houses with sizes. Add sizes in the house list, or disable “Select from saved house list” in Options."
        or "No houses in the current list — open View house list and refresh, or visit the neighborhood."
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

function S.PickRandomGameplayHouse(housesCache)
  local elig, err = S.GameplayRandomHouseEligible(housesCache)
  if not elig then
    return nil, err
  end
  return elig[math.random(1, #elig)]
end
