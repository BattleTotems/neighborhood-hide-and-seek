--[[
  “How to play” scrollable help window.
  Loaded after Core.lua; see NeighborhoodHideSeek.toc (Ui/HowToPlay.lua).
]]

local NHS_HOW_TO_PLAY_TEXT = table.concat({
  "Overview",
  "Neighborhood Hide & Seek is for parties and raids in housing neighborhoods. Each round, one player is the seeker; everyone else hides. The party/raid leader keeps the game running and moves through the phases.",
  "",
  "Gameplay",
  "• Phases: House selection -> Seeker selection -> Preparing -> Hiding -> Searching.",
  "• Information is shown in the compact HUD while a session or synced round is active.",
  "• Phase - House Selection: the leader picks which house the round uses (saved list or current neighborhood list, per Options). Random house avoids repeats until everyone has been used once.",
  "• Phase - Seeker Selection: during this phase, the leader picks a seeker from the group.",
  "• Phase - Preparing: during this phase, the whole group has a chance to move to the selected house and prepare for the next phase.",
  "• Phase - Hiding: during this phase, everyone but the seeker hides. This is started by a timer. Everyone has the set amount of time to hide before the seeker starts searching.",
  "• Phase - Searching: during this phase, the seeker searches. This is started by a timer. The seeker has the set amount of time to search before the round ends. The round ends early if the seeker finds all players. The designated seeker marks hiders found by targeting them (seeker mode turns on automatically; you can also toggle it under Options).",
  "",
  "Game control (leader only)",
  "• Start game session — begins a session. End game session stops it.",
  "• House selection — Random house / view list / confirm house (same rotation idea as seekers). Past houses / past seekers are under the live gameplay details (phase, house, seeker, hidden, found) whenever a session is active.",
  "• Seeker selection — Random seeker, Select seeker (group list), and Confirm seeker (same row layout as house selection).",
  "• In Preparing, use the hiding countdown presets (party countdown) to move to the next phase when the group is prepared.",
  "• In Hiding, use the searching countdown presets to move to the next phase when the seeker starts searching.",
  "• In Searching, when the searching countdown ends or when seeker finds all players, this can end the round and move to the next round.",
  "",
  "Houses",
  "• Use the house list, map pin, and share actions to pick a plot and post a pin in chat.",
  "• Gameplay “house selection” in a session is separate from that list: it only chooses which house the round uses for the group (and syncs to others).",
  "• The main house list can still be used to browse plots and save sizes for saved-list picking.",
  "",
  "Sync",
  "Rounds, locked house, and found players sync through party/raid chat lines beginning with [NHS]. Group members see the same phases, house, and seeker as the leader.",
}, "\n")

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
  htpfTitle:SetText("How to play")

  local htpScroll = CreateFrame("ScrollFrame", nil, htpf)
  htpScroll:SetPoint("TOPLEFT", 16, -42)
  htpScroll:SetSize(328, 358)
  NeighborhoodHideSeek.SetupScrollFrameMouseWheel(htpScroll)
  local htpScrollChild = CreateFrame("Frame", nil, htpScroll)
  htpScrollChild:SetSize(328, 1)
  htpScroll:SetScrollChild(htpScrollChild)
  local howToPlayBody = htpScrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  howToPlayBody:SetPoint("TOPLEFT", htpScrollChild, "TOPLEFT", 0, 0)
  howToPlayBody:SetWidth(318)
  howToPlayBody:SetJustifyH("LEFT")
  howToPlayBody:SetJustifyV("TOP")
  howToPlayBody:SetSpacing(4)
  howToPlayBody:SetText(NHS_HOW_TO_PLAY_TEXT)
  htpScrollChild:SetHeight(math.max(howToPlayBody:GetStringHeight() + 12, 1))
  htpScroll:SetVerticalScroll(0)

  local htpfCloseBtn = CreateFrame("Button", nil, htpf, "UIPanelCloseButton")
  htpfCloseBtn:SetPoint("TOPRIGHT", -6, -6)
  htpfCloseBtn:SetScript("OnClick", function()
    htpf:Hide()
  end)
  htpf:Hide()

  return { frame = htpf }
end
