--[[
  Neighborhood Hide & Seek — prototype (Retail Midnight housing neighborhoods).
  Target live client: 12.0.1 (TOC interface 120001). Verify with /dump select(4, GetBuildInfo()).
  Uses C_HousingNeighborhood / C_Housing for map/roster data; C_Map for waypoints/hyperlinks.
]]

-- Must match your AddOns folder name (used for ADDON_LOADED and SavedVariables).
local ADDON_NAME = "NeighborhoodHideSeek"

-- Ephemeral session state (not saved between sessions).
local State = {
  seekerMode = false,
  savedNameplateCVars = nil,
  -- Discovery order (keys = Ambiguate(..., "none")); foundSet avoids duplicates.
  foundOrder = {},
  foundSet = {},
  selectedNeighborID = nil,
  selectedLabel = nil,
  selectedEntry = nil,
  selectedIndex = nil,
  -- Leader-only game rounds (ephemeral; lost on reload)
  gameSessionActive = false,
  gamePhase = "none", -- none | pick_seeker | round_active
  gameCandidateKey = nil,
  gameCandidateDisplay = nil,
  gameLockedSeekerKey = nil,
  gameLockedSeekerDisplay = nil,
  gameSeekerHistory = {},
  gameRotationUsed = {},
  -- Round flow for leader + party/raid sync (followers listen to leader chat)
  roundPhase = "none", -- none | pending (preparing) | hiding | searching
  remoteRoundActive = false,
  remoteSeekerKey = nil,
}

local function clearFound()
  wipe(State.foundOrder)
  wipe(State.foundSet)
end

-- NHSV (SavedVariables): layout + seeker UI options.
local function ensureSavedVars()
  NHSV = NHSV or {}
  if NHSV.hideGroupFramesInSeeker == nil then
    NHSV.hideGroupFramesInSeeker = true
  end
  if NHSV.hideMinimapInSeeker == nil then
    NHSV.hideMinimapInSeeker = false
  end
  if NHSV.minimapButtonAngle == nil then
    NHSV.minimapButtonAngle = math.rad(200)
  end
end

--[[
  Nameplate-related CVars snapshotted in seeker mode (Names / Nameplates options).
  Midnight (12.x) removed nameplateShowFriends; friendly *player* plates are driven
  largely by nameplatePlayerMaxDistance — set to 0 in seeker mode when present.
  We still SetCVar nameplateShowFriends for older clients (pcall, no GetCVar guard).
]]
local NAMEPLATE_CVARS = {
  -- Core toggles (Interface → Names / nameplate checkboxes)
  "nameplateShowAll",
  "nameplateShowEnemies",
  "nameplateShowFriends",
  "nameplateShowSelf",
  "nameplateShowFriendlyNPCs",
  "nameplateShowEnemyMinus",
  "nameplateShowEnemyMinions",
  "nameplateShowFriendlyMinions",
  "nameplateShowEnemyPets",
  "nameplateShowFriendlyPets",
  "nameplateShowEnemyGuardians",
  "nameplateShowFriendlyGuardians",
  "nameplateShowEnemyTotems",
  "nameplateShowFriendlyTotems",
  "nameplateShowOnlyNames",
  -- Player / world nameplate draw distance (Midnight: primary lever for player plates)
  "nameplatePlayerMaxDistance",
  "nameplateGameObjectMaxDistance",
  "nameplateMaxDistance",
  -- Offscreen / behind camera nameplates
  "nameplateTargetRadialPosition",
  "nameplateTargetBehindMaxDistance",
  -- Personal nameplate visibility (stack/resource)
  "NameplatePersonalShowAlways",
  "NameplatePersonalShowInCombat",
  "NameplatePersonalShowWithTarget",
  -- Floating unit names (often still visible when “nameplates” feel on)
  "UnitNameFriendlyPlayerName",
}

local function snapshotNameplates()
  local t = {}
  for _, key in ipairs(NAMEPLATE_CVARS) do
    local v = C_CVar.GetCVar(key)
    if v ~= nil then
      t[key] = v
    end
  end
  return t
end

local function applyNameplateSnapshot(t)
  if not t then
    return
  end
  for k, v in pairs(t) do
    if v ~= nil then
      pcall(C_CVar.SetCVar, k, v)
    end
  end
end

-- Seeker mode: force everything off. Do not require GetCVar first — removed CVars
-- (e.g. nameplateShowFriends on Midnight) are skipped for snapshot but SetCVar may still apply.
local function hideAllNameplates()
  for _, key in ipairs(NAMEPLATE_CVARS) do
    pcall(C_CVar.SetCVar, key, "0")
  end
end

-- While seeker: keep default party/raid (and optionally minimap) hidden — Blizz re-shows often, so we poll.
local SEEKER_UI_HIDE_FRAMES = {
  "PartyFrame",
  "CompactPartyFrame",
  "CompactRaidFrameContainer",
  "CompactRaidFrameManager",
}

local seekerUiPoll = CreateFrame("Frame")
seekerUiPoll:Hide()
seekerUiPoll:SetScript("OnUpdate", function(self, elapsed)
  self._acc = (self._acc or 0) + elapsed
  if self._acc < 0.35 then
    return
  end
  self._acc = 0
  if not State.seekerMode then
    return
  end
  ensureSavedVars()
  if NHSV.hideGroupFramesInSeeker then
    for _, fname in ipairs(SEEKER_UI_HIDE_FRAMES) do
      local fr = _G[fname]
      if fr and fr.IsShown and fr:IsShown() then
        fr:Hide()
      end
    end
  end
  if NHSV.hideMinimapInSeeker then
    local mc = _G.MinimapCluster
    if mc and mc.IsShown and mc:IsShown() then
      mc:Hide()
    end
  end
end)

local function seekerUiSuppressActive()
  ensureSavedVars()
  return State.seekerMode and (NHSV.hideGroupFramesInSeeker or NHSV.hideMinimapInSeeker)
end

local function seekerUiSuppressStart()
  if seekerUiSuppressActive() then
    seekerUiPoll:Show()
  end
end

local function seekerUiSuppressStop()
  seekerUiPoll:Hide()
  for _, fname in ipairs(SEEKER_UI_HIDE_FRAMES) do
    local fr = _G[fname]
    if fr and fr.Show then
      pcall(fr.Show, fr)
    end
  end
  local mc = _G.MinimapCluster
  if mc and mc.Show then
    pcall(mc.Show, mc)
  end
end

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

