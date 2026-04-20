--[[
  Main window show/hide and closing sub-panels. Load after Ui/MainFrame.lua (BuildMainFrame); see NeighborhoodHideSeek.toc (Ui/MainFrameToggle.lua).
  Escape: one UISpecialFrames proxy (named frame) so Esc closes floating panels first, then the main window (see InitEscapeCloseProxy).
]]

local NHS = NeighborhoodHideSeek
local B = assert(NHS.SeekerModeBridge, "NeighborhoodHideSeek.SeekerModeBridge missing (load order).")

local ESC_PROXY_NAME = "NHS_UISpecialEscapeProxy"

--- True if any floating panel tied to the main game window is visible (house list, options, pickers, etc.).
function NHS.AnyMainFloatingPanelOpen(UI)
  if not UI then
    return false
  end
  return (UI.houseListFrame and UI.houseListFrame:IsShown())
    or (UI.optionsFrame and UI.optionsFrame:IsShown())
    or (UI.pastSeekersFrame and UI.pastSeekersFrame:IsShown())
    or (UI.gameplayHousePickFrame and UI.gameplayHousePickFrame:IsShown())
    or (UI.gameplayPastHousesFrame and UI.gameplayPastHousesFrame:IsShown())
    or (UI.gameplayPastRoundsFrame and UI.gameplayPastRoundsFrame:IsShown())
    or (UI.gameplayRandomPickFrame and UI.gameplayRandomPickFrame:IsShown())
    or (UI.gameplaySeekerPickFrame and UI.gameplaySeekerPickFrame:IsShown())
    or (UI.howToPlayFrame and UI.howToPlayFrame:IsShown())
    or (UI.savedSizesFrame and UI.savedSizesFrame:IsShown())
end

--- Main window or any of its floating panels visible.
function NHS.AnyMainWindowOrPanelOpen(UI)
  return (UI and UI.frame and UI.frame:IsShown()) or NHS.AnyMainFloatingPanelOpen(UI)
end

--- Close floating panels only (matches X close on main window except the main frame stays open).
function NHS.HideMainFloatingPanels(UI)
  if not UI then
    return
  end
  if NHS.RestoreEmbeddedSettingsFrames then
    NHS.RestoreEmbeddedSettingsFrames()
  end
  if UI.houseListFrame and UI.houseListFrame:IsShown() then
    UI.houseListFrame:Hide()
  end
  if UI.syncViewHouseListButtonLabel then
    UI.syncViewHouseListButtonLabel()
  elseif UI.viewHouseListBtn then
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
  NHS.SyncEscapeProxyVisibility()
end

--- Full dismiss: all floating panels plus main frame (same as the main window X button).
function NHS.HideMainWindowFully(UI)
  NHS.HideMainFloatingPanels(UI)
  if UI and UI.frame then
    UI.frame:Hide()
  end
  NHS.SyncEscapeProxyVisibility()
end

--- Show the Esc proxy while any NHS main UI is open so the client routes Esc through UISpecialFrames.
function NHS.SyncEscapeProxyVisibility()
  local proxy = _G[ESC_PROXY_NAME]
  local proto = NHS._escapeProxyProtoHide
  if not proxy or not proto then
    return
  end
  local UI = B.getUI()
  if NHS.AnyMainWindowOrPanelOpen(UI) then
    if not proxy:IsShown() then
      proxy:Show()
    end
  else
    proto(proxy)
  end
end

--- One-time: invisible proxy in UISpecialFrames; Esc calls Hide() which closes panels first, then main.
function NHS.InitEscapeCloseProxy()
  if NHS._escapeProxyInitialized then
    return
  end
  NHS._escapeProxyInitialized = true

  local proxy = CreateFrame("Frame", ESC_PROXY_NAME, UIParent)
  proxy:SetSize(1, 1)
  proxy:ClearAllPoints()
  proxy:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  proxy:SetAlpha(0)
  proxy:EnableMouse(false)
  proxy:Hide()

  local protoHide = proxy.Hide
  NHS._escapeProxyProtoHide = protoHide

  function proxy:Hide()
    local UI = B.getUI()
    if not UI or not UI.frame then
      protoHide(self)
      return
    end
    if NHS.AnyMainFloatingPanelOpen(UI) then
      NHS.HideMainFloatingPanels(UI)
      return
    end
    if UI.frame:IsShown() then
      NHS.HideMainWindowFully(UI)
      return
    end
    protoHide(self)
  end

  local listed
  for _, name in ipairs(UISpecialFrames) do
    if name == ESC_PROXY_NAME then
      listed = true
      break
    end
  end
  if not listed then
    tinsert(UISpecialFrames, ESC_PROXY_NAME)
  end
end

--- After BuildMainFrame: keep the Esc proxy in sync whenever main or a satellite shows/hides.
function NHS.RegisterEscapeProxyFrameHooks(UI)
  NHS.InitEscapeCloseProxy()
  if UI._nhsEscapeProxyHooks then
    NHS.SyncEscapeProxyVisibility()
    return
  end
  UI._nhsEscapeProxyHooks = true

  local function hook(fr)
    if fr then
      fr:HookScript("OnShow", NHS.SyncEscapeProxyVisibility)
      fr:HookScript("OnHide", NHS.SyncEscapeProxyVisibility)
    end
  end

  hook(UI.frame)
  hook(UI.houseListFrame)
  hook(UI.optionsFrame)
  hook(UI.pastSeekersFrame)
  hook(UI.gameplayHousePickFrame)
  hook(UI.gameplayPastHousesFrame)
  hook(UI.gameplayPastRoundsFrame)
  hook(UI.gameplayRandomPickFrame)
  hook(UI.gameplaySeekerPickFrame)
  hook(UI.howToPlayFrame)
  hook(UI.savedSizesFrame)

  NHS.SyncEscapeProxyVisibility()
end

--- Build the main + satellite frames once (lazy until first toggle).
function NHS.EnsureMainFrameCreated()
  local UI = B.getUI()
  if not UI.frame then
    NHS.BuildMainFrame(UI)
  end
  return UI
end

local function toggleMainFrame()
  local ok, err = pcall(function()
    local UI = NHS.EnsureMainFrameCreated()
    if not UI.frame then
      print("|cffff0000[NHS]|r Window failed to create. Enable Lua errors (Esc → Options → Help).")
      return
    end
    if UI.frame:IsShown() then
      NHS.HideMainFloatingPanels(UI)
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

NHS.ToggleMainWindow = toggleMainFrame

NHS.InitEscapeCloseProxy()
