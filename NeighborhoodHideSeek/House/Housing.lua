--[[
  Core housing API: resolver, visitable list, visit diagnostics, plot pin index, map coords, user waypoint.
  Loaded before HousingPinShare.lua — see NeighborhoodHideSeek.toc.
]]
-- --- Housing API (resolver: namespace + method names differ by patch) ---------

local Housing = {
  listMethod = nil,
  nsKey = nil,
  -- Filled when list APIs return a root table with a map id (for pins on plot-only entries).
  lastNeighborhoodUiMapID = nil,
  -- Last successful raw return from a list getter (for plot→coordinate index when entries lack x/y).
  lastMapDataRoot = nil,
  plotPinIndex = {},
}

local HOUSING_NAMESPACE_KEYS = {
  "C_HousingNeighborhood",
  "C_Housing",
}

-- Midnight exposes map/roster getters; older docs mentioned GetVisitableHouses.
local HOUSING_LIST_METHODS = {
  "GetNeighborhoodMapData",
  "GetCornerstoneNeighborhoodInfo",
  "GetNeighborhoodRoster",
  "GetCornerstoneHouseInfo",
  "GetVisitableHouses",
  "GetVisitableHomes",
  "GetNeighborhoodVisitableHouses",
  "GetNeighborhoodHouses",
}

-- Explicit names to try on each namespace (game may not expose Visit* on Neighborhood).
local HOUSING_VISIT_METHODS = {
  "VisitNeighbor",
  "VisitNeighborhoodHouse",
  "VisitNeighborhoodPlot",
  "VisitPlot",
  "VisitHouse",
  "VisitHome",
  "VisitCornerstoneHouse",
  "RequestVisitNeighbor",
  "RequestVisitToNeighbor",
  "RequestVisitToPlot",
  "RequestVisit",
  "TeleportToNeighborhoodPlot",
  "TeleportToPlot",
  "TeleportToNeighborHouse",
  "NavigateToNeighborhoodPlot",
}

-- Extra globals that may own Visit/Teleport (not only C_HousingNeighborhood).
local HOUSING_VISIT_NAMESPACE_KEYS = {
  "C_HousingNeighborhood",
  "C_Housing",
  "C_HouseExterior",
  "C_HouseVisit",
}

local function housingAnyNamespaceTable()
  for _, key in ipairs(HOUSING_NAMESPACE_KEYS) do
    local ns = rawget(_G, key)
    if type(ns) == "table" then
      return ns, key
    end
  end
  return nil, nil
end

local function housingHasListCandidate(ns)
  if type(ns) ~= "table" then
    return false
  end
  for _, method in ipairs(HOUSING_LIST_METHODS) do
    if type(ns[method]) == "function" then
      return true
    end
  end
  for k, v in pairs(ns) do
    if type(k) == "string" and type(v) == "function" and k:find("Visitable", 1, true) then
      return true
    end
  end
  return false
end

local function housingResolve()
  if Housing.nsKey and type(rawget(_G, Housing.nsKey)) == "table" then
    return true
  end
  for _, key in ipairs(HOUSING_NAMESPACE_KEYS) do
    local ns = rawget(_G, key)
    if type(ns) == "table" and housingHasListCandidate(ns) then
      Housing.nsKey = key
      Housing.listMethod = nil
      return true
    end
  end
  for _, key in ipairs(HOUSING_NAMESPACE_KEYS) do
    local ns = rawget(_G, key)
    if type(ns) == "table" then
      Housing.nsKey = key
      Housing.listMethod = nil
      return true
    end
  end
  return false
end

local function housingInvalidate()
  Housing.listMethod = nil
  Housing.nsKey = nil
  Housing.lastNeighborhoodUiMapID = nil
  Housing.lastMapDataRoot = nil
  wipe(Housing.plotPinIndex)
end

local function housingCaptureRootMapId(result)
  if type(result) ~= "table" then
    return
  end
  local mid = result.uiMapID or result.mapID or result.UiMapID or result.uiMapId or result.neighborhoodUiMapID
  if type(mid) == "number" and mid > 0 then
    Housing.lastNeighborhoodUiMapID = mid
    return
  end
  for _, v in pairs(result) do
    if type(v) == "table" then
      mid = v.uiMapID or v.mapID or v.UiMapID
      if type(mid) == "number" and mid > 0 then
        Housing.lastNeighborhoodUiMapID = mid
        return
      end
    end
  end
end

