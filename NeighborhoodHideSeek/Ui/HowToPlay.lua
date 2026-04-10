--[[
  “How to play” scrollable help window.
  Loaded after Core.lua; see NeighborhoodHideSeek.toc (Ui/HowToPlay.lua).
]]

local function houseSizePresetMinuteBullets()
  local pr = NeighborhoodHideSeek.ROUND_PRESETS
  if not pr or #pr == 0 then
    return "• Size presets set hiding and searching time for rounds (hover the preset buttons in the house list for details)."
  end
  local lines = {}
  for i = 1, #pr do
    local p = pr[i]
    lines[#lines + 1] = ("• %s: %d min hiding, %d min searching."):format(
      p.label,
      p.hideSec / 60,
      p.searchSec / 60
    )
  end
  return table.concat(lines, "\n")
end

local NHS_HOW_TO_PLAY_SECTIONS = {
  {
    title = "Overview",
    body = "Neighborhood Hide & Seek is to help you run a game of hide and seek with a group of friends in your neighborhood. The party/raid leader keeps the game running and moves through the phases. You can create your own saved list of houses to use or just play in the neighborhood you are standing in. In each round a house and seeker are picked. As a group decide if the group is hiding inside or outside of the house.",
  },
  {
    title = "Gameplay",
    body = table.concat({
      "• Phases: House selection -> Seeker selection -> Preparing -> Hiding -> Searching.",
      "• Information is shown in the compact HUD while a session or synced round is active.",
      "• Phase - House Selection: the leader picks which house the round uses.",
      "• Phase - Seeker Selection: during this phase, the leader picks a seeker from the group.",
      "• Phase - Preparing: during this phase, the whole group has a chance to move to the selected house and prepare for the next phase.",
      "• Phase - Hiding: during this phase, everyone but the seeker hides. This is started by a timer. Everyone has the set amount of time to hide before the seeker starts searching.",
      "• Phase - Searching: during this phase, the seeker searches. This is started by a timer. The seeker has the set amount of time to search before the round ends. The round ends early if the seeker finds all players. The designated seeker marks hiders found by targeting them (seeker mode turns on automatically; you can also toggle it under Options).",
    }, "\n"),
  },
  {
    title = "Game control (leader only)",
    body = table.concat({
      "• Start game session — begins a session. End game session stops it.",
      "• House selection — Select a house randomly or a specifically from either your saved list or the current neighborhood. Random house avoids repeats until everyone has been used once.",
      "• Seeker selection — Select a seeker randomly or a specifically from the group. Random seeker avoids repeats until everyone has been the seeker once.",
      "• In Preparing, use the hiding countdown presets (party countdown) to move to the next phase when the group is prepared. If a saved house is selected their size will be highlighted.",
      "• In Hiding, use the searching countdown presets to move to the next phase when the seeker starts searching. If a saved house is selected their size will be highlighted.",
      "• In Searching, when the searching countdown ends or when seeker finds all players, this can end the round and move to the next round.",
    }, "\n"),
  },
  {
    title = "Houses",
    body = table.concat({
      "• The house list of the current neighborhood is shown. Houses can be selected and saved with a size preset.",
      "• Houses can be removed or edited once saved to your saved list.",
      houseSizePresetsMinutesBullet(),
    }, "\n"),
  },
  {
    title = "Sync",
    body = "Game session, rounds, and phases are all automatically synced to all group members.",
  },
}

function NeighborhoodHideSeek.CreateHowToPlayFrame()
  local NHS = NeighborhoodHideSeek

  local function ensureSaved()
    if NHS.EnsureSavedVars then
      NHS.EnsureSavedVars()
    end
  end

  local htpf = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  htpf:SetSize(360, 420)
  htpf:SetClampedToScreen(true)
  htpf:SetMovable(true)
  htpf:EnableMouse(true)
  htpf:RegisterForDrag("LeftButton")
  htpf:SetScript("OnDragStart", function(self)
    self:StartMoving()
  end)
  htpf:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ensureSaved()
    local p, _, rp, x, y = self:GetPoint(1)
    NHSV.howToPlayFramePoint = { p, rp or "UIParent", x, y }
  end)
  htpf:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 8, right = 8, top = 8, bottom = 8 },
  })
  htpf:SetBackdropColor(0, 0, 0, 0.9)

  local htpfTitle = htpf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  htpfTitle:SetPoint("TOP", 0, -14)
  htpfTitle:SetText("How To Play")

  local htpScroll = CreateFrame("ScrollFrame", nil, htpf)
  htpScroll:SetPoint("TOPLEFT", 16, -42)
  htpScroll:SetSize(328, 358)
  NeighborhoodHideSeek.SetupScrollFrameMouseWheel(htpScroll)
  local htpScrollChild = CreateFrame("Frame", nil, htpScroll)
  htpScrollChild:SetSize(328, 1)
  htpScroll:SetScrollChild(htpScrollChild)

  local textWidth = 318
  local gapTitleToBody = 6
  local gapBetweenSections = 14
  local bottomPad = 12

  local yOffset = 0
  local n = #NHS_HOW_TO_PLAY_SECTIONS
  for i, sec in ipairs(NHS_HOW_TO_PLAY_SECTIONS) do
    local hdr = htpScrollChild:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    hdr:SetWidth(textWidth)
    hdr:SetJustifyH("LEFT")
    hdr:SetText(sec.title .. ":")
    hdr:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", 0, -yOffset)
    yOffset = yOffset + hdr:GetStringHeight() + gapTitleToBody

    local body = htpScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    body:SetWidth(textWidth)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(4)
    body:SetText(sec.body)
    body:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", 0, -yOffset)
    yOffset = yOffset + body:GetStringHeight()
    if i < n then
      yOffset = yOffset + gapBetweenSections
    end
  end

  htpScrollChild:SetHeight(math.max(yOffset + bottomPad, 1))
  htpScroll:SetVerticalScroll(0)

  local htpfCloseBtn = CreateFrame("Button", nil, htpf, "UIPanelCloseButton")
  htpfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  htpfCloseBtn:SetScript("OnClick", function()
    htpf:Hide()
  end)
  htpf:Hide()

  return { frame = htpf }
end
