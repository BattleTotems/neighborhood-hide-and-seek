--[[
  Full-screen grid + animated highlight for random house / random seeker picks.
  Returns frame + openAnimated + syncPhase for MainFrame wiring.
]]

local NHS = NeighborhoodHideSeek

function NHS.CreateRandomPickAnimationFrame()
  local NHS_RANDOM_GRID_COLS = 4
  local NHS_RANDOM_GRID_PAD = 5
  local NHS_RANDOM_GRID_CELL_H = 28
  local NHS_RANDOM_FRAME_W = 464
  local NHS_RANDOM_FRAME_H = 486
  local NHS_RANDOM_SCROLL_W = NHS_RANDOM_FRAME_W - 32
  local NHS_GRID_FAST_STEP_SEC = 0.05
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
    NHS.EnsureSavedVars()
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
  randomPickTitle:SetText("Random Selection")
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
  NeighborhoodHideSeek.SetupScrollFrameMouseWheel(randomGridScroll, 34)

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
    NHS.EnsureSavedVars()
    if NHSV.useRandomPickAnimation == false then
      onPicked(n > 1 and math.random(1, n) or 1)
      return
    end

    local winIdx, h0
    if n == 1 then
      winIdx, h0 = 1, 1
    else
      winIdx = math.random(1, n)
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
      local fastListPasses = math.min(4, math.max(1, math.floor(6 - math.ceil(n / 10))))
      if n <= 14 then
        fastListPasses = fastListPasses + 2 + math.random(0, 4)
      end
      randomPickFrame.nhsGridFastStepsLeft = fastListPasses * n
      local slowTotal = math.random(10, 18)
      randomPickFrame.nhsGridSlowTotalSteps = slowTotal
      randomPickFrame.nhsGridSlowMovesLeft = 0
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

  local function syncPhase(sess, pickHouse, pickGameMode, pickSeeker, useLeaderUi)
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
    elseif ctx == "game_mode" and not pickGameMode then
      randomPickFrame:Hide()
    elseif ctx == "seeker" and not pickSeeker then
      randomPickFrame:Hide()
    end
  end

  return {
    frame = randomPickFrame,
    openAnimated = openAnimatedRandomPick,
    syncPhase = syncPhase,
  }
end