-- Exclude capability/query getters, wrong semantics, and secure-only APIs.
-- VisitHouse: Blizzard shows “blocked from an action only available to the Blizzard UI”; also often
-- describes *your* house / instance flow, not “teleport to arbitrary neighbor plot” from addons.
local HOUSING_VISIT_REJECT_EXACT = {
  VisitHouse = true,
  TeleportHome = true,
  ReturnAfterVisitingHouse = true,
}

local function housingIsProbableVisitAction(name)
  if type(name) ~= "string" or name == "" then
    return false
  end
  if HOUSING_VISIT_REJECT_EXACT[name] then
    return false
  end
  if name:sub(1, 3) == "Can" then
    return false
  end
  if name:sub(1, 3) == "Get" then
    return false
  end
  if name:sub(1, 2) == "Is" then
    return false
  end
  if name:sub(1, 3) == "Has" then
    return false
  end
  return true
end

-- Discover Visit/Teleport-like functions (dump often shows no literal "VisitNeighbor").
local function housingCollectVisitFunctions()
  local list = {}
  local dup = {}
  local function add(nsKey, name, fn)
    if type(name) ~= "string" or type(fn) ~= "function" then
      return
    end
    if not housingIsProbableVisitAction(name) then
      return
    end
    local id = nsKey .. "\0" .. name
    if dup[id] then
      return
    end
    dup[id] = true
    list[#list + 1] = { nsKey = nsKey, name = name, fn = fn }
  end
  for _, gkey in ipairs(HOUSING_VISIT_NAMESPACE_KEYS) do
    local ns = rawget(_G, gkey)
    if type(ns) == "table" then
      for _, method in ipairs(HOUSING_VISIT_METHODS) do
        add(gkey, method, ns[method])
      end
      for k, v in pairs(ns) do
        if type(k) == "string" and type(v) == "function" then
          local lk = k:lower()
          if lk:find("visit", 1, true) or lk:find("teleport", 1, true) or lk:find("warp", 1, true) then
            add(gkey, k, v)
          elseif lk:find("travel", 1, true) and (lk:find("house", 1, true) or lk:find("plot", 1, true)) then
            add(gkey, k, v)
          elseif lk:find("request", 1, true) and lk:find("visit", 1, true) then
            add(gkey, k, v)
          end
        end
      end
    end
  end
  -- Any global C_Housing* table (names differ by patch): pick up Visit/Teleport we did not list explicitly.
  for gkey, ns in pairs(_G) do
    if type(gkey) == "string" and gkey:sub(1, 9) == "C_Housing" and type(ns) == "table" then
      for k, v in pairs(ns) do
        if type(k) == "string" and type(v) == "function" then
          local lk = k:lower()
          if lk:find("visit", 1, true) or lk:find("teleport", 1, true) or lk:find("warp", 1, true) then
            add(gkey, k, v)
          elseif lk:find("travel", 1, true) and (lk:find("house", 1, true) or lk:find("plot", 1, true)) then
            add(gkey, k, v)
          end
        end
      end
    end
  end
  table.sort(list, function(a, b)
    local pa = (a.name:lower():find("visit", 1, true) and 0 or 1)
    local pb = (b.name:lower():find("visit", 1, true) and 0 or 1)
    if pa ~= pb then
      return pa < pb
    end
    return a.name < b.name
  end)
  return list
end

local function housingNamespacePresent()
  return housingAnyNamespaceTable() ~= nil
end

local function housingAvailable()
  return housingResolve()
end

-- Turn API return value into a dense array for ipairs.
local function normalizeHouseList(raw)
  if type(raw) ~= "table" then
    return {}
  end
  if raw[1] ~= nil then
    return raw
  end
  local keys = {}
  for k in pairs(raw) do
    if type(k) == "number" then
      keys[#keys + 1] = k
    end
  end
  if #keys > 0 then
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
      out[#out + 1] = raw[k]
    end
    return out
  end
  local out = {}
  for _, v in pairs(raw) do
    out[#out + 1] = v
  end
  return out
end

local function housingIdNonZero(v)
  if v == nil then
    return nil
  end
  if type(v) == "number" and v == 0 then
    return nil
  end
  return v
end

local function neighborIDFromEntry(entry)
  if type(entry) == "number" then
    return housingIdNonZero(entry)
  end
  if type(entry) ~= "table" then
    return nil
  end
  local v = entry.neighborID
    or entry.neighborId
    or entry.NeighborID
    or entry.houseID
    or entry.houseId
    or entry.houseGuid
    or entry.houseGUID
    or housingIdNonZero(entry.plotID)
    or housingIdNonZero(entry.plotId)
    or housingIdNonZero(entry.lotID)
    or housingIdNonZero(entry.lotId)
    or entry.cornerstoneID
    or entry.cornerstoneId
    or entry.characterGUID
    or entry.guid
    or housingIdNonZero(entry.id)
  return housingIdNonZero(v)
end

-- Key for plotPinIndex: explicit plot/lot fields or neighbor id (no row fallback).
local function housingWaypointIndexKeyFromTable(t)
  if type(t) ~= "table" then
    return nil
  end
  local v = t.plotIndex
    or t.lotIndex
    or t.LotIndex
    or t.plotNumber
    or t.lotNumber
    or t.slotIndex
    or t.index
    or t.plotID
    or t.plotId
    or t.lotID
    or t.lotId
  if v ~= nil then
    return tostring(tonumber(v) or v)
  end
  local nid = neighborIDFromEntry(t)
  if nid ~= nil then
    return tostring(nid)
  end
  return nil
end

local HOUSING_ENTRY_CONTAINER_KEYS = {
  "houses",
  "homes",
  "plots",
  "plotInfos",
  "markers",
  "roster",
  "members",
  "entries",
  "lots",
  "Lots",
  "homeInfos",
  "houseInfos",
  "cornerstones",
  "neighbors",
  "playerHomes",
  "mapMarkers",
  "pins",
}

local function tableLooksLikeHouseEntry(t)
  if type(t) ~= "table" then
    return false
  end
  if neighborIDFromEntry(t) ~= nil then
    return true
  end
  if t.plotIndex ~= nil or t.lotIndex ~= nil or t.LotIndex ~= nil then
    return true
  end
  if t.plotID ~= nil or t.plotId ~= nil or t.lotID ~= nil or t.lotId ~= nil then
    return true
  end
  if t.ownerName or t.characterName or t.playerName or t.owner then
    return true
  end
  return false
end

-- Display / owner fields: non-empty after trim counts as a real neighbor row.
local HOUSING_MEANINGFUL_NAME_KEYS = {
  "name",
  "playerName",
  "ownerName",
  "characterName",
  "neighborName",
  "displayName",
  "OwnerName",
  "houseName",
  "HouseName",
  "owner",
}

local function housingTrimNonEmpty(s)
  if type(s) ~= "string" then
    return nil
  end
  local t = s:match("^%s*(.-)%s*$")
  if not t or t == "" then
    return nil
  end
  return t
end

local function housingEntryIsExplicitPlaceholder(t)
  if type(t) ~= "table" then
    return false
  end
  if t.isEmpty == true or t.empty == true or t.placeholder == true or t.isPlaceholder == true then
    return true
  end
  return false
end

-- Plot / lot index 0 is valid in-neighborhood; off-neighborhood APIs often return stub tables with
-- only zeroed ids and no owner/GUID. Require at least one signal besides bare plot/lot slot fields.
local function housingEntryHasMeaningfulNeighborData(entry)
  if entry == nil then
    return false
  end
  if type(entry) == "number" then
    return housingIdNonZero(entry) ~= nil
  end
  if type(entry) ~= "table" then
    return false
  end
  if housingEntryIsExplicitPlaceholder(entry) then
    return false
  end
  for _, k in ipairs(HOUSING_MEANINGFUL_NAME_KEYS) do
    if housingTrimNonEmpty(entry[k]) then
      return true
    end
  end
  local g = entry.houseGuid or entry.houseGUID or entry.characterGUID or entry.guid
  if housingTrimNonEmpty(g) then
    return true
  end
  if housingIdNonZero(entry.neighborID or entry.neighborId or entry.NeighborID) ~= nil then
    return true
  end
  if housingIdNonZero(entry.houseID or entry.houseId) ~= nil then
    return true
  end
  if housingIdNonZero(entry.cornerstoneID or entry.cornerstoneId) ~= nil then
    return true
  end
  if housingIdNonZero(entry.plotDataID or entry.plotDataId) ~= nil then
    return true
  end
  if housingIdNonZero(entry.id) ~= nil
    and entry.plotID == nil
    and entry.plotId == nil
    and entry.lotID == nil
    and entry.lotId == nil
  then
    return true
  end
  return false
end

local function filterHouseEntries(list)
  local out = {}
  for _, v in ipairs(list) do
    if type(v) == "number" then
      if housingEntryHasMeaningfulNeighborData(v) then
        out[#out + 1] = v
      end
    elseif tableLooksLikeHouseEntry(v) and housingEntryHasMeaningfulNeighborData(v) then
      out[#out + 1] = v
    end
  end
  return out
end

-- Map/roster APIs return nested tables; normalize to a list the UI can use.
local function coerceToVisitableHouseList(raw)
  if raw == nil then
    return {}
  end
  if type(raw) ~= "table" then
    return {}
  end
  for _, key in ipairs(HOUSING_ENTRY_CONTAINER_KEYS) do
    local sub = raw[key]
    if type(sub) == "table" then
      local arr = filterHouseEntries(normalizeHouseList(sub))
      if #arr > 0 then
        return arr
      end
    end
  end
  local flat = normalizeHouseList(raw)
  local filtered = filterHouseEntries(flat)
  if #filtered > 0 then
    return filtered
  end
  if tableLooksLikeHouseEntry(raw) and housingEntryHasMeaningfulNeighborData(raw) then
    return { raw }
  end
  return {}
end

local function tryAllHouseListSources(ns)
  if type(ns) ~= "table" then
    return {}, nil, "invalid namespace"
  end
  local lastCallErr = nil
  local sawCallable = false
  local sawEmptyCoerce = false
  for _, method in ipairs(HOUSING_LIST_METHODS) do
    local fn = ns[method]
    if type(fn) == "function" then
      sawCallable = true
      local ok, result = pcall(fn)
      if not ok then
        lastCallErr = tostring(result)
      else
        housingCaptureRootMapId(result)
        local list = coerceToVisitableHouseList(result)
        if #list > 0 then
          if type(result) == "table" then
            Housing.lastMapDataRoot = result
          end
          return list, method, nil
        end
        sawEmptyCoerce = true
      end
    end
  end
  for k, v in pairs(ns) do
    if type(k) == "string" and type(v) == "function" and k:find("Visitable", 1, true) then
      sawCallable = true
      local ok, result = pcall(v)
      if ok then
        housingCaptureRootMapId(result)
        local list = coerceToVisitableHouseList(result)
        if #list > 0 then
          if type(result) == "table" then
            Housing.lastMapDataRoot = result
          end
          return list, k, nil
        end
        sawEmptyCoerce = true
      else
        lastCallErr = tostring(result)
      end
    end
  end
  if type(ns.RequestNeighborhoodRoster) == "function" and type(ns.GetNeighborhoodRoster) == "function" then
    sawCallable = true
    pcall(ns.RequestNeighborhoodRoster)
    local ok, result = pcall(ns.GetNeighborhoodRoster)
    if not ok then
      lastCallErr = tostring(result)
    else
      housingCaptureRootMapId(result)
      local list = coerceToVisitableHouseList(result)
      if #list > 0 then
        if type(result) == "table" then
          Housing.lastMapDataRoot = result
        end
        return list, "GetNeighborhoodRoster", nil
      end
      sawEmptyCoerce = true
    end
  end
  if lastCallErr then
    return {}, nil, lastCallErr
  end
  if not sawCallable then
    return {}, nil, "no_getter"
  end
  if sawEmptyCoerce then
    return {}, nil, "empty_coerce"
  end
  return {}, nil, "no_getter"
end

-- Plot / lot identifier for sorting and "Number - Name" labels (API field names vary).
local function plotSortKeyFromEntry(entry, rowIndex)
  if type(entry) == "number" then
    return entry
  end
  if type(entry) == "table" then
    local v = entry.plotIndex
      or entry.lotIndex
      or entry.LotIndex
      or entry.plotNumber
      or entry.lotNumber
      or entry.slotIndex
      or entry.index
      or entry.plotID
      or entry.plotId
      or entry.lotID
      or entry.lotId
    if v ~= nil then
      local tn = tonumber(v)
      if tn then
        return tn
      end
      return v
    end
  end
  return rowIndex
end

-- For saved rows we only have label + stable key (no API entry). Prefer leading "12 - Name" plot style.
local function nhsPlotSortKeyFromSavedLabelOrKey(label, stableKey)
  local lab = type(label) == "string" and label or ""
  local head = lab:match("^%s*(%d+)%s*%-%s*") or lab:match("^%s*(%d+)%s*$")
  local tn = tonumber(head)
  if tn then
    return tn
  end
  if type(stableKey) == "string" then
    -- StableKeyFromEntry forms: p:/l:/slot:/n: — use embedded id for numeric sort.
    tn = tonumber(
      stableKey:match("^p:(%d+)$")
        or stableKey:match("^l:(%d+)$")
        or stableKey:match("^slot:(%d+)$")
        or stableKey:match("^n:(%d+)$")
    )
    if tn then
      return tn
    end
    tn = tonumber((stableKey:match("^(%d+)")))
    if tn then
      return tn
    end
  end
  if lab ~= "" then
    return lab
  end
  return tostring(stableKey or "")
end

local function sortHouseListInPlace(list)
  local n = #list
  if n < 2 then
    return
  end
  local wrapped = {}
  for i = 1, n do
    wrapped[i] = {
      k = plotSortKeyFromEntry(list[i], i),
      ord = i,
      e = list[i],
    }
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
  for i = 1, n do
    list[i] = wrapped[i].e
  end
end

local function plotDisplayFromEntry(entry, rowIndex)
  return tostring(plotSortKeyFromEntry(entry, rowIndex))
end

local function houseNameFromEntry(entry, fallbackIndex)
  if type(entry) == "number" then
    return "House"
  end
  if type(entry) == "table" then
    local name = entry.name or entry.playerName or entry.ownerName or entry.characterName
      or entry.neighborName or entry.displayName or entry.OwnerName or entry.houseName
      or entry.HouseName or entry.owner
    if name and name ~= "" then
      return tostring(name)
    end
    local nid = neighborIDFromEntry(entry)
    if nid then
      return ("Neighbor %s"):format(tostring(nid))
    end
  end
  return ("Row %s"):format(tostring(fallbackIndex))
end

local function labelFromEntry(entry, fallbackIndex)
  local num = plotDisplayFromEntry(entry, fallbackIndex)
  local name = houseNameFromEntry(entry, fallbackIndex)
  return ("%s - %s"):format(num, name)
end

-- Returns: list, detailTag, detailText (detail for status line when list empty or error)
local function fetchVisitableHouses()
  if not housingResolve() then
    if housingNamespacePresent() then
      return {}, "list_fn_missing",
        "housing tables load, but no list function — try /dump C_HousingNeighborhood in-game."
    end
    return {}, "namespace_missing",
      "no C_HousingNeighborhood / C_Housing — housing not loaded on this client or wrong flavor."
  end
  local ns = rawget(_G, Housing.nsKey)
  if type(ns) ~= "table" then
    return {}, "namespace_missing", "housing namespace disappeared."
  end
  if not housingHasListCandidate(ns) then
    return {}, "list_fn_missing",
      "no GetNeighborhoodMapData-style getters — need a game/API update."
  end
  local list, method, err = tryAllHouseListSources(ns)
  Housing.listMethod = method
  if #list > 0 then
    sortHouseListInPlace(list)
    return list, "ok", ""
  end
  if err and err ~= "empty_coerce" and err ~= "no_getter" then
    return {}, "call_failed", err
  end
  if err == "empty_coerce" then
    return {},
      "empty_shape",
      "API returned data we couldn't parse. Run: /dump C_HousingNeighborhood.GetNeighborhoodMapData()"
  end
  return {}, "empty", "0 houses parsed — be in neighborhood; try Refresh after opening Housing map."
end

-- Returned when pcall succeeded but the C function gave no values — may still be a no-op in UI.
local NHS_VISIT_VOID_RETURN = "nil (void return — game may still ignore)"

-- pcall only catches Lua errors; many C APIs return false, errMsg on failure without erroring.
-- Captures several returns so diagnostics can show Blizzard reason enums / strings.
local function housingTryVisitFn(fn, ...)
  local callOk, a, b, c, d = pcall(fn, ...)
  if not callOk then
    return false, "lua: " .. tostring(a)
  end
  if a == false then
    local parts = {}
    if b ~= nil then
      parts[#parts + 1] = tostring(b)
    end
    if c ~= nil then
      parts[#parts + 1] = tostring(c)
    end
    if #parts == 0 then
      return false, "false (no message)"
    end
    return false, table.concat(parts, ", ")
  end
  if a == nil then
    return true, NHS_VISIT_VOID_RETURN
  end
  if a == true then
    if b ~= nil or c ~= nil then
      return true, ("true + %s %s"):format(tostring(b), tostring(c))
    end
    return true, "true"
  end
  return true, ("ok first=%s %s %s"):format(tostring(a), tostring(b or ""), tostring(c or ""))
end

-- Values we try as single arguments to Visit* APIs (order: most specific first).
local function housingBuildVisitSinglesList(entry, rowIndex)
  local id = neighborIDFromEntry(entry)
  local plotIdx = type(entry) == "table"
    and (entry.plotIndex or entry.lotIndex or entry.LotIndex or entry.index or entry.slotIndex or entry.plotSlotIndex)
  local plotID = type(entry) == "table" and (entry.plotID or entry.plotId or entry.lotID or entry.lotId) or nil
  local plotDataID = type(entry) == "table" and (entry.plotDataID or entry.plotDataId)
  local guid = type(entry) == "table" and (entry.houseGuid or entry.houseGUID or entry.characterGUID or entry.guid)
  local ownerName = type(entry) == "table"
    and (entry.ownerName or entry.playerName or entry.characterName or entry.owner or entry.neighborName)
  if type(ownerName) ~= "string" or ownerName == "" then
    ownerName = nil
  end
  local singles = {}
  local seen = {}
  local function push(v)
    if v == nil then
      return
    end
    local key = tostring(v) .. "\0" .. type(v)
    if seen[key] then
      return
    end
    seen[key] = true
    singles[#singles + 1] = v
  end
  push(id)
  push(plotID)
  push(plotDataID)
  push(plotIdx)
  push(guid)
  push(rowIndex)
  if type(entry) == "number" then
    push(entry)
  end
  return {
    id = id,
    plotID = plotID,
    plotDataID = plotDataID,
    plotIdx = plotIdx,
    guid = guid,
    ownerName = ownerName,
    singles = singles,
  }
end

local function housingPrintVisitDiagnostics(entry, rowIndex)
  print("|cff88ccff[NHS]|r — visit diagnostics (why Visit may do nothing)")
  if entry == nil then
    print("  No plot selected — pick a row in the list first.")
    return
  end
  if not housingResolve() then
    print("  Housing API not resolved (wrong place or patch).")
    return
  end
  print(("  List namespace: |cffffffff%s|r"):format(tostring(Housing.nsKey)))
  local meta = housingBuildVisitSinglesList(entry, rowIndex)
  print(
    ("  Fields: neighborID=%s plotID=%s plotDataID=%s plotIdx=%s guid=%s owner=%s row=%s"):format(
      tostring(meta.id),
      tostring(meta.plotID),
      tostring(meta.plotDataID),
      tostring(meta.plotIdx),
      tostring(meta.guid),
      tostring(meta.ownerName or "—"),
      tostring(rowIndex or "—")
    )
  )
  if meta.guid == nil and meta.id ~= nil and meta.plotID ~= nil and tostring(meta.id) == tostring(meta.plotID) then
    print(
      "  |cffddaa00Tip:|r id is plotID fallback (no neighborGUID in row) — Visit APIs may need another key; compare full /dump of this plot.|r"
    )
  end
  local inInstance, instType = IsInInstance()
  print(
    ("  IsInInstance=%s (%s)  IsInGroup=%s  IsInRaid=%s"):format(
      tostring(inInstance),
      tostring(instType or "?"),
      tostring(IsInGroup()),
      tostring(IsInRaid())
    )
  )
  local visitList = housingCollectVisitFunctions()
  print(
    ("  Action APIs to try: |cffffffff%d|r (|cff888888excludes Can*/Get*/Is*/Has*, TeleportHome, ReturnAfterVisitingHouse|r)"):format(
      #visitList
    )
  )
  if #visitList == 0 then
    print(
      "  |cffaaaaaaNo addon-callable visit actions.|r |cffffffffC_Housing.VisitHouse|r is |cffffffffsecure UI only|r (chat: blocked for addons)."
    )
    print(
      "  It is also oriented around |cffffffffyour house / instance flow|r, not “jump to this neighbor row” from Lua. Use the Housing map UI."
    )
    return
  end
  local maxApis = 45
  for i, item in ipairs(visitList) do
    if i > maxApis then
      print(("  … +%d more APIs not shown"):format(#visitList - maxApis))
      break
    end
    local fn = item.fn
    local bits = {}
    local function addBit(label, ok, detail)
      local tag = ok and "|cff88ff88+|" or "|cffff6666x|"
      bits[#bits + 1] = ("%s%s:%s"):format(tag, label, detail:gsub("|", " "))
    end
    for si = 1, math.min(3, #meta.singles) do
      local ok, det = housingTryVisitFn(fn, meta.singles[si])
      addBit(("a%d"):format(si), ok, det)
    end
    if type(entry) == "table" then
      local ok, det = housingTryVisitFn(fn, entry)
      addBit("tbl", ok, det)
    end
    if type(entry) == "table" and meta.plotID ~= nil and meta.guid ~= nil then
      local ok, det = housingTryVisitFn(fn, meta.plotID, meta.guid)
      addBit("plot+guid", ok, det)
    end
    if type(entry) == "table" and meta.plotIdx ~= nil and meta.id ~= nil then
      local ok, det = housingTryVisitFn(fn, meta.plotIdx, meta.id)
      addBit("idx+id", ok, det)
    end
    if meta.ownerName and meta.id ~= nil then
      local ok, det = housingTryVisitFn(fn, meta.id, meta.ownerName)
      addBit("id+owner", ok, det)
    end
    if type(entry) == "table" and meta.plotID ~= nil and meta.plotDataID ~= nil then
      local ok, det = housingTryVisitFn(fn, meta.plotID, meta.plotDataID)
      addBit("plot+plotData", ok, det)
      ok, det = housingTryVisitFn(fn, meta.plotDataID, meta.plotID)
      addBit("plotData+plot", ok, det)
    end
    if meta.id ~= nil and meta.plotDataID ~= nil then
      local ok, det = housingTryVisitFn(fn, meta.id, meta.plotDataID)
      addBit("id+plotData", ok, det)
      ok, det = housingTryVisitFn(fn, meta.plotDataID, meta.id)
      addBit("plotData+id", ok, det)
    end
    print(("  |cffffffff%s.%s|r %s"):format(item.nsKey, item.name, table.concat(bits, "  ")))
  end
  print("  |cffaaaaaaIf every try is + with “void return”, the client likely ignores scripted calls — use Housing UI.|r")
  print("  |cffaaaaaax:lua / x:false = wrong args or blocked. neighborID vs plotID vs GUID matters — compare /dump keys.|r")
end

-- Housing plots use mapPosition (table with x,y or Vector2D userdata with :GetXY()).
local function extractXYFromMapPosition(mp)
  if mp == nil then
    return nil, nil
  end
  if type(mp) == "table" then
    local px = mp.x or mp.normalizedX
    local py = mp.y or mp.normalizedY
    if px ~= nil and py ~= nil then
      return px, py
    end
    return nil, nil
  end
  if type(mp) == "userdata" and mp.GetXY then
    local ok, a, b = pcall(mp.GetXY, mp)
    if ok and a ~= nil and b ~= nil then
      return a, b
    end
  end
  return nil, nil
end

local function extractWaypointShallow(t)
  if type(t) ~= "table" then
    return nil, nil, nil
  end
  local mapID = t.uiMapID or t.mapID or t.UiMapID or t.uiMapId or t.worldMapID
  local x = t.x or t.normalizedX or t.normalizedx or t.nX or t.posX
  local y = t.y or t.normalizedY or t.normalizedy or t.nY or t.posY
  if (not x or not y) and t.position and type(t.position) == "table" then
    local p = t.position
    x = x or p.x or p.normalizedX
    y = y or p.y or p.normalizedY
    mapID = mapID or p.uiMapID or p.mapID
  end
  if (not x or not y) and t.offset and type(t.offset) == "table" then
    local o = t.offset
    x = x or o.x or o.normalizedX
    y = y or o.y or o.normalizedY
  end
  if (not x or not y) and t.mapPosition ~= nil then
    local px, py = extractXYFromMapPosition(t.mapPosition)
    if px ~= nil and py ~= nil then
      x, y = px, py
    end
  end
  if mapID and x ~= nil and y ~= nil then
    return mapID, x, y
  end
  if (not x or not y) and t.mapPoint and type(t.mapPoint) == "table" then
    return extractWaypointShallow(t.mapPoint)
  end
  if (not x or not y) and t.worldPosition and type(t.worldPosition) == "table" then
    return extractWaypointShallow(t.worldPosition)
  end
  if (not x or not y) and t.location and type(t.location) == "table" then
    return extractWaypointShallow(t.location)
  end
  if (not x or not y) and t.pin and type(t.pin) == "table" then
    return extractWaypointShallow(t.pin)
  end
  if (not x or not y) and t.coords and type(t.coords) == "table" then
    return extractWaypointShallow(t.coords)
  end
  if (not x or not y) and t.worldMapPosition and type(t.worldMapPosition) == "table" then
    return extractWaypointShallow(t.worldMapPosition)
  end
  if x ~= nil and y ~= nil then
    return mapID, x, y
  end
  return nil, nil, nil
end

local function extractWaypointDeep(t, depth, seen)
  if depth > 6 or type(t) ~= "table" then
    return nil, nil, nil
  end
  if seen[t] then
    return nil, nil, nil
  end
  seen[t] = true
  local m, x, y = extractWaypointShallow(t)
  if x ~= nil and y ~= nil then
    if not m or m == 0 then
      m = Housing.lastNeighborhoodUiMapID
    end
    return m, x, y
  end
  for _, v in pairs(t) do
    if type(v) == "table" then
      local mid, xx, yy = extractWaypointDeep(v, depth + 1, seen)
      if xx ~= nil and yy ~= nil then
        if not mid or mid == 0 then
          mid = Housing.lastNeighborhoodUiMapID
        end
        return mid, xx, yy
      end
    end
  end
  return nil, nil, nil
end

-- Scan full map API payload: marker tables often sit beside roster rows without coords.
local function housingRebuildPlotPinIndexFromRoot()
  wipe(Housing.plotPinIndex)
  local raw = Housing.lastMapDataRoot
  if type(raw) ~= "table" then
    return
  end
  local function walk(t, depth, seen)
    if depth > 12 or type(t) ~= "table" or seen[t] then
      return
    end
    seen[t] = true
    local mid, x, y = extractWaypointShallow(t)
    if x ~= nil and y ~= nil then
      if (not mid or mid == 0) and Housing.lastNeighborhoodUiMapID then
        mid = Housing.lastNeighborhoodUiMapID
      end
      if mid and mid ~= 0 then
        local key = housingWaypointIndexKeyFromTable(t)
        if key then
          Housing.plotPinIndex[key] = { mid, x, y }
        end
      end
    end
    for _, v in pairs(t) do
      if type(v) == "table" then
        walk(v, depth + 1, seen)
      end
    end
  end
  walk(raw, 0, {})
end

local function housingPlotPinLookupKeys(entry, rowIndex)
  local keys = {}
  local dup = {}
  local function add(k)
    if k == nil then
      return
    end
    local s = tostring(k)
    if not dup[s] then
      dup[s] = true
      keys[#keys + 1] = s
    end
  end
  if type(entry) == "number" then
    add(entry)
    return keys
  end
  if type(entry) ~= "table" then
    return keys
  end
  add(plotSortKeyFromEntry(entry, rowIndex))
  add(neighborIDFromEntry(entry))
  return keys
end

local function housingLookupPlotPin(entry, rowIndex)
  for _, key in ipairs(housingPlotPinLookupKeys(entry, rowIndex)) do
    local slot = Housing.plotPinIndex[key]
    if slot then
      return slot[1], slot[2], slot[3]
    end
  end
  return nil, nil, nil
end

-- Normalized 0–1 map coordinates + uiMapID (same resolution as Map pin; no C_Map side effects).
local function housingGetPinCoordsForEntry(entry, rowIndex)
  local mapID, x, y
  if type(entry) == "table" then
    local seen = {}
    mapID, x, y = extractWaypointDeep(entry, 0, seen)
  end
  if x == nil or y == nil then
    mapID, x, y = housingLookupPlotPin(entry, rowIndex)
  end
  if type(entry) == "number" and (x == nil or y == nil) then
    mapID, x, y = housingLookupPlotPin(entry, rowIndex)
  end
  if (not mapID or mapID == 0) and x ~= nil and y ~= nil then
    mapID = Housing.lastNeighborhoodUiMapID
    if (not mapID or mapID == 0) and C_Map.GetBestMapForUnit then
      mapID = C_Map.GetBestMapForUnit("player")
    end
  end
  if not mapID or mapID == 0 or x == nil or y == nil then
    return nil, nil, nil
  end
  return mapID, x, y
end

NeighborhoodHideSeek.NeighborIDFromEntry = neighborIDFromEntry
NeighborhoodHideSeek.GetPinCoordsForHouseEntry = housingGetPinCoordsForEntry
NeighborhoodHideSeek.PlotSortKeyFromSavedLabelOrKey = nhsPlotSortKeyFromSavedLabelOrKey
NeighborhoodHideSeek.SortHouseListInPlace = sortHouseListInPlace
NeighborhoodHideSeek.LabelFromEntry = labelFromEntry

local function tryWaypointForEntry(entry, rowIndex)
  local mapID, x, y = housingGetPinCoordsForEntry(entry, rowIndex)
  if not mapID or x == nil or y == nil then
    return false
  end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
    return false
  end
  local pt
  local ok = pcall(function()
    if UiMapPoint.CreateFromCoordinates then
      pt = UiMapPoint.CreateFromCoordinates(mapID, x, y)
    elseif CreateVector2D and UiMapPoint.CreateFromVector2D then
      pt = UiMapPoint.CreateFromVector2D(mapID, CreateVector2D(x, y))
    end
    if pt then
      C_Map.SetUserWaypoint(pt)
    end
  end)
  return ok and pt ~= nil
end

NeighborhoodHideSeek.HousingRegistry = Housing
NeighborhoodHideSeek.HousingApi = {
  Invalidate = housingInvalidate,
  FetchVisitableHouses = fetchVisitableHouses,
  RebuildPlotPinIndexFromRoot = housingRebuildPlotPinIndexFromRoot,
  Available = housingAvailable,
  TryWaypointForEntry = tryWaypointForEntry,
  PrintVisitDiagnostics = housingPrintVisitDiagnostics,
}