local function filterHouseEntries(list)
  local out = {}
  for _, v in ipairs(list) do
    if type(v) == "number" then
      out[#out + 1] = v
    elseif tableLooksLikeHouseEntry(v) then
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
  if #flat > 0 and type(flat[1]) == "table" then
    return flat
  end
  if tableLooksLikeHouseEntry(raw) then
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

-- Plain-text pin lines: | in SendChatMessage starts UI escapes — strip/replace for those only.
local function housingSanitizePinShareForChat(s)
  if not s then
    return ""
  end
  return (s:gsub("|", " · "))
end

-- Blizzard user-waypoint chat link (click sets map pin for the reader). Do not sanitize | in this string.
local function housingBuildBlizzardWaypointHyperlink(mapID, x, y)
  if not C_Map.SetUserWaypoint or not C_Map.GetUserWaypointHyperlink then
    return nil
  end
  local newPt
  if UiMapPoint.CreateFromCoordinates then
    newPt = UiMapPoint.CreateFromCoordinates(mapID, x, y)
  end
  if not newPt then
    return nil
  end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then
    return nil
  end
  local oldPt = nil
  if C_Map.GetUserWaypoint then
    local ok, prev = pcall(C_Map.GetUserWaypoint)
    if ok and prev ~= nil then
      oldPt = prev
    end
  end
  if not pcall(C_Map.SetUserWaypoint, newPt) then
    return nil
  end
  local okH, link = pcall(C_Map.GetUserWaypointHyperlink)
  if oldPt then
    pcall(C_Map.SetUserWaypoint, oldPt)
  elseif C_Map.ClearUserWaypoint then
    pcall(C_Map.ClearUserWaypoint)
  end
  if okH and type(link) == "string" and link ~= "" then
    return link
  end
  return nil
end

-- Only real SendChatMessage counts as “shared” — no edit-box prefill, no Yell, no printing coords on failure.
-- Channels: raid → party → say (no instance group requirement).
local function housingSendPinShareTryChannels(text)
  if IsInRaid() then
    local ok = pcall(SendChatMessage, text, "RAID")
    if ok then
      return true, "RAID", nil
    end
  end
  if IsInGroup() then
    local ok = pcall(SendChatMessage, text, "PARTY")
    if ok then
      return true, "PARTY", nil
    end
  end
  local ok = pcall(SendChatMessage, text, "SAY")
  if ok then
    return true, "SAY", nil
  end
  return false, nil, "Could not send to raid, party, or say."
end

local function housingSendPinShareChatRaw(text)
  if not text or text == "" then
    return false, nil, "empty message"
  end
  return housingSendPinShareTryChannels(text)
end

local function housingSendPinShareChat(text)
  text = housingSanitizePinShareForChat(text)
  if not text or text == "" then
    return false, nil, "empty message"
  end
  return housingSendPinShareTryChannels(text)
end

local function housingShareSelectedPinInChat(entry, rowIndex, labelText)
  local mapID, x, y = housingGetPinCoordsForEntry(entry, rowIndex)
  if not mapID or x == nil or y == nil then
    return false, "No coordinates for this plot — Refresh houses (Housing map open helps)."
  end
  local pctX = x * 100
  local pctY = y * 100
  local label = (labelText and labelText ~= "") and labelText or "plot"
  if #label > 72 then
    label = label:sub(1, 69) .. "..."
  end
  local msg = ("[NHS] Neighborhood pin: %s — uiMapID %d  %.4f %.4f  (~%.1f%% , ~%.1f%%)"):format(
    label,
    mapID,
    x,
    y,
    pctX,
    pctY
  )
  if #msg > 255 then
    msg = ("[NHS] Pin uiMapID %d %.4f %.4f — %s"):format(mapID, x, y, label)
  end
  if #msg > 255 then
    msg = ("[NHS] %d %.4f %.4f"):format(mapID, x, y)
  end
  local link = housingBuildBlizzardWaypointHyperlink(mapID, x, y)
  if link and #link <= 255 then
    local ok, ch, err = housingSendPinShareChatRaw(link)
    if ok then
      return true, ch
    end
  end
  local ok, ch, err = housingSendPinShareChat(msg)
  if ok then
    return true, ch
  end
  return false, err or "Send failed."
end

-- --- Game rounds (party/raid leader) ----------------------------------------
-- UI table exists early for GROUP_ROSTER_UPDATE / PARTY_LEADER_CHANGED refresh hooks.
local UI = {}
local setSeekerMode -- assigned with main frame; follower sync may call to exit seeker when a round ends.

local ROUND_PRESETS = {
  { label = "Small", hideSec = 180, searchSec = 240 },
  { label = "Medium", hideSec = 240, searchSec = 360 },
  { label = "Large", hideSec = 300, searchSec = 480 },
  { label = "Theme Park", hideSec = 300, searchSec = 600 },
}

local NHS_HOW_TO_PLAY_TEXT = table.concat({
  "|cffffffffOverview|r",
  "Neighborhood Hide & Seek is for parties and raids in housing neighborhoods. Each round, one player is the seeker; everyone else hides. The party/raid leader runs timers and seeker picks (you can also play solo).",
  "",
  "|cffffffffGame control|r",
  "• |cffffffffStart game session|r — begins a session. |cffffffffEnd game session|r stops it.",
  "• |cffffffffSeeker selection|r — |cffffffffRandom seeker|r picks a candidate, then |cffffffffConfirm seeker|r locks them in for the round.",
  "• Phases: |cffffffffSeeker selection|r → |cffffffffPreparing|r → |cffffffffHiding|r → |cffffffffSearching|r.",
  "• In |cffffffffPreparing|r, use the hiding countdown presets (party countdown). In |cffffffffHiding|r, use the searching countdown presets.",
  "• |cffffffffEnd round|r ends the current round so you can pick the next seeker (available during Preparing, Hiding, and Searching).",
  "",
  "|cffffffffGameplay|r",
  "• The current seeker is shown for the active round.",
  "• Only the designated seeker may |cffffffffEnter seeker mode|r (simplified nameplates / UI).",
  "• In |cffffffffSearching|r, the seeker targets a found player and uses |cffffffffMark target as found|r. A short [NHS] chat line syncs the found list for the group.",
  "• |cffffffffView past seekers|r lists everyone who has already been seeker this session (leader/solo).",
  "",
  "|cffffffffHouses|r",
  "• Use the house list, map pin, and share actions to pick a plot and post a pin in chat.",
  "",
  "|cffffffffSync|r",
  "Rounds and found players sync through party/raid chat lines beginning with [NHS]. Followers see the same phases and seeker as the leader.",
}, "\n")

local function nhsUnitSortKey(unit)
  if not UnitExists(unit) then
    return nil
  end
  local name, realm = UnitFullName(unit)
  if not name then
    return nil
  end
  local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
  return Ambiguate(full, "none")
end

local function nhsUnitDisplay(unit)
  return UnitName(unit) or "?"
end

local function nhsGetGroupRoster()
  local list = {}
  if not IsInGroup() then
    local unit = "player"
    if UnitExists(unit) and UnitIsPlayer(unit) then
      local key = nhsUnitSortKey(unit)
      if key then
        list[#list + 1] = { unit = unit, key = key, display = nhsUnitDisplay(unit) }
      end
    end
    return list
  end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitExists(unit) and UnitIsPlayer(unit) then
        local key = nhsUnitSortKey(unit)
        if key then
          list[#list + 1] = { unit = unit, key = key, display = nhsUnitDisplay(unit) }
        end
      end
    end
  elseif IsInGroup() then
    do
      local unit = "player"
      local key = nhsUnitSortKey(unit)
      if key then
        list[#list + 1] = { unit = unit, key = key, display = nhsUnitDisplay(unit) }
      end
    end
    for i = 1, GetNumGroupMembers() - 1 do
      local unit = "party" .. i
      if UnitExists(unit) and UnitIsPlayer(unit) then
        local key = nhsUnitSortKey(unit)
        if key then
          list[#list + 1] = { unit = unit, key = key, display = nhsUnitDisplay(unit) }
        end
      end
    end
  end
  return list
end

local function nhsIsRoundLeader()
  return IsInGroup() and UnitIsGroupLeader("player")
end

-- Solo (not in a group) may use game controls; in a group only the leader may.
local function nhsMayUseLeaderGameActions()
  if not IsInGroup() then
    return true
  end
  return nhsIsRoundLeader()
end

-- Blizzard party/raid countdown (same system as /cd in many setups); not an addon timer.
local function nhsStartBuiltInCountdown(seconds)
  seconds = math.floor(tonumber(seconds) or 0)
  if seconds < 1 then
    return false, "Invalid duration."
  end
  if C_PartyInfo and C_PartyInfo.DoCountdown then
    local ok, success = pcall(C_PartyInfo.DoCountdown, seconds)
    if ok and success then
      return true
    end
    if ok and success == false then
      return false, "Countdown failed — try in a party/raid or instance."
    end
    return false, "Could not start countdown."
  end
  return false, "C_PartyInfo.DoCountdown not available on this client."
end

local function nhsStopPartyCountdown()
  if C_PartyInfo and C_PartyInfo.DoCountdown then
    pcall(C_PartyInfo.DoCountdown, 0)
  end
end

-- Saved to NHSV.gameRounds so sessions survive /reload and match in-memory state after travel.
local function nhsPersistGameSessionToSaved()
  ensureSavedVars()
  if not State.gameSessionActive then
    NHSV.gameRounds = nil
    return
  end
  local rotKeys = {}
  for k in pairs(State.gameRotationUsed) do
    rotKeys[#rotKeys + 1] = k
  end
  local hist = {}
  for i = 1, #State.gameSeekerHistory do
    hist[i] = State.gameSeekerHistory[i]
  end
  NHSV.gameRounds = {
    sessionActive = true,
    phase = State.gamePhase,
    candidateKey = State.gameCandidateKey,
    candidateDisplay = State.gameCandidateDisplay,
    lockedKey = State.gameLockedSeekerKey,
    lockedDisplay = State.gameLockedSeekerDisplay,
    seekerHistory = hist,
    rotationKeys = rotKeys,
  }
end

local function nhsHydrateGameSessionFromSaved()
  ensureSavedVars()
  local s = NHSV.gameRounds
  if not s or not s.sessionActive then
    return
  end
  if State.gameSessionActive then
    return
  end
  State.gameSessionActive = true
  State.gamePhase = (s.phase == "round_active" or s.phase == "pick_seeker") and s.phase or "pick_seeker"
  State.gameCandidateKey = s.candidateKey
  State.gameCandidateDisplay = s.candidateDisplay
  State.gameLockedSeekerKey = s.lockedKey
  State.gameLockedSeekerDisplay = s.lockedDisplay
  wipe(State.gameSeekerHistory)
  for i, v in ipairs(s.seekerHistory or {}) do
    State.gameSeekerHistory[i] = v
  end
  wipe(State.gameRotationUsed)
  for _, k in ipairs(s.rotationKeys or {}) do
    State.gameRotationUsed[k] = true
  end
  if State.gamePhase == "round_active" then
    State.roundPhase = "pending"
  else
    State.roundPhase = "none"
  end
end

local function nhsResetGameSession()
  State.gameSessionActive = false
  State.gamePhase = "none"
  State.gameCandidateKey = nil
  State.gameCandidateDisplay = nil
  State.gameLockedSeekerKey = nil
  State.gameLockedSeekerDisplay = nil
  wipe(State.gameSeekerHistory)
  wipe(State.gameRotationUsed)
  State.roundPhase = "none"
  State.remoteRoundActive = false
  State.remoteSeekerKey = nil
  clearFound()
  ensureSavedVars()
  NHSV.gameRounds = nil
end

local function nhsPickRandomSeekerMember()
  local roster = nhsGetGroupRoster()
  if #roster == 0 then
    return nil, "No players in group."
  end
  local eligible = {}
  for _, m in ipairs(roster) do
    if not State.gameRotationUsed[m.key] then
      eligible[#eligible + 1] = m
    end
  end
  if #eligible == 0 then
    wipe(State.gameRotationUsed)
    eligible = roster
  end
  return eligible[math.random(1, #eligible)]
end

-- Party/raid chat sync — human-readable lines; only the group leader may send.
local NHS_CHAT_TAG = "[NHS]"
local NHS_MSG_ROUND_START = "[NHS] Round Start: "
local NHS_MSG_HIDING = "[NHS] Hiding Starts Now"
local NHS_MSG_SEEKING = "[NHS] The Seeking Begins!"
local NHS_MSG_ROUND_OVER = "[NHS] Round is over!"
local NHS_MSG_GAME_OVER = "[NHS] Game Over! Thanks for playing!"
local NHS_MSG_FOUND_PREFIX = "[NHS] Found: "

local function nhsLocalPlayerSortKey()
  return nhsUnitSortKey("player")
end

-- Who may send "mark found" sync: leader uses locked seeker key; followers use remote seeker key.
local function nhsGetDesignatedSeekerKey()
  if State.remoteRoundActive and State.remoteSeekerKey then
    return State.remoteSeekerKey
  end
  if State.gameSessionActive and State.gamePhase == "round_active" and State.gameLockedSeekerKey then
    if not IsInGroup() or nhsIsRoundLeader() then
      return State.gameLockedSeekerKey
    end
  end
  return nil
end

local function nhsChatSenderIsDesignatedSeeker(senderName)
  local seeker = nhsGetDesignatedSeekerKey()
  if not seeker or type(senderName) ~= "string" or senderName == "" then
    return false
  end
  return Ambiguate(senderName, "none") == seeker
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
        local k = nhsUnitSortKey(u)
        if k and k == sk then
          return true
        end
      end
    end
  elseif IsInGroup() then
    if UnitExists("player") and UnitIsGroupLeader("player") then
      local k = nhsUnitSortKey("player")
      if k and k == sk then
        return true
      end
    end
    for i = 1, GetNumGroupMembers() - 1 do
      local u = "party" .. i
      if UnitExists(u) and UnitIsGroupLeader(u) then
        local k = nhsUnitSortKey(u)
        if k and k == sk then
          return true
        end
      end
    end
  end
  return false
end

local function nhsGroupSyncChannel()
  return IsInRaid() and "RAID" or "PARTY"
end

local function nhsBroadcastLeaderSync(message)
  if not IsInGroup() or not nhsIsRoundLeader() or not message or message == "" then
    return
  end
  if #message > 255 then
    return
  end
  pcall(SendChatMessage, message, nhsGroupSyncChannel())
end

local function nhsClearRemoteRoundSync()
  State.remoteRoundActive = false
  State.remoteSeekerKey = nil
  State.roundPhase = "none"
  clearFound()
end

-- Enter seeker mode: only the designated seeker for the current round may enable it. While a game
-- session is up but no round is running (pick_seeker), nobody may enter seeker mode.
local function nhsMayEnterSeekerMode()
  if not IsInGroup() then
    if State.gameSessionActive and State.gamePhase == "pick_seeker" then
      return false
    end
    if State.gameSessionActive and State.gamePhase == "round_active" then
      if not State.gameLockedSeekerKey then
        return false
      end
      local me = nhsLocalPlayerSortKey()
      return me ~= nil and State.gameLockedSeekerKey == me
    end
    return true
  end
  if State.gameSessionActive and State.gamePhase == "pick_seeker" then
    return false
  end
  if nhsIsRoundLeader() and State.gameSessionActive and State.gamePhase == "round_active" then
    if not State.gameLockedSeekerKey then
      return false
    end
    local me = nhsLocalPlayerSortKey()
    return me ~= nil and State.gameLockedSeekerKey == me
  end
  if State.remoteRoundActive and State.remoteSeekerKey then
    local me = nhsLocalPlayerSortKey()
    return me ~= nil and State.remoteSeekerKey == me
  end
  if State.remoteRoundActive then
    return false
  end
  return true
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
  if not nhsChatSenderIsDesignatedSeeker(senderName) then
    return true
  end
  if State.roundPhase ~= "searching" then
    return true
  end
  local foundKey = Ambiguate(body:match("^%s*(.-)%s*$") or body, "none")
  if not foundKey or foundKey == "" then
    return true
  end
  if State.foundSet[foundKey] then
    return true
  end
  State.foundSet[foundKey] = true
  State.foundOrder[#State.foundOrder + 1] = foundKey
  if UI.RefreshAll then
    UI.RefreshAll()
  elseif UI.RefreshFound then
    UI.RefreshFound()
  end
  return true
end

local function nhsBroadcastSeekerFound(foundKey)
  if not IsInGroup() or type(foundKey) ~= "string" or foundKey == "" then
    return
  end
  local me = nhsLocalPlayerSortKey()
  local sk = nhsGetDesignatedSeekerKey()
  if not me or not sk or me ~= sk then
    return
  end
  local msg = NHS_MSG_FOUND_PREFIX .. foundKey
  if #msg > 255 then
    return
  end
  pcall(SendChatMessage, msg, nhsGroupSyncChannel())
end

local function nhsApplyGroupSyncFromLeader(senderName, text)
  if nhsIsRoundLeader() or not IsInGroup() then
    return
  end
  if not nhsChatSenderIsGroupLeader(senderName) then
    return
  end
  if type(text) ~= "string" or text:sub(1, #NHS_CHAT_TAG) ~= NHS_CHAT_TAG then
    return
  end
  local myKey = nhsLocalPlayerSortKey()
  local senderKey = Ambiguate(senderName, "none")
  if myKey and senderKey == myKey then
    return
  end
  local seekerPart = text:match("^%[NHS%]%s*Round Start:%s*(.+)%s*$")
  if seekerPart and seekerPart ~= "" then
    local key = Ambiguate(seekerPart:match("^%s*(.-)%s*$") or seekerPart, "none")
    if key and key ~= "" then
      clearFound()
      State.remoteRoundActive = true
      State.remoteSeekerKey = key
      State.roundPhase = "pending"
    end
  elseif text:match("^%[NHS%]%s*Hiding Starts Now%s*$") then
    if State.remoteRoundActive then
      State.roundPhase = "hiding"
    end
  elseif text:match("^%[NHS%]%s*The Seeking Begins!%s*$") then
    if State.remoteRoundActive then
      State.roundPhase = "searching"
    end
    elseif text:match("^%[NHS%]%s*Round is over!%s*$") or text:match("^%[NHS%]%s*Game Over! Thanks for playing!%s*$") then
      nhsClearRemoteRoundSync()
      if State.seekerMode and setSeekerMode then
        setSeekerMode(false)
      end
    end
  if UI.RefreshAll then
    UI.RefreshAll()
  elseif UI.RefreshGameRounds then
    UI.RefreshGameRounds()
  end
end

-- --- UI -----------------------------------------------------------------------

setSeekerMode = function(enabled)
  State.seekerMode = enabled and true or false
  if State.seekerMode then
    if not State.savedNameplateCVars then
      State.savedNameplateCVars = snapshotNameplates()
    end
    hideAllNameplates()
    seekerUiSuppressStart()
  else
    seekerUiSuppressStop()
    applyNameplateSnapshot(State.savedNameplateCVars)
    State.savedNameplateCVars = nil
    clearFound()
    State.selectedNeighborID = nil
    State.selectedLabel = nil
    State.selectedEntry = nil
    State.selectedIndex = nil
  end
  if UI.RefreshAll then
    UI.RefreshAll()
  end
end

local function markTargetFound()
  if not State.seekerMode then
    return
  end
  if State.roundPhase ~= "searching" then
    print("|cffff8800[NHS]|r Mark found is only available during the searching phase.")
    return
  end
  if not UnitExists("target") then
    print("|cffff8800[NHS]|r No target.")
    return
  end
  if not UnitIsPlayer("target") then
    print("|cffff8800[NHS]|r Target a player.")
    return
  end
  local key = nhsUnitSortKey("target")
  if not key then
    local name = UnitName("target")
    if not name then
      return
    end
    key = Ambiguate(name, "none")
  end
  if State.foundSet[key] then
    return
  end
  local disp = UnitName("target") or Ambiguate(key, "short")
  State.foundSet[key] = true
  State.foundOrder[#State.foundOrder + 1] = key
  print(("|cff88ff88[NHS]|r Marked found: %s"):format(disp))
  nhsBroadcastSeekerFound(key)
  if UI.RefreshFound then
    UI.RefreshFound()
  end
end

local function buildMainFrame()
  -- Unnamed frame avoids CreateFrame failing if a stale global name already exists.
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(360, 380)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.framePoint = { p, rp or "UIParent", x, y }
  end)
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  f:SetBackdropColor(0, 0, 0, 0.85)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  title:SetText("Neighborhood Hide & Seek")

  local roundsHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  roundsHint:SetWidth(328)
  roundsHint:SetJustifyH("LEFT")
  roundsHint:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -38)

  local divChromeGame = f:CreateTexture(nil, "ARTWORK", nil, 1)
  divChromeGame:SetColorTexture(1, 1, 1, 0.12)
  divChromeGame:SetSize(312, 1)
  divChromeGame:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -54)

  local sessionToggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sessionToggleBtn:SetSize(308, 24)
  sessionToggleBtn:SetPoint("TOPLEFT", divChromeGame, "BOTTOMLEFT", -8, -8)

  local seekerSelectHdr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  seekerSelectHdr:SetPoint("TOPLEFT", sessionToggleBtn, "BOTTOMLEFT", 0, -12)
  seekerSelectHdr:SetWidth(328)
  seekerSelectHdr:SetJustifyH("LEFT")
  seekerSelectHdr:SetText("Seeker selection")

  local candidateSeekerLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  candidateSeekerLbl:SetPoint("TOPLEFT", seekerSelectHdr, "BOTTOMLEFT", 0, -4)
  candidateSeekerLbl:SetWidth(328)
  candidateSeekerLbl:SetJustifyH("LEFT")
  candidateSeekerLbl:SetText("Current seeker (not locked in): —")

  local randSeekerBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  randSeekerBtn:SetSize(150, 22)
  randSeekerBtn:SetText("Random seeker")
  randSeekerBtn:SetPoint("TOPLEFT", candidateSeekerLbl, "BOTTOMLEFT", 0, -8)

  local startRoundBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  startRoundBtn:SetSize(150, 22)
  startRoundBtn:SetText("Confirm seeker")
  startRoundBtn:SetPoint("LEFT", randSeekerBtn, "RIGHT", 8, 0)

  local hideRowLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hideRowLbl:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -12)
  hideRowLbl:SetWidth(328)
  hideRowLbl:SetJustifyH("LEFT")
  hideRowLbl:SetText("Hiding — game countdown")

  local hidePresetBtns = {}
  for i = 1, 4 do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(150, 22)
    b._presetIdx = i
    b._kind = "hide"
    hidePresetBtns[i] = b
  end
  hidePresetBtns[1]:SetPoint("TOPLEFT", hideRowLbl, "BOTTOMLEFT", 0, -6)
  hidePresetBtns[2]:SetPoint("LEFT", hidePresetBtns[1], "RIGHT", 8, 0)
  hidePresetBtns[3]:SetPoint("TOPLEFT", hidePresetBtns[1], "BOTTOMLEFT", 0, -6)
  hidePresetBtns[4]:SetPoint("LEFT", hidePresetBtns[3], "RIGHT", 8, 0)

  local searchRowLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  searchRowLbl:SetPoint("TOPLEFT", hidePresetBtns[3], "BOTTOMLEFT", 0, -12)
  searchRowLbl:SetWidth(328)
  searchRowLbl:SetJustifyH("LEFT")
  searchRowLbl:SetText("Searching — game countdown")

  local searchPresetBtns = {}
  for i = 1, 4 do
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(150, 22)
    b._presetIdx = i
    b._kind = "search"
    searchPresetBtns[i] = b
  end
  searchPresetBtns[1]:SetPoint("TOPLEFT", searchRowLbl, "BOTTOMLEFT", 0, -6)
  searchPresetBtns[2]:SetPoint("LEFT", searchPresetBtns[1], "RIGHT", 8, 0)
  searchPresetBtns[3]:SetPoint("TOPLEFT", searchPresetBtns[1], "BOTTOMLEFT", 0, -6)
  searchPresetBtns[4]:SetPoint("LEFT", searchPresetBtns[3], "RIGHT", 8, 0)

  local ctrlSectionSpacer = CreateFrame("Frame", nil, f)
  ctrlSectionSpacer:SetSize(308, 16)
  ctrlSectionSpacer:SetPoint("TOPLEFT", searchPresetBtns[3], "BOTTOMLEFT", 0, -10)

  local endRoundBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  endRoundBtn:SetSize(308, 24)
  endRoundBtn:SetText("End round")
  endRoundBtn:SetPoint("TOPLEFT", ctrlSectionSpacer, "BOTTOMLEFT", 0, 0)

  local divControlGameplay = f:CreateTexture(nil, "ARTWORK", nil, 1)
  divControlGameplay:SetColorTexture(1, 1, 1, 0.12)
  divControlGameplay:SetSize(312, 1)
  divControlGameplay:SetPoint("TOPLEFT", endRoundBtn, "BOTTOMLEFT", -8, -10)

  local orphanSessionBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  orphanSessionBtn:SetSize(308, 24)
  orphanSessionBtn:SetText("End game session")
  orphanSessionBtn:Hide()

  local roundPhaseLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  roundPhaseLabel:SetWidth(328)
  roundPhaseLabel:SetJustifyH("LEFT")
  roundPhaseLabel:SetSpacing(2)
  roundPhaseLabel:SetPoint("TOPLEFT", divControlGameplay, "BOTTOMLEFT", 8, -8)

  local gameplaySeekerLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gameplaySeekerLbl:SetWidth(328)
  gameplaySeekerLbl:SetJustifyH("LEFT")
  gameplaySeekerLbl:SetPoint("TOPLEFT", roundPhaseLabel, "BOTTOMLEFT", 0, -6)
  gameplaySeekerLbl:SetText("Current seeker: —")

  local seekerBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  seekerBtn:SetSize(150, 28)
  seekerBtn:SetPoint("TOPLEFT", gameplaySeekerLbl, "BOTTOMLEFT", 0, -10)

  local viewPastSeekersBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewPastSeekersBtn:SetSize(150, 28)
  viewPastSeekersBtn:SetText("View past seekers")
  viewPastSeekersBtn:SetPoint("LEFT", seekerBtn, "RIGHT", 8, 0)

  local foundBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  foundBtn:SetSize(308, 28)
  foundBtn:SetText("Mark target as found")
  foundBtn:SetPoint("TOPLEFT", seekerBtn, "BOTTOMLEFT", 0, -8)

  local foundList = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  foundList:SetWidth(328)
  foundList:SetJustifyH("LEFT")
  foundList:SetSpacing(2)
  foundList:SetPoint("TOPLEFT", foundBtn, "BOTTOMLEFT", 0, -8)
  foundList:SetText("Found: (none)")

  local roundHintText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  roundHintText:SetWidth(328)
  roundHintText:SetJustifyH("LEFT")
  roundHintText:SetSpacing(2)
  roundHintText:Hide()

  local divGameplayHouse = f:CreateTexture(nil, "ARTWORK", nil, 1)
  divGameplayHouse:SetColorTexture(1, 1, 1, 0.12)
  divGameplayHouse:SetSize(312, 1)
  divGameplayHouse:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", -8, -12)

  local housingSelText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  housingSelText:SetPoint("TOPLEFT", divGameplayHouse, "BOTTOMLEFT", 8, -8)
  housingSelText:SetWidth(328)
  housingSelText:SetJustifyH("LEFT")
  housingSelText:SetText("Selected House: (none)")

  local viewHouseListBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewHouseListBtn:SetSize(308, 26)
  viewHouseListBtn:SetText("View House List")
  viewHouseListBtn:SetPoint("TOPLEFT", housingSelText, "BOTTOMLEFT", 0, -8)

  local pinBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  pinBtn:SetSize(308, 26)
  pinBtn:SetText("House Pin")
  pinBtn:SetPoint("TOPLEFT", viewHouseListBtn, "BOTTOMLEFT", 0, -8)

  local sharePinBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sharePinBtn:SetSize(308, 26)
  sharePinBtn:SetText("Share House Pin")
  sharePinBtn:SetPoint("TOPLEFT", pinBtn, "BOTTOMLEFT", 0, -8)

  local divHouseOptions = f:CreateTexture(nil, "ARTWORK", nil, 1)
  divHouseOptions:SetColorTexture(1, 1, 1, 0.12)
  divHouseOptions:SetSize(312, 1)
  divHouseOptions:SetPoint("TOPLEFT", sharePinBtn, "BOTTOMLEFT", -8, -10)

  local howToPlayBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  howToPlayBtn:SetSize(308, 26)
  howToPlayBtn:SetText("How to play")
  howToPlayBtn:SetPoint("TOPLEFT", divHouseOptions, "BOTTOMLEFT", 8, -8)

  local optionsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  optionsBtn:SetSize(308, 26)
  optionsBtn:SetText("Options")
  optionsBtn:SetPoint("TOPLEFT", howToPlayBtn, "BOTTOMLEFT", 0, -8)

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -6, -6)

  -- Options: seeker UI visibility (party/raid frames, minimap).
  local optf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  optf:SetSize(340, 168)
  optf:SetClampedToScreen(true)
  optf:SetMovable(true)
  optf:EnableMouse(true)
  optf:RegisterForDrag("LeftButton")
  optf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  optf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.optionsFramePoint = { p, rp or "UIParent", x, y }
  end)
  optf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  optf:SetBackdropColor(0, 0, 0, 0.88)

  local optTitle = optf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  optTitle:SetPoint("TOP", 0, -14)
  optTitle:SetText("Options")

  local optSub = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  optSub:SetPoint("TOPLEFT", 20, -42)
  optSub:SetWidth(300)
  optSub:SetJustifyH("LEFT")
  optSub:SetText("While in seeker mode")

  local cbParty = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbParty:SetSize(22, 22)
  cbParty:SetPoint("TOPLEFT", 16, -62)
  local cbPartyText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbPartyText:SetPoint("LEFT", cbParty, "RIGHT", 4, 0)
  cbPartyText:SetText("Hide party / raid frames")

  local cbMini = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbMini:SetSize(22, 22)
  cbMini:SetPoint("TOPLEFT", 16, -86)
  local cbMiniText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbMiniText:SetPoint("LEFT", cbMini, "RIGHT", 4, 0)
  cbMiniText:SetText("Hide minimap (entire cluster)")

  local function syncSeekerUiOptionsFromSaved()
    ensureSavedVars()
    cbParty:SetChecked(NHSV.hideGroupFramesInSeeker ~= false)
    cbMini:SetChecked(NHSV.hideMinimapInSeeker == true)
  end

  local function applySeekerUiOptionChange()
    ensureSavedVars()
    NHSV.hideGroupFramesInSeeker = cbParty:GetChecked() and true or false
    NHSV.hideMinimapInSeeker = cbMini:GetChecked() and true or false
    if State.seekerMode then
      if NHSV.hideGroupFramesInSeeker or NHSV.hideMinimapInSeeker then
        seekerUiPoll:Show()
      else
        seekerUiSuppressStop()
      end
    end
  end

  cbParty:SetScript("OnClick", applySeekerUiOptionChange)
  cbMini:SetScript("OnClick", applySeekerUiOptionChange)

  local optCloseBtn = CreateFrame("Button", nil, optf, "UIPanelCloseButton")
  optCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  optCloseBtn:SetScript("OnClick", function()
    optf:Hide()
  end)

  -- Second window: scrollable house list + refresh / random.
  local hf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  hf:SetSize(320, 420)
  hf:SetClampedToScreen(true)
  hf:SetMovable(true)
  hf:EnableMouse(true)
  hf:RegisterForDrag("LeftButton")
  hf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  hf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.houseListFramePoint = { p, rp or "UIParent", x, y }
  end)
  hf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  hf:SetBackdropColor(0, 0, 0, 0.88)

  local listTitle = hf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  listTitle:SetPoint("TOP", 0, -14)
  listTitle:SetText("House list")

  local listStatus = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  listStatus:SetPoint("TOPLEFT", 16, -40)
  listStatus:SetWidth(288)
  listStatus:SetJustifyH("LEFT")

  local refreshBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
  refreshBtn:SetSize(136, 24)
  refreshBtn:SetText("Refresh houses")
  refreshBtn:SetPoint("TOPLEFT", 16, -62)

  local randomBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
  randomBtn:SetSize(136, 24)
  randomBtn:SetText("Random house")
  randomBtn:SetPoint("LEFT", refreshBtn, "RIGHT", 8, 0)

  local scroll = CreateFrame("ScrollFrame", nil, hf)
  scroll:SetPoint("TOPLEFT", 16, -92)
  scroll:SetSize(288, 300)
  scroll:EnableMouse(true)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * 30)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(288, 1)
  child:EnableMouse(true)
  scroll:SetScrollChild(child)

  local function syncViewHouseListButtonLabel()
    viewHouseListBtn:SetText(hf:IsShown() and "Hide House List" or "View House List")
  end

  local listCloseBtn = CreateFrame("Button", nil, hf, "UIPanelCloseButton")
  listCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  listCloseBtn:SetScript("OnClick", function()
    hf:Hide()
    syncViewHouseListButtonLabel()
  end)

  local psf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  psf:SetSize(300, 280)
  psf:SetClampedToScreen(true)
  psf:SetMovable(true)
  psf:EnableMouse(true)
  psf:RegisterForDrag("LeftButton")
  psf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  psf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.pastSeekersFramePoint = { p, rp or "UIParent", x, y }
  end)
  psf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  psf:SetBackdropColor(0, 0, 0, 0.88)

  local psfTitle = psf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  psfTitle:SetPoint("TOP", 0, -14)
  psfTitle:SetText("Seekers this session")

  local psScroll = CreateFrame("ScrollFrame", nil, psf)
  psScroll:SetPoint("TOPLEFT", 16, -42)
  psScroll:SetSize(268, 210)
  psScroll:EnableMouse(true)
  psScroll:EnableMouseWheel(true)
  psScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * 30)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)
  local psScrollChild = CreateFrame("Frame", nil, psScroll)
  psScrollChild:SetSize(268, 1)
  psScroll:SetScrollChild(psScrollChild)
  local pastSeekersBody = psScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  pastSeekersBody:SetPoint("TOPLEFT", psScrollChild, "TOPLEFT", 0, 0)
  pastSeekersBody:SetWidth(258)
  pastSeekersBody:SetJustifyH("LEFT")
  pastSeekersBody:SetJustifyV("TOP")

  local psfCloseBtn = CreateFrame("Button", nil, psf, "UIPanelCloseButton")
  psfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  psfCloseBtn:SetScript("OnClick", function()
    psf:Hide()
  end)
  psf:Hide()

  local htpf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  htpf:SetSize(360, 420)
  htpf:SetClampedToScreen(true)
  htpf:SetMovable(true)
  htpf:EnableMouse(true)
  htpf:RegisterForDrag("LeftButton")
  htpf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  htpf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.howToPlayFramePoint = { p, rp or "UIParent", x, y }
  end)
  htpf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  htpf:SetBackdropColor(0, 0, 0, 0.9)

  local htpfTitle = htpf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  htpfTitle:SetPoint("TOP", 0, -14)
  htpfTitle:SetText("How to play")

  local htpScroll = CreateFrame("ScrollFrame", nil, htpf)
  htpScroll:SetPoint("TOPLEFT", 16, -42)
  htpScroll:SetSize(328, 358)
  htpScroll:EnableMouse(true)
  htpScroll:EnableMouseWheel(true)
  htpScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * 30)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)
  local htpScrollChild = CreateFrame("Frame", nil, htpScroll)
  htpScrollChild:SetSize(328, 1)
  htpScroll:SetScrollChild(htpScrollChild)
  local howToPlayBody = htpScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  howToPlayBody:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", 0, 0)
  howToPlayBody:SetWidth(318)
  howToPlayBody:SetJustifyH("LEFT")
  howToPlayBody:SetJustifyV("TOP")
  howToPlayBody:SetSpacing(4)
  howToPlayBody:SetText(NHS_HOW_TO_PLAY_TEXT)
  htpScrollChild:SetHeight(math.max(howToPlayBody:GetStringHeight() + 12, 1))
  htpScroll:SetVerticalScroll(0)

  local htpfCloseBtn = CreateFrame("Button", nil, htpf, "UIPanelCloseButton")
  htpfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  htpfCloseBtn:SetScript("OnClick", function()
    htpf:Hide()
  end)
  htpf:Hide()

  howToPlayBtn:SetScript("OnClick", function()
    htpf:Show()
  end)

  local function refreshPastSeekersPanel()
    local t = #State.gameSeekerHistory == 0 and "No seekers recorded this session yet."
      or table.concat(State.gameSeekerHistory, "\n")
    pastSeekersBody:SetText(t)
    psScrollChild:SetHeight(math.max(pastSeekersBody:GetStringHeight() + 8, 1))
    psScroll:SetVerticalScroll(0)
  end

  closeBtn:SetScript("OnClick", function()
    hf:Hide()
    syncViewHouseListButtonLabel()
    optf:Hide()
    psf:Hide()
    htpf:Hide()
    f:Hide()
  end)

  optionsBtn:SetScript("OnClick", function()
    if optf:IsShown() then
      optf:Hide()
    else
      syncSeekerUiOptionsFromSaved()
      optf:Show()
    end
  end)

  local houseButtons = {}
  local housesCache = {}

  local function selectHouse(index)
    local entry = housesCache[index]
    if not entry then
      return
    end
    State.selectedEntry = entry
    State.selectedIndex = index
    State.selectedNeighborID = neighborIDFromEntry(entry)
    State.selectedLabel = labelFromEntry(entry, index)
    housingSelText:SetText(
      State.selectedLabel and ("Selected House: %s"):format(State.selectedLabel)
        or "Selected House: (none)"
    )
    local can = housingAvailable()
    pinBtn:SetEnabled(can)
    sharePinBtn:SetEnabled(can)
  end

  local function refreshHouseList()
    local list, tag, detail = fetchVisitableHouses()
    housesCache = list
    housingRebuildPlotPinIndexFromRoot()
    for _, b in ipairs(houseButtons) do
      b:Hide()
    end
    local y = 0
    for i, entry in ipairs(housesCache) do
      local btn = houseButtons[i]
      if not btn then
        btn = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
        btn:SetSize(268, 22)
        btn:SetScript("OnClick", function()
          selectHouse(btn._idx)
        end)
        houseButtons[i] = btn
      end
      btn._idx = i
      btn:SetText(labelFromEntry(entry, i))
      btn:SetPoint("TOPLEFT", 10, -y)
      btn:Show()
      y = y + 24
    end
    child:SetHeight(math.max(y, 1))
    scroll:SetVerticalScroll(0)
    local suffix = ""
    if #housesCache > 0 then
      suffix = " — sorted by plot #"
    elseif #housesCache == 0 then
      if tag == "namespace_missing" or tag == "list_fn_missing" or tag == "call_failed" then
        suffix = " — " .. (detail or tag)
      else
        suffix = " — " .. (detail or "")
      end
    end
    listStatus:SetText(("Visitable houses: %d%s"):format(#housesCache, suffix))
  end

  viewHouseListBtn:SetScript("OnClick", function()
    if hf:IsShown() then
      hf:Hide()
    else
      hf:Show()
      refreshHouseList()
    end
    syncViewHouseListButtonLabel()
  end)

  local function refreshFoundList()
    local parts = {}
    for i = 1, #State.foundOrder do
      parts[#parts + 1] = Ambiguate(State.foundOrder[i], "short")
    end
    if #parts == 0 then
      foundList:SetText("Found: (none)")
    else
      foundList:SetText("Found: " .. table.concat(parts, ", "))
    end
  end

  local function gameplayCurrentSeekerCaption()
    if State.remoteRoundActive and State.remoteSeekerKey then
      return ("Current seeker: %s"):format(Ambiguate(State.remoteSeekerKey, "short"))
    end
    if State.gamePhase == "round_active" and State.gameLockedSeekerDisplay then
      return ("Current seeker: %s"):format(State.gameLockedSeekerDisplay)
    end
    return "Current seeker: —"
  end

  local function roundPhaseDescription()
    if State.roundPhase == "pending" then
      return "Preparing"
    elseif State.roundPhase == "hiding" then
      return "Hiding"
    elseif State.roundPhase == "searching" then
      return "Searching"
    end
    return tostring(State.roundPhase)
  end

  local function gameplayPhaseLine()
    if State.gameSessionActive and State.gamePhase == "pick_seeker" then
      return "Phase: Seeker selection"
    end
    if State.gameSessionActive and State.gamePhase == "round_active" then
      return ("Phase: %s"):format(roundPhaseDescription())
    end
    return nil
  end

  local function syncMainFrameHeight()
    if not f or not optionsBtn then
      return
    end
    local topEdge = f:GetTop()
    local btnBottom = optionsBtn:GetBottom()
    if not topEdge or not btnBottom then
      return
    end
    local lowest = btnBottom
    local htpBottom = howToPlayBtn and howToPlayBtn:GetBottom()
    if htpBottom then
      lowest = math.min(lowest, htpBottom)
    end
    if roundHintText:IsShown() then
      local hb = roundHintText:GetBottom()
      if hb then
        lowest = math.min(lowest, hb)
      end
    end
    local pad = 22
    local h = topEdge - lowest + pad
    h = math.max(260, math.min(1000, h))
    f:SetHeight(h)
  end

  local function setControlSectionVisible(show)
    divChromeGame:SetShown(show)
    sessionToggleBtn:SetShown(show)
    seekerSelectHdr:SetShown(show)
    candidateSeekerLbl:SetShown(show)
    randSeekerBtn:SetShown(show)
    startRoundBtn:SetShown(show)
    hideRowLbl:SetShown(show)
    searchRowLbl:SetShown(show)
    ctrlSectionSpacer:SetShown(show)
    for _, b in ipairs(hidePresetBtns) do
      b:SetShown(show)
    end
    for _, b in ipairs(searchPresetBtns) do
      b:SetShown(show)
    end
    endRoundBtn:SetShown(show)
  end

  local function layoutGameplayBlock(topAnchor, xOff, yOff, forLeaderUi)
    forLeaderUi = forLeaderUi ~= false
    if forLeaderUi then
      divControlGameplay:ClearAllPoints()
      divControlGameplay:Show()
      if topAnchor == f then
        divControlGameplay:SetPoint("TOPLEFT", f, "TOPLEFT", xOff, yOff)
      else
        divControlGameplay:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", xOff - 8, yOff + 6)
      end
    else
      divControlGameplay:Hide()
    end

    local phaseAnchor
    local phasePoint
    local phaseRel
    local phaseX
    local phaseY

    if orphanSessionBtn:IsShown() then
      orphanSessionBtn:ClearAllPoints()
      if forLeaderUi then
        orphanSessionBtn:SetPoint("TOPLEFT", divControlGameplay, "BOTTOMLEFT", 8, -8)
      else
        orphanSessionBtn:SetPoint("TOPLEFT", f, "TOPLEFT", xOff, yOff)
      end
      phaseAnchor = orphanSessionBtn
      phasePoint = "BOTTOMLEFT"
      phaseRel = "TOPLEFT"
      phaseX = 0
      phaseY = -8
    elseif forLeaderUi then
      phaseAnchor = divControlGameplay
      phasePoint = "BOTTOMLEFT"
      phaseRel = "TOPLEFT"
      phaseX = 8
      phaseY = -8
    else
      phaseAnchor = f
      phasePoint = "TOPLEFT"
      phaseRel = "TOPLEFT"
      phaseX = xOff
      phaseY = yOff
    end

    roundPhaseLabel:ClearAllPoints()
    roundPhaseLabel:SetPoint(phaseRel, phaseAnchor, phasePoint, phaseX, phaseY)
    gameplaySeekerLbl:ClearAllPoints()
    gameplaySeekerLbl:SetPoint("TOPLEFT", roundPhaseLabel, "BOTTOMLEFT", 0, -6)
    seekerBtn:ClearAllPoints()
    seekerBtn:SetPoint("TOPLEFT", gameplaySeekerLbl, "BOTTOMLEFT", 0, -10)
    viewPastSeekersBtn:ClearAllPoints()
    viewPastSeekersBtn:SetPoint("LEFT", seekerBtn, "RIGHT", 8, 0)
    foundBtn:ClearAllPoints()
    foundBtn:SetPoint("TOPLEFT", seekerBtn, "BOTTOMLEFT", 0, -8)
    foundList:ClearAllPoints()
    foundList:SetPoint("TOPLEFT", foundBtn, "BOTTOMLEFT", 0, -8)
  end

  local function refreshGameRounds()
    local leader = nhsIsRoundLeader()
    local ingroup = IsInGroup()
    local useLeaderUi = not ingroup or leader
    local mayAct = nhsMayUseLeaderGameActions()
    local sess = State.gameSessionActive
    local pick = State.gamePhase == "pick_seeker"
    local inRound = State.gamePhase == "round_active"
    local showOrphanEnd = sess and ingroup and not leader

    if ingroup and leader then
      State.remoteRoundActive = false
      State.remoteSeekerKey = nil
    end

    roundHintText:Hide()

    if not useLeaderUi then
      setControlSectionVisible(false)
      sessionToggleBtn:Hide()
      orphanSessionBtn:SetShown(showOrphanEnd)
      roundsHint:Show()
      if State.gameSessionActive then
        roundsHint:SetText(
          "Party/raid data may be unavailable briefly during travel or loading. "
            .. "Session is kept in memory and saved — it will not be deleted automatically."
        )
        layoutGameplayBlock(f, 16, -72, false)
        roundPhaseLabel:Hide()
        gameplaySeekerLbl:SetText(gameplayCurrentSeekerCaption())
        roundHintText:ClearAllPoints()
        roundHintText:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", 0, -10)
        roundHintText:SetWidth(328)
        roundHintText:Show()
        roundHintText:SetText(
          "Game control is hidden until you are party/raid leader again. "
            .. "Use End game session below to clear saved state."
        )
        viewPastSeekersBtn:SetEnabled(#State.gameSeekerHistory > 0)
        syncMainFrameHeight()
        return
      end
      if ingroup and State.remoteRoundActive then
        roundsHint:SetText("Party / raid sync (leader chat)")
        orphanSessionBtn:Hide()
        layoutGameplayBlock(f, 16, -40, false)
        roundPhaseLabel:SetWidth(328)
        roundPhaseLabel:SetText(("Phase: %s"):format(roundPhaseDescription()))
        roundPhaseLabel:Show()
        gameplaySeekerLbl:SetText(gameplayCurrentSeekerCaption())
        roundHintText:ClearAllPoints()
        roundHintText:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", 0, -10)
        roundHintText:SetWidth(328)
        roundHintText:Show()
        if State.roundPhase == "searching" then
          roundHintText:SetText(
            "If you are the seeker, use Enter seeker mode, then mark players when you find them."
          )
        elseif State.roundPhase == "hiding" then
          roundHintText:SetText(
            "Hiding — the leader can start a searching countdown when ready."
          )
        else
          roundHintText:SetText(
            "Preparing — the leader will start a hiding countdown when ready."
          )
        end
        viewPastSeekersBtn:SetEnabled(false)
        syncMainFrameHeight()
        return
      end
      orphanSessionBtn:Hide()
      roundsHint:SetText(
        not ingroup and "Join a party or raid to sync game rounds with the leader."
          or "Only the party/raid leader can run game control."
      )
      roundsHint:Show()
      layoutGameplayBlock(f, 16, -40, false)
      roundPhaseLabel:Hide()
      gameplaySeekerLbl:SetText(gameplayCurrentSeekerCaption())
      viewPastSeekersBtn:SetEnabled(false)
      syncMainFrameHeight()
      return
    end

    -- Leader or solo (not in group): show full control strip
    setControlSectionVisible(true)
    roundsHint:Hide()
    sessionToggleBtn:Show()
    orphanSessionBtn:Hide()

    sessionToggleBtn:SetText(sess and "End game session" or "Start game session")
    sessionToggleBtn:SetEnabled(mayAct)

    if State.gameCandidateDisplay then
      candidateSeekerLbl:SetText(
        ("Current seeker (not locked in): %s"):format(State.gameCandidateDisplay)
      )
    else
      candidateSeekerLbl:SetText("Current seeker (not locked in): —")
    end

    for i, b in ipairs(hidePresetBtns) do
      b:SetText(ROUND_PRESETS[i].label)
    end
    for i, b in ipairs(searchPresetBtns) do
      b:SetText(ROUND_PRESETS[i].label)
    end

    if not sess then
      randSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      endRoundBtn:SetEnabled(false)
    elseif pick then
      randSeekerBtn:SetEnabled(mayAct)
      startRoundBtn:SetEnabled(mayAct and State.gameCandidateKey ~= nil)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      endRoundBtn:SetEnabled(false)
    elseif inRound then
      randSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      local rp = State.roundPhase
      local hideOn = mayAct and rp == "pending"
      local searchOn = mayAct and rp == "hiding"
      local endOn = mayAct and (rp == "pending" or rp == "hiding" or rp == "searching")
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(hideOn)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(searchOn)
      end
      endRoundBtn:SetEnabled(endOn)
    else
      randSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      endRoundBtn:SetEnabled(false)
    end

    layoutGameplayBlock(endRoundBtn, 0, -16, true)

    local phaseLine = gameplayPhaseLine()
    if phaseLine then
      roundPhaseLabel:SetWidth(328)
      roundPhaseLabel:SetText(phaseLine)
      roundPhaseLabel:Show()
    else
      roundPhaseLabel:Hide()
    end
    gameplaySeekerLbl:SetText(gameplayCurrentSeekerCaption())

    viewPastSeekersBtn:SetEnabled(#State.gameSeekerHistory > 0)
    syncMainFrameHeight()
  end

  function UI.RefreshGameRounds()
    refreshGameRounds()
  end

  function UI.RefreshFound()
    refreshFoundList()
    syncMainFrameHeight()
  end

  function UI.RefreshAll()
    syncSeekerUiOptionsFromSaved()
    seekerBtn:SetText(State.seekerMode and "Leave seeker mode" or "Enter seeker mode")
    if State.seekerMode then
      seekerBtn:SetEnabled(true)
    else
      seekerBtn:SetEnabled(nhsMayEnterSeekerMode())
    end
    foundBtn:SetEnabled(State.seekerMode and State.roundPhase == "searching")
    refreshBtn:SetEnabled(true)
    refreshHouseList()
    local canHousing = housingAvailable()
    randomBtn:SetEnabled(canHousing and #housesCache > 0)
    pinBtn:SetEnabled(canHousing and State.selectedEntry ~= nil)
    sharePinBtn:SetEnabled(canHousing and State.selectedEntry ~= nil)
    housingSelText:SetText(
      State.selectedLabel and ("Selected House: %s"):format(State.selectedLabel)
        or "Selected House: (none)"
    )
    refreshFoundList()
    refreshGameRounds()
  end

  viewPastSeekersBtn:SetScript("OnClick", function()
    refreshPastSeekersPanel()
    psf:Show()
  end)

  orphanSessionBtn:SetScript("OnClick", function()
    if not (State.gameSessionActive and IsInGroup() and not nhsIsRoundLeader()) then
      return
    end
    nhsStopPartyCountdown()
    nhsResetGameSession()
    print("|cff88ccff[NHS]|r Game session ended.")
    refreshGameRounds()
  end)

  sessionToggleBtn:SetScript("OnClick", function()
    if State.gameSessionActive then
      nhsStopPartyCountdown()
      if nhsIsRoundLeader() and IsInGroup() then
        nhsBroadcastLeaderSync(NHS_MSG_GAME_OVER)
      end
      nhsResetGameSession()
      print("|cff88ccff[NHS]|r Game session ended.")
      refreshGameRounds()
      return
    end
    if IsInGroup() and not nhsIsRoundLeader() then
      return
    end
    State.gameSessionActive = true
    State.gamePhase = "pick_seeker"
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.gameLockedSeekerKey = nil
    State.gameLockedSeekerDisplay = nil
    wipe(State.gameSeekerHistory)
    wipe(State.gameRotationUsed)
    nhsPersistGameSessionToSaved()
    print("|cff88ccff[NHS]|r Game session started. Random a seeker, then confirm seeker to start the round.")
    refreshGameRounds()
  end)

  randSeekerBtn:SetScript("OnClick", function()
    if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_seeker" then
      return
    end
    local m, err = nhsPickRandomSeekerMember()
    if not m then
      print("|cffff8800[NHS]|r " .. tostring(err))
      return
    end
    State.gameCandidateKey = m.key
    State.gameCandidateDisplay = m.display
    print(
      ("|cff88ccff[NHS]|r Seeker pick: |cffffffff%s|r — Confirm seeker to lock in (or random again)."):format(
        m.display
      )
    )
    nhsPersistGameSessionToSaved()
    refreshGameRounds()
  end)

  startRoundBtn:SetScript("OnClick", function()
    if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_seeker" then
      return
    end
    if not State.gameCandidateKey then
      return
    end
    clearFound()
    State.gameRotationUsed[State.gameCandidateKey] = true
    State.gameSeekerHistory[#State.gameSeekerHistory + 1] = State.gameCandidateDisplay
    State.gameLockedSeekerKey = State.gameCandidateKey
    State.gameLockedSeekerDisplay = State.gameCandidateDisplay
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.gamePhase = "round_active"
    State.roundPhase = "pending"
    nhsBroadcastLeaderSync(NHS_MSG_ROUND_START .. tostring(State.gameLockedSeekerKey))
    print(
      ("|cff88ccff[NHS]|r Round started. |cffffffff%s|r is the seeker."):format(State.gameLockedSeekerDisplay)
    )
    nhsPersistGameSessionToSaved()
    refreshGameRounds()
  end)

  local function onPresetCountdownClick(self)
    if not nhsMayUseLeaderGameActions() or State.gamePhase ~= "round_active" then
      return
    end
    local idx = self._presetIdx
    local pr = ROUND_PRESETS[idx]
    local sec = (self._kind == "hide") and pr.hideSec or pr.searchSec
    local ok, err = nhsStartBuiltInCountdown(sec)
    if ok then
      local phaseLabel = (self._kind == "hide") and "Hiding" or "Searching"
      if self._kind == "hide" then
        State.roundPhase = "hiding"
        nhsBroadcastLeaderSync(NHS_MSG_HIDING)
      else
        State.roundPhase = "searching"
        nhsBroadcastLeaderSync(NHS_MSG_SEEKING)
      end
      print(
        ("|cff88ccff[NHS]|r %s — %s (%d s)."):format(phaseLabel, pr.label, sec)
      )
      if UI.RefreshAll then
        UI.RefreshAll()
      end
    else
      print("|cffff8800[NHS]|r " .. tostring(err))
    end
  end

  for _, b in ipairs(hidePresetBtns) do
    b:SetScript("OnClick", onPresetCountdownClick)
  end
  for _, b in ipairs(searchPresetBtns) do
    b:SetScript("OnClick", onPresetCountdownClick)
  end

  endRoundBtn:SetScript("OnClick", function()
    if not nhsMayUseLeaderGameActions() or State.gamePhase ~= "round_active" then
      return
    end
    State.gamePhase = "pick_seeker"
    State.gameLockedSeekerKey = nil
    State.gameLockedSeekerDisplay = nil
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.roundPhase = "none"
    clearFound()
    nhsStopPartyCountdown()
    nhsBroadcastLeaderSync(NHS_MSG_ROUND_OVER)
    print("|cff88ccff[NHS]|r Round ended. Random the next seeker.")
    nhsPersistGameSessionToSaved()
    if State.seekerMode then
      setSeekerMode(false)
    end
    refreshGameRounds()
  end)

  seekerBtn:SetScript("OnClick", function()
    setSeekerMode(not State.seekerMode)
  end)

  refreshBtn:SetScript("OnClick", function()
    refreshHouseList()
  end)

  randomBtn:SetScript("OnClick", function()
    if not housingAvailable() then
      print("|cffff8800[NHS]|r Housing API not ready.")
      return
    end
    if #housesCache == 0 then
      refreshHouseList()
    end
    if #housesCache == 0 then
      print("|cffff8800[NHS]|r No houses in list — click Refresh houses.")
      return
    end
    local idx = math.random(1, #housesCache)
    selectHouse(idx)
  end)

  pinBtn:SetScript("OnClick", function()
    if tryWaypointForEntry(State.selectedEntry, State.selectedIndex) then
      print("|cff88ff88[NHS]|r Map pin set.")
    else
      local n = 0
      for _ in pairs(Housing.plotPinIndex) do
        n = n + 1
      end
      if n == 0 then
        print(
          "|cffff8800[NHS]|r No coordinates on this row and no plot index from map data — open the Housing map, Refresh, or /dump C_HousingNeighborhood.GetNeighborhoodMapData()."
        )
      else
        print(
          ("|cffff8800[NHS]|r No pin for this plot (%d plot positions in map cache). Try Refresh after opening the neighborhood map."):format(
            n
          )
        )
      end
    end
  end)

  sharePinBtn:SetScript("OnClick", function()
    local ok, info = housingShareSelectedPinInChat(
      State.selectedEntry,
      State.selectedIndex,
      State.selectedLabel
    )
    if ok then
      print(("|cff88ff88[NHS]|r Pin shared to %s."):format(tostring(info)))
    else
      print("|cffff8800[NHS]|r " .. tostring(info))
    end
  end)

  foundBtn:SetScript("OnClick", markTargetFound)

  -- Without at least one SetPoint, the frame often never draws on screen.
  ensureSavedVars()
  f:ClearAllPoints()
  if NHSV.framePoint then
    local p = NHSV.framePoint
    f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  f:SetFrameStrata("DIALOG")
  f:SetFrameLevel(200)
  f:SetToplevel(true)
  f:Hide()

  hf:ClearAllPoints()
  if NHSV.houseListFramePoint then
    local hp = NHSV.houseListFramePoint
    hf:SetPoint(hp[1], UIParent, hp[2], hp[3], hp[4])
  else
    hf:SetPoint("TOPLEFT", f, "TOPRIGHT", 16, 0)
  end
  hf:SetFrameStrata("DIALOG")
  hf:SetFrameLevel(205)
  hf:SetToplevel(true)
  hf:Hide()

  optf:ClearAllPoints()
  if NHSV.optionsFramePoint then
    local op = NHSV.optionsFramePoint
    optf:SetPoint(op[1], UIParent, op[2], op[3], op[4])
  else
    optf:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -12)
  end
  optf:SetFrameStrata("DIALOG")
  optf:SetFrameLevel(204)
  optf:SetToplevel(true)
  optf:Hide()

  psf:ClearAllPoints()
  if NHSV.pastSeekersFramePoint then
    local pp = NHSV.pastSeekersFramePoint
    psf:SetPoint(pp[1], UIParent, pp[2], pp[3], pp[4])
  else
    psf:SetPoint("LEFT", f, "RIGHT", 16, 0)
  end
  psf:SetFrameStrata("DIALOG")
  psf:SetFrameLevel(206)
  psf:SetToplevel(true)

  htpf:ClearAllPoints()
  if NHSV.howToPlayFramePoint then
    local hp = NHSV.howToPlayFramePoint
    htpf:SetPoint(hp[1], UIParent, hp[2], hp[3], hp[4])
  else
    htpf:SetPoint("TOP", f, "TOP", 0, -24)
  end
  htpf:SetFrameStrata("DIALOG")
  htpf:SetFrameLevel(207)
  htpf:SetToplevel(true)

  UI.optionsFrame = optf
  UI.houseListFrame = hf
  UI.pastSeekersFrame = psf
  UI.howToPlayFrame = htpf
  UI.viewHouseListBtn = viewHouseListBtn
  UI.frame = f
end

-- --- Minimap button (no external libs) --------------------------------------

local nhsMinimapButton

local function nhsToggleMainFrame()
  local ok, err = pcall(function()
    if not UI.frame then
      buildMainFrame()
    end
    if not UI.frame then
      print("|cffff0000[NHS]|r Window failed to create. Enable Lua errors (Esc → Options → Help).")
      return
    end
    if UI.frame:IsShown() then
      if UI.houseListFrame and UI.houseListFrame:IsShown() then
        UI.houseListFrame:Hide()
      end
      if UI.viewHouseListBtn then
        UI.viewHouseListBtn:SetText("View House List")
      end
      if UI.optionsFrame and UI.optionsFrame:IsShown() then
        UI.optionsFrame:Hide()
      end
      if UI.pastSeekersFrame and UI.pastSeekersFrame:IsShown() then
        UI.pastSeekersFrame:Hide()
      end
      if UI.howToPlayFrame and UI.howToPlayFrame:IsShown() then
        UI.howToPlayFrame:Hide()
      end
      UI.frame:Hide()
    else
      if UI.RefreshAll then
        UI.RefreshAll()
      end
      UI.frame:Show()
    end
  end)
  if not ok then
    print("|cffff0000[NHS] Error:|r", tostring(err))
  end
end

-- Distance from minimap center to button center: outside the circular map (not tucked inside).
local function nhsMinimapOrbitRadius()
  if not Minimap then
    return 100
  end
  local w = Minimap:GetWidth() or 140
  local half = w * 0.5
  return half + 22
end

local function nhsMinimapButton_ApplyPosition()
  local b = nhsMinimapButton
  if not b or not Minimap then
    return
  end
  ensureSavedVars()
  local angle = NHSV.minimapButtonAngle or math.rad(200)
  local r = nhsMinimapOrbitRadius()
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function nhsMinimapButton_OnDragUpdate(self)
  if not Minimap then
    return
  end
  local scale = UIParent:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  local left = Minimap:GetLeft()
  local bottom = Minimap:GetBottom()
  if not left or not bottom then
    return
  end
  local w, h = Minimap:GetWidth(), Minimap:GetHeight()
  local mx = left + w / 2
  local my = bottom + h / 2
  local dx = cx - mx
  local dy = cy - my
  local angle = math.atan2(dy, dx)
  local r = nhsMinimapOrbitRadius()
  self:ClearAllPoints()
  self:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
  self._dragAngle = angle
end

local function nhsInitMinimapButton()
  if nhsMinimapButton or not Minimap then
    return
  end
  ensureSavedVars()
  local b = CreateFrame("Button", ADDON_NAME .. "MinimapButton", Minimap)
  nhsMinimapButton = b
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(9)
  b:SetMovable(true)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("RightButton")
  -- Use the button's normal/pushed texture slots so the icon is truly centered on Retail;
  -- a plain child texture can end up with TOPLEFT pinned at the button center on some Button layouts.
  b:SetNormalTexture("Interface\\Icons\\Ability_Stealth")
  b:SetPushedTexture("Interface\\Icons\\Ability_Stealth")
  local function nhsMinimapButton_StyleIconTexture(tex)
    if not tex then
      return
    end
    tex:SetTexCoord(0, 1, 0, 1)
    tex:ClearAllPoints()
    tex:SetSize(20, 20)
    tex:SetPoint("CENTER", b, "CENTER", 0, 0)
  end
  nhsMinimapButton_StyleIconTexture(b:GetNormalTexture())
  nhsMinimapButton_StyleIconTexture(b:GetPushedTexture())
  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(52, 52)
  ring:SetPoint("CENTER", b, "CENTER", 0, 0)
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
  b:SetScript("OnClick", function(_, btn)
    if btn == "LeftButton" then
      nhsToggleMainFrame()
    end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Neighborhood Hide & Seek", 1, 1, 1)
    GameTooltip:AddLine("Click to open or close the window.", 1, 1, 1, true)
    GameTooltip:AddLine("Right-drag to move this icon.", 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("/nhs", 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", nhsMinimapButton_OnDragUpdate)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    if self._dragAngle ~= nil then
      ensureSavedVars()
      NHSV.minimapButtonAngle = self._dragAngle
      self._dragAngle = nil
    end
    nhsMinimapButton_ApplyPosition()
  end)
  nhsMinimapButton_ApplyPosition()
end

-- --- Slash commands -----------------------------------------------------------
-- Chat only sees slash globals on the real _G table. Also refresh the hash after register.

local SLASH_TOKEN = "NHIDESEEK"

local function nhsSlashHandler(msg, editBox)
  local trimmed = (msg or ""):match("^%s*(.-)%s*$") or ""
  local cmd = trimmed:match("^(%S+)") or ""
  cmd = cmd:lower()
  if cmd == "visitinfo" or cmd == "visitdebug" or cmd == "whyvisit" then
    pcall(function()
      housingPrintVisitDiagnostics(State.selectedEntry, State.selectedIndex)
    end)
    return
  end
  nhsToggleMainFrame()
end

local function chatImportSlashCommands()
  if ChatFrame_ImportAllListsToHash then
    pcall(ChatFrame_ImportAllListsToHash)
  end
end

local function registerSlashCommands()
  if SlashCmdList_AddSlashCommand then
    local added = pcall(SlashCmdList_AddSlashCommand, SLASH_TOKEN, nhsSlashHandler, "nhs", "neighborhoodhs", "nhseek")
    if added then
      chatImportSlashCommands()
      return
    end
  end
  _G.SlashCmdList[SLASH_TOKEN] = nhsSlashHandler
  _G["SLASH_" .. SLASH_TOKEN .. "1"] = "/nhs"
  _G["SLASH_" .. SLASH_TOKEN .. "2"] = "/neighborhoodhs"
  _G["SLASH_" .. SLASH_TOKEN .. "3"] = "/nhseek"
  chatImportSlashCommands()
end

-- Fallback if slash routing still fails on your client: /run NHS_Toggle()
_G.NHS_Toggle = function()
  nhsToggleMainFrame()
end

registerSlashCommands()

local loader = CreateFrame("Frame")
local didPewImport
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:RegisterEvent("PLAYER_LOGOUT")
loader:RegisterEvent("GROUP_ROSTER_UPDATE")
loader:RegisterEvent("PARTY_LEADER_CHANGED")
loader:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON_NAME then
    ensureSavedVars()
    nhsHydrateGameSessionFromSaved()
    nhsPersistGameSessionToSaved()
    nhsInitMinimapButton()
    print(
      "|cff88ccff[NHS]|r Loaded. Minimap stealth icon or |cffffffff/nhs|r toggles the window. |cffffffff/nhs visitinfo|r explains Visit attempts. |cffffffff/run NHS_Toggle()|r if slash fails."
    )
  elseif event == "PLAYER_ENTERING_WORLD" then
    ensureSavedVars()
    nhsInitMinimapButton()
    nhsHydrateGameSessionFromSaved()
    nhsPersistGameSessionToSaved()
    if UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    end
    if not didPewImport then
      didPewImport = true
      housingInvalidate()
      chatImportSlashCommands()
    end
  elseif event == "PLAYER_LOGOUT" then
    nhsPersistGameSessionToSaved()
    seekerUiSuppressStop()
    if State.seekerMode and State.savedNameplateCVars then
      applyNameplateSnapshot(State.savedNameplateCVars)
    end
  elseif event == "GROUP_ROSTER_UPDATE" or event == "PARTY_LEADER_CHANGED" then
    if not IsInGroup() and State.remoteRoundActive then
      nhsClearRemoteRoundSync()
    end
    if UI.RefreshAll then
      UI.RefreshAll()
    elseif UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    end
  end
end)

local nhsSyncChatFrame = CreateFrame("Frame")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_PARTY")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_RAID")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
nhsSyncChatFrame:SetScript("OnEvent", function(_, _, text, sender)
  if type(text) ~= "string" or text:sub(1, #NHS_CHAT_TAG) ~= NHS_CHAT_TAG then
    return
  end
  if nhsApplyFoundSyncFromChat(sender, text) then
    return
  end
  nhsApplyGroupSyncFromLeader(sender, text)
end)
