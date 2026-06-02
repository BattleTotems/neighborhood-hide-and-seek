--[[
  Toy & Seek — seeker hindrance test panel.
  Opens a floating window with a button for every individual effect so each one can
  be triggered in isolation without running a full game session.

  Access: /nhs testtas   (or the fallback: /run NHSTASTest())

  Remove this file (and its .toc entry) before a production release if desired.
  All functions here go through NHS.ToyAndSeek.TEST, which is set in ToyAndSeekMode.lua.
]]

local NHS = NeighborhoodHideSeek

-- ─── Layout helpers ──────────────────────────────────────────────────────────
local PANEL_W    = 300
local BTN_H      = 26
local BTN_GAP    = 4    -- gap between buttons in a row
local ROW_GAP    = 6    -- gap between rows
local SECTION_GAP= 10   -- gap above a new section label
local PAD_X      = 10
local PAD_TOP    = 36
local PAD_BOT    = 12

-- Two-column row width
local COL2_W = math.floor((PANEL_W - PAD_X * 2 - BTN_GAP) / 2)

-- Lay buttons out in a two-column grid, returning the new Y offset (distance from top).
-- parent  : frame to parent buttons into
-- buttons : list of { label, fn } pairs
-- yStart  : distance from the top of `parent` where the first row begins
-- Returns the new yStart after all rows.
local function nhsTASTestLayoutButtons(parent, buttons, yStart)
  local col = 0
  local rowY = yStart
  for i, b in ipairs(buttons) do
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(COL2_W, BTN_H)
    if col == 0 then
      btn:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -rowY)
    else
      btn:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X + COL2_W + BTN_GAP, -rowY)
    end
    btn:SetText(b.label)
    local fn = b.fn
    btn:SetScript("OnClick", function() if fn then fn() end end)
    col = col + 1
    if col == 2 then
      col = 0
      rowY = rowY + BTN_H + ROW_GAP
    end
  end
  if col ~= 0 then
    rowY = rowY + BTN_H + ROW_GAP  -- finish the incomplete last row
  end
  return rowY
end

-- Add a section label and return the new yStart.
local function nhsTASTestSectionLabel(parent, text, yStart)
  local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD_X, -(yStart + SECTION_GAP))
  lbl:SetText(text)
  lbl:Show()
  return yStart + SECTION_GAP + (lbl:GetStringHeight() or 14) + ROW_GAP
end

-- ─── Panel construction (lazy — built once on first open) ────────────────────
local nhsTASTestPanel

local function nhsTASTestBuildPanel()
  if nhsTASTestPanel then return nhsTASTestPanel end

  local T = NHS.ToyAndSeek and NHS.ToyAndSeek.TEST
  if not T then
    print("|cffff4444[NHS]|r Toy & Seek TEST table not found — is ToyAndSeekMode.lua loaded?")
    return nil
  end

  local panel = CreateFrame("Frame", "NHSToySeekTestPanel", UIParent, "BackdropTemplate")
  panel:SetFrameStrata("DIALOG")
  panel:SetFrameLevel(200)
  panel:SetWidth(PANEL_W)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
  panel:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
  panel:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  panel:SetClampedToScreen(true)
  panel:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  panel:SetBackdropColor(0, 0, 0, 0.92)

  -- Title
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, -12)
  title:SetText("|cff88ccffToying Around — Seeker Test|r")
  title:Show()

  -- Close button
  local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  closeBtn:SetSize(24, 24)
  closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)
  closeBtn:SetScript("OnClick", function() panel:Hide() end)

  -- ── Build content ─────────────────────────────────────────────────────────
  local yOff = PAD_TOP

  -- Full-width "Fire Random" button at the top
  local randomBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  randomBtn:SetSize(PANEL_W - PAD_X * 2, BTN_H + 4)
  randomBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X, -yOff)
  randomBtn:SetText("Fire Random Hindrance")
  randomBtn:SetScript("OnClick", function() if T.FireRandom then T.FireRandom() end end)
  yOff = yOff + BTN_H + 4 + ROW_GAP

  -- ── Hindrances section ───────────────────────────────────────────────────
  yOff = nhsTASTestSectionLabel(panel, "Hindrances", yOff)
  yOff = nhsTASTestLayoutButtons(panel, {
    { label = "Low Health",      fn = T.LowHealth       },
    { label = "Color Tint",      fn = T.ColorTint       },
    { label = "Achievement",     fn = T.FakeAchievement },
    { label = "/Chicken",        fn = T.Chicken         },
    { label = "World Map",       fn = T.WorldMap        },
    { label = "Screen Blind",    fn = T.Blind           },
  }, yOff)

  -- ── Art Popups section ───────────────────────────────────────────────────
  yOff = nhsTASTestSectionLabel(panel, "Art Popups", yOff)
  local popupBtns = {}
  if T.Popups and T.PopupLabels then
    for i, fn in ipairs(T.Popups) do
      popupBtns[#popupBtns + 1] = { label = T.PopupLabels[i] or ("Popup " .. i), fn = fn }
    end
  end
  yOff = nhsTASTestLayoutButtons(panel, popupBtns, yOff)

  -- ── Sound ID Tester ──────────────────────────────────────────────────────
  -- Enter any SoundKit or fileDataID; try both APIs to find the right one.
  yOff = nhsTASTestSectionLabel(panel, "Sound ID Tester", yOff)

  local idBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  idBox:SetSize(PANEL_W - PAD_X * 2 - 12, BTN_H)
  idBox:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD_X + 6, -yOff)
  idBox:SetAutoFocus(false)
  idBox:SetText("12345")
  idBox:SetNumeric(true)
  idBox:Show()
  yOff = yOff + BTN_H + ROW_GAP

  yOff = nhsTASTestLayoutButtons(panel, {
    {
      label = "PlaySound",
      fn = function()
        local id = tonumber(idBox:GetText())
        if id then
          pcall(PlaySound, id, "Dialog")
          print(("[NHS TASTest] PlaySound(%d, \"Dialog\")"):format(id))
        end
      end,
    },
    {
      label = "PlaySoundFile",
      fn = function()
        local id = tonumber(idBox:GetText())
        if id then
          pcall(PlaySoundFile, id, "Dialog")
          print(("[NHS TASTest] PlaySoundFile(%d, \"Dialog\")"):format(id))
        end
      end,
    },
  }, yOff)

  -- ── Finalize height ──────────────────────────────────────────────────────
  panel:SetHeight(yOff + PAD_BOT)

  nhsTASTestPanel = panel
  return panel
end

-- ─── Toggle ──────────────────────────────────────────────────────────────────
local function nhsTASTestToggle()
  local p = nhsTASTestBuildPanel()
  if not p then return end
  if p:IsShown() then
    p:Hide()
  else
    p:Show()
  end
end

-- ─── Register ────────────────────────────────────────────────────────────────
-- Exposed on the module so SlashCommands.lua and the fallback global can both reach it.
if NHS.ToyAndSeek then
  NHS.ToyAndSeek.ToggleTestPanel = nhsTASTestToggle
end

-- Fallback: /run NHSTASTest()
_G.NHSTASTest = nhsTASTestToggle
