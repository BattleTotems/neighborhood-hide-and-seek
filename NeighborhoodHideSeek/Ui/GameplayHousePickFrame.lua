--[[
  Gameplay "Pick a house" scroll list. opts: getHousesCache(), onAfterPick().
  Load after SavedHouses; Ui/ScrollUtil.lua; before Ui/MainFrame.lua.
]]

local NHS = NeighborhoodHideSeek

--- @param opts table { getHousesCache = function(): table, onAfterPick = function() }
function NHS.CreateGameplayHousePickFrame(opts)
  local State = NHS.State
  local getHousesCache = assert(opts.getHousesCache, "getHousesCache required")
  local onAfterPick = opts.onAfterPick or function() end

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
    NHS.EnsureSavedVars()
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
  ghfpTitle:SetText("Pick A House")
  local ghfpStatus = ghfp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ghfpStatus:SetPoint("TOPLEFT", 16, -40)
  ghfpStatus:SetWidth(268)
  ghfpStatus:SetJustifyH("LEFT")
  ghfpStatus:SetText("—")
  local ghfpScroll = CreateFrame("ScrollFrame", nil, ghfp)
  ghfpScroll:SetPoint("TOPLEFT", 16, -62)
  ghfpScroll:SetSize(268, 300)
  NHS.SetupScrollFrameMouseWheel(ghfpScroll)

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

  local gameplayPickRowBtns = {}

  local function refreshGameplayHousePickList()
    NHS.EnsureSavedVars()
    local src = State.gameSessionHouseListSource
    if not src then
      ghfpTitle:SetText("Pick A House")
      ghfpStatus:SetText("Choose Neighborhood, Saved list, or Group on the main window first.")
      for i = 1, #gameplayPickRowBtns do
        gameplayPickRowBtns[i]:Hide()
      end
      ghfpScrollChild:SetHeight(1)
      ghfpScroll:SetVerticalScroll(0)
      return
    end
    local pool = NHS.SavedHouses.BuildGameplayHousePickPool(getHousesCache(), src)
    local title = "Pick A House"
    if src == "saved" then
      title = "Pick A House (Saved List)"
    elseif src == "group" then
      title = "Pick A House (Group)"
    elseif src == "neighborhood" then
      title = "Pick A House (Neighborhood)"
    end
    ghfpTitle:SetText(title)
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
        local B = NHS.BuildMainFrameBridge
        if B and B.nhsPersistGameSessionToSaved then
          B.nhsPersistGameSessionToSaved()
        end
        onAfterPick()
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

  return {
    frame = ghfp,
    refresh = refreshGameplayHousePickList,
  }
end
