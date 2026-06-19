--[[
  Group version check: [NHS] Version? <ver> request / [NHS] Version: <key> <ver> reply protocol
  and a live-updating popup.

  GroupSync.lua dispatches CHAT_MSG_ADDON lines to NHS.VersionCheck.ApplyVersionQuery and
  NHS.VersionCheck.ApplyVersionReply (defined at the bottom of this file).

  NHS.VersionCheck.TriggerCheck() is called by the Options "Check Group Versions" button
  and auto-triggered by the leader when a game session starts (Gameplay/GameSession.lua).
]]

local NHS = NeighborhoodHideSeek

local NHS_MSG_VERSION_REPLY_PREFIX = "[NHS] Version: "

-- Sender-side cooldown: limits how often THIS client can broadcast a new version check.
-- Receivers have no cooldown and always reply immediately.
local SEND_COOLDOWN          = 15   -- seconds between outgoing checks from this client
local lastSendAt             = 0
local activeCountdownTicker  = nil  -- tracked so it can be cancelled and re-armed

-- Non-nil only while this client is the initiator of an active check.
-- { active=bool, results={[canonicalKey]={display, version, responded, mismatch, noResponse}} }
local activeCheck = nil

local checkFrame = nil  -- lazy-created popup

-- Forward declarations
local nhsTriggerVersionCheck
local nhsRefreshVersionCheckFrame

-- ---- Helpers -----------------------------------------------------------------

local function nhsVersionSyncChannel()
  if IsInRaid() then return "RAID" end
  local inst = LE_PARTY_CATEGORY_INSTANCE or 2
  if IsInGroup(inst) then return "INSTANCE_CHAT" end
  return "PARTY"
end

local function nhsSendVersionAddonMsg(msg)
  if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
  if not IsInGroup() then return false end
  if not NHS.AddonMessagePrefix then return false end
  if #msg > 255 then return false end
  pcall(C_ChatInfo.SendAddonMessage, NHS.AddonMessagePrefix, msg, nhsVersionSyncChannel())
  return true
end

local function nhsMyKey()
  local gsb = NHS.GroupSyncBridge
  return gsb and gsb.nhsLocalPlayerSortKey and gsb.nhsLocalPlayerSortKey()
end

local function nhsMyVersion()
  return NHS.ADDON_VERSION or "unknown"
end

-- Returns the sort key of the current group leader, or nil.
local function nhsGroupLeaderKey()
  local gsb = NHS.GroupSyncBridge
  if not gsb or not gsb.nhsUnitSortKey then return nil end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local u = "raid" .. i
      if UnitExists(u) and UnitIsGroupLeader(u) then
        return gsb.nhsUnitSortKey(u)
      end
    end
  elseif IsInGroup() then
    for _, u in ipairs({"player", "party1", "party2", "party3", "party4"}) do
      if UnitExists(u) and UnitIsGroupLeader(u) then
        return gsb.nhsUnitSortKey(u)
      end
    end
  end
  return nil
end

-- Map an incoming key from a message to the canonical key already stored in activeCheck.results,
-- using the same roster-identity logic used elsewhere in the addon.
local function nhsFindCanonicalResultKey(playerKey)
  if activeCheck.results[playerKey] then return playerKey end
  local gsb = NHS.GroupSyncBridge
  if gsb then
    if gsb.nhsCanonicalGroupSortKey then
      local ck = gsb.nhsCanonicalGroupSortKey(playerKey)
      if ck and ck ~= playerKey and activeCheck.results[ck] then
        return ck
      end
    end
    if gsb.nhsRosterIdentityEqual then
      for k in pairs(activeCheck.results) do
        if gsb.nhsRosterIdentityEqual(playerKey, k) then
          return k
        end
      end
    end
  end
  return playerKey  -- unknown player; fall through to create a new entry
end

-- Short display name from a raw sender string (e.g. "Name" or "Name-Realm").
local function nhsSenderDisplay(senderName)
  if type(senderName) ~= "string" or senderName == "" then return "A party member" end
  return Ambiguate(senderName, "short")
end

-- ---- Reply (any client receiving a query sends this) -------------------------

local function nhsSendVersionReply()
  local myKey = nhsMyKey()
  if not myKey or myKey == "" then return end
  local msg = NHS_MSG_VERSION_REPLY_PREFIX .. myKey .. " " .. nhsMyVersion()
  nhsSendVersionAddonMsg(msg)
end

-- ---- Protocol handlers (called by GroupSync dispatch) ------------------------

