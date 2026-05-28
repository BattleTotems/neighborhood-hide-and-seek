--[[
  “How to play” scrollable help window.
  Loaded after Core.lua; see NeighborhoodHideSeek.toc (Ui/HowToPlay.lua).
]]

local function houseSizePresetsMinutesBullet()
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
    body = NeighborhoodHideSeek.ABOUT_BLURB
      or "Neighborhood Hide & Seek is to help you run a game of hide and seek with a group of friends.",
  },
  {
    title = "Gameplay",
    body = table.concat({
      "• Phases: House Selection -> Game Mode Selection -> Seeker Selection -> Preparing -> Hiding -> Searching -> Reveal.",
      "• Information is shown in the compact HUD while a session or synced round is active.",
      "• Phase - House Selection: the house is selected.",
      "• Phase - Game Mode Selection: the game mode is selected.",
      "• Phase - Seeker Selection: the seeker is selected",
      "• Phase - Preparing: make sure everyone is at the selected house and ready to start.",
      "• Phase - Hiding: a timer starts allowing all hiders to go hide.",
      "• Phase - Searching: a timer starts letting the seeker(s) start finding any hider.",
      "• Phase - Reveal: any players that are still hidden can reveal themselves and show off their awesome hiding spots.",
    }, "\n"),
  },
  {
    title = "Game control (leader only)",
    body = table.concat({
      "• Start game session — begins a session. End game session stops it.",
      "• House list selection - select what list of houses will be used. This happens only once per game session."
      "• House selection — Select a house at random or from the list. Random house avoids repeats until every entry in that list has been used once.",
      "• Game mode selection — Select which game mode the round uses.",
      "• Seeker selection — Select a seeker at random or a from the group. Random seeker avoids repeats until everyone has been the seeker once.",
      "• Preparing - use the hiding countdown presets (party countdown) to move to the next phase when the group is prepared. If a saved house is selected their size will be highlighted.",
      "• Hiding - use the searching countdown presets to move to the next phase when the seeker starts searching. If a saved house is selected their size will be highlighted.",
      "• Searching - when the searching countdown ends or when seeker(s) finds all players it can move to the next phase.",
      "• Revealing - any players that are still hidden can reveal themselves and show off their awesome hiding spots.",
    }, "\n"),
  },
  {
    title = "Game Modes",
    body = table.concat({
      "• Normal: the default game mode.",
      "• Normal Plus: like normal, but every 10 seconds the closest player to the seeker will do an audible emote. Also, once there is one hider left, the seeker will be given hot and cold information to where the last hider is.",
      "• Hot and Cold: the seeker gets hot and cold information on how close they are to a hider. The search times are reduced.",
      "• Paired: the seeker is paired with another seeker. The search times are reduced.",
      "• Conquer: as the seeker finds players, those players become seekers. The search times are reduced.",
      "• Chosen One: one hider, the rest are seekers. The search times are reduced.",
      "• Lightning: hiders only get 30 seconds to hide. The search times are reduced.",
    }, "\n"),
  },
  {
    title = "Houses",
    body = table.concat({
      "• The house list of the current neighborhood is shown. Houses can be selected and saved with a size preset.",
      "• Houses can be removed or edited once saved to your saved list.",
      "• Subdivison cannot be automatically read, so it can be set manually for any guild neighborhoods that have multiple subdivisions.",
      "\n",
      "• Default times:",
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
  htpf._nhsCloseButton = htpfCloseBtn
  htpf:Hide()

  return { frame = htpf }
end
