--[[
  Esc → Options → AddOns: single “Neighborhood Hide & Seek” row with About only.
  Options and How To Play stay on the main game window (lazy-built).
  InitBlizzardSettingsAboutOnly: deferred after load so the row exists before /nhs.
]]

local NHS = NeighborhoodHideSeek

local settingsPanel = _G.SettingsPanel

--- If satellite frames were ever parented off UIParent, restore them for floating popups.
function NHS.RestoreEmbeddedSettingsFrames()
  if NHS.EnsureSavedVars then
    NHS.EnsureSavedVars()
  end
  local B = NHS.SeekerModeBridge
  local UI = B.getUI()
  local optf = UI.optionsFrame
  if optf and optf:GetParent() ~= UIParent then
    optf:Hide()
    optf:SetParent(UIParent)
    optf:ClearAllPoints()
    if NHSV.optionsFramePoint then
      local op = NHSV.optionsFramePoint
      optf:SetPoint(op[1], UIParent, op[2], op[3], op[4])
    else
      optf:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    optf:SetFrameStrata("DIALOG")
    optf:SetFrameLevel(204)
    if optf._nhsCloseButton then
      optf._nhsCloseButton:Show()
    end
  end
  local htpf = UI.howToPlayFrame
  if htpf and htpf:GetParent() ~= UIParent then
    htpf:Hide()
    htpf:SetParent(UIParent)
    htpf:ClearAllPoints()
    if NHSV.howToPlayFramePoint then
      local hp = NHSV.howToPlayFramePoint
      htpf:SetPoint(hp[1], UIParent, hp[2], hp[3], hp[4])
    else
      htpf:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    htpf:SetFrameStrata("DIALOG")
    htpf:SetFrameLevel(207)
    if htpf._nhsCloseButton then
      htpf._nhsCloseButton:Show()
    end
  end
  local gmif = UI.gameModesInfoFrame
  if gmif and gmif:GetParent() ~= UIParent then
    gmif:Hide()
    gmif:SetParent(UIParent)
    gmif:ClearAllPoints()
    if NHSV.gameModesInfoFramePoint then
      local hp = NHSV.gameModesInfoFramePoint
      gmif:SetPoint(hp[1], UIParent, hp[2], hp[3], hp[4])
    else
      gmif:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    gmif:SetFrameStrata("DIALOG")
    gmif:SetFrameLevel(207)
    if gmif._nhsCloseButton then
      gmif._nhsCloseButton:Show()
    end
  end
end

local function nhsAboutOpenMainClick()
  NHS.EnsureMainFrameCreated()
  local B = NHS.SeekerModeBridge
  local UI = B.getUI()
  if UI.RefreshAll then
    UI.RefreshAll()
  end
  if UI.frame then
    UI.frame:Show()
  end
  if NHS.SyncEscapeProxyVisibility then
    NHS.SyncEscapeProxyVisibility()
  end
end

local function nhsBuildAboutFrame()
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(560, 420)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -28, 48)
  NHS.SetupScrollFrameMouseWheel(scroll)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetWidth(500)
  scroll:SetScrollChild(child)

  local y = 0
  local function addTitle(text)
    local fs = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetWidth(500)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    y = y + fs:GetStringHeight() + 10
  end
  local function addBody(text, font)
    font = font or "GameFontHighlightSmall"
    local fs = child:CreateFontString(nil, "OVERLAY", font)
    fs:SetWidth(500)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(4)
    fs:SetText(text)
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    y = y + fs:GetStringHeight() + 12
  end

  addTitle("Neighborhood Hide & Seek")
  addBody(
    (NHS.ADDON_VERSION_DISPLAY or "Version —") .. "\n\n" .. (NHS.ABOUT_BLURB or ""),
    "GameFontHighlight"
  )
  addTitle("License")
  addBody(
    "Distributed as-is.",
    "GameFontHighlightSmall"
  )
  addTitle("Development")
  addBody("Battletotems", "GameFontHighlightSmall")
  addTitle("Testers")
  addBody("Warforged guild on Stormrage", "GameFontHighlightSmall")

  child:SetHeight(math.max(y + 24, 1))
  scroll:SetVerticalScroll(0)

  local openBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  openBtn:SetSize(220, 26)
  openBtn:SetText("Open Game Window")
  openBtn:SetPoint("BOTTOMLEFT", 12, 12)
  openBtn:SetScript("OnClick", nhsAboutOpenMainClick)

  return f
end

local function nhsRefreshSettingsCategoryList()
  if settingsPanel and settingsPanel.GetCategoryList then
    local list = settingsPanel:GetCategoryList()
    if list and list.CreateCategories then
      list:CreateCategories()
    end
  end
end

--- Deferred from ADDON_LOADED so Settings APIs exist; About shows before the main UI is built.
function NHS.InitBlizzardSettingsAboutOnly()
  if NHS._blizzardAboutSettingsRegistered then
    return
  end
  if not Settings or not Settings.RegisterCanvasLayoutCategory or not Settings.RegisterAddOnCategory then
    return
  end

  local aboutFrame = nhsBuildAboutFrame()
  local parentCategory = select(1, Settings.RegisterCanvasLayoutCategory(aboutFrame, "Neighborhood Hide & Seek"))
  parentCategory.ID = "NHS"
  Settings.RegisterAddOnCategory(parentCategory)
  NHS._blizzardAboutSettingsRegistered = true
  nhsRefreshSettingsCategoryList()
end
