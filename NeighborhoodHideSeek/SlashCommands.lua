--[[
  /nhs and aliases; visitinfo delegates to HousingApi. Load after Ui/MainFrameToggle.lua.
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State

local SLASH_TOKEN = "NHIDESEEK"

local function chatImportSlashCommands()
  if ChatFrame_ImportAllListsToHash then
    pcall(ChatFrame_ImportAllListsToHash)
  end
end

local function nhsSlashHandler(msg, editBox)
  local trimmed = (msg or ""):match("^%s*(.-)%s*$") or ""
  local cmd = trimmed:match("^(%S+)") or ""
  cmd = cmd:lower()
  if cmd == "visitinfo" or cmd == "visitdebug" or cmd == "whyvisit" then
    pcall(function()
      NHS.HousingApi.PrintVisitDiagnostics(State.selectedEntry, State.selectedIndex)
    end)
    return
  end
  if NHS.ToggleMainWindow then
    NHS.ToggleMainWindow()
  end
end

local function registerSlashCommands()
  if SlashCmdList_AddSlashCommand then
    local added = pcall(SlashCmdList_AddSlashCommand, SLASH_TOKEN, nhsSlashHandler, "nhs", "neighborhoodhs", "nhseek")
    if added then
      chatImportSlashCommands()
      return
    end
  end
  _G.SlashCmdList[SLASH_TOKEN] = nhsSlashHandler
  _G["SLASH_" .. SLASH_TOKEN .. "1"] = "/nhs"
  _G["SLASH_" .. SLASH_TOKEN .. "2"] = "/neighborhoodhs"
  _G["SLASH_" .. SLASH_TOKEN .. "3"] = "/nhseek"
  chatImportSlashCommands()
end

NHS.ChatImportSlashCommands = chatImportSlashCommands

-- Fallback if slash routing still fails on your client: /run NHS_Toggle()
_G.NHS_Toggle = function()
  if NHS.ToggleMainWindow then
    NHS.ToggleMainWindow()
  end
end

registerSlashCommands()