-- Query format: "[NHS] Version? <version>"
-- The first whitespace-delimited token after "?" is the initiator's version; anything
-- further is ignored (forward-compat).  Bare "[NHS] Version?" is also accepted.
local function nhsApplyVersionQuery(senderName, text)
  local rest = text:match("^%[NHS%] Version%?(.*)$")
  if not rest then return false end
  local queryVer = rest:match("^%s+(%S+)")  -- nil for bare "[NHS] Version?"

  -- Non-initiators: compare the embedded version against ours immediately.
  if not activeCheck and queryVer then
    local myVer = nhsMyVersion()
    if queryVer ~= myVer then
      print(("|cffff9900[NHS]|r Version check: %s has version %s; you have %s — consider updating."):format(
        nhsSenderDisplay(senderName), queryVer, myVer))
    end
  end

  nhsSendVersionReply()
  return true
end

-- Reply format: "[NHS] Version: <playerKey> <version>"
local function nhsApplyVersionReply(senderName, text)
  local body = text:match("^%[NHS%] Version: (.+)$")
  if not body then return false end
  -- playerKey has no spaces (Name-Realm); version has no spaces (1.2.5).
  local playerKey, version = body:match("^(%S+) (%S+)$")
  if not playerKey or not version then return false end

  if not activeCheck then return true end  -- passive warning is now handled in the query handler

  -- Use the same key-normalisation logic as the rest of the addon so same-realm name-only
  -- keys and cross-realm Name-Realm keys both resolve to the correct entry.
  local myVer     = nhsMyVersion()
  local canonical = nhsFindCanonicalResultKey(playerKey)
  local entry     = activeCheck.results[canonical]
  if entry then
    entry.version   = version
    entry.responded = true
    entry.mismatch  = (version ~= myVer)
  else
    activeCheck.results[canonical] = {
      display   = Ambiguate(playerKey, "short"),
      version   = version,
      responded = true,
      mismatch  = (version ~= myVer),
    }
  end
  nhsRefreshVersionCheckFrame()
  return true
end

-- ---- UI ----------------------------------------------------------------------

local function nhsGetOrCreateCheckFrame()
  if checkFrame then return checkFrame end

  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetSize(310, 268)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
  f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  f:SetBackdropColor(0, 0, 0, 0.88)
  f:SetPoint("CENTER")
  f:Hide()

  local titleFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleFS:SetPoint("TOP", 0, -14)
  titleFS:SetText("Group Version Check")

  local myVerFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  myVerFS:SetPoint("TOPLEFT", 20, -38)
  myVerFS:SetWidth(270)
  myVerFS:SetJustifyH("LEFT")
  f._myVerFS = myVerFS

  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetColorTexture(1, 1, 1, 0.12)
  sep:SetSize(270, 1)
  sep:SetPoint("TOPLEFT", 20, -55)

  local scroll = CreateFrame("ScrollFrame", nil, f)
  scroll:SetPoint("TOPLEFT", 20, -64)
  scroll:SetSize(270, 162)
  if NHS.SetupScrollFrameMouseWheel then
    NHS.SetupScrollFrameMouseWheel(scroll)
  end

  local scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(270, 1)
  scroll:SetScrollChild(scrollChild)

  local bodyFS = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  bodyFS:SetPoint("TOPLEFT", 0, 0)
  bodyFS:SetWidth(262)
  bodyFS:SetJustifyH("LEFT")
  bodyFS:SetJustifyV("TOP")
  f._bodyFS      = bodyFS
  f._scrollChild = scrollChild
  f._scroll      = scroll

  local recheckBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  recheckBtn:SetSize(130, 22)
  recheckBtn:SetPoint("BOTTOMLEFT", 16, 12)
  recheckBtn:SetText("Re-check")
  recheckBtn:SetScript("OnClick", function()
    if nhsTriggerVersionCheck then nhsTriggerVersionCheck() end
  end)
  f._recheckBtn = recheckBtn

  local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -6, -6)
  closeBtn:SetScript("OnClick", function() f:Hide() end)

  checkFrame = f
  return f
end

