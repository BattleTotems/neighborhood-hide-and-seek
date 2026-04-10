--[[
  House list window (refresh, pin, share, size presets, scrollable rows).
  Path: House/HouseList.lua — see NeighborhoodHideSeek.toc.
]]

function NeighborhoodHideSeek.CreateHouseListFrame(viewHouseListBtn)
  local NHS = NeighborhoodHideSeek
  local PRESETS = NHS.ROUND_PRESETS

  local function ensureSaved()
    if NHS.EnsureSavedVars then
      NHS.EnsureSavedVars()
    end
  end

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
    ensureSaved()
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
  listTitle:SetText("House List")

  local listStatus = hf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  listStatus:SetPoint("TOPLEFT", 16, -40)
  listStatus:SetWidth(288)
  listStatus:SetJustifyH("LEFT")

  local refreshBtn = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
  refreshBtn:SetSize(288, 24)
  refreshBtn:SetText("Refresh Houses")
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
  for i = 1, #PRESETS do
    local pr = PRESETS[i]
    local b = CreateFrame("Button", nil, hf, "UIPanelButtonTemplate")
    b:SetSize(140, 22)
    b._housePresetIdx = i
    houseSizePresetBtns[i] = b
    b:SetText(pr.label)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(pr.label, 1, 1, 1)
      GameTooltip:AddLine(
        ("Hide %ds · Search %ds"):format(pr.hideSec, pr.searchSec),
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
  houseSizeClearBtn:SetText("Clear Saved Size (Selected House)")
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
  NeighborhoodHideSeek.SetupScrollFrameMouseWheel(scroll)
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

  return {
    frame = hf,
    listStatus = listStatus,
    refreshBtn = refreshBtn,
    pinBtn = pinBtn,
    sharePinBtn = sharePinBtn,
    housingSelText = housingSelText,
    housingSizeText = housingSizeText,
    houseSizePresetBtns = houseSizePresetBtns,
    houseSizeClearBtn = houseSizeClearBtn,
    savedListBtn = savedListBtn,
    scroll = scroll,
    child = child,
    syncViewHouseListButtonLabel = syncViewHouseListButtonLabel,
  }
end
