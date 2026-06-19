--[[
  "Your Stats" lifetime stats popup. Load after Ui/ScrollUtil.lua; before Ui/MainFrame.lua.
]]

local NHS = NeighborhoodHideSeek

StaticPopupDialogs["NHS_CONFIRM_RESET_STATS"] = {
  text = "Reset all lifetime stats for |cffffffff%s|r?\n\nThis cannot be undone.",
  button1 = "Reset",
  button2 = "Cancel",
  OnAccept = function()
    local charKey = NeighborhoodHideSeek.LocalCharacterKey
    if charKey and NHSV and type(NHSV.charStats) == "table" then
      NHSV.charStats[charKey] = nil
    end
    print("|cff88ff88[NHS]|r Character stats have been reset.")
    if NeighborhoodHideSeek.LiveRefreshIfOpen then
      NeighborhoodHideSeek.LiveRefreshIfOpen("stats")
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

local function fmtSeconds(s)
  s = math.floor(s or 0)
  if s <= 0 then return "0s" end
  local h = math.floor(s / 3600)
  local m = math.floor((s % 3600) / 60)
  local rem = s % 60
  if h > 0 then
    return ("%dh %dm"):format(h, m)
  elseif m > 0 then
    return ("%dm %ds"):format(m, rem)
  else
    return ("%ds"):format(rem)
  end
end

local function pct(num, den)
  if not num or not den or den == 0 then return "-" end
  return ("%.0f%%"):format(100 * num / den)
end

local function topNEncounterTable(t, n)
  if type(t) ~= "table" then return {} end
  local items = {}
  for k, v in pairs(t) do
    local count = type(v) == "table" and (v.count or 0) or (tonumber(v) or 0)
    local disp = type(v) == "table" and v.display or Ambiguate(tostring(k), "short")
    items[#items + 1] = { disp = disp, count = count }
  end
  table.sort(items, function(a, b) return a.count > b.count end)
  local result = {}
  for i = 1, math.min(n, #items) do
    result[#result + 1] = items[i]
  end
  return result
end


function NHS.CreateStatsFrame()
  local statsFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  statsFrame:SetSize(320, 460)
  statsFrame:SetClampedToScreen(true)
  statsFrame:SetMovable(true)
  statsFrame:EnableMouse(true)
  statsFrame:RegisterForDrag("LeftButton")
  statsFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  statsFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    NHS.EnsureSavedVars()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.statsFramePoint = { p, rp or "UIParent", x, y }
  end)
  statsFrame:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  statsFrame:SetBackdropColor(0, 0, 0, 0.9)

  local titleFs = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleFs:SetPoint("TOP", 0, -14)
  titleFs:SetText("Your Stats")

  local scroll = CreateFrame("ScrollFrame", nil, statsFrame)
  scroll:SetPoint("TOPLEFT", 16, -42)
  scroll:SetSize(288, 370)
  NHS.SetupScrollFrameMouseWheel(scroll)

  local scrollChild = CreateFrame("Frame", nil, scroll)
  scrollChild:SetSize(288, 1)
  scroll:SetScrollChild(scrollChild)

  local bodyText = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  bodyText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
  bodyText:SetWidth(278)
  bodyText:SetJustifyH("LEFT")
  bodyText:SetJustifyV("TOP")
  bodyText:SetSpacing(3)

  local closeBtn = CreateFrame("Button", nil, statsFrame, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -6, -6)
  closeBtn:SetScript("OnClick", function() statsFrame:Hide() end)

  local resetStatsBtn = CreateFrame("Button", nil, statsFrame, "UIPanelButtonTemplate")
  resetStatsBtn:SetSize(150, 24)
  resetStatsBtn:SetPoint("BOTTOM", statsFrame, "BOTTOM", 0, 12)
  resetStatsBtn:SetText("Reset Stats")
  resetStatsBtn:SetScript("OnClick", function()
    local charKey = NHS.LocalCharacterKey
    local shortName = charKey and Ambiguate(charKey, "short") or "this character"
    StaticPopup_Show("NHS_CONFIRM_RESET_STATS", shortName)
  end)
  resetStatsBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Reset Stats")
    GameTooltip:AddLine("Permanently clears all lifetime stats\nfor your character. Cannot be undone.", 1, 0.6, 0.6, true)
    GameTooltip:Show()
  end)
  resetStatsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  statsFrame:Hide()

  local function refreshStatsPanel()
    scroll:SetVerticalScroll(0)
    local charKey = NHS.LocalCharacterKey
    local s = charKey and NHSV and type(NHSV.charStats) == "table" and NHSV.charStats[charKey]
    -- Migrate legacy house stat keys to canonical player keys if not yet done.
    -- Runs here so the user sees merged data immediately without needing a session first.
    if s and (s.statsVersion or 1) < 3 then
      local SH = NHS.SavedHouses
      if SH and SH.MigrateHouseCountsToPlayerKeys and SH.MigrateHouseCountsToPlayerKeys(s.houseCounts) then
        s.statsVersion = 3
      end
    end
    if not s then
      bodyText:SetText("No stats recorded yet.\n\nPlay some rounds to start tracking!")
      scrollChild:SetHeight(math.max(bodyText:GetStringHeight() + 8, 1))
      return
    end

    local G = "|cffffd700"
    local D = "|cffaaaaaa"
    local W = "|cff88ccff"
    local R = "|r"
    local lines = {}
    local function add(t) lines[#lines + 1] = t end
    local function gap() add("") end
    local function hdr(t) add(G .. t .. R) end
    local function v(n) return W .. tostring(n) .. R end

    add(D .. Ambiguate(charKey, "short") .. R)
    gap()

    hdr("SESSIONS")
    add("  Played: " .. v(s.sessionsPlayed or 0))

    gap()
    hdr("ROUNDS")
    add(("  Played: %s  |  Seeker: %s  |  Hider: %s"):format(
      v(s.roundsPlayed or 0), v(s.roundsAsSeeker or 0), v(s.roundsAsHider or 0)))

    gap()
    hdr("TIME")
    add("  Finding Spot: " .. v(fmtSeconds(s.secondsFindingSpot)))
    add("  Hiding:          " .. v(fmtSeconds(s.secondsHiding)))
    add("  Seeking:         " .. v(fmtSeconds(s.secondsSearching)))
    add("  In Sessions:    " .. v(fmtSeconds(s.totalSessionSeconds)))

    gap()
    hdr("WINS")
    add(("  Wins as Seeker:     %s / %s  (%s)"):format(
      v(s.seekerWins or 0), v(s.roundsAsSeeker or 0), v(pct(s.seekerWins, s.roundsAsSeeker))))
    add(("  Wins as Hider: %s / %s  (%s)"):format(
      v(s.hiderSurvivals or 0), v(s.roundsAsHider or 0), v(pct(s.hiderSurvivals, s.roundsAsHider))))
    if (s.timesFirstFound or 0) > 0 or (s.timesLastFound or 0) > 0 then
      add(("  First Found: %s  |  Last Found: %s"):format(
        v(s.timesFirstFound or 0), v(s.timesLastFound or 0)))
    end

    if type(s.modeCounts) == "table" and next(s.modeCounts) then
      local modeList = {}
      for _, modeId in ipairs(NHS.GAME_MODE_IDS or {}) do
        local count = s.modeCounts[modeId]
        if count and count > 0 then
          modeList[#modeList + 1] = { id = modeId, count = count }
        end
      end

      if #modeList > 0 then
        gap()
        hdr("BY GAME MODE")
        for _, entry in ipairs(modeList) do
          local modeId = entry.id
          local label = (NHS.GameModeHudLabel and NHS.GameModeHudLabel(modeId)) or modeId
          add(("  %s (%s)"):format(label, v(entry.count)))
          local seekRounds = (type(s.modeSeekerRounds)   == "table" and s.modeSeekerRounds[modeId])   or 0
          local hideRounds = (type(s.modeHiderRounds)    == "table" and s.modeHiderRounds[modeId])    or 0
          local seekWins   = (type(s.modeSeekerWins)     == "table" and s.modeSeekerWins[modeId])     or 0
          local hideWins   = (type(s.modeHiderSurvivals) == "table" and s.modeHiderSurvivals[modeId]) or 0
          if seekRounds > 0 then
            add(("    Wins as Seeker: %s / %s  (%s)"):format(v(seekWins), v(seekRounds), v(pct(seekWins, seekRounds))))
          end
          if hideRounds > 0 then
            add(("    Wins as Hider:  %s / %s  (%s)"):format(v(hideWins), v(hideRounds), v(pct(hideWins, hideRounds))))
          end
        end
      end
    end

    if type(s.playerEncounters) == "table" and next(s.playerEncounters) then
      gap()
      hdr("PLAYED WITH")
      for _, e in ipairs(topNEncounterTable(s.playerEncounters, 8)) do
        add(("  %s  " .. D .. "||" .. R .. "  %s"):format(v(e.count), tostring(e.disp)))
      end
    end

    if type(s.houseCounts) == "table" and next(s.houseCounts) then
      gap()
      hdr("BY HOUSE")
      for _, e in ipairs(topNEncounterTable(s.houseCounts, 5)) do
        add(("  %s  " .. D .. "||" .. R .. "  %s"):format(v(e.count), tostring(e.disp)))
      end
    end

    bodyText:SetText(table.concat(lines, "\n"))
    scrollChild:SetHeight(math.max(bodyText:GetStringHeight() + 8, 1))
  end

  return {
    frame = statsFrame,
    refresh = refreshStatsPanel,
  }
end