nhsRefreshVersionCheckFrame = function()
  local f = checkFrame
  if not f or not f:IsShown() then return end
  if not activeCheck then return end

  f._myVerFS:SetText("Your version: " .. nhsMyVersion())

  local leaderKey = nhsGroupLeaderKey()

  -- Sort: leader first, then alphabetical by key.
  local keys = {}
  for k in pairs(activeCheck.results) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if a == leaderKey then return true end
    if b == leaderKey then return false end
    return a < b
  end)

  local lines      = {}
  local anyPending = false
  local anyProblem = false

  for _, k in ipairs(keys) do
    local e     = activeCheck.results[k]
    local label = e.display
    if k == leaderKey then label = label .. " (leader)" end

    if not e.responded then
      anyPending = true
      lines[#lines + 1] = "|cff888888[?] " .. label .. " — Waiting...|r"
    elseif e.noResponse then
      anyProblem = true
      lines[#lines + 1] = "|cffff4444[!] " .. label .. " — No response|r"
    elseif e.mismatch then
      anyProblem = true
      lines[#lines + 1] = "|cffff4444[!] " .. label .. " — " .. e.version .. "|r"
    else
      lines[#lines + 1] = "|cff44ff44[+] " .. label .. " — " .. (e.version or "?") .. "|r"
    end
  end

  if not activeCheck.active and not anyPending then
    lines[#lines + 1] = ""
    if anyProblem then
      lines[#lines + 1] = "|cffff9900Version mismatch or missing response detected.|r"
    else
      lines[#lines + 1] = "|cff44ff44All players on the same version.|r"
    end
  end

  local text = table.concat(lines, "\n")
  f._bodyFS:SetText(text)
  f._scrollChild:SetHeight(math.max(f._bodyFS:GetStringHeight() + 8, 1))
  f._scroll:SetVerticalScroll(0)
end

-- ---- Sender-side cooldown countdown -----------------------------------------

local function nhsStartRecheckCountdown(btn, remainingSeconds)
  if not btn then return end
  if activeCountdownTicker then
    activeCountdownTicker:Cancel()
    activeCountdownTicker = nil
  end
  local remaining = math.max(1, math.floor(remainingSeconds or SEND_COOLDOWN))
  btn:SetEnabled(false)
  btn:SetText("Re-check (" .. remaining .. "s)")
  activeCountdownTicker = C_Timer.NewTicker(1, function()
    remaining = remaining - 1
    if remaining <= 0 then
      activeCountdownTicker = nil
      btn:SetEnabled(true)
      btn:SetText("Re-check")
    else
      btn:SetText("Re-check (" .. remaining .. "s)")
    end
  end, remaining)
end

-- ---- TriggerCheck (public entry point) ---------------------------------------

nhsTriggerVersionCheck = function()
  if not IsInGroup() then
    print("|cffffcc00[NHS]|r Join a group to check addon versions.")
    return
  end

  local now = GetTime()
  if (now - lastSendAt) < SEND_COOLDOWN then
    -- Still on cooldown — surface the existing popup and ensure the button stays disabled
    -- with the correct remaining time (re-arms the ticker in case of edge-case timing drift).
    local f = nhsGetOrCreateCheckFrame()
    f:Show()
    nhsStartRecheckCountdown(f._recheckBtn, math.ceil(SEND_COOLDOWN - (now - lastSendAt)))
    return
  end
  lastSendAt = now

  activeCheck = { active = true, results = {} }

  -- Pre-populate roster as pending so the popup shows everyone immediately.
  local gsb = NHS.GroupSyncBridge
  if gsb and gsb.nhsGetGroupRoster then
    for _, m in ipairs(gsb.nhsGetGroupRoster()) do
      activeCheck.results[m.key] = {
        display   = m.display,
        version   = nil,
        responded = false,
        mismatch  = false,
      }
    end
  end

  -- Register our own entry immediately so we appear green, not "Waiting".
  local myKey = nhsMyKey()
  if myKey then
    local myVer = nhsMyVersion()
    -- Use canonical key in case our key differs from what the roster stored.
    local canonical = nhsFindCanonicalResultKey(myKey)
    local entry     = activeCheck.results[canonical]
    if entry then
      entry.version   = myVer
      entry.responded = true
      entry.mismatch  = false
    else
      activeCheck.results[canonical] = {
        display   = Ambiguate(myKey, "short"),
        version   = myVer,
        responded = true,
        mismatch  = false,
      }
    end
  end

  nhsSendVersionAddonMsg("[NHS] Version? " .. nhsMyVersion())

  local f = nhsGetOrCreateCheckFrame()
  f:Show()
  nhsRefreshVersionCheckFrame()
  nhsStartRecheckCountdown(f._recheckBtn)

  -- After 5 seconds mark non-responders and close the active state.
  C_Timer.After(5, function()
    if not activeCheck then return end
    for _, entry in pairs(activeCheck.results) do
      if not entry.responded then
        entry.version    = "No response"
        entry.responded  = true
        entry.noResponse = true
        entry.mismatch   = true
      end
    end
    activeCheck.active = false
    nhsRefreshVersionCheckFrame()
  end)
end

-- ---- Public API --------------------------------------------------------------

NHS.VersionCheck = {
  TriggerCheck      = nhsTriggerVersionCheck,
  ApplyVersionQuery = nhsApplyVersionQuery,
  ApplyVersionReply = nhsApplyVersionReply,
}
