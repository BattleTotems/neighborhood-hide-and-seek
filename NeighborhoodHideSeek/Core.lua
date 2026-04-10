--[[
  Neighborhood Hide & Seek — prototype (Retail Midnight housing neighborhoods).
  Target live client: 12.0.1 (TOC interface 120001). Verify with /dump select(4, GetBuildInfo()).
  Uses C_HousingNeighborhood / C_Housing for map/roster data; C_Map for waypoints/hyperlinks.
]]

-- Must match your AddOns folder name (used for ADDON_LOADED and SavedVariables).
local ADDON_NAME = "NeighborhoodHideSeek"
-- Minimap button art: PNG works on many Retail builds; if the icon is green or missing, export the same
-- image as MinimapIcon.tga (power-of-2 size) in Textures/ and switch the extension below.
local NHS_MINIMAP_ICON_TEXTURE = "Interface\\AddOns\\NeighborhoodHideSeek\\Textures\\MinimapIcon.tga"

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
  gamePhase = "none", -- none | pick_house | pick_seeker | round_active
  gameHouseCandidateKey = nil,
  gameHouseCandidateDisplay = nil,
  gameLockedHouseKey = nil,
  gameLockedHouseDisplay = nil,
  gameLockedHouseLiveEntry = nil,
  gameLockedHouseLiveIndex = nil,
  gameHouseRotationUsed = {},
  gameHouseHistory = {},
  gameCandidateKey = nil,
  gameCandidateDisplay = nil,
  gameLockedSeekerKey = nil,
  gameLockedSeekerDisplay = nil,
  gameSeekerHistory = {},
  gameRotationUsed = {},
  -- Follower: last house line from leader chat sync.
  remoteHouseDisplay = nil,
  -- Round flow for leader + party/raid sync (followers listen to leader chat)
  roundPhase = "none", -- none | pending (preparing) | hiding | searching
  remoteRoundActive = false,
  remoteSeekerKey = nil,
  -- Follower: leader sent "[NHS] Game session started" (stays true until Game Over chat).
  remoteSessionActive = false,
  -- Raid leader: we PromoteToAssistant'd the seeker for RAID_WARNING; demote on round/session end.
  nhsSeekerPromotedAsAssistantKey = nil,
  -- Completed rounds this session (house+size / seeker / hidden / found); cleared on new session or game over.
  pastRounds = {},
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
    NHSV.hideMinimapInSeeker = true
  end
  if NHSV.minimapButtonAngle == nil then
    NHSV.minimapButtonAngle = math.rad(200)
  end
  -- Fine-tune ring vs icon (default 0; added to built-in CENTER nudge in nhsInitMinimapButton).
  if NHSV.minimapRingOffsetX == nil then
    NHSV.minimapRingOffsetX = 0
  end
  if NHSV.minimapRingOffsetY == nil then
    NHSV.minimapRingOffsetY = 0
  end
  if type(NHSV.houseSizes) ~= "table" then
    NHSV.houseSizes = {}
  end
  if type(NHSV.houseLabels) ~= "table" then
    NHSV.houseLabels = {}
  end
  if type(NHSV.housePinCoords) ~= "table" then
    NHSV.housePinCoords = {}
  end
  if NHSV.selectHouseFromSavedList == nil then
    NHSV.selectHouseFromSavedList = true
  end
  if NHSV.useRandomPickAnimation == nil then
    if NHSV.useSpinnerRandomSelection ~= nil then
      NHSV.useRandomPickAnimation = NHSV.useSpinnerRandomSelection
    else
      NHSV.useRandomPickAnimation = true
    end
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

-- Plain-text fallback when a waypoint hyperlink cannot be built or sent (same tiers as Share House Pin).
local function housingPinShareCoordinateMessage(mapID, x, y, labelText)
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
  return msg
end

local function housingShareSelectedPinInChat(entry, rowIndex, labelText)
  local mapID, x, y = housingGetPinCoordsForEntry(entry, rowIndex)
  if not mapID or x == nil or y == nil then
    return false, "No coordinates for this plot — Refresh houses (Housing map open helps)."
  end
  local msg = housingPinShareCoordinateMessage(mapID, x, y, labelText)
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
local nhsSeekerAutoModeSyncToPhase -- after setSeekerMode: auto-enable seeker mode in Hiding / Searching
local nhsGetGroupRoster -- session HUD hidden list; assigned below with roster helpers

-- Compact session summary (Phase / Seeker / Hidden / Found) while a session or synced round is active.
local function nhsSessionHudIsActive()
  return State.gameSessionActive or State.remoteSessionActive or State.remoteRoundActive
end

local function nhsSessionHudPhaseText()
  if State.gameSessionActive and State.gamePhase == "pick_house" then
    return "House selection"
  end
  if State.gameSessionActive and State.gamePhase == "pick_seeker" then
    return "Seeker selection"
  end
  if State.gamePhase == "round_active" or State.remoteRoundActive then
    if State.roundPhase == "pending" then
      return "Preparing"
    elseif State.roundPhase == "hiding" then
      return "Hiding"
    elseif State.roundPhase == "searching" then
      return "Searching"
    end
    return "Round active"
  end
  if State.remoteSessionActive then
    return "Waiting for round"
  end
  return "—"
end

local function nhsSessionHudHouseText()
  if State.gameSessionActive and State.gamePhase == "pick_house" and State.gameHouseCandidateDisplay then
    return State.gameHouseCandidateDisplay
  end
  if State.gameSessionActive and (State.gamePhase == "pick_seeker" or State.gamePhase == "round_active") then
    if State.gameLockedHouseDisplay then
      return State.gameLockedHouseDisplay
    end
  end
  if State.remoteHouseDisplay and State.remoteHouseDisplay ~= "" then
    return State.remoteHouseDisplay
  end
  return "—"
end

local function nhsSessionHudSeekerText()
  if State.remoteRoundActive and State.remoteSeekerKey then
    return Ambiguate(State.remoteSeekerKey, "short")
  end
  if State.gamePhase == "round_active" and State.gameLockedSeekerDisplay then
    return State.gameLockedSeekerDisplay
  end
  if State.gamePhase == "pick_seeker" and State.gameCandidateDisplay then
    return State.gameCandidateDisplay
  end
  return "—"
end

local function nhsSessionHudSeekerKeyForLists()
  if State.remoteRoundActive and State.remoteSeekerKey then
    return State.remoteSeekerKey
  end
  if State.gamePhase == "round_active" and State.gameLockedSeekerKey then
    return State.gameLockedSeekerKey
  end
  if State.gamePhase == "pick_seeker" and State.gameCandidateKey then
    return State.gameCandidateKey
  end
  return nil
end

