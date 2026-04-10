--[[
  Main window show/hide and closing sub-panels. Load after Ui/MainFrame.lua (BuildMainFrame); see NeighborhoodHideSeek.toc (Ui/MainFrameToggle.lua).
]]

local NHS = NeighborhoodHideSeek
local B = assert(NHS.SeekerModeBridge, "NeighborhoodHideSeek.SeekerModeBridge missing (load order).")

local function toggleMainFrame()
  local ok, err = pcall(function()
    local UI = B.getUI()
    if not UI.frame then
      NHS.BuildMainFrame(UI)
    end
    if not UI.frame then
      print("|cffff0000[NHS]|r Window failed to create. Enable Lua errors (Esc → Options → Help).")
      return
    end
    if UI.frame:IsShown() then
      if UI.houseListFrame and UI.houseListFrame:IsShown() then
        UI.houseListFrame:Hide()
      end
      if UI.viewHouseListBtn then
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
