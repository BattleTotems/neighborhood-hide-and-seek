--[[
  Saved house sizes editor (NHSV). callbacks.afterRowRemove optional — called after a row is removed.
  Load after House modules for PlotSortKey / ROUND_PRESETS; after Ui/ScrollUtil.lua; before Ui/MainFrame.lua.
]]

local NHS = NeighborhoodHideSeek

--- @param callbacks table|nil { afterRowRemove = function() end }
function NHS.CreateSavedSizesFrame(callbacks)
  callbacks = callbacks or {}

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
    NHS.EnsureSavedVars()
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
  NHS.SetupScrollFrameMouseWheel(shScroll)

  local shScrollChild = CreateFrame("Frame", nil, shScroll)
  shScrollChild:SetSize(308, 1)
  shScroll:SetScrollChild(shScrollChild)
  local shfCloseBtn = CreateFrame("Button", nil, shf, "UIPanelCloseButton")
  shfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  shfCloseBtn:SetScript("OnClick", function()
    shf:Hide()
  end)
  shf:Hide()

  local savedHouseRowBtns = {}

  local function refreshSavedHousesPanel()
    NHS.EnsureSavedVars()
    local rows = {}
    for key, idx in pairs(NHSV.houseSizes) do
      idx = tonumber(idx)
      if idx and idx >= 1 and idx <= #NHS.ROUND_PRESETS then
        local n = #rows + 1
        rows[n] = {
          key = key,
          idx = idx,
          label = NHSV.houseLabels[key] or key,
          ord = n,
        }
      end
    end
    local plotKey = NHS.PlotSortKeyFromSavedLabelOrKey
    table.sort(rows, function(a, b)
      local ka = plotKey and plotKey(a.label, a.key) or tostring(a.label)
      local kb = plotKey and plotKey(b.label, b.key) or tostring(b.label)
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
          NHS.EnsureSavedVars()
          NHSV.houseSizes[k] = nil
          NHSV.houseLabels[k] = nil
          NHSV.housePinCoords[k] = nil
          refreshSavedHousesPanel()
          local fn = callbacks.afterRowRemove
          if fn then
            fn()
          end
        end)
        savedHouseRowBtns[i] = btn
      end
      btn._rowKey = row.key
      btn:SetText(("%s — %s (remove)"):format(row.label, NHS.ROUND_PRESETS[row.idx].label))
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", 8, -y)
      btn:Show()
      y = y + 24
    end
    shScrollChild:SetHeight(math.max(y + 8, 1))
    shScroll:SetVerticalScroll(0)
  end

  return {
    frame = shf,
    refresh = refreshSavedHousesPanel,
  }
end
