--[[
  "Game Modes" scrollable help window with per-mode default-inclusion checkboxes.
  Loaded after Core.lua; see NeighborhoodHideSeek.toc (Ui/GameModesInfo.lua).
]]

function NeighborhoodHideSeek.CreateGameModesInfoFrame()
  local NHS = NeighborhoodHideSeek

  local function ensureSaved()
    if NHS.EnsureSavedVars then NHS.EnsureSavedVars() end
  end

  local htpf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  htpf:SetSize(360, 420)
  htpf:SetClampedToScreen(true)
  htpf:SetMovable(true)
  htpf:EnableMouse(true)
  htpf:RegisterForDrag("LeftButton")
  htpf:SetScript("OnDragStart", function(self) self:StartMoving() end)
  htpf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSaved()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.gameModesInfoFramePoint = { p, rp or "UIParent", x, y }
  end)
  htpf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  htpf:SetBackdropColor(0, 0, 0, 0.9)

  local htpfTitle = htpf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  htpfTitle:SetPoint("TOP", 0, -14)
  htpfTitle:SetText("Game Modes")

  local htpScroll = CreateFrame("ScrollFrame", nil, htpf)
  htpScroll:SetPoint("TOPLEFT", 16, -42)
  htpScroll:SetSize(328, 358)
  NeighborhoodHideSeek.SetupScrollFrameMouseWheel(htpScroll)
  local htpScrollChild = CreateFrame("Frame", nil, htpScroll)
  htpScrollChild:SetSize(328, 1)
  htpScroll:SetScrollChild(htpScrollChild)

  local textWidth = 318
  local cbSize = 20
  local cbGap = 6
  local modeTextWidth = textWidth - cbSize - cbGap
  local gapBetweenModes = 8
  local bottomPad = 12

  -- Section header
  local sectionHdr = htpScrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  sectionHdr:SetWidth(textWidth)
  sectionHdr:SetJustifyH("LEFT")
  sectionHdr:SetText("Game Modes:")
  sectionHdr:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", 0, 0)

  local subHint = htpScrollChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  subHint:SetWidth(textWidth)
  subHint:SetJustifyH("LEFT")
  subHint:SetText("Use the checkboxes to set which modes are included in Random by default.")
  subHint:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", 0, -(sectionHdr:GetStringHeight() + 4))

  local yOffset = sectionHdr:GetStringHeight() + 4 + subHint:GetStringHeight() + 10

  -- Per-mode rows: [checkbox] [description text]
  local modeCheckboxes = {}
  for _, id in ipairs(NHS.GAME_MODE_IDS) do
    local def = NHS.GameModeDefinition(id)
    if def and def.description then
      local chk = CreateFrame("CheckButton", nil, htpScrollChild, "UICheckButtonTemplate")
      chk:SetSize(cbSize, cbSize)
      chk:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", 0, -yOffset - 1)
      chk._gameModeId = id
      chk:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Random Default", 1, 1, 1)
        GameTooltip:AddLine("When checked, this mode is included in the Random pool by default at the start of each round.", nil, nil, nil, true)
        GameTooltip:AddLine("The main window's checkboxes can still be adjusted per-round.", nil, nil, nil, true)
        GameTooltip:Show()
      end)
      chk:SetScript("OnLeave", function() GameTooltip:Hide() end)
      chk:SetScript("OnClick", function(self)
        ensureSaved()
        NHSV.gameModeDefaults[self._gameModeId] = self:GetChecked() and true or false
      end)
      modeCheckboxes[id] = chk

      local txt = htpScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      txt:SetWidth(modeTextWidth)
      txt:SetJustifyH("LEFT")
      txt:SetJustifyV("TOP")
      txt:SetSpacing(4)
      local line = ("• %s: %s"):format(def.label, def.description)
      if def.warning then line = line .. " " .. def.warning end
      txt:SetText(line)
      txt:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", cbSize + cbGap, -yOffset)

      local rowHeight = math.max(txt:GetStringHeight(), cbSize)
      yOffset = yOffset + rowHeight + gapBetweenModes
    end
  end

  htpScrollChild:SetHeight(math.max(yOffset + bottomPad, 1))
  htpScroll:SetVerticalScroll(0)

  local htpfCloseBtn = CreateFrame("Button", nil, htpf, "UIPanelCloseButton")
  htpfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  htpfCloseBtn:SetScript("OnClick", function() htpf:Hide() end)
  htpf._nhsCloseButton = htpfCloseBtn
  htpf:Hide()

  local function syncFromSaved()
    ensureSaved()
    for id, chk in pairs(modeCheckboxes) do
      chk:SetChecked(NHSV.gameModeDefaults[id] ~= false)
    end
  end

  return { frame = htpf, syncFromSaved = syncFromSaved }
end