local function nhsSessionHudCommaList(names, maxShown)
  maxShown = maxShown or 14
  if #names == 0 then
    return "(none)"
  end
  table.sort(names)
  if #names <= maxShown then
    return table.concat(names, ", ")
  end
  local parts = {}
  for i = 1, maxShown do
    parts[i] = names[i]
  end
  return table.concat(parts, ", ") .. (", +" .. tostring(#names - maxShown) .. " more")
end

-- Everyone still hiding (not marked found), excluding the designated seeker once that key is known.
local function nhsSessionHudHiddenPlayerNames()
  local sk = nhsSessionHudSeekerKeyForLists()
  local roster = nhsGetGroupRoster()
  local names = {}
  for _, m in ipairs(roster) do
    if (sk == nil or m.key ~= sk) and not State.foundSet[m.key] then
      names[#names + 1] = Ambiguate(m.key, "short")
    end
  end
  table.sort(names)
  return names
end

local function nhsSessionHudHiddenFormatted()
  local names = nhsSessionHudHiddenPlayerNames()
  local n = #names
  if n == 0 then
    return "Hidden (0): —"
  end
  return ("Hidden (%d): %s"):format(n, nhsSessionHudCommaList(names))
end

local function nhsSessionHudFoundFormatted()
  local names = {}
  for i = 1, #State.foundOrder do
    names[#names + 1] = Ambiguate(State.foundOrder[i], "short")
  end
  local n = #names
  if n == 0 then
    return "Found (0): —"
  end
  table.sort(names)
  return ("Found (%d): %s"):format(n, nhsSessionHudCommaList(names))
end

local function nhsSessionHudUpdate()
  local hud = UI.sessionHud
  if not hud then
    return
  end
  if not nhsSessionHudIsActive() then
    hud:Hide()
    return
  end
  hud:Show()
  hud._phaseLine:SetText("Phase: " .. nhsSessionHudPhaseText())
  hud._houseLine:SetText("House: " .. nhsSessionHudHouseText())
  hud._seekerLine:SetText("Seeker: " .. nhsSessionHudSeekerText())
  hud._foundLine:SetText(nhsSessionHudFoundFormatted())
  hud._hiddenLine:SetText(nhsSessionHudHiddenFormatted())
  local w = hud._contentW or 216
  local padBottom = 14
  local hTitle = hud._title:GetStringHeight() or 12
  local hPhase = hud._phaseLine:GetStringHeight() or 12
  local hHouse = hud._houseLine:GetStringHeight() or 12
  local hSeek = hud._seekerLine:GetStringHeight() or 12
  local hHid = hud._hiddenLine:GetStringHeight() or 12
  local hFound = hud._foundLine:GetStringHeight() or 12
  local totalH = 12 + hTitle + 10 + hPhase + 4 + hHouse + 4 + hSeek + 8 + hHid + 6 + hFound + padBottom
  hud:SetHeight(math.max(130, math.min(360, totalH)))
end

local function nhsInitSessionHud()
  if UI.sessionHud then
    return
  end
  ensureSavedVars()
  local hud = CreateFrame("Frame", ADDON_NAME .. "SessionHud", UIParent, "BackdropTemplate")
  local contentW = 216
  hud._contentW = contentW
  hud:SetSize(240, 160)
  hud:SetClampedToScreen(true)
  hud:SetMovable(true)
  hud:SetFrameStrata("MEDIUM")
  hud:SetFrameLevel(25)
  hud:EnableMouse(true)
  hud:RegisterForDrag("LeftButton")
  hud:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.sessionHudPoint = { p, rp or "UIParent", x, y }
  end)
  hud:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  hud:SetBackdropColor(0, 0, 0, 0.85)
  if NHSV.sessionHudPoint then
    local hp = NHSV.sessionHudPoint
    hud:SetPoint(hp[1], UIParent, hp[2], hp[3], hp[4])
  else
    hud:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -160)
  end
  local title = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -12)
  title:SetText("Hide & Seek")
  hud._title = title
  local phaseLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  phaseLine:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  phaseLine:SetWidth(contentW)
  phaseLine:SetJustifyH("LEFT")
  phaseLine:SetSpacing(2)
  local houseLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  houseLine:SetPoint("TOPLEFT", phaseLine, "BOTTOMLEFT", 0, -4)
  houseLine:SetWidth(contentW)
  houseLine:SetJustifyH("LEFT")
  houseLine:SetSpacing(2)
  local seekerLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  seekerLine:SetPoint("TOPLEFT", houseLine, "BOTTOMLEFT", 0, -4)
  seekerLine:SetWidth(contentW)
  seekerLine:SetJustifyH("LEFT")
  seekerLine:SetSpacing(2)
  local hiddenLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hiddenLine:SetPoint("TOPLEFT", seekerLine, "BOTTOMLEFT", 0, -8)
  hiddenLine:SetWidth(contentW)
  hiddenLine:SetJustifyH("LEFT")
  hiddenLine:SetSpacing(2)
  local foundLine = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  foundLine:SetPoint("TOPLEFT", hiddenLine, "BOTTOMLEFT", 0, -6)
  foundLine:SetWidth(contentW)
  foundLine:SetJustifyH("LEFT")
  foundLine:SetSpacing(2)
  hud._phaseLine = phaseLine
  hud._houseLine = houseLine
  hud._seekerLine = seekerLine
  hud._foundLine = foundLine
  hud._hiddenLine = hiddenLine
  UI.sessionHud = hud
  nhsSessionHudUpdate()
end

local ROUND_PRESETS = {
  { label = "Small", hideSec = 180, searchSec = 240 },
  { label = "Medium", hideSec = 240, searchSec = 360 },
  { label = "Large", hideSec = 300, searchSec = 480 },
  { label = "Theme Park", hideSec = 300, searchSec = 600 },
}

-- Stable id for SavedVariables (prefer GUID, then plot/lot id, then neighbor id).
-- Plot / lot id 0 is valid (first plot); do not use housingIdNonZero here.
local function nhsHouseStableKeyFromEntry(entry)
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

local function nhsGetSavedPresetIndexForEntry(entry)
  ensureSavedVars()
  local key = nhsHouseStableKeyFromEntry(entry)
  if not key then
    return nil
  end
  local idx = tonumber(NHSV.houseSizes[key])
  if not idx or idx < 1 or idx > #ROUND_PRESETS then
    return nil
  end
  return idx
end

local function nhsSetSavedPresetForEntry(entry, presetIdx, displayLabel, listRowIndex)
  presetIdx = tonumber(presetIdx)
  if not presetIdx or presetIdx < 1 or presetIdx > #ROUND_PRESETS then
    return false
  end
  local key = nhsHouseStableKeyFromEntry(entry)
  if not key then
    return false
  end
  ensureSavedVars()
  NHSV.houseSizes[key] = presetIdx
  if type(displayLabel) == "string" and displayLabel ~= "" then
    NHSV.houseLabels[key] = displayLabel
  end
  local mapID, x, y = housingGetPinCoordsForEntry(entry, listRowIndex or 1)
  if mapID and mapID ~= 0 and x ~= nil and y ~= nil then
    NHSV.housePinCoords[key] = { mapID = mapID, x = x, y = y }
  else
    NHSV.housePinCoords[key] = nil
  end
  return true
end

local function nhsClearSavedPresetForEntry(entry)
  local key = nhsHouseStableKeyFromEntry(entry)
  if not key then
    return false
  end
  ensureSavedVars()
  NHSV.houseSizes[key] = nil
  NHSV.houseLabels[key] = nil
  NHSV.housePinCoords[key] = nil
  return true
end

-- Persisted when saving size; used for gameplay pin broadcast when picking from saved list (no live row).
local function nhsGetSavedHousePinCoords(stableKey)
  if type(stableKey) ~= "string" or stableKey == "" then
    return nil, nil, nil
  end
  ensureSavedVars()
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

local function nhsSavedSizeSuffixForEntry(entry)
  local idx = nhsGetSavedPresetIndexForEntry(entry)
  if not idx then
    return ""
  end
  return (" [%s]"):format(ROUND_PRESETS[idx].label)
end

local function nhsCountSavedHouseSizes()
  ensureSavedVars()
  local n = 0
  for _ in pairs(NHSV.houseSizes) do
    n = n + 1
  end
  return n
end

local function nhsPresetButtonsApplySavedHighlight(hideBtns, searchBtns, entry)
  local idx = nhsGetSavedPresetIndexForEntry(entry)
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

local function nhsGetSavedPresetIndexForStableKey(stableKey)
  if type(stableKey) ~= "string" or stableKey == "" then
    return nil
  end
  ensureSavedVars()
  local idx = tonumber(NHSV.houseSizes[stableKey])
  if not idx or idx < 1 or idx > #ROUND_PRESETS then
    return nil
  end
  return idx
end

local function nhsPresetButtonsApplySavedHighlightIdx(hideBtns, searchBtns, idx)
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

-- Gameplay house pool (pick_house): saved sizes vs current visitable list (Options).
local function nhsGameplaySavedHousePoolEntries()
  ensureSavedVars()
  local wrapped = {}
  for key, idx in pairs(NHSV.houseSizes) do
    idx = tonumber(idx)
    if idx and idx >= 1 and idx <= #ROUND_PRESETS then
      local label = NHSV.houseLabels[key] or key
      local disp = ("%s [%s]"):format(label, ROUND_PRESETS[idx].label)
      wrapped[#wrapped + 1] = {
        k = nhsPlotSortKeyFromSavedLabelOrKey(label, key),
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

local function nhsGameplayCurrentHousePoolEntries(rows)
  local list = {}
  for i, entry in ipairs(rows or {}) do
    list[i] = entry
  end
  sortHouseListInPlace(list)
  local pool = {}
  for i, entry in ipairs(list) do
    local rk = nhsHouseStableKeyFromEntry(entry)
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

local function nhsBuildGameplayHousePickPool(housesCache)
  ensureSavedVars()
  if NHSV.selectHouseFromSavedList ~= false then
    return nhsGameplaySavedHousePoolEntries()
  end
  return nhsGameplayCurrentHousePoolEntries(housesCache)
end

-- Eligible pool for random house (same rules as pick); used by random pick UI and nhsPickRandomGameplayHouse.
local function nhsGameplayRandomHouseEligible(housesCache)
  local pool = nhsBuildGameplayHousePickPool(housesCache)
  if #pool == 0 then
    return nil,
      (NHSV.selectHouseFromSavedList ~= false)
          and "No saved houses with sizes. Add sizes in the house list, or disable “Select from saved house list” in Options."
        or "No houses in the current list — open View house list and refresh, or visit the neighborhood."
  end
  local elig = {}
  for _, p in ipairs(pool) do
    if not State.gameHouseRotationUsed[p.rotKey] then
      elig[#elig + 1] = p
    end
  end
  if #elig == 0 then
    wipe(State.gameHouseRotationUsed)
    elig = pool
  end
  return elig, nil
end

local function nhsPickRandomGameplayHouse(housesCache)
  local elig, err = nhsGameplayRandomHouseEligible(housesCache)
  if not elig then
    return nil, err
  end
  return elig[math.random(1, #elig)]
end

local NHS_HOW_TO_PLAY_TEXT = table.concat({
  "Overview",
  "Neighborhood Hide & Seek is for parties and raids in housing neighborhoods. Each round, one player is the seeker; everyone else hides. The party/raid leader keeps the game running and moves through the phases.",
  "",
  "Gameplay",
  "• Phases: House selection -> Seeker selection -> Preparing -> Hiding -> Searching.",
  "• Information is shown in the compact HUD while a session or synced round is active.",
  "• Phase - House Selection: the leader picks which house the round uses (saved list or current neighborhood list, per Options). Random house avoids repeats until everyone has been used once.",
  "• Phase - Seeker Selection: during this phase, the leader picks a seeker from the group.",
  "• Phase - Preparing: during this phase, the whole group has a chance to move to the selected house and prepare for the next phase.",
  "• Phase - Hiding: during this phase, everyone but the seeker hides. This is started by a timer. Everyone has the set amount of time to hide before the seeker starts searching.",
  "• Phase - Searching: during this phase, the seeker searches. This is started by a timer. The seeker has the set amount of time to search before the round ends. The round ends early if the seeker finds all players. The designated seeker marks hiders found by targeting them (seeker mode turns on automatically; you can also toggle it under Options).",
  "",
  "Game control (leader only)",
  "• Start game session — begins a session. End game session stops it.",
  "• House selection — Random house / view list / confirm house (same rotation idea as seekers). Past houses / past seekers are under the live gameplay details (phase, house, seeker, hidden, found) whenever a session is active.",
  "• Seeker selection — Random seeker, Select seeker (group list), and Confirm seeker (same row layout as house selection).",
  "• In Preparing, use the hiding countdown presets (party countdown) to move to the next phase when the group is prepared.",
  "• In Hiding, use the searching countdown presets to move to the next phase when the seeker starts searching.",
  "• In Searching, when the searching countdown ends or when seeker finds all players, this can end the round and move to the next round.",
  "",
  "Houses",
  "• Use the house list, map pin, and share actions to pick a plot and post a pin in chat.",
  "• Gameplay “house selection” in a session is separate from that list: it only chooses which house the round uses for the group (and syncs to others).",
  "• The main house list can still be used to browse plots and save sizes for saved-list picking.",
  "",
  "Sync",
  "Rounds, locked house, and found players sync through party/raid chat lines beginning with [NHS]. Group members see the same phases, house, and seeker as the leader.",
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

nhsGetGroupRoster = function()
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

local function nhsUnitIsInGroupRoster(unit)
  if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
    return false
  end
  local tk = nhsUnitSortKey(unit)
  if not tk then
    return false
  end
  for _, m in ipairs(nhsGetGroupRoster()) do
    if m.key == tk then
      return true
    end
  end
  return false
end

local function nhsFindGroupUnitForSortKey(wantKey)
  if not wantKey then
    return nil
  end
  for _, m in ipairs(nhsGetGroupRoster()) do
    if m.key == wantKey then
      return m.unit
    end
  end
  return nil
end

local function nhsIsRoundLeader()
  return IsInGroup() and UnitIsGroupLeader("player")
end

-- Seeker "Found:" sync: raid assistants/leaders may use RAID_WARNING; others fall back to RAID.
local function nhsSeekerFoundSyncChannel()
  if IsInRaid() then
    if UnitIsGroupLeader("player") or (UnitIsRaidOfficer and UnitIsRaidOfficer("player")) then
      return "RAID_WARNING"
    end
    return "RAID"
  end
  return "PARTY"
end

-- Raid leader only: temporary assistant so the seeker can send RAID_WARNING for [NHS] Found lines.
local function nhsLeaderTryPromoteSeekerForRaidWarn()
  if not nhsIsRoundLeader() or not IsInRaid() or not State.gameLockedSeekerKey then
    return
  end
  local key = State.gameLockedSeekerKey
  local unit = nhsFindGroupUnitForSortKey(key)
  if not unit or not UnitExists(unit) then
    return
  end
  if UnitIsGroupLeader(unit) or (UnitIsRaidOfficer and UnitIsRaidOfficer(unit)) then
    return
  end
  if PromoteToAssistant then
    pcall(PromoteToAssistant, unit)
  end
  if UnitIsRaidOfficer and UnitIsRaidOfficer(unit) and not UnitIsGroupLeader(unit) then
    State.nhsSeekerPromotedAsAssistantKey = key
  end
end

local function nhsLeaderDemoteSeekerAssistantIfWePromoted()
  if not State.nhsSeekerPromotedAsAssistantKey then
    return
  end
  local key = State.nhsSeekerPromotedAsAssistantKey
  State.nhsSeekerPromotedAsAssistantKey = nil
  if nhsIsRoundLeader() and IsInRaid() then
    local unit = nhsFindGroupUnitForSortKey(key)
    if unit and UnitExists(unit) and not UnitIsGroupLeader(unit) then
      if UnitIsRaidOfficer and UnitIsRaidOfficer(unit) and DemoteAssistant then
        pcall(DemoteAssistant, unit)
      end
    end
  end
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
local function nhsFoundOrderSnapshot()
  local t = {}
  for i = 1, #State.foundOrder do
    t[i] = State.foundOrder[i]
  end
  return t
end

local function nhsRestoreFoundFromSnapshot(list)
  clearFound()
  if type(list) ~= "table" then
    return
  end
  for _, k in ipairs(list) do
    if type(k) == "string" and k ~= "" and not State.foundSet[k] then
      State.foundSet[k] = true
      State.foundOrder[#State.foundOrder + 1] = k
    end
  end
end

local function nhsPastRoundsSnapshotForSave()
  local out = {}
  for i = 1, #State.pastRounds do
    local r = State.pastRounds[i]
    if type(r) == "table" then
      out[#out + 1] = {
        house = r.house or "",
        seeker = r.seeker or "",
        hidden = r.hidden or "",
        found = r.found or "",
      }
    end
  end
  return out
end

local function nhsRestorePastRoundsFromSave(list)
  wipe(State.pastRounds)
  if type(list) ~= "table" then
    return
  end
  for _, pr in ipairs(list) do
    if type(pr) == "table" then
      State.pastRounds[#State.pastRounds + 1] = {
        house = pr.house or "",
        seeker = pr.seeker or "",
        hidden = pr.hidden or "",
        found = pr.found or "",
      }
    end
  end
end

local function nhsPersistGameSessionToSaved()
  ensureSavedVars()
  local foundSnap = nhsFoundOrderSnapshot()
  local pastSnap = nhsPastRoundsSnapshotForSave()
  if State.gameSessionActive then
    local rotKeys = {}
    for k in pairs(State.gameRotationUsed) do
      rotKeys[#rotKeys + 1] = k
    end
    local hist = {}
    for i = 1, #State.gameSeekerHistory do
      hist[i] = State.gameSeekerHistory[i]
    end
    local houseRotKeys = {}
    for k in pairs(State.gameHouseRotationUsed) do
      houseRotKeys[#houseRotKeys + 1] = k
    end
    local houseHist = {}
    for i = 1, #State.gameHouseHistory do
      houseHist[i] = State.gameHouseHistory[i]
    end
    NHSV.gameRounds = {
      sessionActive = true,
      clientMode = "leader",
      phase = State.gamePhase,
      houseCandidateKey = State.gameHouseCandidateKey,
      houseCandidateDisplay = State.gameHouseCandidateDisplay,
      houseLockedKey = State.gameLockedHouseKey,
      houseLockedDisplay = State.gameLockedHouseDisplay,
      houseRotationKeys = houseRotKeys,
      houseHistory = houseHist,
      candidateKey = State.gameCandidateKey,
      candidateDisplay = State.gameCandidateDisplay,
      lockedKey = State.gameLockedSeekerKey,
      lockedDisplay = State.gameLockedSeekerDisplay,
      seekerHistory = hist,
      rotationKeys = rotKeys,
      foundOrder = foundSnap,
      pastRounds = pastSnap,
    }
    return
  end
  if State.remoteSessionActive or State.remoteRoundActive then
    local houseHist = {}
    for i = 1, #State.gameHouseHistory do
      houseHist[i] = State.gameHouseHistory[i]
    end
    local seekHist = {}
    for i = 1, #State.gameSeekerHistory do
      seekHist[i] = State.gameSeekerHistory[i]
    end
    NHSV.gameRounds = {
      sessionActive = true,
      clientMode = "follower",
      remoteSessionActive = State.remoteSessionActive and true or false,
      remoteRoundActive = State.remoteRoundActive and true or false,
      remoteSeekerKey = State.remoteSeekerKey,
      remoteHouseDisplay = State.remoteHouseDisplay,
      roundPhase = State.roundPhase,
      houseHistory = houseHist,
      seekerHistory = seekHist,
      foundOrder = foundSnap,
      pastRounds = pastSnap,
    }
    return
  end
  NHSV.gameRounds = nil
end

local function nhsHydrateGameSessionFromSaved()
  ensureSavedVars()
  local s = NHSV.gameRounds
  if not s or not s.sessionActive then
    nhsSessionHudUpdate()
    return
  end
  local mode = s.clientMode or "leader"
  if mode == "follower" then
    if State.gameSessionActive then
      nhsSessionHudUpdate()
      return
    end
    State.gameSessionActive = false
    State.remoteSessionActive = s.remoteSessionActive and true or false
    State.remoteRoundActive = s.remoteRoundActive and true or false
    State.remoteSeekerKey = s.remoteSeekerKey
    State.remoteHouseDisplay = s.remoteHouseDisplay
    State.roundPhase = (type(s.roundPhase) == "string" and s.roundPhase ~= "") and s.roundPhase or "none"
    wipe(State.gameHouseHistory)
    for i, v in ipairs(s.houseHistory or {}) do
      State.gameHouseHistory[i] = v
    end
    wipe(State.gameSeekerHistory)
    for i, v in ipairs(s.seekerHistory or {}) do
      State.gameSeekerHistory[i] = v
    end
    nhsRestoreFoundFromSnapshot(s.foundOrder)
    nhsRestorePastRoundsFromSave(s.pastRounds)
    State.gamePhase = "none"
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    wipe(State.gameHouseRotationUsed)
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.gameLockedSeekerKey = nil
    State.gameLockedSeekerDisplay = nil
    wipe(State.gameRotationUsed)
    nhsSessionHudUpdate()
    return
  end
  if State.gameSessionActive then
    nhsSessionHudUpdate()
    return
  end
  State.gameSessionActive = true
  local ph = s.phase
  if ph == "round_active" or ph == "pick_seeker" or ph == "pick_house" then
    State.gamePhase = ph
  else
    State.gamePhase = "pick_house"
  end
  State.gameHouseCandidateKey = s.houseCandidateKey
  State.gameHouseCandidateDisplay = s.houseCandidateDisplay
  State.gameLockedHouseKey = s.houseLockedKey
  State.gameLockedHouseDisplay = s.houseLockedDisplay
  wipe(State.gameHouseHistory)
  for i, v in ipairs(s.houseHistory or {}) do
    State.gameHouseHistory[i] = v
  end
  wipe(State.gameHouseRotationUsed)
  for _, k in ipairs(s.houseRotationKeys or {}) do
    State.gameHouseRotationUsed[k] = true
  end
  State.gameLockedHouseLiveEntry = nil
  State.gameLockedHouseLiveIndex = nil
  if State.gamePhase == "pick_seeker" and not (State.gameLockedHouseKey or State.gameLockedHouseDisplay) then
    State.gamePhase = "pick_house"
  end
  if State.gamePhase == "round_active" and not (State.gameLockedHouseKey or State.gameLockedHouseDisplay) then
    State.gamePhase = "pick_house"
    State.roundPhase = "none"
  end
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
  nhsRestoreFoundFromSnapshot(s.foundOrder)
  nhsRestorePastRoundsFromSave(s.pastRounds)
  nhsSessionHudUpdate()
end

local function nhsResetGameSession()
  nhsStopPartyCountdown()
  nhsLeaderDemoteSeekerAssistantIfWePromoted()
  State.gameSessionActive = false
  State.gamePhase = "none"
  State.gameHouseCandidateKey = nil
  State.gameHouseCandidateDisplay = nil
  State.gameLockedHouseKey = nil
  State.gameLockedHouseDisplay = nil
  State.gameLockedHouseLiveEntry = nil
  State.gameLockedHouseLiveIndex = nil
  wipe(State.gameHouseHistory)
  wipe(State.gameHouseRotationUsed)
  State.remoteHouseDisplay = nil
  State.gameCandidateKey = nil
  State.gameCandidateDisplay = nil
  State.gameLockedSeekerKey = nil
  State.gameLockedSeekerDisplay = nil
  wipe(State.gameSeekerHistory)
  wipe(State.gameRotationUsed)
  State.roundPhase = "none"
  State.remoteRoundActive = false
  State.remoteSeekerKey = nil
  State.remoteSessionActive = false
  wipe(State.pastRounds)
  clearFound()
  ensureSavedVars()
  NHSV.gameRounds = nil
  nhsSessionHudUpdate()
end

local function nhsRandomSeekerEligible()
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
  return eligible, nil
end

local function nhsPickRandomSeekerMember()
  local elig, err = nhsRandomSeekerEligible()
  if not elig then
    return nil, err
  end
  return elig[math.random(1, #elig)]
end

-- Party/raid chat sync — human-readable lines; only the group leader may send.
local NHS_CHAT_TAG = "[NHS]"
local NHS_MSG_ROUND_START = "[NHS] Round Start: "
local NHS_MSG_SESSION_START = "[NHS] Game session started"
local NHS_MSG_HOUSE = "[NHS] House: "
local NHS_MSG_HIDING = "[NHS] Hiding Starts Now: "
local NHS_MSG_SEEKING = "[NHS] The Seeking Begins!: "
local NHS_MSG_ROUND_OVER = "[NHS] Round is over!"
local NHS_MSG_GAME_OVER = "[NHS] Game Over! Thanks for playing!"
local NHS_MSG_FOUND_PREFIX = "[NHS] Found: "

-- Addon comm: same human-readable NHS line as payload (max 255 bytes). Sync applies via CHAT_MSG_ADDON
-- so we avoid combat "secret string" restrictions on parsing CHAT_MSG_RAID / PARTY text.
local NHS_ADDON_PREFIX = "NeighborhoodHS"

-- PARTY reaches party members in open world and in most instances; RAIDs use RAID. Avoid INSTANCE_CHAT
-- here — in some environments routing differed and broke receive-side channel filters.
local function nhsAddonSyncChatType()
  return IsInRaid() and "RAID" or "PARTY"
end

local function nhsSendAddonSyncPayload(message)
  if not message or message == "" or #message > 255 then
    return
  end
  if not IsInGroup() then
    return
  end
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then
    return
  end
  pcall(C_ChatInfo.SendAddonMessage, NHS_ADDON_PREFIX, message, nhsAddonSyncChatType())
end

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

local function nhsLocalPlayerIsDesignatedSeeker()
  local me = nhsLocalPlayerSortKey()
  if not me then
    return false
  end
  if State.remoteRoundActive and State.remoteSeekerKey and me == State.remoteSeekerKey then
    return true
  end
  if State.gameSessionActive and State.gamePhase == "round_active" and State.gameLockedSeekerKey and me == State.gameLockedSeekerKey then
    return true
  end
  return false
end

local function nhsChatSenderIsDesignatedSeeker(senderName)
  local seeker = nhsGetDesignatedSeekerKey()
  if not seeker or type(senderName) ~= "string" or senderName == "" then
    return false
  end
  return Ambiguate(senderName, "none") == seeker
end

local function nhsPastRoundHiddenSnapshotString(seekerKey)
  seekerKey = seekerKey or nhsGetDesignatedSeekerKey()
  local roster = nhsGetGroupRoster()
  local names = {}
  for _, m in ipairs(roster) do
    if (seekerKey == nil or m.key ~= seekerKey) and not State.foundSet[m.key] then
      names[#names + 1] = Ambiguate(m.key, "short")
    end
  end
  table.sort(names)
  local n = #names
  if n == 0 then
    return "Hidden (0): —"
  end
  return ("Hidden (%d): %s"):format(n, nhsSessionHudCommaList(names))
end

local function nhsPastRoundFoundSnapshotString()
  local names = {}
  for i = 1, #State.foundOrder do
    names[#names + 1] = Ambiguate(State.foundOrder[i], "short")
  end
  table.sort(names)
  local n = #names
  if n == 0 then
    return "Found (0): —"
  end
  return ("Found (%d): %s"):format(n, nhsSessionHudCommaList(names))
end

local function nhsPastRoundSeekerDisplay()
  if State.remoteRoundActive and State.remoteSeekerKey then
    return Ambiguate(State.remoteSeekerKey, "short")
  end
  if State.gameSessionActive and State.gamePhase == "round_active" and State.gameLockedSeekerDisplay then
    return State.gameLockedSeekerDisplay
  end
  return "—"
end

local function nhsPastRoundHouseAndKey()
  if State.gameSessionActive and State.gamePhase == "round_active" then
    return State.gameLockedHouseDisplay, State.gameLockedHouseKey
  end
  if State.remoteRoundActive and State.remoteHouseDisplay and State.remoteHouseDisplay ~= "" then
    return State.remoteHouseDisplay, nil
  end
  return nil, nil
end

-- Call before clearing round state (leader End round, follower Round is over! sync).
local function nhsAppendPastRoundSnapshotIfActiveRound()
  if not nhsSessionHudIsActive() then
    return
  end
  local inLeaderRound = State.gameSessionActive and State.gamePhase == "round_active"
  local inFollowerRound = State.remoteRoundActive
  if not inLeaderRound and not inFollowerRound then
    return
  end
  local houseDisp = nhsPastRoundHouseAndKey()
  if not houseDisp or houseDisp == "" then
    houseDisp = "—"
  end
  local seekerKey = nhsGetDesignatedSeekerKey()
  State.pastRounds[#State.pastRounds + 1] = {
    house = ("House: %s"):format(houseDisp),
    seeker = ("Seeker: %s"):format(nhsPastRoundSeekerDisplay()),
    hidden = nhsPastRoundHiddenSnapshotString(seekerKey),
    found = nhsPastRoundFoundSnapshotString(),
  }
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

-- Party: normal party chat. Raid: raid warning (center screen) so [NHS] sync stands out.
local function nhsGroupSyncChannel()
  return IsInRaid() and "RAID_WARNING" or "PARTY"
end

local function nhsBroadcastLeaderSync(message)
  if not IsInGroup() or not nhsIsRoundLeader() or not message or message == "" then
    return
  end
  if #message > 255 then
    return
  end
  pcall(SendChatMessage, message, nhsGroupSyncChannel())
  nhsSendAddonSyncPayload(message)
end

local function nhsBroadcastHouseLocked(display)
  if type(display) ~= "string" or display == "" then
    return
  end
  local safe = housingSanitizePinShareForChat(display)
  local msg = NHS_MSG_HOUSE .. safe
  if #msg > 250 then
    msg = NHS_MSG_HOUSE .. safe:sub(1, math.max(1, 250 - #NHS_MSG_HOUSE - 1)) .. "…"
  end
  nhsBroadcastLeaderSync(msg)
end

-- Second line after [NHS] House: … — same as Share House Pin (waypoint link, or coordinate text). No addon payload:
-- hyperlink is not an [NHS] line; followers already got the house name from nhsBroadcastHouseLocked.
-- stableKey: same as game house rotKey; used for NHSV.housePinCoords when saved-list pick has no live entry.
local function nhsBroadcastGameplayHousePin(entry, rowIndex, labelText, stableKey)
  if not IsInGroup() or not nhsIsRoundLeader() then
    return
  end
  local mapID, x, y
  if entry ~= nil and rowIndex ~= nil then
    mapID, x, y = housingGetPinCoordsForEntry(entry, rowIndex)
  end
  if (not mapID or mapID == 0 or x == nil or y == nil) and type(stableKey) == "string" and stableKey ~= "" then
    mapID, x, y = nhsGetSavedHousePinCoords(stableKey)
  end
  if not mapID or mapID == 0 or x == nil or y == nil then
    return
  end
  local link = housingBuildBlizzardWaypointHyperlink(mapID, x, y)
  if link and #link <= 255 then
    local ok = pcall(SendChatMessage, link, nhsGroupSyncChannel())
    if ok then
      return
    end
  end
  local fb = housingPinShareCoordinateMessage(mapID, x, y, labelText)
  fb = housingSanitizePinShareForChat(fb)
  if fb ~= "" and #fb <= 255 then
    pcall(SendChatMessage, fb, nhsGroupSyncChannel())
  end
end

local function nhsClearRemoteRoundSync()
  State.remoteRoundActive = false
  State.remoteSeekerKey = nil
  State.roundPhase = "none"
  clearFound()
end

-- Follower: apply seeker + phase from a leader line (late joiners may miss Round Start / session start).
local function nhsRemoteFollowerSyncRoundState(key, phase)
  if type(key) ~= "string" or key == "" then
    return
  end
  key = Ambiguate(key:match("^%s*(.-)%s*$") or key, "none")
  if key == "" then
    return
  end
  State.remoteSessionActive = true
  local newRound = not State.remoteRoundActive or State.remoteSeekerKey ~= key
  if newRound then
    clearFound()
  end
  State.remoteRoundActive = true
  State.remoteSeekerKey = key
  State.roundPhase = phase
end

-- Enter seeker mode: with no session/synced round, allow (preview nameplate/UI options). During a
-- session, only the designated seeker may enter, and only in Hiding or Searching (not pick-seeker,
-- preparing/pending, etc.).
local function nhsMayEnterSeekerMode()
  if not State.gameSessionActive and not State.remoteSessionActive and not State.remoteRoundActive then
    return true
  end
  if (State.gameSessionActive and (State.gamePhase == "pick_house" or State.gamePhase == "pick_seeker"))
    or (State.remoteSessionActive and not State.remoteRoundActive) then
    return false
  end
  if not nhsLocalPlayerIsDesignatedSeeker() then
    return false
  end
  return State.roundPhase == "hiding" or State.roundPhase == "searching"
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
  if not nhsIsRoundLeader() and not nhsGetDesignatedSeekerKey() then
    local senderKey = Ambiguate(senderName, "none")
    if senderKey and senderKey ~= "" then
      for _, m in ipairs(nhsGetGroupRoster()) do
        if m.key == senderKey then
          State.remoteSessionActive = true
          State.remoteRoundActive = true
          State.remoteSeekerKey = senderKey
          State.roundPhase = "searching"
          break
        end
      end
    end
  end
  if not nhsChatSenderIsDesignatedSeeker(senderName) then
    nhsPersistGameSessionToSaved()
    return true
  end
  if State.roundPhase ~= "searching" then
    nhsPersistGameSessionToSaved()
    return true
  end
  local foundKey = Ambiguate(body:match("^%s*(.-)%s*$") or body, "none")
  if not foundKey or foundKey == "" then
    nhsPersistGameSessionToSaved()
    return true
  end
  if State.foundSet[foundKey] then
    nhsPersistGameSessionToSaved()
    return true
  end
  State.foundSet[foundKey] = true
  State.foundOrder[#State.foundOrder + 1] = foundKey
  if UI.RefreshAll then
    UI.RefreshAll()
  elseif UI.RefreshFound then
    UI.RefreshFound()
  end
  nhsPersistGameSessionToSaved()
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
  pcall(SendChatMessage, msg, nhsSeekerFoundSyncChannel())
  nhsSendAddonSyncPayload(msg)
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
      State.remoteSessionActive = true
      State.remoteRoundActive = true
      State.remoteSeekerKey = key
      State.roundPhase = "pending"
      -- Same ordering as the leader's list (one entry per round); display name from sync key.
      State.gameSeekerHistory[#State.gameSeekerHistory + 1] = Ambiguate(key, "short")
    end
  elseif text:match("^%[NHS%]%s*Game session started%s*$") then
    State.remoteSessionActive = true
    wipe(State.gameSeekerHistory)
    wipe(State.gameHouseHistory)
    wipe(State.pastRounds)
    State.remoteHouseDisplay = nil
  elseif text:match("^%[NHS%]%s*House:%s*.+") then
    local housePart = text:match("^%[NHS%]%s*House:%s*(.+)%s*$")
    if housePart then
      State.remoteSessionActive = true
      local disp = housePart:match("^%s*(.-)%s*$") or housePart
      State.remoteHouseDisplay = disp
      -- One entry per leader house confirm (same ordering as Past houses on the leader).
      State.gameHouseHistory[#State.gameHouseHistory + 1] = disp
    end
  elseif text:match("^%[NHS%]%s*Round is over!%s*$") then
    nhsAppendPastRoundSnapshotIfActiveRound()
    nhsClearRemoteRoundSync()
    State.remoteHouseDisplay = nil
    if State.seekerMode and setSeekerMode then
      setSeekerMode(false)
    end
  elseif text:match("^%[NHS%]%s*Game Over! Thanks for playing!%s*$") then
    nhsStopPartyCountdown()
    State.remoteSessionActive = false
    wipe(State.gameSeekerHistory)
    wipe(State.gameHouseHistory)
    wipe(State.pastRounds)
    State.remoteHouseDisplay = nil
    nhsClearRemoteRoundSync()
    if State.seekerMode and setSeekerMode then
      setSeekerMode(false)
    end
  else
    local hideKey = text:match("^%[NHS%]%s*Hiding Starts Now:%s*(.+)%s*$")
    if hideKey then
      nhsRemoteFollowerSyncRoundState(hideKey, "hiding")
    elseif text:match("^%[NHS%]%s*Hiding Starts Now%s*$") then
      State.remoteSessionActive = true
      if State.remoteRoundActive then
        State.roundPhase = "hiding"
      end
    else
      local seekKey = text:match("^%[NHS%]%s*The Seeking Begins!:%s*(.+)%s*$")
      if seekKey then
        nhsRemoteFollowerSyncRoundState(seekKey, "searching")
      elseif text:match("^%[NHS%]%s*The Seeking Begins!%s*$") then
        State.remoteSessionActive = true
        if State.remoteRoundActive then
          State.roundPhase = "searching"
        end
      end
    end
  end
  nhsSeekerAutoModeSyncToPhase()
  if UI.RefreshAll then
    UI.RefreshAll()
  elseif UI.RefreshGameRounds then
    UI.RefreshGameRounds()
  end
  nhsPersistGameSessionToSaved()
  nhsSessionHudUpdate()
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

nhsSeekerAutoModeSyncToPhase = function()
  if State.roundPhase ~= "hiding" and State.roundPhase ~= "searching" then
    return
  end
  if not nhsLocalPlayerIsDesignatedSeeker() or not nhsMayEnterSeekerMode() then
    return
  end
  if State.seekerMode then
    return
  end
  setSeekerMode(true)
  print("|cff88ccff[NHS]|r Seeker mode enabled automatically for this phase.")
end

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
  local me = nhsLocalPlayerSortKey()
  local dsk = nhsGetDesignatedSeekerKey()
  if not me or not dsk or me ~= dsk then
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
  local key = nhsUnitSortKey("target")
  if not key then
    local name = UnitName("target")
    if not name then
      return
    end
    key = Ambiguate(name, "none")
  end
  if not nhsUnitIsInGroupRoster("target") then
    if not quiet then
      print("|cffff8800[NHS]|r Target must be in your party or raid.")
    end
    return
  end
  if key == dsk then
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
  nhsBroadcastSeekerFound(key)
  if UI.RefreshFound then
    UI.RefreshFound()
  end
  nhsPersistGameSessionToSaved()
end

local nhsSeekerAutoMarkFrame = CreateFrame("Frame")
nhsSeekerAutoMarkFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
nhsSeekerAutoMarkFrame:SetScript("OnEvent", function()
  if not State.seekerMode or State.roundPhase ~= "searching" then
    return
  end
  local me = nhsLocalPlayerSortKey()
  local dsk = nhsGetDesignatedSeekerKey()
  if not me or not dsk or me ~= dsk then
    return
  end
  markTargetFound({ quiet = true })
end)

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

  local sessionToggleBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  sessionToggleBtn:SetSize(308, 24)
  sessionToggleBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -63)

  local houseSelectHdr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  houseSelectHdr:SetPoint("TOPLEFT", sessionToggleBtn, "BOTTOMLEFT", 0, -12)
  houseSelectHdr:SetWidth(328)
  houseSelectHdr:SetJustifyH("LEFT")
  houseSelectHdr:SetText("House selection")

  local lockedRoundHouseLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lockedRoundHouseLbl:SetPoint("TOPLEFT", houseSelectHdr, "BOTTOMLEFT", 0, -4)
  lockedRoundHouseLbl:SetWidth(328)
  lockedRoundHouseLbl:SetJustifyH("LEFT")
  lockedRoundHouseLbl:SetText("House for this round: —")

  local candidateGameHouseLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  candidateGameHouseLbl:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -4)
  candidateGameHouseLbl:SetWidth(328)
  candidateGameHouseLbl:SetJustifyH("LEFT")
  candidateGameHouseLbl:SetText("House pick (not confirmed): —")

  local randGameHouseBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  randGameHouseBtn:SetSize(150, 22)
  randGameHouseBtn:SetText("Random house")
  randGameHouseBtn:SetPoint("TOPLEFT", candidateGameHouseLbl, "BOTTOMLEFT", 0, -8)

  local viewGameHousePickBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewGameHousePickBtn:SetSize(150, 22)
  viewGameHousePickBtn:SetText("View house list")
  viewGameHousePickBtn:SetPoint("LEFT", randGameHouseBtn, "RIGHT", 8, 0)

  local confirmGameHouseBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  confirmGameHouseBtn:SetSize(308, 22)
  confirmGameHouseBtn:SetText("Confirm house")
  confirmGameHouseBtn:SetPoint("TOPLEFT", randGameHouseBtn, "BOTTOMLEFT", 0, -8)

  local seekerSelectHdr = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  seekerSelectHdr:SetPoint("TOPLEFT", confirmGameHouseBtn, "BOTTOMLEFT", 0, -12)
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

  local selectSeekerBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  selectSeekerBtn:SetSize(150, 22)
  selectSeekerBtn:SetText("Select seeker")
  selectSeekerBtn:SetPoint("LEFT", randSeekerBtn, "RIGHT", 8, 0)

  local startRoundBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  startRoundBtn:SetSize(308, 22)
  startRoundBtn:SetText("Confirm seeker")
  startRoundBtn:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -8)

  local hideRowLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hideRowLbl:SetPoint("TOPLEFT", startRoundBtn, "BOTTOMLEFT", 0, -12)
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

  local gameplayHouseLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gameplayHouseLbl:SetWidth(328)
  gameplayHouseLbl:SetJustifyH("LEFT")
  gameplayHouseLbl:SetPoint("TOPLEFT", roundPhaseLabel, "BOTTOMLEFT", 0, -6)
  gameplayHouseLbl:SetText("House: —")

  local gameplaySeekerLbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gameplaySeekerLbl:SetWidth(328)
  gameplaySeekerLbl:SetJustifyH("LEFT")
  gameplaySeekerLbl:SetPoint("TOPLEFT", gameplayHouseLbl, "BOTTOMLEFT", 0, -6)
  gameplaySeekerLbl:SetText("Seeker: —")

  local hiddenList = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hiddenList:SetWidth(328)
  hiddenList:SetJustifyH("LEFT")
  hiddenList:SetSpacing(2)
  hiddenList:SetPoint("TOPLEFT", gameplaySeekerLbl, "BOTTOMLEFT", 0, -8)
  hiddenList:SetText("Hidden (0): —")

  local foundList = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  foundList:SetWidth(328)
  foundList:SetJustifyH("LEFT")
  foundList:SetSpacing(2)
  foundList:SetPoint("TOPLEFT", hiddenList, "BOTTOMLEFT", 0, -6)
  foundList:SetText("Found (0): —")

  local viewPastGameHousesBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewPastGameHousesBtn:SetSize(150, 22)
  viewPastGameHousesBtn:SetText("Past houses")
  viewPastGameHousesBtn:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", 0, -8)

  local viewPastSeekersBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewPastSeekersBtn:SetSize(150, 22)
  viewPastSeekersBtn:SetText("Past seekers")
  viewPastSeekersBtn:SetPoint("LEFT", viewPastGameHousesBtn, "RIGHT", 8, 0)

  local pastRoundsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  pastRoundsBtn:SetSize(308, 22)
  pastRoundsBtn:SetText("Past Rounds")
  pastRoundsBtn:Hide()

  viewPastGameHousesBtn:Hide()
  viewPastSeekersBtn:Hide()

  local roundHintText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  roundHintText:SetWidth(328)
  roundHintText:SetJustifyH("LEFT")
  roundHintText:SetSpacing(2)
  roundHintText:Hide()

  local divGameplayHouse = f:CreateTexture(nil, "ARTWORK", nil, 1)
  divGameplayHouse:SetColorTexture(1, 1, 1, 0.12)
  divGameplayHouse:SetSize(312, 1)
  divGameplayHouse:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", -8, -12)

  -- House list / pin / saved size: separate House list window. Bottom row: How to play, View house list, Options.
  local howToPlayBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  howToPlayBtn:SetSize(308, 26)
  howToPlayBtn:SetText("How to play")
  howToPlayBtn:SetPoint("TOPLEFT", divGameplayHouse, "BOTTOMLEFT", 8, -8)

  local viewHouseListBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  viewHouseListBtn:SetSize(308, 26)
  viewHouseListBtn:SetText("View House List")
  viewHouseListBtn:SetPoint("TOPLEFT", howToPlayBtn, "BOTTOMLEFT", 0, -8)

  local optionsBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  optionsBtn:SetSize(308, 26)
  optionsBtn:SetText("Options")
  optionsBtn:SetPoint("TOPLEFT", viewHouseListBtn, "BOTTOMLEFT", 0, -8)

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -6, -6)

  -- Options: seeker UI visibility (party/raid frames, minimap).
  local optf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  optf:SetSize(340, 302)
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

  local cbHouseSaved = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbHouseSaved:SetSize(22, 22)
  cbHouseSaved:SetPoint("TOPLEFT", 16, -112)
  local cbHouseSavedText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbHouseSavedText:SetPoint("LEFT", cbHouseSaved, "RIGHT", 4, 0)
  cbHouseSavedText:SetWidth(292)
  cbHouseSavedText:SetJustifyH("LEFT")
  cbHouseSavedText:SetText("Gameplay: choose house from saved list (off = current neighborhood list)")

  local cbRandPickAnim = CreateFrame("CheckButton", nil, optf, "UICheckButtonTemplate")
  cbRandPickAnim:SetSize(22, 22)
  cbRandPickAnim:SetPoint("TOPLEFT", 16, -136)
  local cbRandPickAnimText = optf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbRandPickAnimText:SetPoint("LEFT", cbRandPickAnim, "RIGHT", 4, 0)
  cbRandPickAnimText:SetWidth(292)
  cbRandPickAnimText:SetJustifyH("LEFT")
  cbRandPickAnimText:SetText("Animate random pick (cycle highlights; off = instant)")

  local optSeekerSep = optf:CreateTexture(nil, "ARTWORK", nil, 1)
  optSeekerSep:SetColorTexture(1, 1, 1, 0.12)
  optSeekerSep:SetSize(300, 1)
  optSeekerSep:SetPoint("TOPLEFT", 20, -160)

  local optSeekerHint = optf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  optSeekerHint:SetPoint("TOPLEFT", optSeekerSep, "BOTTOMLEFT", 0, -10)
  optSeekerHint:SetWidth(300)
  optSeekerHint:SetJustifyH("LEFT")
  optSeekerHint:SetText(
    "Seeker mode is usually enabled automatically during hiding/searching when you are the seeker. Use the button below if you need it manually to view the changes made in the options."
  )

  local optSeekerModeBtn = CreateFrame("Button", nil, optf, "UIPanelButtonTemplate")
  optSeekerModeBtn:SetSize(300, 26)
  optSeekerModeBtn:SetPoint("TOPLEFT", optSeekerHint, "BOTTOMLEFT", 0, -10)
  optSeekerModeBtn:SetText("Enter seeker mode")

  local function syncSeekerModeOptionButton()
    optSeekerModeBtn:SetText(State.seekerMode and "Leave seeker mode" or "Enter seeker mode")
    if State.seekerMode then
      optSeekerModeBtn:SetEnabled(true)
    else
      optSeekerModeBtn:SetEnabled(nhsMayEnterSeekerMode())
    end
  end

  optSeekerModeBtn:SetScript("OnClick", function()
    setSeekerMode(not State.seekerMode)
  end)

  local function syncSeekerUiOptionsFromSaved()
    ensureSavedVars()
    cbParty:SetChecked(NHSV.hideGroupFramesInSeeker ~= false)
    cbMini:SetChecked(NHSV.hideMinimapInSeeker == true)
    cbHouseSaved:SetChecked(NHSV.selectHouseFromSavedList ~= false)
    cbRandPickAnim:SetChecked(NHSV.useRandomPickAnimation ~= false)
    syncSeekerModeOptionButton()
  end

  local function applySeekerUiOptionChange()
    ensureSavedVars()
    NHSV.hideGroupFramesInSeeker = cbParty:GetChecked() and true or false
    NHSV.hideMinimapInSeeker = cbMini:GetChecked() and true or false
    NHSV.selectHouseFromSavedList = cbHouseSaved:GetChecked() and true or false
    NHSV.useRandomPickAnimation = cbRandPickAnim:GetChecked() and true or false
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
  cbHouseSaved:SetScript("OnClick", applySeekerUiOptionChange)
  cbRandPickAnim:SetScript("OnClick", applySeekerUiOptionChange)

  local optCloseBtn = CreateFrame("Button", nil, optf, "UIPanelCloseButton")
  optCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  optCloseBtn:SetScript("OnClick", function()
    optf:Hide()
  end)

  -- Second window: scrollable house list + refresh / random (height from syncHouseListFrameHeight).
  local hf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  hf:SetSize(320, 360)
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
  refreshBtn:SetSize(288, 24)
  refreshBtn:SetText("Refresh houses")
  refreshBtn:SetPoint("TOPLEFT", 16, -62)

  local pinBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
  pinBtn:SetSize(288, 26)
  pinBtn:SetText("House Pin")
  pinBtn:SetPoint("TOPLEFT", refreshBtn, "BOTTOMLEFT", 0, -6)

  local sharePinBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
  sharePinBtn:SetSize(288, 26)
  sharePinBtn:SetText("Share House Pin")
  sharePinBtn:SetPoint("TOPLEFT", pinBtn, "BOTTOMLEFT", 0, -6)

  local housingSelText = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  housingSelText:SetPoint("TOPLEFT", sharePinBtn, "BOTTOMLEFT", 0, -8)
  housingSelText:SetWidth(288)
  housingSelText:SetJustifyH("LEFT")
  housingSelText:SetText("Selected House: (none)")

  local housingSizeText = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  housingSizeText:SetPoint("TOPLEFT", housingSelText, "BOTTOMLEFT", 0, -4)
  housingSizeText:SetWidth(288)
  housingSizeText:SetJustifyH("LEFT")
  housingSizeText:SetText("")

  local houseSizeHelp = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  houseSizeHelp:SetPoint("TOPLEFT", housingSizeText, "BOTTOMLEFT", 0, -8)
  houseSizeHelp:SetWidth(288)
  houseSizeHelp:SetJustifyH("CENTER")
  houseSizeHelp:SetText("Save the size for selected house:")

  local houseSizePresetBtns = {}
  for i = 1, #ROUND_PRESETS do
    local b = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
    b:SetSize(140, 22)
    b._housePresetIdx = i
    houseSizePresetBtns[i] = b
    b:SetText(ROUND_PRESETS[i].label)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(ROUND_PRESETS[i].label, 1, 1, 1)
      GameTooltip:AddLine(
        ("Hide %ds · Search %ds"):format(ROUND_PRESETS[i].hideSec, ROUND_PRESETS[i].searchSec),
        1,
        0.82,
        0,
        true
      )
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
  end
  houseSizePresetBtns[1]:SetPoint("TOPLEFT", houseSizeHelp, "BOTTOMLEFT", 0, -6)
  houseSizePresetBtns[2]:SetPoint("LEFT", houseSizePresetBtns[1], "RIGHT", 8, 0)
  houseSizePresetBtns[3]:SetPoint("TOPLEFT", houseSizePresetBtns[1], "BOTTOMLEFT", 0, -6)
  houseSizePresetBtns[4]:SetPoint("LEFT", houseSizePresetBtns[3], "RIGHT", 8, 0)

  local houseSizeClearBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
  houseSizeClearBtn:SetSize(288, 22)
  houseSizeClearBtn:SetText("Clear saved size (selected house)")
  houseSizeClearBtn:SetPoint("TOPLEFT", houseSizePresetBtns[3], "BOTTOMLEFT", 0, -6)

  local savedListBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
  savedListBtn:SetSize(288, 22)
  savedListBtn:SetPoint("TOPLEFT", houseSizeClearBtn, "BOTTOMLEFT", 0, -4)

  local divHouseListSep = hf:CreateTexture(nil, "ARTWORK", nil, 1)
  divHouseListSep:SetColorTexture(1, 1, 1, 0.12)
  divHouseListSep:SetSize(288, 1)

  local scroll = CreateFrame("ScrollFrame", nil, hf)
  scroll:SetPoint("TOPLEFT", savedListBtn, "BOTTOMLEFT", 0, -8)
  divHouseListSep:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", 0, 0)
  scroll:SetWidth(288)
  scroll:SetHeight(120)
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

  local shf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  shf:SetSize(340, 380)
  shf:SetClampedToScreen(true)
  shf:SetMovable(true)
  shf:EnableMouse(true)
  shf:RegisterForDrag("LeftButton")
  shf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  shf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.savedSizesFramePoint = { p, rp or "UIParent", x, y }
  end)
  shf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  shf:SetBackdropColor(0, 0, 0, 0.88)
  local shfTitle = shf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  shfTitle:SetPoint("TOP", 0, -14)
  shfTitle:SetText("Saved house sizes")
  local shfHelp = shf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  shfHelp:SetPoint("TOPLEFT", 16, -40)
  shfHelp:SetWidth(308)
  shfHelp:SetJustifyH("LEFT")
  shfHelp:SetText("Click a row to remove that saved entry. Sizes persist in SavedVariables (NHSV).")
  local shScroll = CreateFrame("ScrollFrame", nil, shf)
  shScroll:SetPoint("TOPLEFT", 16, -72)
  shScroll:SetSize(308, 290)
  shScroll:EnableMouse(true)
  shScroll:EnableMouseWheel(true)
  shScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * 30)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)
  local shScrollChild = CreateFrame("Frame", nil, shScroll)
  shScrollChild:SetSize(308, 1)
  shScroll:SetScrollChild(shScrollChild)
  local shfCloseBtn = CreateFrame("Button", nil, shf, "UIPanelCloseButton")
  shfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  shfCloseBtn:SetScript("OnClick", function()
    shf:Hide()
  end)
  shf:Hide()

  local ghfp = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  ghfp:SetSize(300, 380)
  ghfp:SetClampedToScreen(true)
  ghfp:SetMovable(true)
  ghfp:EnableMouse(true)
  ghfp:RegisterForDrag("LeftButton")
  ghfp:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  ghfp:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.gameplayHousePickFramePoint = { p, rp or "UIParent", x, y }
  end)
  ghfp:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  ghfp:SetBackdropColor(0, 0, 0, 0.9)
  local ghfpTitle = ghfp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ghfpTitle:SetPoint("TOP", 0, -14)
  ghfpTitle:SetText("Pick a house")
  local ghfpStatus = ghfp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ghfpStatus:SetPoint("TOPLEFT", 16, -40)
  ghfpStatus:SetWidth(268)
  ghfpStatus:SetJustifyH("LEFT")
  ghfpStatus:SetText("—")
  local ghfpScroll = CreateFrame("ScrollFrame", nil, ghfp)
  ghfpScroll:SetPoint("TOPLEFT", 16, -62)
  ghfpScroll:SetSize(268, 300)
  ghfpScroll:EnableMouse(true)
  ghfpScroll:EnableMouseWheel(true)
  ghfpScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * 30)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)
  local ghfpScrollChild = CreateFrame("Frame", nil, ghfpScroll)
  ghfpScrollChild:SetSize(268, 1)
  ghfpScrollChild:EnableMouse(true)
  ghfpScroll:SetScrollChild(ghfpScrollChild)
  local ghfpCloseBtn = CreateFrame("Button", nil, ghfp, "UIPanelCloseButton")
  ghfpCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  ghfpCloseBtn:SetScript("OnClick", function()
    ghfp:Hide()
  end)
  ghfp:Hide()

  local ghpf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  ghpf:SetSize(300, 260)
  ghpf:SetClampedToScreen(true)
  ghpf:SetMovable(true)
  ghpf:EnableMouse(true)
  ghpf:RegisterForDrag("LeftButton")
  ghpf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  ghpf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.gameplayPastHousesFramePoint = { p, rp or "UIParent", x, y }
  end)
  ghpf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  ghpf:SetBackdropColor(0, 0, 0, 0.9)
  local ghpfTitle = ghpf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ghpfTitle:SetPoint("TOP", 0, -14)
  ghpfTitle:SetText("Houses this session")
  local ghpastScroll = CreateFrame("ScrollFrame", nil, ghpf)
  ghpastScroll:SetPoint("TOPLEFT", 16, -42)
  ghpastScroll:SetSize(268, 200)
  ghpastScroll:EnableMouse(true)
  ghpastScroll:EnableMouseWheel(true)
  ghpastScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * 30)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)
  local ghpastScrollChild = CreateFrame("Frame", nil, ghpastScroll)
  ghpastScrollChild:SetSize(268, 1)
  ghpastScroll:SetScrollChild(ghpastScrollChild)
  local ghpastBody = ghpastScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  ghpastBody:SetPoint("TOPLEFT", ghpastScrollChild, "TOPLEFT", 0, 0)
  ghpastBody:SetWidth(258)
  ghpastBody:SetJustifyH("LEFT")
  ghpastBody:SetJustifyV("TOP")
  local ghpfCloseBtn = CreateFrame("Button", nil, ghpf, "UIPanelCloseButton")
  ghpfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  ghpfCloseBtn:SetScript("OnClick", function()
    ghpf:Hide()
  end)
  ghpf:Hide()

  local pastRoundsFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  pastRoundsFrame:SetSize(320, 380)
  pastRoundsFrame:SetClampedToScreen(true)
  pastRoundsFrame:SetMovable(true)
  pastRoundsFrame:EnableMouse(true)
  pastRoundsFrame:RegisterForDrag("LeftButton")
  pastRoundsFrame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  pastRoundsFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.pastRoundsFramePoint = { p, rp or "UIParent", x, y }
  end)
  pastRoundsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  pastRoundsFrame:SetBackdropColor(0, 0, 0, 0.9)
  local pastRoundsTitle = pastRoundsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  pastRoundsTitle:SetPoint("TOP", 0, -14)
  pastRoundsTitle:SetText("Past rounds")
  local pastRoundsScroll = CreateFrame("ScrollFrame", nil, pastRoundsFrame)
  pastRoundsScroll:SetPoint("TOPLEFT", 16, -42)
  pastRoundsScroll:SetSize(288, 310)
  pastRoundsScroll:EnableMouse(true)
  pastRoundsScroll:EnableMouseWheel(true)
  pastRoundsScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * 30)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)
  local pastRoundsScrollChild = CreateFrame("Frame", nil, pastRoundsScroll)
  pastRoundsScrollChild:SetSize(288, 1)
  pastRoundsScroll:SetScrollChild(pastRoundsScrollChild)
  local pastRoundsBody = pastRoundsScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  pastRoundsBody:SetPoint("TOPLEFT", pastRoundsScrollChild, "TOPLEFT", 0, 0)
  pastRoundsBody:SetWidth(278)
  pastRoundsBody:SetJustifyH("LEFT")
  pastRoundsBody:SetJustifyV("TOP")
  pastRoundsBody:SetSpacing(4)
  local pastRoundsBlockTexts = {}
  local pastRoundsDividers = {}
  local pastRoundsCloseBtn = CreateFrame("Button", nil, pastRoundsFrame, "UIPanelCloseButton")
  pastRoundsCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  pastRoundsCloseBtn:SetScript("OnClick", function()
    pastRoundsFrame:Hide()
  end)
  pastRoundsFrame:Hide()

  local NHS_RANDOM_GRID_COLS = 4
  local NHS_RANDOM_GRID_PAD = 5
  local NHS_RANDOM_GRID_CELL_H = 28
  local NHS_RANDOM_FRAME_W = 464
  local NHS_RANDOM_FRAME_H = 486
  local NHS_RANDOM_SCROLL_W = NHS_RANDOM_FRAME_W - 32
  -- Seconds per advance during fast_laps / fast_chase (fixed; not scaled by list size).
  local NHS_GRID_FAST_STEP_SEC = 0.05
  -- Slow phase: first slow tick and ramp (each step multiplies delay until cap).
  local NHS_GRID_SLOW_START_MULT = 1.62
  local NHS_GRID_SLOW_STEP_GROW = 1.1
  local NHS_GRID_SLOW_STEP_MIN_SEC = 0.056
  local NHS_GRID_SLOW_STEP_CAP_SEC = 0.58

  local randomPickFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  randomPickFrame:SetSize(NHS_RANDOM_FRAME_W, NHS_RANDOM_FRAME_H)
  randomPickFrame:SetClampedToScreen(true)
  randomPickFrame:SetMovable(true)
  randomPickFrame:EnableMouse(true)
  randomPickFrame:RegisterForDrag("LeftButton")
  randomPickFrame:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  randomPickFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.randomPickFramePoint = { p, rp or "UIParent", x, y }
  end)
  randomPickFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  randomPickFrame:SetBackdropColor(0, 0, 0, 0.92)
  local randomPickTitle = randomPickFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  randomPickTitle:SetPoint("TOP", 0, -14)
  randomPickTitle:SetText("Random selection")
  local randomPickSubtitle = randomPickFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  randomPickSubtitle:SetPoint("TOP", randomPickTitle, "BOTTOM", 0, -4)
  randomPickSubtitle:SetWidth(NHS_RANDOM_SCROLL_W - 8)
  randomPickSubtitle:SetJustifyH("CENTER")
  randomPickSubtitle:SetText("—")

  local randomPickStatus = randomPickFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  randomPickStatus:SetPoint("TOP", randomPickSubtitle, "BOTTOM", 0, -8)
  randomPickStatus:SetWidth(NHS_RANDOM_SCROLL_W - 8)
  randomPickStatus:SetJustifyH("CENTER")
  randomPickStatus:SetText("")

  local randomGridScroll = CreateFrame("ScrollFrame", nil, randomPickFrame)
  randomGridScroll:SetPoint("TOP", randomPickStatus, "BOTTOM", 0, -8)
  randomGridScroll:SetPoint("LEFT", randomPickFrame, "LEFT", 16, 0)
  randomGridScroll:SetPoint("RIGHT", randomPickFrame, "RIGHT", -16, 0)
  randomGridScroll:SetPoint("BOTTOM", randomPickFrame, "BOTTOM", 0, 16)
  randomGridScroll:EnableMouse(true)
  randomGridScroll:EnableMouseWheel(true)
  randomGridScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * 34)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)

  local randomGridScrollChild = CreateFrame("Frame", nil, randomGridScroll)
  randomGridScrollChild:SetSize(NHS_RANDOM_SCROLL_W, 1)
  randomGridScroll:SetScrollChild(randomGridScrollChild)

  local randomPickCells = {}

  local function nhsRandomPickEnsureCells(need)
    while #randomPickCells < need do
      local cell = CreateFrame("Frame", nil, randomGridScrollChild)
      cell:SetSize(100, NHS_RANDOM_GRID_CELL_H)
      local bg = cell:CreateTexture(nil, "BACKGROUND")
      bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg:SetAllPoints()
      local fs = cell:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      fs:SetPoint("TOPLEFT", 6, -6)
      fs:SetPoint("BOTTOMRIGHT", -6, 6)
      fs:SetJustifyH("CENTER")
      fs:SetJustifyV("MIDDLE")
      cell:Hide()
      randomPickCells[#randomPickCells + 1] = { frame = cell, bg = bg, fs = fs }
    end
  end

  local randomPickFrameCloseX = CreateFrame("Button", nil, randomPickFrame, "UIPanelCloseButton")
  randomPickFrameCloseX:SetPoint("TOPRIGHT", -6, -6)
  randomPickFrameCloseX:SetScript("OnClick", function()
    if randomPickFrame.nhsPickAnimRunning then
      return
    end
    randomPickFrame:Hide()
  end)

  randomPickFrame:SetScript("OnHide", function(self)
    self:SetScript("OnUpdate", nil)
    self.nhsPickAnimRunning = false
    self.nhsPickAnimPhase = nil
    self.nhsPickAnimOnPicked = nil
    self.nhsPickAnimContext = nil
    self.nhsGridHighlight = 1
    self.nhsGridAnimPhase = nil
    self.nhsGridFastStepsLeft = nil
    self.nhsGridSlowMovesLeft = nil
    self.nhsGridSlowInterval = nil
    self.nhsGridAccum = 0
    randomPickFrameCloseX:Enable()
  end)

  randomPickFrame:Hide()

  local gsfp = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  gsfp:SetSize(300, 380)
  gsfp:SetClampedToScreen(true)
  gsfp:SetMovable(true)
  gsfp:EnableMouse(true)
  gsfp:RegisterForDrag("LeftButton")
  gsfp:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  gsfp:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.gameplaySeekerPickFramePoint = { p, rp or "UIParent", x, y }
  end)
  gsfp:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  gsfp:SetBackdropColor(0, 0, 0, 0.9)
  local gsfpTitle = gsfp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  gsfpTitle:SetPoint("TOP", 0, -14)
  gsfpTitle:SetText("Select seeker")
  local gsfpStatus = gsfp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gsfpStatus:SetPoint("TOPLEFT", 16, -40)
  gsfpStatus:SetWidth(268)
  gsfpStatus:SetJustifyH("LEFT")
  gsfpStatus:SetText("—")
  local gsfpScroll = CreateFrame("ScrollFrame", nil, gsfp)
  gsfpScroll:SetPoint("TOPLEFT", 16, -62)
  gsfpScroll:SetSize(268, 258)
  gsfpScroll:EnableMouse(true)
  gsfpScroll:EnableMouseWheel(true)
  gsfpScroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(self:GetVerticalScrollRange(), 0)
    local next = self:GetVerticalScroll() - (delta * 30)
    if next < 0 then
      next = 0
    elseif next > max then
      next = max
    end
    self:SetVerticalScroll(next)
  end)
  local gsfpScrollChild = CreateFrame("Frame", nil, gsfpScroll)
  gsfpScrollChild:SetSize(268, 1)
  gsfpScrollChild:EnableMouse(true)
  gsfpScroll:SetScrollChild(gsfpScrollChild)
  local gsfpAnimRandomSeekerBtn = CreateFrame("Button", nil, gsfp, "UIPanelButtonTemplate")
  gsfpAnimRandomSeekerBtn:SetSize(268, 24)
  gsfpAnimRandomSeekerBtn:SetText("Random seeker")
  gsfpAnimRandomSeekerBtn:SetPoint("BOTTOM", gsfp, "BOTTOM", 0, 12)
  gsfpAnimRandomSeekerBtn:Hide()
  local gsfpCloseBtn = CreateFrame("Button", nil, gsfp, "UIPanelCloseButton")
  gsfpCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  gsfpCloseBtn:SetScript("OnClick", function()
    gsfp:Hide()
  end)
  gsfp:Hide()

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
    shf:Hide()
    ghfp:Hide()
    ghpf:Hide()
    pastRoundsFrame:Hide()
    randomPickFrame:Hide()
    gsfp:Hide()
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
  local savedHouseRowBtns = {}
  local gameplayPickRowBtns = {}
  local gameplaySeekerPickRowBtns = {}

  local function refreshGameplayPastHousesPanel()
    local t = #State.gameHouseHistory == 0 and "No houses chosen this session yet."
      or table.concat(State.gameHouseHistory, "\n")
    ghpastBody:SetText(t)
    ghpastScrollChild:SetHeight(math.max(ghpastBody:GetStringHeight() + 8, 1))
    ghpastScroll:SetVerticalScroll(0)
  end

  local function refreshPastRoundsPanel()
    local n = #State.pastRounds
    for _, fs in ipairs(pastRoundsBlockTexts) do
      fs:Hide()
    end
    for _, div in ipairs(pastRoundsDividers) do
      div:Hide()
    end
    if n == 0 then
      pastRoundsBody:Show()
      pastRoundsBody:ClearAllPoints()
      pastRoundsBody:SetPoint("TOPLEFT", pastRoundsScrollChild, "TOPLEFT", 0, 0)
      pastRoundsBody:SetText("No completed rounds recorded this session yet.")
      pastRoundsScrollChild:SetHeight(math.max(pastRoundsBody:GetStringHeight() + 8, 1))
      pastRoundsScroll:SetVerticalScroll(0)
      return
    end
    pastRoundsBody:Hide()
    local gap = 12
    local ruleW = 278
    local y = 0
    for i = 1, n do
      local r = State.pastRounds[i]
      if i > 1 then
        y = y + gap
        local div = pastRoundsDividers[i - 1]
        if not div then
          div = CreateFrame("Frame", nil, pastRoundsScrollChild)
          div:SetSize(ruleW, 1)
          local tex = div:CreateTexture(nil, "ARTWORK")
          tex:SetAllPoints()
          tex:SetColorTexture(1, 1, 1, 0.12)
          pastRoundsDividers[i - 1] = div
        end
        div:SetParent(pastRoundsScrollChild)
        div:ClearAllPoints()
        div:SetPoint("TOPLEFT", pastRoundsScrollChild, "TOPLEFT", 0, -y)
        div:Show()
        y = y + 1 + gap
      end
      local fs = pastRoundsBlockTexts[i]
      if not fs then
        fs = pastRoundsScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetWidth(278)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetSpacing(4)
        pastRoundsBlockTexts[i] = fs
      end
      fs:SetParent(pastRoundsScrollChild)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", pastRoundsScrollChild, "TOPLEFT", 0, -y)
      fs:SetText(
        table.concat({
          r.house or "",
          r.seeker or "",
          r.hidden or "",
          r.found or "",
        }, "\n")
      )
      fs:Show()
      y = y + fs:GetStringHeight()
    end
    pastRoundsScrollChild:SetHeight(math.max(y + 8, 1))
    pastRoundsScroll:SetVerticalScroll(0)
  end

  local function refreshGameplayHousePickList()
    ensureSavedVars()
    local pool = nhsBuildGameplayHousePickPool(housesCache)
    ghfpTitle:SetText(
      NHSV.selectHouseFromSavedList ~= false and "Pick a house (saved list)" or "Pick a house (current list)"
    )
    ghfpStatus:SetText(("Tap a row to choose (%d available)."):format(#pool))
    for i = 1, #gameplayPickRowBtns do
      gameplayPickRowBtns[i]:Hide()
    end
    local y = 0
    for i, row in ipairs(pool) do
      local btn = gameplayPickRowBtns[i]
      if not btn then
        btn = CreateFrame("Button", nil, ghfpScrollChild, "UIPanelButtonTemplate")
        gameplayPickRowBtns[i] = btn
      end
      btn:SetSize(252, 22)
      btn:SetText(row.display)
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", 8, -y)
      btn._gpRow = row
      btn:SetScript("OnClick", function(self)
        local r = self._gpRow
        if not r then
          return
        end
        State.gameHouseCandidateKey = r.rotKey
        State.gameHouseCandidateDisplay = r.display
        State.gameLockedHouseLiveEntry = r.liveEntry
        State.gameLockedHouseLiveIndex = r.liveIndex
        ghfp:Hide()
        nhsPersistGameSessionToSaved()
        if UI.RefreshGameRounds then
          UI.RefreshGameRounds()
        end
        nhsSessionHudUpdate()
        print(
          ("|cff88ccff[NHS]|r Gameplay house: |cffffffff%s|r — Confirm house when ready."):format(r.display)
        )
      end)
      btn:Show()
      y = y + 24
    end
    ghfpScrollChild:SetHeight(math.max(y + 8, 1))
    ghfpScroll:SetVerticalScroll(0)
  end

  local function refreshGroupSeekerPickList()
    local roster = nhsGetGroupRoster()
    gsfpTitle:SetText("Select seeker")
    gsfpStatus:SetText(("Tap a row to choose (%d in group)."):format(#roster))
    for i = 1, #gameplaySeekerPickRowBtns do
      gameplaySeekerPickRowBtns[i]:Hide()
    end
    local y = 0
    for i, m in ipairs(roster) do
      local btn = gameplaySeekerPickRowBtns[i]
      if not btn then
        btn = CreateFrame("Button", nil, gsfpScrollChild, "UIPanelButtonTemplate")
        gameplaySeekerPickRowBtns[i] = btn
      end
      btn:SetSize(252, 22)
      btn:SetText(m.display)
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", 8, -y)
      btn._gspMember = m
      btn:SetScript("OnClick", function(self)
        local mem = self._gspMember
        if not mem then
          return
        end
        State.gameCandidateKey = mem.key
        State.gameCandidateDisplay = mem.display
        gsfp:Hide()
        nhsPersistGameSessionToSaved()
        if UI.RefreshGameRounds then
          UI.RefreshGameRounds()
        end
        nhsSessionHudUpdate()
        print(
          ("|cff88ccff[NHS]|r Seeker pick: |cffffffff%s|r — Confirm seeker to lock in (or pick again)."):format(
            mem.display
          )
        )
      end)
      btn:Show()
      y = y + 24
    end
    gsfpScrollChild:SetHeight(math.max(y + 8, 1))
    gsfpScroll:SetVerticalScroll(0)
    gsfpAnimRandomSeekerBtn:SetShown(#roster > 0)
    gsfpAnimRandomSeekerBtn:SetEnabled(nhsMayUseLeaderGameActions() and #roster > 0)
  end

  local function updateMainHouseSizeLine()
    local idx = nhsGetSavedPresetIndexForEntry(State.selectedEntry)
    if idx then
      local pr = ROUND_PRESETS[idx]
      housingSizeText:SetText(("Saved size: %s"):format(pr.label))
    else
      housingSizeText:SetText("")
    end
  end

  local function updateHouseListButtonLabels()
    for i, entry in ipairs(housesCache) do
      local btn = houseButtons[i]
      if btn and btn:IsShown() then
        btn:SetText(labelFromEntry(entry, i) .. nhsSavedSizeSuffixForEntry(entry))
      end
    end
  end

  local function syncHouseSizePickerEnabled()
    local canKey = State.selectedEntry ~= nil and nhsHouseStableKeyFromEntry(State.selectedEntry) ~= nil
    for _, b in ipairs(houseSizePresetBtns) do
      b:SetEnabled(canKey)
    end
    houseSizeClearBtn:SetEnabled(canKey and nhsGetSavedPresetIndexForEntry(State.selectedEntry) ~= nil)
    savedListBtn:SetText(("Saved sizes… (%d)"):format(nhsCountSavedHouseSizes()))
  end

  local function refreshSavedHousesPanel()
    ensureSavedVars()
    local rows = {}
    for key, idx in pairs(NHSV.houseSizes) do
      idx = tonumber(idx)
      if idx and idx >= 1 and idx <= #ROUND_PRESETS then
        rows[#rows + 1] = { key = key, idx = idx, label = NHSV.houseLabels[key] or key }
      end
    end
    table.sort(rows, function(a, b)
      return tostring(a.label):lower() < tostring(b.label):lower()
    end)
    for i = 1, #savedHouseRowBtns do
      savedHouseRowBtns[i]:Hide()
    end
    local y = 0
    for i, row in ipairs(rows) do
      local btn = savedHouseRowBtns[i]
      if not btn then
        btn = CreateFrame("Button", nil, shScrollChild, "UIPanelButtonTemplate")
        btn:SetSize(292, 22)
        btn:SetScript("OnClick", function(self)
          local k = self._rowKey
          if not k then
            return
          end
          ensureSavedVars()
          NHSV.houseSizes[k] = nil
          NHSV.houseLabels[k] = nil
          NHSV.housePinCoords[k] = nil
          refreshSavedHousesPanel()
          updateHouseListButtonLabels()
          updateMainHouseSizeLine()
          syncHouseSizePickerEnabled()
          if UI.RefreshGameRounds then
            UI.RefreshGameRounds()
          end
        end)
        savedHouseRowBtns[i] = btn
      end
      btn._rowKey = row.key
      btn:SetText(("%s — %s (remove)"):format(row.label, ROUND_PRESETS[row.idx].label))
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", 8, -y)
      btn:Show()
      y = y + 24
    end
    shScrollChild:SetHeight(math.max(y + 8, 1))
    shScroll:SetVerticalScroll(0)
  end

  -- Match row spacing in refreshHouseList (y += 24 per button).
  local HOUSE_LIST_ROW_H = 24
  local HOUSE_LIST_SCROLL_MIN = 52
  local HOUSE_LIST_SCROLL_MAX = 280
  local HOUSE_LIST_BOTTOM_PAD = 16

  local function syncHouseListFrameHeight()
    if not hf or not scroll then
      return
    end
    local n = #housesCache
    local listWant = math.max(n, 1) * HOUSE_LIST_ROW_H
    local scrollH = math.min(HOUSE_LIST_SCROLL_MAX, math.max(HOUSE_LIST_SCROLL_MIN, listWant))
    scroll:SetHeight(scrollH)
    local hfTop = hf:GetTop()
    local scrollTop = scroll:GetTop()
    if not hfTop or not scrollTop then
      return
    end
    local chromeAboveScroll = hfTop - scrollTop
    hf:SetHeight(chromeAboveScroll + scrollH + HOUSE_LIST_BOTTOM_PAD)
  end

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
    updateMainHouseSizeLine()
    syncHouseSizePickerEnabled()
    updateHouseListButtonLabels()
    if UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    end
    nhsSessionHudUpdate()
  end

  local function refreshHouseList()
    local list = fetchVisitableHouses()
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
      btn:SetText(labelFromEntry(entry, i) .. nhsSavedSizeSuffixForEntry(entry))
      btn:SetPoint("TOPLEFT", 10, -y)
      btn:Show()
      y = y + 24
    end
    child:SetHeight(math.max(y, 1))
    scroll:SetVerticalScroll(0)
    listStatus:SetText(("Visitable houses: %d"):format(#housesCache))
    syncHouseSizePickerEnabled()
    syncHouseListFrameHeight()
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
    hiddenList:SetText(nhsSessionHudHiddenFormatted())
    foundList:SetText(nhsSessionHudFoundFormatted())
  end

  local function syncGameplayHouseSeekerLabels()
    gameplayHouseLbl:SetText("House: " .. nhsSessionHudHouseText())
    gameplaySeekerLbl:SetText("Seeker: " .. nhsSessionHudSeekerText())
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
    if State.gameSessionActive and State.gamePhase == "pick_house" then
      return "Phase: House selection"
    end
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
    local vhlBottom = viewHouseListBtn and viewHouseListBtn:GetBottom()
    if vhlBottom then
      lowest = math.min(lowest, vhlBottom)
    end
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
    sessionToggleBtn:SetShown(show)
    houseSelectHdr:SetShown(show)
    lockedRoundHouseLbl:SetShown(show)
    candidateGameHouseLbl:SetShown(show)
    randGameHouseBtn:SetShown(show)
    viewGameHousePickBtn:SetShown(show)
    confirmGameHouseBtn:SetShown(show)
    seekerSelectHdr:SetShown(show)
    candidateSeekerLbl:SetShown(show)
    randSeekerBtn:SetShown(show)
    selectSeekerBtn:SetShown(show)
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
    gameplayHouseLbl:ClearAllPoints()
    gameplayHouseLbl:SetPoint("TOPLEFT", roundPhaseLabel, "BOTTOMLEFT", 0, -6)
    gameplaySeekerLbl:ClearAllPoints()
    gameplaySeekerLbl:SetPoint("TOPLEFT", gameplayHouseLbl, "BOTTOMLEFT", 0, -6)
    hiddenList:ClearAllPoints()
    hiddenList:SetPoint("TOPLEFT", gameplaySeekerLbl, "BOTTOMLEFT", 0, -8)
    foundList:ClearAllPoints()
    foundList:SetPoint("TOPLEFT", hiddenList, "BOTTOMLEFT", 0, -6)
  end

  -- Past session lists + divider below phase / house / seeker / hidden / found (any phase with an active session HUD).
  local function layoutGameplayDetailsFooter(showPastHistoryRow)
    viewPastGameHousesBtn:ClearAllPoints()
    viewPastSeekersBtn:ClearAllPoints()
    pastRoundsBtn:ClearAllPoints()
    divGameplayHouse:ClearAllPoints()
    if showPastHistoryRow then
      viewPastGameHousesBtn:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", 0, -8)
      viewPastSeekersBtn:SetPoint("LEFT", viewPastGameHousesBtn, "RIGHT", 8, 0)
      pastRoundsBtn:SetPoint("TOPLEFT", viewPastGameHousesBtn, "BOTTOMLEFT", 0, -8)
      viewPastGameHousesBtn:Show()
      viewPastSeekersBtn:Show()
      pastRoundsBtn:Show()
      divGameplayHouse:SetPoint("TOPLEFT", pastRoundsBtn, "BOTTOMLEFT", -8, -10)
    else
      viewPastGameHousesBtn:Hide()
      viewPastSeekersBtn:Hide()
      pastRoundsBtn:Hide()
      divGameplayHouse:SetPoint("TOPLEFT", foundList, "BOTTOMLEFT", -8, -12)
    end
  end

  local function nhsSyncRandomPickFramePhase(sess, pickHouse, pickSeeker, useLeaderUi)
    if not randomPickFrame:IsShown() then
      return
    end
    if not useLeaderUi or not sess then
      randomPickFrame:Hide()
      return
    end
    local ctx = randomPickFrame.nhsPickAnimContext
    if ctx == "house" and not pickHouse then
      randomPickFrame:Hide()
    elseif ctx == "seeker" and not pickSeeker then
      randomPickFrame:Hide()
    end
  end

  local function refreshGameRounds()
    local leader = nhsIsRoundLeader()
    local ingroup = IsInGroup()
    local useLeaderUi = not ingroup or leader
    local mayAct = nhsMayUseLeaderGameActions()
    local sess = State.gameSessionActive
    local pickHouse = sess and State.gamePhase == "pick_house"
    local pickSeeker = sess and State.gamePhase == "pick_seeker"
    local inRound = sess and State.gamePhase == "round_active"
    local showOrphanEnd = sess and ingroup and not leader

    nhsSyncRandomPickFramePhase(sess, pickHouse, pickSeeker, useLeaderUi)

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
        layoutGameplayDetailsFooter(nhsSessionHudIsActive())
        roundPhaseLabel:Hide()
        syncGameplayHouseSeekerLabels()
        roundHintText:ClearAllPoints()
        roundHintText:SetPoint("TOPLEFT", divGameplayHouse, "BOTTOMLEFT", 8, -10)
        roundHintText:SetWidth(328)
        roundHintText:Show()
        roundHintText:SetText(
          "Game control is hidden until you are party/raid leader again. "
            .. "Use End game session below to clear saved state."
        )
        viewPastGameHousesBtn:SetEnabled(#State.gameHouseHistory > 0)
        viewPastSeekersBtn:SetEnabled(#State.gameSeekerHistory > 0)
        pastRoundsBtn:SetEnabled(#State.pastRounds > 0)
        refreshFoundList()
        syncSeekerModeOptionButton()
        syncMainFrameHeight()
        return
      end
      if ingroup and State.remoteRoundActive then
        roundsHint:SetText("Party / raid sync (leader chat)")
        orphanSessionBtn:Hide()
        layoutGameplayBlock(f, 16, -40, false)
        layoutGameplayDetailsFooter(nhsSessionHudIsActive())
        roundPhaseLabel:SetWidth(328)
        roundPhaseLabel:SetText(("Phase: %s"):format(roundPhaseDescription()))
        roundPhaseLabel:Show()
        syncGameplayHouseSeekerLabels()
        roundHintText:ClearAllPoints()
        roundHintText:SetPoint("TOPLEFT", divGameplayHouse, "BOTTOMLEFT", 8, -10)
        roundHintText:SetWidth(328)
        roundHintText:Show()
        if State.roundPhase == "searching" then
          roundHintText:SetText(
            "If you are the seeker, use Options → Enter seeker mode if needed, then target party/raid members to mark them found."
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
        viewPastGameHousesBtn:SetEnabled(#State.gameHouseHistory > 0)
        viewPastSeekersBtn:SetEnabled(#State.gameSeekerHistory > 0)
        pastRoundsBtn:SetEnabled(#State.pastRounds > 0)
        refreshFoundList()
        syncSeekerModeOptionButton()
        syncMainFrameHeight()
        return
      end
      orphanSessionBtn:Hide()
      roundsHint:SetText(
        not ingroup and "Join a party or raid to sync game rounds with the leader."
          or "Only the party/raid leader can run game control."
      )
      roundsHint:Show()
      layoutGameplayBlock(f, 16, -64, false)
      layoutGameplayDetailsFooter(nhsSessionHudIsActive())
      roundPhaseLabel:Hide()
      syncGameplayHouseSeekerLabels()
      viewPastGameHousesBtn:SetEnabled(#State.gameHouseHistory > 0)
      viewPastSeekersBtn:SetEnabled(#State.gameSeekerHistory > 0)
      pastRoundsBtn:SetEnabled(#State.pastRounds > 0)
      refreshFoundList()
      syncSeekerModeOptionButton()
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

    if State.gameHouseCandidateDisplay then
      candidateGameHouseLbl:SetText(
        ("House pick (not confirmed): %s"):format(State.gameHouseCandidateDisplay)
      )
    else
      candidateGameHouseLbl:SetText("House pick (not confirmed): —")
    end
    if State.gameLockedHouseDisplay then
      lockedRoundHouseLbl:SetText(
        ("House for this round: %s"):format(State.gameLockedHouseDisplay)
      )
    else
      lockedRoundHouseLbl:SetText("House for this round: —")
    end

    if not sess then
      houseSelectHdr:Hide()
      lockedRoundHouseLbl:Hide()
      candidateGameHouseLbl:Hide()
      randGameHouseBtn:Hide()
      viewGameHousePickBtn:Hide()
      confirmGameHouseBtn:Hide()
      seekerSelectHdr:Hide()
      candidateSeekerLbl:Hide()
      randSeekerBtn:Hide()
      selectSeekerBtn:Hide()
      startRoundBtn:Hide()
    else
      houseSelectHdr:Show()
      local showHousePick = pickHouse
      candidateGameHouseLbl:SetShown(showHousePick)
      randGameHouseBtn:SetShown(showHousePick)
      viewGameHousePickBtn:SetShown(showHousePick)
      confirmGameHouseBtn:SetShown(showHousePick)
      lockedRoundHouseLbl:SetShown(pickSeeker or inRound)
      seekerSelectHdr:SetShown(pickSeeker)
      candidateSeekerLbl:SetShown(pickSeeker)
      randSeekerBtn:SetShown(pickSeeker)
      selectSeekerBtn:SetShown(pickSeeker)
      startRoundBtn:SetShown(pickSeeker)
    end

    local showRoundTimers = sess and inRound
    hideRowLbl:SetShown(showRoundTimers)
    searchRowLbl:SetShown(showRoundTimers)
    ctrlSectionSpacer:SetShown(showRoundTimers)
    endRoundBtn:SetShown(showRoundTimers)
    for _, b in ipairs(hidePresetBtns) do
      b:SetShown(showRoundTimers)
    end
    for _, b in ipairs(searchPresetBtns) do
      b:SetShown(showRoundTimers)
    end

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
      randGameHouseBtn:SetEnabled(false)
      viewGameHousePickBtn:SetEnabled(false)
      confirmGameHouseBtn:SetEnabled(false)
      randSeekerBtn:SetEnabled(false)
      selectSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      endRoundBtn:SetEnabled(false)
    elseif pickHouse then
      randGameHouseBtn:SetEnabled(mayAct)
      viewGameHousePickBtn:SetEnabled(mayAct)
      confirmGameHouseBtn:SetEnabled(mayAct and State.gameHouseCandidateKey ~= nil)
      randSeekerBtn:SetEnabled(false)
      selectSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      endRoundBtn:SetEnabled(false)
    elseif pickSeeker then
      randGameHouseBtn:SetEnabled(false)
      viewGameHousePickBtn:SetEnabled(false)
      confirmGameHouseBtn:SetEnabled(false)
      randSeekerBtn:SetEnabled(mayAct)
      selectSeekerBtn:SetEnabled(mayAct)
      startRoundBtn:SetEnabled(
        mayAct and State.gameCandidateKey ~= nil and State.gameLockedHouseDisplay ~= nil
      )
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      endRoundBtn:SetEnabled(false)
    elseif inRound then
      randGameHouseBtn:SetEnabled(false)
      viewGameHousePickBtn:SetEnabled(false)
      confirmGameHouseBtn:SetEnabled(false)
      randSeekerBtn:SetEnabled(false)
      selectSeekerBtn:SetEnabled(false)
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
      randGameHouseBtn:SetEnabled(false)
      viewGameHousePickBtn:SetEnabled(false)
      confirmGameHouseBtn:SetEnabled(false)
      randSeekerBtn:SetEnabled(false)
      selectSeekerBtn:SetEnabled(false)
      startRoundBtn:SetEnabled(false)
      for _, b in ipairs(hidePresetBtns) do
        b:SetEnabled(false)
      end
      for _, b in ipairs(searchPresetBtns) do
        b:SetEnabled(false)
      end
      endRoundBtn:SetEnabled(false)
    end

    if sess then
      if pickHouse then
        seekerSelectHdr:ClearAllPoints()
        seekerSelectHdr:SetPoint("TOPLEFT", confirmGameHouseBtn, "BOTTOMLEFT", 0, -12)
      else
        seekerSelectHdr:ClearAllPoints()
        seekerSelectHdr:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -12)
      end
      candidateSeekerLbl:ClearAllPoints()
      candidateSeekerLbl:SetPoint("TOPLEFT", seekerSelectHdr, "BOTTOMLEFT", 0, -4)
      randSeekerBtn:ClearAllPoints()
      randSeekerBtn:SetPoint("TOPLEFT", candidateSeekerLbl, "BOTTOMLEFT", 0, -8)
      selectSeekerBtn:ClearAllPoints()
      selectSeekerBtn:SetPoint("LEFT", randSeekerBtn, "RIGHT", 8, 0)
      startRoundBtn:ClearAllPoints()
      startRoundBtn:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -8)
      if inRound then
        hideRowLbl:ClearAllPoints()
        hideRowLbl:SetPoint("TOPLEFT", lockedRoundHouseLbl, "BOTTOMLEFT", 0, -12)
      else
        hideRowLbl:ClearAllPoints()
        if pickSeeker then
          hideRowLbl:SetPoint("TOPLEFT", startRoundBtn, "BOTTOMLEFT", 0, -12)
        else
          hideRowLbl:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -12)
        end
      end
    else
      seekerSelectHdr:ClearAllPoints()
      seekerSelectHdr:SetPoint("TOPLEFT", sessionToggleBtn, "BOTTOMLEFT", 0, -12)
      candidateSeekerLbl:ClearAllPoints()
      candidateSeekerLbl:SetPoint("TOPLEFT", seekerSelectHdr, "BOTTOMLEFT", 0, -4)
      randSeekerBtn:ClearAllPoints()
      randSeekerBtn:SetPoint("TOPLEFT", candidateSeekerLbl, "BOTTOMLEFT", 0, -8)
      startRoundBtn:ClearAllPoints()
      startRoundBtn:SetPoint("LEFT", randSeekerBtn, "RIGHT", 8, 0)
      hideRowLbl:ClearAllPoints()
      hideRowLbl:SetPoint("TOPLEFT", randSeekerBtn, "BOTTOMLEFT", 0, -12)
    end

    -- Anchor the divider + “rest of UI” to the left column so housing/options stay aligned with the panel edge.
    local layoutAnchor = sessionToggleBtn
    if sess then
      if inRound then
        layoutAnchor = endRoundBtn
      elseif pickSeeker then
        layoutAnchor = startRoundBtn
      elseif pickHouse then
        layoutAnchor = confirmGameHouseBtn
      else
        layoutAnchor = randSeekerBtn
      end
    end
    layoutGameplayBlock(layoutAnchor, 0, -16, true)
    layoutGameplayDetailsFooter(nhsSessionHudIsActive())

    local phaseLine = gameplayPhaseLine()
    if phaseLine then
      roundPhaseLabel:SetWidth(328)
      roundPhaseLabel:SetText(phaseLine)
      roundPhaseLabel:Show()
    else
      roundPhaseLabel:Hide()
    end
    syncGameplayHouseSeekerLabels()
    refreshFoundList()

    selectSeekerBtn:SetEnabled(pickSeeker and mayAct)
    viewPastGameHousesBtn:SetEnabled(sess and #State.gameHouseHistory > 0)
    viewPastSeekersBtn:SetEnabled(sess and #State.gameSeekerHistory > 0)
    pastRoundsBtn:SetEnabled(sess and #State.pastRounds > 0)
    syncSeekerModeOptionButton()
    local hlIdx = nhsGetSavedPresetIndexForEntry(State.selectedEntry)
    if not hlIdx and State.gameLockedHouseKey then
      hlIdx = nhsGetSavedPresetIndexForStableKey(State.gameLockedHouseKey)
    end
    if not hlIdx and State.gameLockedHouseLiveEntry then
      hlIdx = nhsGetSavedPresetIndexForEntry(State.gameLockedHouseLiveEntry)
    end
    nhsPresetButtonsApplySavedHighlightIdx(hidePresetBtns, searchPresetBtns, hlIdx)
    syncMainFrameHeight()
    nhsSessionHudUpdate()
  end

  function UI.RefreshGameRounds()
    refreshGameRounds()
  end

  for _, b in ipairs(houseSizePresetBtns) do
    b:SetScript("OnClick", function(self)
      if not State.selectedEntry then
        return
      end
      local idx = self._housePresetIdx
      if nhsSetSavedPresetForEntry(State.selectedEntry, idx, State.selectedLabel, State.selectedIndex) then
        print(
          ("|cff88ccff[NHS]|r Saved size |cffffffff%s|r for this house."):format(ROUND_PRESETS[idx].label)
        )
      else
        print(
          "|cffff8800[NHS]|r Could not save — this house row has no stable id (GUID / plot / neighbor)."
        )
      end
      updateMainHouseSizeLine()
      updateHouseListButtonLabels()
      syncHouseSizePickerEnabled()
      refreshSavedHousesPanel()
      if UI.RefreshGameRounds then
        UI.RefreshGameRounds()
      end
    end)
  end

  houseSizeClearBtn:SetScript("OnClick", function()
    if nhsClearSavedPresetForEntry(State.selectedEntry) then
      print("|cff88ccff[NHS]|r Cleared saved size for this house.")
    end
    updateMainHouseSizeLine()
    updateHouseListButtonLabels()
    syncHouseSizePickerEnabled()
    refreshSavedHousesPanel()
    if UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    end
  end)

  savedListBtn:SetScript("OnClick", function()
    refreshSavedHousesPanel()
    shf:Show()
  end)

  function UI.RefreshFound()
    refreshFoundList()
    syncMainFrameHeight()
    nhsSessionHudUpdate()
  end

  function UI.RefreshAll()
    syncSeekerUiOptionsFromSaved()
    refreshBtn:SetEnabled(true)
    refreshHouseList()
    local canHousing = housingAvailable()
    pinBtn:SetEnabled(canHousing and State.selectedEntry ~= nil)
    sharePinBtn:SetEnabled(canHousing and State.selectedEntry ~= nil)
    housingSelText:SetText(
      State.selectedLabel and ("Selected House: %s"):format(State.selectedLabel)
        or "Selected House: (none)"
    )
    updateMainHouseSizeLine()
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
    nhsResetGameSession()
    print("|cff88ccff[NHS]|r Game session ended.")
    refreshGameRounds()
  end)

  sessionToggleBtn:SetScript("OnClick", function()
    if State.gameSessionActive then
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
    State.gamePhase = "pick_house"
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    wipe(State.gameHouseHistory)
    wipe(State.gameHouseRotationUsed)
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.gameLockedSeekerKey = nil
    State.gameLockedSeekerDisplay = nil
    wipe(State.gameSeekerHistory)
    wipe(State.gameRotationUsed)
    wipe(State.pastRounds)
    nhsPersistGameSessionToSaved()
    if IsInGroup() and nhsIsRoundLeader() then
      nhsBroadcastLeaderSync(NHS_MSG_SESSION_START)
    end
    print(
      "|cff88ccff[NHS]|r Game session started. Pick a house (random or list), confirm, then choose the seeker."
    )
    refreshGameRounds()
  end)

  local function nhsRandomPickCellText(disp)
    if type(disp) ~= "string" then
      disp = tostring(disp or "?")
    end
    if #disp > 22 then
      disp = disp:sub(1, 21) .. "…"
    end
    return disp
  end

  local function nhsRandomPickApplyGridHighlight(nActive, highlightIdx)
    for j = 1, #randomPickCells do
      local c = randomPickCells[j]
      if j <= nActive then
        c.frame:Show()
        if j == highlightIdx then
          c.bg:SetVertexColor(0.5, 0.38, 0.1, 1)
        else
          c.bg:SetVertexColor(0.14, 0.15, 0.19, 1)
        end
      else
        c.frame:Hide()
      end
    end
  end

  local function nhsRandomPickScrollHighlightIntoView(idx, n, cols, cellH, pad)
    local row = math.floor((idx - 1) / cols)
    local rowTop = row * (cellH + pad)
    local viewH = randomGridScroll:GetHeight()
    local maxScroll = math.max(randomGridScroll:GetVerticalScrollRange(), 0)
    local target = rowTop + cellH * 0.5 - viewH * 0.5
    if target < 0 then
      target = 0
    elseif target > maxScroll then
      target = maxScroll
    end
    randomGridScroll:SetVerticalScroll(target)
  end

  local function nhsRandomPickLayoutGrid(n, items)
    nhsRandomPickEnsureCells(n)
    local gw = randomGridScrollChild:GetWidth()
    local cols = NHS_RANDOM_GRID_COLS
    local pad = NHS_RANDOM_GRID_PAD
    local cellH = NHS_RANDOM_GRID_CELL_H
    local cellW = (gw - pad * (cols - 1)) / cols
    local rows = math.ceil(n / cols)
    for i = 1, n do
      local c = randomPickCells[i]
      local row = math.floor((i - 1) / cols)
      local col = (i - 1) % cols
      local x = col * (cellW + pad)
      local y = -row * (cellH + pad)
      c.frame:SetSize(cellW, cellH)
      c.frame:ClearAllPoints()
      c.frame:SetPoint("TOPLEFT", randomGridScrollChild, "TOPLEFT", x, y)
      c.fs:SetText(nhsRandomPickCellText(items[i].display))
    end
    for j = n + 1, #randomPickCells do
      randomPickCells[j].frame:Hide()
    end
    randomGridScrollChild:SetHeight(math.max(rows * (cellH + pad) + pad, 1))
    randomGridScroll:SetVerticalScroll(0)
    return cols, cellH, pad
  end

  local function openAnimatedRandomPick(phaseContext, subtitle, items, onPicked)
    local n = #items
    if n < 1 then
      return
    end
    ensureSavedVars()
    if NHSV.useRandomPickAnimation == false then
      onPicked(n > 1 and math.random(1, n) or 1)
      return
    end

    local winIdx, h0
    if n == 1 then
      winIdx, h0 = 1, 1
    else
      winIdx = math.random(1, n)
      -- Always start at the first slot each open (avoids stale highlight / “continues where it stopped”).
      h0 = 1
    end

    randomPickFrame.nhsPickAnimContext = phaseContext
    randomPickFrame.nhsPickAnimPhase = "anim"
    randomPickFrame.nhsPickAnimItems = items
    randomPickFrame.nhsPickAnimN = n
    randomPickFrame.nhsPickAnimWin = winIdx
    randomPickFrame.nhsGridHighlight = h0
    if n <= 1 then
      randomPickFrame.nhsGridFastStepsLeft = 0
      randomPickFrame.nhsGridAnimPhase = nil
    else
      -- Phase 1: fast full-list passes. Phase 2: fast until we land on slowStartIdx. Phase 3: exactly
      -- slowTotal slow ramp steps, landing on win on the last step (wrap math matches user spec).
      local fastListPasses = math.min(4, math.max(1, math.floor(6 - math.ceil(n / 10))))
      if n <= 14 then
        fastListPasses = fastListPasses + 2 + math.random(0, 4)
      end
      randomPickFrame.nhsGridFastStepsLeft = fastListPasses * n
      local slowTotal = math.random(10, 18)
      randomPickFrame.nhsGridSlowTotalSteps = slowTotal
      randomPickFrame.nhsGridSlowMovesLeft = 0
      -- 1-based index where slow ramp begins: win - slowTotal, wrapped into 1..n (e.g. win=3, n=6, 11 -> 4).
      randomPickFrame.nhsGridSlowStartIdx = ((winIdx - 1 - slowTotal) % n + n) % n + 1
      randomPickFrame.nhsGridAnimPhase = "fast_laps"
    end
    randomPickFrame.nhsGridFastBase = NHS_GRID_FAST_STEP_SEC
    randomPickFrame.nhsGridSlowInterval = nil
    randomPickFrame.nhsGridInterval = randomPickFrame.nhsGridFastBase
    randomPickFrame.nhsGridAccum = 0
    randomPickFrame:SetScript("OnUpdate", nil)
    randomPickFrame.nhsPickAnimOnPicked = onPicked
    randomPickFrame.nhsPickAnimRunning = true
    randomPickFrame.nhsSettleElapsed = 0

    local cols, cellH, pad = nhsRandomPickLayoutGrid(n, items)
    randomPickFrame.nhsGridCols = cols
    randomPickFrame.nhsGridCellH = cellH
    randomPickFrame.nhsGridPad = pad

    nhsRandomPickApplyGridHighlight(n, h0)
    nhsRandomPickScrollHighlightIntoView(h0, n, cols, cellH, pad)

    randomPickSubtitle:SetText(subtitle)
    randomPickFrameCloseX:Disable()

    if n == 1 then
      randomPickFrame.nhsPickAnimPhase = "settled"
      randomPickFrame.nhsSettleElapsed = 0
      local disp1 = items[1] and items[1].display or "?"
      if type(disp1) ~= "string" then
        disp1 = tostring(disp1)
      end
      randomPickStatus:SetText(("Selected: |cffffffff%s|r"):format(disp1))
      local cb1 = randomPickFrame.nhsPickAnimOnPicked
      randomPickFrame.nhsPickAnimOnPicked = nil
      if cb1 then
        cb1(1)
      end
    else
      randomPickStatus:SetText("Choosing…")
    end

    randomPickFrame:Show()

    randomPickFrame:SetScript("OnUpdate", function(self, el)
      if self.nhsPickAnimPhase == "settled" then
        self.nhsSettleElapsed = (self.nhsSettleElapsed or 0) + el
        if self.nhsSettleElapsed >= 0.55 then
          self:SetScript("OnUpdate", nil)
          self.nhsPickAnimPhase = nil
          self.nhsPickAnimRunning = false
          randomPickFrameCloseX:Enable()
        end
        return
      end

      if not self.nhsPickAnimRunning or self.nhsPickAnimPhase ~= "anim" then
        return
      end

      local nn = self.nhsPickAnimN
      local cols2 = self.nhsGridCols
      local ch = self.nhsGridCellH
      local pd = self.nhsGridPad
      local win = self.nhsPickAnimWin
      local fastB = self.nhsGridFastBase or NHS_GRID_FAST_STEP_SEC
      local animPhase = self.nhsGridAnimPhase or "fast_laps"

      self.nhsGridAccum = (self.nhsGridAccum or 0) + el

      local function finishRandomPickGrid()
        self.nhsPickAnimPhase = "settled"
        self.nhsSettleElapsed = 0
        local disp = self.nhsPickAnimItems[self.nhsPickAnimWin] and self.nhsPickAnimItems[self.nhsPickAnimWin].display or "?"
        if type(disp) ~= "string" then
          disp = tostring(disp)
        end
        randomPickStatus:SetText(("Selected: |cffffffff%s|r"):format(disp))
        local w = self.nhsPickAnimWin
        local cb = self.nhsPickAnimOnPicked
        self.nhsPickAnimOnPicked = nil
        if cb then
          cb(w)
        end
      end

      -- At most one cell advance per OnUpdate. A inner while + large |el| skipped most indices (looked
      -- like “never went around once”); leftover time stays in accum for the next tick.
      if self.nhsGridAccum < self.nhsGridInterval then
        return
      end
      self.nhsGridAccum = self.nhsGridAccum - self.nhsGridInterval

      local cur = self.nhsGridHighlight
      if type(cur) ~= "number" or cur < 1 or cur > nn then
        cur = 1
        self.nhsGridHighlight = 1
      end
      local fastLeftBefore = self.nhsGridFastStepsLeft or 0

      if animPhase == "fast_laps" then
        self.nhsGridHighlight = (cur % nn) + 1
        if fastLeftBefore > 0 then
          self.nhsGridFastStepsLeft = fastLeftBefore - 1
        end
        if (self.nhsGridFastStepsLeft or 0) == 0 then
          self.nhsGridAnimPhase = "fast_chase"
          if self.nhsGridHighlight == self.nhsGridSlowStartIdx then
            self.nhsGridAnimPhase = "slow_seq"
            self.nhsGridSlowMovesLeft = self.nhsGridSlowTotalSteps
            self.nhsGridSlowInterval = nil
          end
        end
      elseif animPhase == "fast_chase" then
        self.nhsGridHighlight = (cur % nn) + 1
        if self.nhsGridHighlight == self.nhsGridSlowStartIdx then
          self.nhsGridAnimPhase = "slow_seq"
          self.nhsGridSlowMovesLeft = self.nhsGridSlowTotalSteps
          self.nhsGridSlowInterval = nil
        end
      else
        -- slow_seq: each tick is one slow ramp step; exactly slowTotal advances from slowStart lands on win.
        self.nhsGridHighlight = (cur % nn) + 1
        self.nhsGridSlowMovesLeft = (self.nhsGridSlowMovesLeft or 0) - 1
      end

      animPhase = self.nhsGridAnimPhase or animPhase

      nhsRandomPickApplyGridHighlight(nn, self.nhsGridHighlight)
      nhsRandomPickScrollHighlightIntoView(self.nhsGridHighlight, nn, cols2, ch, pd)

      if animPhase == "slow_seq" and (self.nhsGridSlowMovesLeft or 0) == 0 and self.nhsGridHighlight == win then
        finishRandomPickGrid()
        return
      end

      if animPhase == "slow_seq" then
        local slow0 = math.max(NHS_GRID_SLOW_STEP_MIN_SEC, fastB * NHS_GRID_SLOW_START_MULT)
        local s = (self.nhsGridSlowInterval or slow0) * NHS_GRID_SLOW_STEP_GROW
        self.nhsGridSlowInterval = math.min(
          NHS_GRID_SLOW_STEP_CAP_SEC,
          math.max(NHS_GRID_SLOW_STEP_MIN_SEC, s)
        )
        self.nhsGridInterval = self.nhsGridSlowInterval
      else
        self.nhsGridSlowInterval = nil
        self.nhsGridInterval = fastB
      end
    end)
  end

  local function nhsOpenSeekerAnimatedRandomPick(hideSeekerListFrame)
    if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_seeker" then
      return
    end
    local elig, err = nhsRandomSeekerEligible()
    if not elig then
      print("|cffff8800[NHS]|r " .. tostring(err))
      return
    end
    if hideSeekerListFrame then
      gsfp:Hide()
    end
    openAnimatedRandomPick("seeker", "Random seeker (eligible this rotation)", elig, function(winIdx)
      local m = elig[winIdx]
      if not m then
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
  end

  gsfpAnimRandomSeekerBtn:SetScript("OnClick", function()
    nhsOpenSeekerAnimatedRandomPick(true)
  end)

  randGameHouseBtn:SetScript("OnClick", function()
    if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_house" then
      return
    end
    ensureSavedVars()
    if NHSV.selectHouseFromSavedList ~= false then
      -- saved list: no API needed
    elseif not housingAvailable() then
      print("|cffff8800[NHS]|r Housing API not ready — open the neighborhood or use saved list in Options.")
      return
    end
    if NHSV.selectHouseFromSavedList == false and #housesCache == 0 then
      refreshHouseList()
    end
    local elig, err = nhsGameplayRandomHouseEligible(housesCache)
    if not elig then
      print("|cffff8800[NHS]|r " .. tostring(err))
      return
    end
    openAnimatedRandomPick("house", "Random house (eligible this rotation)", elig, function(winIdx)
      local pick = elig[winIdx]
      if not pick then
        return
      end
      State.gameHouseCandidateKey = pick.rotKey
      State.gameHouseCandidateDisplay = pick.display
      State.gameLockedHouseLiveEntry = pick.liveEntry
      State.gameLockedHouseLiveIndex = pick.liveIndex
      print(
        ("|cff88ccff[NHS]|r Gameplay house: |cffffffff%s|r — Confirm house when ready."):format(pick.display)
      )
      nhsPersistGameSessionToSaved()
      refreshGameRounds()
    end)
  end)

  viewGameHousePickBtn:SetScript("OnClick", function()
    if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_house" then
      return
    end
    ensureSavedVars()
    if NHSV.selectHouseFromSavedList == false then
      if not housingAvailable() then
        print("|cffff8800[NHS]|r Housing API not ready.")
        return
      end
      refreshHouseList()
    end
    refreshGameplayHousePickList()
    ghfp:Show()
  end)

  confirmGameHouseBtn:SetScript("OnClick", function()
    if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_house" then
      return
    end
    if not State.gameHouseCandidateKey then
      return
    end
    State.gameLockedHouseKey = State.gameHouseCandidateKey
    State.gameLockedHouseDisplay = State.gameHouseCandidateDisplay
    State.gameHouseRotationUsed[State.gameLockedHouseKey] = true
    State.gameHouseHistory[#State.gameHouseHistory + 1] = State.gameLockedHouseDisplay
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gamePhase = "pick_seeker"
    if IsInGroup() and nhsIsRoundLeader() then
      nhsBroadcastHouseLocked(State.gameLockedHouseDisplay)
      nhsBroadcastGameplayHousePin(
        State.gameLockedHouseLiveEntry,
        State.gameLockedHouseLiveIndex,
        State.gameLockedHouseDisplay,
        State.gameLockedHouseKey
      )
    end
    print(
      ("|cff88ccff[NHS]|r House locked for this round: |cffffffff%s|r — pick a seeker."):format(
        State.gameLockedHouseDisplay
      )
    )
    nhsPersistGameSessionToSaved()
    refreshGameRounds()
  end)

  viewPastGameHousesBtn:SetScript("OnClick", function()
    refreshGameplayPastHousesPanel()
    ghpf:Show()
  end)

  pastRoundsBtn:SetScript("OnClick", function()
    refreshPastRoundsPanel()
    pastRoundsFrame:Show()
  end)

  randSeekerBtn:SetScript("OnClick", function()
    nhsOpenSeekerAnimatedRandomPick(false)
  end)

  selectSeekerBtn:SetScript("OnClick", function()
    if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_seeker" then
      return
    end
    if #nhsGetGroupRoster() == 0 then
      print("|cffff8800[NHS]|r No players in group.")
      return
    end
    refreshGroupSeekerPickList()
    gsfp:Show()
  end)

  startRoundBtn:SetScript("OnClick", function()
    if not nhsMayUseLeaderGameActions() or not State.gameSessionActive or State.gamePhase ~= "pick_seeker" then
      return
    end
    if not State.gameCandidateKey then
      return
    end
    if not State.gameLockedHouseDisplay then
      print("|cffff8800[NHS]|r Confirm a house first (house selection phase).")
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
        if State.gameLockedSeekerKey then
          nhsBroadcastLeaderSync(NHS_MSG_HIDING .. State.gameLockedSeekerKey)
        end
      else
        State.roundPhase = "searching"
        if State.gameLockedSeekerKey then
          nhsBroadcastLeaderSync(NHS_MSG_SEEKING .. State.gameLockedSeekerKey)
        end
        nhsLeaderTryPromoteSeekerForRaidWarn()
      end
      print(
        ("|cff88ccff[NHS]|r %s — %s (%d s)."):format(phaseLabel, pr.label, sec)
      )
      if UI.RefreshAll then
        UI.RefreshAll()
      end
      nhsSeekerAutoModeSyncToPhase()
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
    nhsAppendPastRoundSnapshotIfActiveRound()
    nhsLeaderDemoteSeekerAssistantIfWePromoted()
    State.gamePhase = "pick_house"
    State.gameHouseCandidateKey = nil
    State.gameHouseCandidateDisplay = nil
    State.gameLockedHouseKey = nil
    State.gameLockedHouseDisplay = nil
    State.gameLockedHouseLiveEntry = nil
    State.gameLockedHouseLiveIndex = nil
    State.gameLockedSeekerKey = nil
    State.gameLockedSeekerDisplay = nil
    State.gameCandidateKey = nil
    State.gameCandidateDisplay = nil
    State.roundPhase = "none"
    clearFound()
    nhsStopPartyCountdown()
    nhsBroadcastLeaderSync(NHS_MSG_ROUND_OVER)
    print("|cff88ccff[NHS]|r Round ended. Pick the next house, then the next seeker.")
    nhsPersistGameSessionToSaved()
    if State.seekerMode then
      setSeekerMode(false)
    end
    refreshGameRounds()
  end)

  refreshBtn:SetScript("OnClick", function()
    refreshHouseList()
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

  shf:ClearAllPoints()
  if NHSV.savedSizesFramePoint then
    local sp = NHSV.savedSizesFramePoint
    shf:SetPoint(sp[1], UIParent, sp[2], sp[3], sp[4])
  else
    shf:SetPoint("TOPLEFT", hf, "TOPRIGHT", 12, 0)
  end
  shf:SetFrameStrata("DIALOG")
  shf:SetFrameLevel(208)
  shf:SetToplevel(true)

  ghfp:ClearAllPoints()
  if NHSV.gameplayHousePickFramePoint then
    local gp = NHSV.gameplayHousePickFramePoint
    ghfp:SetPoint(gp[1], UIParent, gp[2], gp[3], gp[4])
  else
    ghfp:SetPoint("TOPLEFT", f, "TOPRIGHT", 16, 0)
  end
  ghfp:SetFrameStrata("DIALOG")
  ghfp:SetFrameLevel(206)
  ghfp:SetToplevel(true)

  ghpf:ClearAllPoints()
  if NHSV.gameplayPastHousesFramePoint then
    local pp = NHSV.gameplayPastHousesFramePoint
    ghpf:SetPoint(pp[1], UIParent, pp[2], pp[3], pp[4])
  else
    ghpf:SetPoint("LEFT", f, "RIGHT", 16, 0)
  end
  ghpf:SetFrameStrata("DIALOG")
  ghpf:SetFrameLevel(206)
  ghpf:SetToplevel(true)

  pastRoundsFrame:ClearAllPoints()
  if NHSV.pastRoundsFramePoint then
    local pp = NHSV.pastRoundsFramePoint
    pastRoundsFrame:SetPoint(pp[1], UIParent, pp[2], pp[3], pp[4])
  else
    pastRoundsFrame:SetPoint("LEFT", f, "RIGHT", 16, -24)
  end
  pastRoundsFrame:SetFrameStrata("DIALOG")
  pastRoundsFrame:SetFrameLevel(206)
  pastRoundsFrame:SetToplevel(true)

  gsfp:ClearAllPoints()
  if NHSV.gameplaySeekerPickFramePoint then
    local sp = NHSV.gameplaySeekerPickFramePoint
    gsfp:SetPoint(sp[1], UIParent, sp[2], sp[3], sp[4])
  else
    gsfp:SetPoint("TOPLEFT", f, "TOPRIGHT", 16, -40)
  end
  gsfp:SetFrameStrata("DIALOG")
  gsfp:SetFrameLevel(206)
  gsfp:SetToplevel(true)

  randomPickFrame:ClearAllPoints()
  if NHSV.randomPickFramePoint then
    local rp = NHSV.randomPickFramePoint
    randomPickFrame:SetPoint(rp[1], UIParent, rp[2], rp[3], rp[4])
  else
    randomPickFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  randomPickFrame:SetFrameStrata("DIALOG")
  randomPickFrame:SetFrameLevel(210)
  randomPickFrame:SetToplevel(true)

  UI.optionsFrame = optf
  UI.houseListFrame = hf
  UI.pastSeekersFrame = psf
  UI.gameplayHousePickFrame = ghfp
  UI.gameplayPastHousesFrame = ghpf
  UI.gameplayPastRoundsFrame = pastRoundsFrame
  UI.gameplaySeekerPickFrame = gsfp
  UI.gameplayRandomPickFrame = randomPickFrame
  UI.howToPlayFrame = htpf
  UI.savedSizesFrame = shf
  UI.viewHouseListBtn = viewHouseListBtn
  UI.frame = f
  syncHouseSizePickerEnabled()
  syncHouseListFrameHeight()
  nhsSessionHudUpdate()
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
      if UI.gameplayHousePickFrame and UI.gameplayHousePickFrame:IsShown() then
        UI.gameplayHousePickFrame:Hide()
      end
      if UI.gameplayPastHousesFrame and UI.gameplayPastHousesFrame:IsShown() then
        UI.gameplayPastHousesFrame:Hide()
      end
      if UI.gameplayPastRoundsFrame and UI.gameplayPastRoundsFrame:IsShown() then
        UI.gameplayPastRoundsFrame:Hide()
      end
      if UI.gameplayRandomPickFrame and UI.gameplayRandomPickFrame:IsShown() then
        UI.gameplayRandomPickFrame:Hide()
      end
      if UI.gameplaySeekerPickFrame and UI.gameplaySeekerPickFrame:IsShown() then
        UI.gameplaySeekerPickFrame:Hide()
      end
      if UI.howToPlayFrame and UI.howToPlayFrame:IsShown() then
        UI.howToPlayFrame:Hide()
      end
      if UI.savedSizesFrame and UI.savedSizesFrame:IsShown() then
        UI.savedSizesFrame:Hide()
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
  return half + 10
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
  -- Icon: direct texture on the button (no child Frame + SetAllPoints); TOPLEFT from CENTER ± half
  -- size keeps the spell art centered on the 32×32 hit box.
  local iconSize = 20
  -- MiniMap-TrackingBorder: the gold ring sits low/right inside the bitmap; a centered 54×54 quad leaves the
  -- circle’s bottom-right on the icon. Nudge the ring frame down/right (positive x, negative y on CENTER).
  local ringSize = 54
  local ringCenterNudgeX = 10
  local ringCenterNudgeY = -11
  local halfIcon = iconSize / 2
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture(NHS_MINIMAP_ICON_TEXTURE)
  icon:SetTexCoord(0, 1, 0, 1)
  icon:SetSize(iconSize, iconSize)
  icon:ClearAllPoints()
  icon:SetPoint("TOPLEFT", b, "CENTER", -halfIcon, halfIcon)
  if icon.SetSnapToPixelGrid then
    icon:SetSnapToPixelGrid(false)
  end
  if icon.SetTexelSnappingBias then
    icon:SetTexelSnappingBias(0)
  end
  local ring = b:CreateTexture(nil, "OVERLAY")
  ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  ring:SetSize(ringSize, ringSize)
  ring:SetTexCoord(0, 1, 0, 1)
  ring:ClearAllPoints()
  ring:SetPoint(
    "CENTER",
    b,
    "CENTER",
    ringCenterNudgeX + (NHSV.minimapRingOffsetX or 0),
    ringCenterNudgeY + (NHSV.minimapRingOffsetY or 0)
  )
  if ring.SetSnapToPixelGrid then
    ring:SetSnapToPixelGrid(false)
  end
  if ring.SetTexelSnappingBias then
    ring:SetTexelSnappingBias(0)
  end
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
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
      C_ChatInfo.RegisterAddonMessagePrefix(NHS_ADDON_PREFIX)
    end
    ensureSavedVars()
    nhsInitSessionHud()
    nhsHydrateGameSessionFromSaved()
    nhsPersistGameSessionToSaved()
    nhsInitMinimapButton()
    print(
      "|cff88ccff[NHS]|r Loaded. Minimap stealth icon or |cffffffff/nhs|r toggles the window. |cffffffff/nhs visitinfo|r explains Visit attempts. |cffffffff/run NHS_Toggle()|r if slash fails."
    )
  elseif event == "PLAYER_ENTERING_WORLD" then
    ensureSavedVars()
    nhsInitSessionHud()
    nhsInitMinimapButton()
    nhsHydrateGameSessionFromSaved()
    nhsPersistGameSessionToSaved()
    if UI.RefreshGameRounds then
      UI.RefreshGameRounds()
    end
    nhsSessionHudUpdate()
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

-- Dedupe when the same NHS line arrives via addon comm and visible chat in the same tick (or twice).
local nhsSyncDedupeAt, nhsSyncDedupeKey = 0, nil
local function nhsGroupSyncLineRecentlyHandled(senderName, text)
  local sk = type(senderName) == "string" and Ambiguate(senderName, "none") or ""
  local key = sk .. "\0" .. text
  local now = GetTime()
  if nhsSyncDedupeKey == key and (now - nhsSyncDedupeAt) < 0.35 then
    return true
  end
  nhsSyncDedupeKey = key
  nhsSyncDedupeAt = now
  return false
end

local function nhsDispatchGroupNhsLine(senderName, text)
  if nhsGroupSyncLineRecentlyHandled(senderName, text) then
    return
  end
  if nhsApplyFoundSyncFromChat(senderName, text) then
    return
  end
  nhsApplyGroupSyncFromLeader(senderName, text)
end

local function nhsAddonCommChannelAllowed(channel)
  if type(channel) ~= "string" or channel == "" then
    return false
  end
  local c = strupper(channel)
  return c == "PARTY" or c == "RAID" or c == "INSTANCE_CHAT"
end

local nhsSyncChatFrame = CreateFrame("Frame")
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(NHS_ADDON_PREFIX)
end
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_ADDON")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_PARTY")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_RAID")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
nhsSyncChatFrame:RegisterEvent("CHAT_MSG_RAID_WARNING")
nhsSyncChatFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    local prefix, msg, channel, sender = ...
    if prefix ~= NHS_ADDON_PREFIX then
      return
    end
    if not nhsAddonCommChannelAllowed(channel) then
      return
    end
    if type(msg) ~= "string" or msg:sub(1, #NHS_CHAT_TAG) ~= NHS_CHAT_TAG then
      return
    end
    nhsDispatchGroupNhsLine(sender, msg)
    return
  end
  if InCombatLockdown() then
    return
  end
  local text, sender = ...
  if type(text) ~= "string" or text:sub(1, #NHS_CHAT_TAG) ~= NHS_CHAT_TAG then
    return
  end
  nhsDispatchGroupNhsLine(sender, text)
end)
