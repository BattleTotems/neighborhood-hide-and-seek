--[[
  Toy & Seek mode: during the searching phase, hiders get a button (30 s cooldown) that picks
  a random toy from the group's common pool, uses it to change their appearance, and fires a
  random hindrance at the seeker(s). Seekers have a 5 s global cooldown on receiving effects.
  Hiders' buff bars are hidden while searching so they can't accidentally right-click off their
  transformation. Load after BloodhoundMode.lua; before SessionHud.lua.

  NEEDS IN-GAME TESTING:
  - PlaySoundFile IDs (voice lines) — verify with /run PlaySoundFile(id,"Dialog")
  - Camera_OscillateUIShake() amplitude arg and availability
  - ToggleWorldMap() — may be combat-lockdown restricted on some builds
  - SecureActionButton programmatic Click() — works in non-combat (housing) zones
  - BuffFrame re-show: confirm Blizzard doesn't re-show it via UNIT_AURA
]]

local NHS = NeighborhoodHideSeek
local State = NHS.State
local Phase = NHS.Phase

-- ─── Toy list (64 items — all require player ownership) ──────────────────────
-- Item IDs sourced from Wowhead; verify any marked "?" in-game.
local TOY_LIST = {
  { id = 118937, name = "Gamon's Braid" },
  { id = 233202, name = "G.O.L.E.M. Jr." },
  { id = 191891, name = "Professor Chirpsnide's Im-PECK-able Harpy Disguise" },
  { id = 230924, name = "Spotlight Materializer 1000" },
  { id = 37254,  name = "Super Simian Sphere" },
  { id = 279052, name = "Ancient Amani Mask" },
  { id = 129165, name = "Barnacle-Encrusted Gem" },
  { id = 205418, name = "Blazing Shadowflame Cinder" },
  { id = 113096, name = "Bloodmane Charm" },
  { id = 64646,  name = "Bones of Transformation" },  -- ? changes UnitName; verify found marking keeps the real name
  { id = 170154, name = "Book of the Unshackled" },
  { id = 228698, name = "Candleflexer's Dumbbell" },
  { id = 275988, name = "Corrosive Victory" },
  { id = 130171, name = "Cursed Orb" },
  { id = 166544, name = "Dark Ranger's Spare Cowl" },
  { id = 129149, name = "Death's Door Charm" },
  { id = 108743, name = "Deceptia's Smoldering Boots" },
  { id = 212523, name = "Delicate Jade Parasol" },
  { id = 264413, name = "Dominating Victory" },
  { id = 276189, name = "Effigy of Dundun" },
  { id = 164373, name = "Enchanted Soup Stone" },
  { id = 244470, name = "Etheric Victory" },
  { id = 129113, name = "Faintly Glowing Flagon of Mead" },
  { id = 279021, name = "Forgotten Memento" },
  { id = 119211, name = "Golden Hearthstone Card: Lord Jaraxxus" },  -- ? changes UnitName; verify found marking keeps the real name
  { id = 163742, name = "Heartsbane Grimoire" },
  { id = 184223, name = "Helm of the Dominated" },
  { id = 252265, name = "Hexed Potatoad Mucus" },
  { id = 140325, name = "Home Made Party Mask" },
  { id = 225641, name = "Illusive Kobyss Lure" },
  { id = 43499,  name = "Iron Boot Flask" },
  { id = 198090, name = "Jar of Excess Slime" },
  { id = 116125, name = "Klikixx's Webspinner" },
  { id = 163750, name = "Kovork Kostume" },
  { id = 88566,  name = "Krastinov's Bag of Horrors" },
  { id = 228413, name = "Lampyridae Lure" },
  { id = 280820, name = "Loa-Blessed Victory" },
  { id = 118938, name = "Manastorm's Duplicator" },
  { id = 119092, name = "Moroes' Famous Polish" },
  { id = 141862, name = "Mote of Light" },
  { id = 138873, name = "Mystical Frosh Hat" },
  { id = 35275,  name = "Orb of the Sin'dorei" },
  { id = 268717, name = "Pango Plating" },
  { id = 130158, name = "Path of Elothir" },
  { id = 274921, name = "Pearl of Jubilation" },
  { id = 198409, name = "Personal Shell" },
  { id = 127864, name = "Personal Spotlight" },
  { id = 225910, name = "Pileus Delight" },
  { id = 108739, name = "Pretty Draenor Pearl" },
  { id = 119215, name = "Robo-Gnomebulator" },
  { id = 268728, name = "Saptor Salve" },
  { id = 141649, name = "Set of Matches" },
  { id = 147843, name = "Sira's Extra Cloak" },
  { id = 163736, name = "Spectral Visage" },
  { id = 203852, name = "Spore-Bound Essence" },
  { id = 208415, name = "Stasis Sand" },
  { id = 140160, name = "Stormforged Vrykul Horn" },
  { id = 200857, name = "Talisman of Sargha" },
  { id = 130147, name = "Thistleleaf Branch" },
  { id = 113375, name = "Vindicator's Armor Polish Kit" },
  { id = 152982, name = "Vixx's Chest of Tricks" },
  { id = 97919,  name = "Whole-Body Shrinka'" },
  { id = 64651,  name = "Wisp Amulet" },
  { id = 202022, name = "Yennu's Kite" },
}

-- ─── Constants ────────────────────────────────────────────────────────────────
local HIDER_BTN_COOLDOWN = 30   -- seconds between hider button presses
local SEEKER_GLOBAL_CD   = 5    -- seconds between hindrance effects on seeker

-- ─── Module state ─────────────────────────────────────────────────────────────
local btnCooldownEnd        = 0      -- GetTime() when hider button is next usable
local nhsTASHindranceQueue  = 0      -- pending seeker hindrances waiting to fire
local nhsTASQueueDraining   = false  -- true while the drain timer chain is active
local nhsTASHindranceHistory = {}  -- last 4 hindrance picks; avoids recent repeats
local buffBarHidden  = false
local nhsTASClearGen = 0             -- bumped on clear so pending hindrance timers no-op
local nhsTASActiveRoots = {}         -- hindrance root frames to hide on clear
local nhsTASWasSearching = false     -- detects the transition out of the searching phase

-- ─── Role predicates ──────────────────────────────────────────────────────────
local function nhsTASIsActive()
  local id = NHS.GetEffectiveGameModeId and NHS.GetEffectiveGameModeId()
  return id == "toy_and_seek"
end

local function nhsTASIsHider()
  if not nhsTASIsActive() then return false end
  if State.phase ~= Phase.SEARCHING then return false end
  if NHS.LocalPlayerIsDesignatedSeeker and NHS.LocalPlayerIsDesignatedSeeker() then return false end
  -- Once found, the player is no longer hiding.
  local myKey = NHS.LocalPlayerSortKey and NHS.LocalPlayerSortKey()
  if myKey and State.foundSet[myKey] then return false end
  return true
end

local function nhsTASIsSeeker()
  if not nhsTASIsActive() then return false end
  if State.phase ~= Phase.SEARCHING then return false end
  return NHS.LocalPlayerIsDesignatedSeeker and NHS.LocalPlayerIsDesignatedSeeker()
end

-- ─── Toy picker ───────────────────────────────────────────────────────────────
-- Pick a random toy from the player's own collection that isn't on item cooldown.
local function nhsTASPickToy()
  local available = {}
  for _, toy in ipairs(TOY_LIST) do
    if PlayerHasToy and PlayerHasToy(toy.id) then
      available[#available + 1] = toy
    end
  end
  if #available == 0 then return nil end
  for i = #available, 2, -1 do    -- Fisher-Yates shuffle
    local j = math.random(i)
    available[i], available[j] = available[j], available[i]
  end
  for _, toy in ipairs(available) do
    local _, dur = C_Item.GetItemCooldown(toy.id)
    if not (dur and dur > 1.5) then
      -- /use item: does nothing for an item not yet cached, so load it before the click.
      C_Item.RequestLoadItemDataByID(toy.id)
      return toy
    end
  end
  return nil  -- every owned toy is on cooldown
end

-- ─── Buff bar management ──────────────────────────────────────────────────────
local function nhsTASHideBuffBar()
  if BuffFrame and not buffBarHidden then
    BuffFrame:Hide()
    buffBarHidden = true
  end
end

local function nhsTASShowBuffBar()
  if BuffFrame and buffBarHidden then
    BuffFrame:Show()
    buffBarHidden = false
  end
end

-- ─── Seeker hindrances ────────────────────────────────────────────────────────

-- Hindrance: Low health frame flash.
local function nhsTASHindranceLowHealth()
  if UIFrameFlash and LowHealthFrame then
    UIFrameFlash(LowHealthFrame, 0.5, 0.5, 10, false, 0.2, 0)
  end
  pcall(PlaySoundFile, 548880, "Master")  -- Fel Reaver horn (fileDataID)
end

-- Hindrance: Screen color tint (random color, fades out).
-- One voice line fires at random from the pool each time.
local nhsTintFrame
local TINT_VOICE_LINES = {
  54460,   -- Malfurion  "So says the shadow of Xavius"           (NPC 100652, Darkheart Thicket)
  17126,   -- Putricide  "Good news! I fixed the slime pipes!"    (IC_Putricide_SlimeFlow01 — verify in-game)
  28292,   -- Uncle Gao  "Yes! Yes, yes! No! PEPPERS!"            (NPC 59074, Stormstout Brewery)
  21921,   -- Ozruk      "Break yourselves upon my body!"          (VO_SC_Ozruk_Event03, The Stonecore)
  65819,   -- Duskwatch  "An illusion! What are you hiding?"       (VO_SC_Duskwatch_Orbitist, Suramar)
  270304,  -- Gallywix   "Nice job, morons!"                       (VO_1110_Jastor_Gallywix, Liberation of Undermine)
}
local function nhsTASHindranceColorTint()
  pcall(PlaySound, TINT_VOICE_LINES[math.random(#TINT_VOICE_LINES)], "Dialog")
  if not nhsTintFrame then
    nhsTintFrame = CreateFrame("Frame", nil, UIParent)
    nhsTintFrame:SetAllPoints(UIParent)
    nhsTintFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    nhsTintFrame:SetFrameLevel(95)
    local t = nhsTintFrame:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    nhsTintFrame._tex = t
    nhsTintFrame:Hide()
  end
  local colors = { {1,0,0}, {0,0.8,0}, {0,0,1}, {1,0.8,0}, {0.8,0,1}, {0,0.8,0.8} }
  local c = colors[math.random(#colors)]
  nhsTintFrame._tex:SetColorTexture(c[1], c[2], c[3], 0.45)
  nhsTintFrame:SetAlpha(0)
  nhsTintFrame:Show()
  UIFrameFadeIn(nhsTintFrame, 2.0, 0, 1)
  local gen = nhsTASClearGen
  C_Timer.After(6.0, function()
    if gen ~= nhsTASClearGen then return end
    UIFrameFadeOut(nhsTintFrame, 2.0, 1, 0)
    C_Timer.After(2.1, function()
      if gen ~= nhsTASClearGen then return end
      nhsTintFrame:Hide()
    end)
  end)
end

-- Confetti burst that rains down the whole screen, played with the achievement banner.
local function nhsTASConfetti()
  local PIECES   = 90
  local DURATION = 5.0
  local COLORS = {
    {1, 0.2, 0.2}, {1, 0.8, 0.1}, {0.2, 0.9, 0.3}, {0.2, 0.6, 1}, {0.9, 0.3, 1},
  }

  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(97)
  root:Show()
  nhsTASActiveRoots[#nhsTASActiveRoots + 1] = root

  local sw = GetScreenWidth()
  local sh = GetScreenHeight()

  local pieces = {}
  for i = 1, PIECES do
    local c = COLORS[math.random(#COLORS)]
    local tex = root:CreateTexture(nil, "ARTWORK")
    tex:SetSize(math.random(8, 14), math.random(14, 22))
    tex:SetColorTexture(c[1], c[2], c[3], 0.95)
    pieces[i] = {
      tex   = tex,
      x     = math.random() * sw,
      y     = sh * (1 + math.random() * 0.4),  -- staggered start above the screen
      fall  = sh * (0.3 + math.random() * 0.2),
      phase = math.random() * math.pi * 2,
      spin  = (math.random() - 0.5) * 8,
    }
  end

  local elapsed = 0
  root:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed >= DURATION then
      self:SetScript("OnUpdate", nil)
      self:Hide()
      return
    end
    for _, p in ipairs(pieces) do
      p.tex:ClearAllPoints()
      p.tex:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT",
          p.x + math.sin(elapsed * 3 + p.phase) * 30, p.y - p.fall * elapsed)
      p.tex:SetRotation(p.phase + p.spin * elapsed)
    end
  end)
end

-- Hindrance: Fake achievement banner.
local nhsAchieveFrame
local nhsAchieveQueue  = {}
local nhsAchieveActive = false
local ACHIEVE_TAUNTS = {
  "Found: Zero Hiders",
  "Still Looking…",
  "Master of Being Fooled",
  "Did Not Find the Hider",
  "They're Still Out There",
}
local function nhsAchieveShowNext()
  if #nhsAchieveQueue == 0 then nhsAchieveActive = false; return end
  nhsAchieveActive = true
  local taunt = table.remove(nhsAchieveQueue, 1)
  if not nhsAchieveFrame then
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(840, 160)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(96)
    f:SetBackdrop({
      bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\AchievementFrame\\UI-Achievement-Category-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 12, right = 12, top = 12, bottom = 12 },
    })
    f:SetBackdropColor(0.07, 0.05, 0.01, 0.96)
    f:SetBackdropBorderColor(1, 0.82, 0, 1)
    local iconBorder = f:CreateTexture(nil, "BACKGROUND")
    iconBorder:SetSize(120, 120)
    iconBorder:SetPoint("LEFT", f, "LEFT", 16, 0)
    iconBorder:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(80, 80)
    icon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\Achievement_General_StayClassy")
    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetFont("Fonts\\FRIZQT__.TTF", 30, "OUTLINE")
    hdr:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 20, -12)
    hdr:SetText("|cffffdd00Achievement Earned!|r")
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    sub:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -10)
    f._sub = sub
    f:Hide()
    nhsAchieveFrame = f
  end
  nhsAchieveFrame._sub:SetText(taunt)
  nhsAchieveFrame:SetAlpha(1)
  nhsAchieveFrame:Show()
  nhsTASConfetti()
  -- Play achievement toast sound (or level-up ding as fallback)
  local acheiveSound = (SOUNDKIT and SOUNDKIT.UI_ACHIEVEMENT_TOAST) or 888
  pcall(PlaySound, acheiveSound, "Master")
  local gen = nhsTASClearGen
  C_Timer.After(4.0, function()
    if gen ~= nhsTASClearGen then return end
    UIFrameFadeOut(nhsAchieveFrame, 0.8, 1, 0)
    C_Timer.After(0.9, function()
      if gen ~= nhsTASClearGen then return end
      nhsAchieveFrame:Hide()
      nhsAchieveShowNext()
    end)
  end)
end
local function nhsTASHindranceFakeAchievement()
  nhsAchieveQueue[#nhsAchieveQueue + 1] = ACHIEVE_TAUNTS[math.random(#ACHIEVE_TAUNTS)]
  if not nhsAchieveActive then nhsAchieveShowNext() end
end

-- Hindrance: /chicken emote on the seeker (visible to everyone nearby), with a shaking
-- chicken icon near each corner of the screen.
local function nhsTASHindranceChicken()
  if not InCombatLockdown() then pcall(DoEmote, "CHICKEN") end

  local ICON_SIZE = 128
  local MARGIN    = 40
  local DURATION  = 6.0
  local SHAKE     = 10    -- max pixels of jitter each way
  local INTERVAL  = 0.04  -- seconds between jitter steps

  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(96)
  root:Show()
  nhsTASActiveRoots[#nhsTASActiveRoots + 1] = root

  local corners = {
    { point = "TOPLEFT",     x =  MARGIN, y = -MARGIN },
    { point = "TOPRIGHT",    x = -MARGIN, y = -MARGIN },
    { point = "BOTTOMLEFT",  x =  MARGIN, y =  MARGIN },
    { point = "BOTTOMRIGHT", x = -MARGIN, y =  MARGIN },
  }
  for _, c in ipairs(corners) do
    local tex = root:CreateTexture(nil, "ARTWORK")
    tex:SetSize(ICON_SIZE, ICON_SIZE)
    tex:SetPoint(c.point, root, c.point, c.x, c.y)
    tex:SetTexture("Interface\\Icons\\Spell_Magic_PolymorphChicken")
    c.tex = tex
  end

  local elapsed, sinceShake = 0, 0
  root:SetScript("OnUpdate", function(self, dt)
    elapsed    = elapsed + dt
    sinceShake = sinceShake + dt
    if elapsed >= DURATION then
      self:SetScript("OnUpdate", nil)
      self:Hide()
      return
    end
    if sinceShake < INTERVAL then return end
    sinceShake = 0
    for _, c in ipairs(corners) do
      c.tex:ClearAllPoints()
      c.tex:SetPoint(c.point, root, c.point,
          c.x + math.random(-SHAKE, SHAKE), c.y + math.random(-SHAKE, SHAKE))
    end
  end)
end

-- Hindrance: Force world map open.
local function nhsTASHindranceWorldMap()
  if not InCombatLockdown() then pcall(ToggleWorldMap) end
end

-- Hindrance: Force achievement frame open.
local function nhsTASHindranceAchievements()
  if not InCombatLockdown() then pcall(ToggleAchievementFrame) end
end

-- Hindrance: Open the chat input box — any keystroke the seeker presses types into chat.
local function nhsTASHindranceOpenChat()
  if not InCombatLockdown() then
    pcall(ChatFrame_OpenChat, "", DEFAULT_CHAT_FRAME)
  end
end

-- Hindrance: Open all bags.
local function nhsTASHindranceOpenBags()
  if not InCombatLockdown() then pcall(OpenAllBags) end
end

-- Hindrance: "Want to join in on the fun?" — offers the seeker a toy to use.
-- Uses the same toy-pick logic as the hider button but does NOT broadcast a strike.
-- Stays up 20 s or until the button is clicked.
local function nhsTASHindranceToyInvite()
  if InCombatLockdown() then return end
  local toy = nhsTASPickToy()
  if not toy then return end  -- seeker owns no compatible toys; skip silently

  pcall(PlaySoundFile, 641976, "Dialog")

  local sh = GetScreenHeight()

  local root = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  root:SetSize(340, 130)
  root:SetPoint("CENTER", UIParent, "CENTER", 0, sh * 0.20)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(96)
  root:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
  })
  root:SetBackdropColor(0, 0, 0, 0.88)
  root:Show()
  nhsTASActiveRoots[#nhsTASActiveRoots + 1] = root

  local lbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  lbl:SetPoint("TOP", root, "TOP", 0, -18)
  lbl:SetText("|cffffff00Want to join in on the fun?|r")
  lbl:Show()

  local btn = CreateFrame("Button", nil, root,
      "SecureActionButtonTemplate,UIPanelButtonTemplate")
  btn:SetSize(220, 44)
  btn:SetPoint("BOTTOM", root, "BOTTOM", 0, 18)
  btn:SetText("Use Toy!")
  btn:SetAttribute("type", "macro")
  btn:SetAttribute("macrotext", "/use item:" .. toy.id)
  btn:RegisterForClicks("AnyDown", "AnyUp")
  btn:SetScript("PostClick", function(self, button, down)
    if down then return end
    root:Hide()
  end)
  btn:Show()

  -- Gentle vertical wiggle on the popup frame
  local wiggleT = 0
  local baseY   = sh * 0.20
  local wiggler = CreateFrame("Frame", nil, root)
  wiggler:SetScript("OnUpdate", function(self, dt)
    wiggleT = wiggleT + dt
    local off = math.sin(wiggleT * 2.0) * 6
    root:ClearAllPoints()
    root:SetPoint("CENTER", UIParent, "CENTER", 0, baseY + off)
  end)

  C_Timer.After(20.0, function()
    if root:IsShown() then
      UIFrameFadeOut(root, 0.5, 1, 0)
      C_Timer.After(0.6, function() root:Hide() end)
    end
  end)
end

-- Hindrance: Growing button — must be clicked 10 times to dismiss.
-- Each press resets to base size and jumps to a new random position.
local function nhsTASHindranceGrowingButton()
  local PRESSES   = 10
  local BASE_W    = 240
  local BASE_H    = 64
  local GROW_RATE = 0.04   -- fractional scale increase per second
  local MAX_SCALE = 2.5

  local sw = GetScreenWidth()
  local sh = GetScreenHeight()

  -- Random center position that keeps the BASE-size button fully on screen.
  local function randomPos()
    local margin = 30
    local minX = math.floor(BASE_W / 2) + margin
    local maxX = math.floor(sw - BASE_W / 2) - margin
    local minY = math.floor(BASE_H / 2) + margin
    local maxY = math.floor(sh - BASE_H / 2) - margin
    return math.random(minX, maxX), math.random(minY, maxY)
  end

  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(98)
  root:Show()
  nhsTASActiveRoots[#nhsTASActiveRoots + 1] = root

  local presses     = PRESSES
  local growElapsed = 0

  local btn = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
  btn:SetSize(BASE_W, BASE_H)
  btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
  local bx, by = randomPos()
  btn:SetPoint("CENTER", root, "BOTTOMLEFT", bx, by)
  btn:Show()

  local function refreshText()
    btn:SetText(string.format("Press to close (%d)", presses))
  end
  refreshText()

  btn:SetScript("OnClick", function(self)
    presses = presses - 1
    if presses <= 0 then
      root:Hide()
      return
    end
    growElapsed = 0
    btn:SetSize(BASE_W, BASE_H)
    local nx, ny = randomPos()
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", root, "BOTTOMLEFT", nx, ny)
    refreshText()
  end)

  -- Grow the button each frame until capped
  local updater = CreateFrame("Frame", nil, root)
  updater:SetScript("OnUpdate", function(self, dt)
    growElapsed = growElapsed + dt
    local scale = math.min(1 + growElapsed * GROW_RATE, MAX_SCALE)
    btn:SetSize(BASE_W * scale, BASE_H * scale)
  end)
end

-- Hindrance: Screen blind (white flash in and out).
local nhsBlindFrame
local function nhsTASHindranceBlind()
  if not nhsBlindFrame then
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(97)
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(0, 0, 0, 1)
    f:Hide()
    nhsBlindFrame = f
  end
  -- Voice line fires immediately so the seeker can hear the warning before darkness hits.
  pcall(PlaySound, 11466, "Dialog")  -- Illidan "You are not prepared!"
  local gen = nhsTASClearGen
  C_Timer.After(2.0, function()      -- black screen 2 s after the voice line starts
    if gen ~= nhsTASClearGen then return end
    nhsBlindFrame:SetAlpha(0)
    nhsBlindFrame:Show()
    UIFrameFadeIn(nhsBlindFrame, 0.25, 0, 1)
    C_Timer.After(1.2, function()    -- hold full black 0.5 s longer (was 0.7)
      if gen ~= nhsTASClearGen then return end
      UIFrameFadeOut(nhsBlindFrame, 1.0, 1, 0)
      C_Timer.After(1.1, function()
        if gen ~= nhsTASClearGen then return end
        nhsBlindFrame:Hide()
      end)
    end)
  end)
end


-- Hindrance: Locked camera — re-asserts the zoom every tick for a few seconds so the
-- seeker can't just scroll back; a one-shot CameraZoomIn/Out or CVar set alone wouldn't
-- stick. A generation token guards the delayed release so overlapping triggers (a new
-- lock firing before the previous one's timer expires) don't let the old timer cancel
-- the new lock early.
local nhsCameraLockTicker
local nhsCameraLockLabel
local nhsCameraLockGen = 0
local CAMERA_LOCK_DURATION = 12.0

local function nhsTASCameraLockLabel()
  if nhsCameraLockLabel then return nhsCameraLockLabel end
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(420, 40)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetFrameLevel(99)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetAllPoints()
  fs:SetJustifyH("CENTER")
  f._fs = fs
  f:Hide()
  nhsCameraLockLabel = f
  return f
end

local function nhsTASCameraLockStart(zoomFn, text)
  if nhsCameraLockTicker then nhsCameraLockTicker:Cancel() end
  nhsCameraLockGen = nhsCameraLockGen + 1
  local myGen = nhsCameraLockGen

  local lbl = nhsTASCameraLockLabel()
  lbl._fs:SetText(text)
  lbl:SetAlpha(0)
  lbl:Show()
  UIFrameFadeIn(lbl, 0.4, 0, 1)

  nhsCameraLockTicker = C_Timer.NewTicker(0.1, function() pcall(zoomFn, 50) end)
  C_Timer.After(CAMERA_LOCK_DURATION, function()
    if myGen ~= nhsCameraLockGen then return end  -- superseded by a newer lock
    if nhsCameraLockTicker then
      nhsCameraLockTicker:Cancel()
      nhsCameraLockTicker = nil
    end
    UIFrameFadeOut(lbl, 0.4, 1, 0)
    C_Timer.After(0.5, function()
      if myGen == nhsCameraLockGen then lbl:Hide() end
    end)
  end)
end

-- Hindrance: Locked close camera — snaps to first person and holds it.
local function nhsTASHindranceLockedCloseCamera()
  nhsTASCameraLockStart(CameraZoomIn, "|cffff4444Camera Locked: First Person!|r")
end

-- Hindrance: Locked far camera — snaps to max zoom-out and holds it.
local function nhsTASHindranceLockedFarCamera()
  nhsTASCameraLockStart(CameraZoomOut, "|cffff4444Camera Locked: Max Zoom!|r")
end

-- ─── Silly art popups ─────────────────────────────────────────────────────────
-- Each popup creates a fresh root frame so cleanup is trivial (just hide the root).

-- Shared fade-out and cleanup after a popup has run.
local function nhsTASPopupClose(root, delay)
  nhsTASActiveRoots[#nhsTASActiveRoots + 1] = root
  C_Timer.After(delay or 3.0, function()
    -- UIFrameFadeOut re-shows its frame, so skip popups already cleared.
    if root and root:IsShown() then
      UIFrameFadeOut(root, 0.5, 1, 0)
      C_Timer.After(0.6, function() root:Hide() end)
    end
  end)
end

-- Popup 1 — A Turtle Made It to the Water
local function nhsTASPopupTurtle()
  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(110)
  root:Show()

  -- "A turtle made it to the water!" voice line — fileDataID 2015890.
  pcall(PlaySoundFile, 2015890, "Dialog")

  local sw = GetScreenWidth()
  local sh = GetScreenHeight()

  -- Turtle icon — file data ID 1738657 (verified in-game).
  local TURTLE_SIZE = 256
  local turtleY  = (sh - TURTLE_SIZE) / 2
  local turtleX2 = sw * 0.72 - TURTLE_SIZE / 2
  local iconFrm = CreateFrame("Frame", nil, root)
  iconFrm:SetSize(TURTLE_SIZE, TURTLE_SIZE)
  iconFrm:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 40, turtleY)
  iconFrm:SetFrameLevel(root:GetFrameLevel() + 5)  -- swims on top of the water
  local iconTex = iconFrm:CreateTexture(nil, "ARTWORK")
  iconTex:SetAllPoints()
  iconTex:SetTexture(1738657)
  iconFrm:Show()

  -- Water tiles fill the screen from the destination X to the right edge. Rows and
  -- columns come from the actual screen size so any resolution or UI scale is covered.
  local WALL_SIZE = 240
  local wallX = sw * 0.72
  local rows = math.ceil(sh / WALL_SIZE)
  local cols = math.ceil((sw - wallX) / WALL_SIZE)
  for c = 1, cols do
    for r = 1, rows do
      local wf = CreateFrame("Frame", nil, root)
      wf:SetSize(WALL_SIZE, WALL_SIZE)
      wf:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT",
          wallX + (c - 1) * WALL_SIZE, (r - 1) * WALL_SIZE)
      local wt = wf:CreateTexture(nil, "ARTWORK")
      wt:SetAllPoints()
      wt:SetTexture(135861)  -- water icon — file data ID verified in-game
      wf:Show()
    end
  end

  -- Slide turtle from left toward the wall of water
  local duration = 2.8
  local elapsed  = 0
  iconFrm:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    local pct  = math.min(elapsed / duration, 1)
    local ease = 1 - (1 - pct) * (1 - pct)  -- ease-out
    self:ClearAllPoints()
    self:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 40 + (turtleX2 - 40) * ease, turtleY)
    if pct >= 1 then self:SetScript("OnUpdate", nil) end
  end)

  local lbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  lbl:SetPoint("CENTER", root, "CENTER", 0, sh * 0.18)
  lbl:SetText("|cff00ff88A turtle made it to the water!|r")
  lbl:Show()

  nhsTASPopupClose(root, 3.5)
end

-- Popup 2 — LEEEEEEROY JENKINS!
local function nhsTASPopupLeeroy()
  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(110)
  root:Show()

  local sw = GetScreenWidth()
  local sh = GetScreenHeight()
  local midY = sh * 0.44

  -- Big text
  local lbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  lbl:SetPoint("CENTER", root, "CENTER", 0, sh * 0.15)
  lbl:SetText("|cffff4400LEEEEEEROY JENKINS!|r")
  lbl:Show()

  -- Warrior icon
  local wFrm = CreateFrame("Frame", nil, root)
  wFrm:SetSize(80, 80)
  wFrm:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", -10, midY)
  local wTex = wFrm:CreateTexture(nil, "ARTWORK")
  wTex:SetAllPoints()
  wTex:SetTexture("Interface\\Icons\\ClassIcon_Warrior")
  wFrm:Show()

  -- Ten whelp targets
  local whelps = {}
  local clusterX = sw * 0.58
  for i = 1, 10 do
    local wf = CreateFrame("Frame", nil, root)
    wf:SetSize(56, 56)
    local ox = (i - 5.5) * 28          -- spread across ~252 px, centered on cluster
    local oy = ((i - 1) % 3 - 1) * 22 -- three-row stagger
    wf:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", clusterX + ox, midY + oy)
    local wt = wf:CreateTexture(nil, "ARTWORK")
    wt:SetAllPoints()
    wt:SetTexture("Interface\\Icons\\inv_misc_head_dragon_01")
    wf:Show()
    whelps[i] = {
      frame  = wf,
      startX = clusterX + ox,
      startY = midY + oy,
      vx     = (math.random() - 0.5) * 320,
      vy     = math.random() * 200 + 80,
    }
  end

  -- Warrior charge animation
  local chargeTime = 0.75
  local elapsed    = 0
  local impacted   = false
  -- Whelp aggro sound fires 0.5 s before impact so it feels like the whelps
  -- notice the warrior charging in rather than reacting after the hit.
  C_Timer.After(chargeTime - 0.5, function()
    pcall(PlaySound, 428, "Master")  -- whelp aggro (DragonWhelpAggro)
  end)
  wFrm:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    local pct = math.min(elapsed / chargeTime, 1)
    self:ClearAllPoints()
    self:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", -10 + (clusterX + 10) * pct, midY)
    if pct >= 1 and not impacted then
      impacted = true
      self:SetScript("OnUpdate", nil)
      -- Scatter whelps — keep flying until the popup fades (~4 s)
      for _, w in ipairs(whelps) do
        local scatterE = 0
        w.frame:SetScript("OnUpdate", function(sf, sdt)
          scatterE = scatterE + sdt
          sf:ClearAllPoints()
          -- Low gravity (30) so they stay visible and chaotic longer
          local nx = w.startX + w.vx * scatterE
          local ny = w.startY + w.vy * scatterE - 30 * scatterE * scatterE
          sf:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", nx, ny)
          if scatterE > 4.0 then sf:SetScript("OnUpdate", nil) end
        end)
      end
    end
  end)

  nhsTASPopupClose(root, 3.5)
end

-- Giant Xal'atath framing.
local nhsXalGiant = {
  fov = 0.55,   -- lower = bigger
  -- Her size follows the screen height, so the offsets are fractions of it too.
  x   = -0.216, -- negative = left
  y   = -0.417, -- negative = down
}

local function nhsTASXalGiantApply(scene)
  -- The scene clips the model, so it must still cover the whole screen after the shift.
  -- Scaling both sides by one factor keeps the aspect ratio, so only the zoom changes.
  local sw = GetScreenWidth()
  local sh = GetScreenHeight()
  local x = nhsXalGiant.x * sh
  local y = nhsXalGiant.y * sh
  local cover = math.max(1 + 2 * math.abs(x) / sw, 1 + 2 * math.abs(y) / sh)
  scene:SetSize(sw * cover, sh * cover)
  scene:ClearAllPoints()
  scene:SetPoint("CENTER", UIParent, "CENTER", x, y)
  -- Zoom with the camera: up close, her float animation swings her size around.
  -- Widening by the same factor cancels the bigger scene, so fov alone sets her size.
  scene:SetCameraFieldOfView(2 * math.atan(math.tan(nhsXalGiant.fov / 2) * cover / 1.5))
end

-- Popup 3 — Xal'atath Whispers
-- Easter egg: 10% of the time she is giant, with her feet at the middle of the screen.
-- forceGiant is for the test panel.
local function nhsTASPopupXalatath(forceGiant)
  local giant = forceGiant or math.random(10) == 1

  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(110)
  root:Show()

  local sw = GetScreenWidth()
  local sh = GetScreenHeight()
  local cX = sw * 0.5
  local cY = sh * 0.5 + 30

  -- Play Xal'atath whisper voice line
  pcall(PlaySound, 126854, "Dialog")  -- Xal'atath whisper — verify ID in-game

  -- Deep void dim overlay
  local dim = root:CreateTexture(nil, "BACKGROUND")
  dim:SetAllPoints()
  dim:SetColorTexture(0, 0, 0.06, 0.72)
  dim:Show()

  -- Xal'atath's 3D model. The scene's default camera sits at the origin looking down +X,
  -- so X is distance, and a negative Z lowers her into view — tune both in-game.
  local XAL_MODEL_FILE = 5159886
  local XAL_MODEL_ANIM = 1138    -- floating idle
  local XAL_MODEL_SIZE = 440
  local XAL_MODEL_DIST = 5
  local XAL_MODEL_Z    = -1.1
  local XAL_FADE_IN    = 0.8
  local mainFrm = CreateFrame("ModelScene", nil, root)
  if giant then
    nhsTASXalGiantApply(mainFrm)
  else
    mainFrm:SetSize(XAL_MODEL_SIZE, XAL_MODEL_SIZE)
    mainFrm:SetPoint("CENTER", root, "BOTTOMLEFT", cX, cY)
  end
  mainFrm:Show()
  local actor = mainFrm:CreateActor()
  actor:SetModelByFileID(XAL_MODEL_FILE)
  actor:SetAnimation(XAL_MODEL_ANIM)
  if giant then
    actor:SetPosition(XAL_MODEL_DIST, 0, 0)
  else
    actor:SetPosition(XAL_MODEL_DIST, 0, XAL_MODEL_Z)
  end
  actor:SetYaw(math.pi)          -- face the camera
  actor:SetAlpha(0)

  -- Xal'atath's artifact dagger (item 128827 — Xal'atath, Blade of the Black Empire),
  -- the last orb in the circle. Lazy-loads via GET_ITEM_INFO_RECEIVED below so it
  -- appears correctly even on first trigger.
  local XAL_ITEM_ID = 128827
  local XAL_FALLBACK = "Interface\\Icons\\inv_weapon_shortblade_92"
  C_Item.RequestLoadItemDataByID(XAL_ITEM_ID)
  local _, _, _, _, _, _, _, _, _, xalIcon = C_Item.GetItemInfo(XAL_ITEM_ID)

  -- Orbiting void icons
  local ORB_COUNT  = 7
  local ORB_RADIUS = 170
  local ORB_SIZE   = 36
  local ORB_ICONS  = {
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Spell_Shadow_Lifedrain",
    "Interface\\Icons\\Spell_Shadow_Painspike",
    "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
    "Interface\\Icons\\Spell_Shadow_MindBlast",
    "Interface\\Icons\\Spell_Shadow_Possession",
    xalIcon or XAL_FALLBACK,
  }
  local orbs = {}
  for i = 1, ORB_COUNT do
    local of = CreateFrame("Frame", nil, root)
    of:SetSize(ORB_SIZE, ORB_SIZE)
    of:SetPoint("CENTER", root, "BOTTOMLEFT", cX, cY)
    local ot = of:CreateTexture(nil, "ARTWORK")
    ot:SetAllPoints()
    ot:SetTexture(ORB_ICONS[i] or "Interface\\Icons\\Spell_Shadow_ShadowWordPain")
    if i < ORB_COUNT then ot:SetVertexColor(0.6, 0.2, 0.9) end  -- dagger keeps its colors
    of:SetAlpha(0)
    of:Show()
    UIFrameFadeIn(of, 0.5, 0, 0.85)
    orbs[i] = { frame = of, tex = ot, angle = (i - 1) * (2 * math.pi / ORB_COUNT) }
  end

  if not xalIcon then
    local xalEvt = CreateFrame("Frame", nil, root)
    xalEvt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    xalEvt:SetScript("OnEvent", function(self, _, id)
      if id == XAL_ITEM_ID then
        local _, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(XAL_ITEM_ID)
        if icon then orbs[ORB_COUNT].tex:SetTexture(icon) end
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
      end
    end)
  end

  -- Fade the model + orbit orbs
  local pulse     = 0
  local ORB_SPEED = 0.7  -- radians per second
  mainFrm:SetScript("OnUpdate", function(self, dt)
    pulse = pulse + dt
    -- The actor's alpha is driven here so the root's fade-out reaches the model too.
    actor:SetAlpha(math.min(pulse / XAL_FADE_IN, 1) * root:GetAlpha())
    for _, orb in ipairs(orbs) do
      local a  = orb.angle + pulse * ORB_SPEED
      local ox = cX + math.cos(a) * ORB_RADIUS
      local oy = cY + math.sin(a) * ORB_RADIUS
      orb.frame:ClearAllPoints()
      orb.frame:SetPoint("CENTER", root, "BOTTOMLEFT", ox, oy)
    end
  end)

  -- Text — fade in well below the model so it's never covered by orbitals
  local lbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  lbl:SetPoint("CENTER", root, "BOTTOMLEFT", cX, cY - 250)
  lbl:SetWidth(520)
  lbl:SetJustifyH("CENTER")
  lbl:SetText(
    "|cffcc66ffXal'atath whispers:|r\n" ..
    "|cffddaaff\"They cannot hide from you forever...\nor can they?\"|r"
  )
  lbl:SetAlpha(0)
  lbl:Show()
  UIFrameFadeIn(lbl, 1.4, 0, 1)

  nhsTASPopupClose(root, 4.2)
end

-- Popup 4 — March of the Murlocs
local function nhsTASPopupMurlocs()
  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(110)
  root:Show()

  local sw    = GetScreenWidth()
  local sh    = GetScreenHeight()
  local COUNT = 16
  local SIZE  = 96
  local SPEED = sh * 0.40  -- px per second upward (fast enough to fully exit top)

  -- Murloc sound at start
  pcall(PlaySound, 416, "Master")

  -- Label
  local lbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  lbl:SetPoint("TOP", root, "TOP", 0, -70)
  lbl:SetText("|cff00ccffMrglglglgl!|r")
  lbl:Show()

  -- Shuffled vertical stagger: build a pool of evenly-spaced depths with per-slot jitter,
  -- then Fisher-Yates shuffle so each column gets a random starting depth — breaks the
  -- diagonal-line artifact that results from arithmetic spacing + uniform speed.
  local staggerPool = {}
  for j = 1, COUNT do
    staggerPool[j] = (j - 1) * sh * 0.05 + math.random() * sh * 0.04
  end
  for j = COUNT, 2, -1 do                          -- Fisher-Yates shuffle
    local k = math.random(j)
    staggerPool[j], staggerPool[k] = staggerPool[k], staggerPool[j]
  end

  -- Horizontal positions spread evenly across screen with slight random jitter.
  local icons = {}
  for i = 1, COUNT do
    local f = CreateFrame("Frame", nil, root)
    f:SetSize(SIZE, SIZE)
    local xPos   = (sw / COUNT) * (i - 0.5) + (math.random() - 0.5) * (sw / COUNT * 0.5)
    local startY = -(SIZE + staggerPool[i])         -- random depth from shuffled pool
    f:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", xPos - SIZE / 2, startY)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(656557)  -- murloc icon — file data ID verified in-game
    f:Show()
    icons[i] = {
      frame  = f,
      xPos   = xPos - SIZE / 2,
      startY = startY,
      phase  = math.random() * math.pi * 2,
    }
  end

  -- Worst-case stagger ≈ (COUNT-1)*sh*0.05 + sh*0.04 ≈ 0.79sh (COUNT=16).
  -- Distance to exit top = sh + SIZE + 0.79sh ≈ 1.79sh + SIZE.
  -- At SPEED = sh*0.40: time ≈ 4.5 + SIZE/(0.40sh) ≈ 4.7 s.
  -- Fade starts at 5.0 s → all murlocs are off the top before fade begins.
  local elapsed = 0
  local updater = CreateFrame("Frame", nil, root)
  updater:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    for _, ic in ipairs(icons) do
      local y   = ic.startY + SPEED * elapsed
      local bob = ic.xPos + math.sin(elapsed * 3.5 + ic.phase) * 18
      ic.frame:ClearAllPoints()
      ic.frame:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", bob, y)
    end
  end)

  nhsTASPopupClose(root, 5.0)
end

-- Popup 5 — [Thunderfury, Blessed Blade of the Windseeker]
local function nhsTASPopupThunderfury()
  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(110)
  root:Show()

  -- Chat ping fires immediately — as if someone just linked the item at you in Trade.
  pcall(PlaySound, SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081, "Master")

  local function typeOut(str, target, idx, onDone)
    idx = idx or 1
    if idx > #str then if onDone then onDone() end; return end
    target:SetText(str:sub(1, idx))
    C_Timer.After(0.055, function() typeOut(str, target, idx + 1, onDone) end)
  end

  -- "Did someone say..." — high above the icon so it never overlaps (icon is 176px tall,
  -- center at y=0, so top edge is at y=+88; we sit at y=+145 for clear separation).
  local preLbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  preLbl:SetPoint("CENTER", root, "CENTER", 0, 145)
  preLbl:SetTextColor(0.9, 0.9, 0.7)
  preLbl:SetText("")
  preLbl:Show()

  -- Sword icon (item 19019) — 176x176, centered on screen, hidden until pre-text done.
  local sfFrm = CreateFrame("Frame", nil, root)
  sfFrm:SetSize(176, 176)
  sfFrm:SetPoint("CENTER", root, "CENTER", 0, 0)
  local sfTex = sfFrm:CreateTexture(nil, "ARTWORK")
  sfTex:SetAllPoints()
  local _, _, _, _, _, _, _, _, _, sfP = C_Item.GetItemInfo(19019)
  sfTex:SetTexture(sfP or "Interface\\Icons\\inv_sword_39")
  sfFrm:SetAlpha(0)
  sfFrm:Show()

  -- Glow (proportionally larger than icon)
  local glow = sfFrm:CreateTexture(nil, "BACKGROUND")
  glow:SetSize(220, 220)
  glow:SetPoint("CENTER", sfFrm, "CENTER")
  glow:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
  glow:SetVertexColor(1, 0.78, 0, 0.65)
  glow:Show()

  -- Faster rotation: 0.8 rad/s
  local rotE = 0
  sfFrm:SetScript("OnUpdate", function(self, dt)
    rotE = rotE + dt
    sfTex:SetRotation(rotE * 0.8)
  end)

  -- Item name label — below the icon (icon bottom edge at y=0-88=-88; label at -130)
  local mainLbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  mainLbl:SetPoint("CENTER", root, "CENTER", 0, -130)
  mainLbl:SetTextColor(1, 0.82, 0)
  mainLbl:SetText("")
  mainLbl:Show()

  -- Sequence: type "Did someone say..." → pause → fade in icon → type item link
  local PRE_TEXT  = "Did someone say..."
  local FULL_TEXT = "[Thunderfury, Blessed Blade of the Windseeker]"

  C_Timer.After(0.4, function()
    typeOut(PRE_TEXT, preLbl, 1, function()
      C_Timer.After(0.35, function()
        if not root:IsShown() then return end
        UIFrameFadeIn(sfFrm, 0.4, 0, 1)
        pcall(PlaySound, 13006, "Master")  -- Shaman Thunderstorm impact
        C_Timer.After(0.5, function()
          typeOut(FULL_TEXT, mainLbl)
        end)
      end)
    end)
  end)

  nhsTASPopupClose(root, 9.5)
end


-- ─── Class quiz data ──────────────────────────────────────────────────────────
local CLASS_ICON_PATH = {
  WARRIOR     = "Interface\\Icons\\ClassIcon_Warrior",
  PALADIN     = "Interface\\Icons\\ClassIcon_Paladin",
  HUNTER      = "Interface\\Icons\\ClassIcon_Hunter",
  ROGUE       = "Interface\\Icons\\ClassIcon_Rogue",
  PRIEST      = "Interface\\Icons\\ClassIcon_Priest",
  SHAMAN      = "Interface\\Icons\\ClassIcon_Shaman",
  MAGE        = "Interface\\Icons\\ClassIcon_Mage",
  WARLOCK     = "Interface\\Icons\\ClassIcon_Warlock",
  DRUID       = "Interface\\Icons\\ClassIcon_Druid",
  DEATHKNIGHT = "Interface\\Icons\\ClassIcon_DeathKnight",
  MONK        = "Interface\\Icons\\ClassIcon_Monk",
  DEMONHUNTER = "Interface\\Icons\\ClassIcon_DemonHunter",
  EVOKER      = "Interface\\Icons\\ClassIcon_Evoker",
}

-- Three iconic spells per class; spell IDs used with GetSpellTexture to fetch art.
local CLASS_QUIZ_DATA = {
  { name = "Warrior",      tag = "WARRIOR",     spells = {100,    6673,   12294}  },  -- Charge, Battle Shout, Mortal Strike
  { name = "Paladin",      tag = "PALADIN",      spells = {642,    633,    20271}  },  -- Divine Shield, Lay on Hands, Judgment
  { name = "Hunter",       tag = "HUNTER",       spells = {19434,  2643,   5384}   },  -- Aimed Shot, Multi-Shot, Feign Death
  { name = "Rogue",        tag = "ROGUE",        spells = {1784,   53,     2094}   },  -- Stealth, Backstab, Blind
  { name = "Priest",       tag = "PRIEST",       spells = {2061,   589,    605}    },  -- Flash Heal, SW:Pain, Mind Control
  { name = "Shaman",       tag = "SHAMAN",       spells = {188443, 51505,  8042}   },  -- Chain Lightning, Lava Burst, Earth Shock
  { name = "Mage",         tag = "MAGE",         spells = {133,    118,    1953}   },  -- Fireball, Polymorph, Blink
  { name = "Warlock",      tag = "WARLOCK",      spells = {172,    686,    5740}   },  -- Corruption, Shadow Bolt, Rain of Fire
  { name = "Druid",        tag = "DRUID",        spells = {8921,   768,    774}    },  -- Moonfire, Cat Form, Rejuvenation
  { name = "Death Knight", tag = "DEATHKNIGHT",  spells = {49576,  42650,  49998}  },  -- Death Grip, Army of the Dead, Death Strike
  { name = "Monk",         tag = "MONK",         spells = {100780, 115057, 115080} },  -- Tiger's Palm, Flying Serpent Kick, Touch of Death
  { name = "Demon Hunter", tag = "DEMONHUNTER",  spells = {191427, 195072, 188499} },  -- Metamorphosis, Fel Rush, Blade Dance
  { name = "Evoker",       tag = "EVOKER",       spells = {375087, 356995, 355913} },  -- Dragonrage, Disintegrate, Emerald Blossom
}

-- Shared typeout: reveals str character-by-character into a FontString.
local function nhsTASTypeOut(str, target, idx, onDone)
  idx = idx or 1
  if idx > #str then if onDone then onDone() end; return end
  target:SetText(str:sub(1, idx))
  C_Timer.After(0.055, function() nhsTASTypeOut(str, target, idx + 1, onDone) end)
end

-- Popup 6 — Class Quiz
local function nhsTASPopupClassQuiz()
  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(110)
  root:Show()

  local sw  = GetScreenWidth()
  local sh  = GetScreenHeight()
  local cX  = sw * 0.5
  local cY  = sh * 0.5

  local cls = CLASS_QUIZ_DATA[math.random(#CLASS_QUIZ_DATA)]

  -- Triangle layout: icon 1 at top-center, icons 2+3 at bottom-left/right.
  -- The centroid of this triangle lands near (cX, cY+60), where the text sits.
  -- The class-icon reveal below the triangle completes a 4-point diamond.
  local ICON_SIZE = 108
  local R_HORIZ   = 165  -- horizontal spread for the two bottom icons
  local R_TOP     = 200  -- height of top icon above cY

  local iconData = {
    { cx = cX,           cy = cY + R_TOP, si = 1, phase = 0                 },
    { cx = cX - R_HORIZ, cy = cY - 10,   si = 2, phase = math.pi * 2 / 3  },
    { cx = cX + R_HORIZ, cy = cY - 10,   si = 3, phase = math.pi * 4 / 3  },
  }

  for _, ic in ipairs(iconData) do
    local frm = CreateFrame("Frame", nil, root)
    frm:SetSize(ICON_SIZE, ICON_SIZE)
    frm:SetPoint("CENTER", root, "BOTTOMLEFT", ic.cx, ic.cy)
    local tex = frm:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture(C_Spell.GetSpellTexture(cls.spells[ic.si])
        or "Interface\\Icons\\INV_Misc_QuestionMark")
    frm:Show()
    ic.frame = frm
  end

  -- Gentle vertical wiggle — 120° phase offset keeps each icon out of sync
  local wiggleT = 0
  local wiggler = CreateFrame("Frame", nil, root)
  wiggler:SetScript("OnUpdate", function(self, dt)
    wiggleT = wiggleT + dt
    for _, ic in ipairs(iconData) do
      local off = math.sin(wiggleT * 2.0 + ic.phase) * 5
      ic.frame:ClearAllPoints()
      ic.frame:SetPoint("CENTER", root, "BOTTOMLEFT", ic.cx, ic.cy + off)
    end
  end)

  -- Question — sits above the triangle centroid (~cY+60)
  local qLbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  qLbl:SetPoint("CENTER", root, "BOTTOMLEFT", cX, cY + 95)
  qLbl:SetText("|cffffff00What class uses these?|r")
  qLbl:Show()

  -- Answer typed out below the question once the seeker picks correctly
  local ansLbl = root:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  ansLbl:SetPoint("CENTER", root, "BOTTOMLEFT", cX, cY + 65)
  ansLbl:SetText("")
  if RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls.tag] then
    local cc = RAID_CLASS_COLORS[cls.tag]
    ansLbl:SetTextColor(cc.r, cc.g, cc.b)
  end
  ansLbl:Show()

  -- Class icon — diamond bottom point, replaces the answer buttons on a correct pick
  local revealFrm = CreateFrame("Frame", nil, root)
  revealFrm:SetSize(ICON_SIZE, ICON_SIZE)
  revealFrm:SetPoint("CENTER", root, "BOTTOMLEFT", cX, cY - 140)
  local revealTex = revealFrm:CreateTexture(nil, "ARTWORK")
  revealTex:SetAllPoints()
  revealTex:SetTexture(CLASS_ICON_PATH[cls.tag] or "Interface\\Icons\\INV_Misc_QuestionMark")
  revealFrm:SetAlpha(0)
  revealFrm:Show()

  -- Stays up until the seeker picks correctly (or the hindrances are cleared).
  nhsTASActiveRoots[#nhsTASActiveRoots + 1] = root

  local BTN_W, BTN_H, BTN_OFF = 240, 56, 130
  local QUESTION = "|cffffff00What class uses these?|r"
  local WRONG_LOCKOUT = 3.0
  local btns = {}
  local lastWrong

  -- Puts the right class and a new wrong class on the buttons in a random order.
  local function setAnswers()
    local wrong
    repeat
      wrong = CLASS_QUIZ_DATA[math.random(#CLASS_QUIZ_DATA)]
    until wrong ~= cls and wrong ~= lastWrong
    lastWrong = wrong
    local right = math.random(2)
    btns[right]:SetText(cls.name)
    btns[right]._correct = true
    btns[3 - right]:SetText(wrong.name)
    btns[3 - right]._correct = false
  end

  local function onAnswer(self)
    if self._correct then
      btns[1]:Hide()
      btns[2]:Hide()
      qLbl:SetText("|cff00ff88Correct!|r")
      pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN or 857, "Master")
      UIFrameFadeIn(revealFrm, 0.5, 0, 1)
      nhsTASTypeOut(cls.name, ansLbl)
      nhsTASPopupClose(root, 3.0)
      return
    end
    -- Wrong answer: lock the buttons, then ask again with a different wrong class.
    btns[1]:Disable()
    btns[2]:Disable()
    qLbl:SetText("|cffff4444Wrong! Think about what you've done...|r")
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_FAILED or 847, "Master")
    C_Timer.After(WRONG_LOCKOUT, function()
      if not root:IsShown() then return end
      qLbl:SetText(QUESTION)
      setAnswers()
      btns[1]:Enable()
      btns[2]:Enable()
    end)
  end

  for i, side in ipairs({ -1, 1 }) do
    local btn = CreateFrame("Button", nil, root, "UIPanelButtonTemplate")
    btn:SetSize(BTN_W, BTN_H)
    btn:SetPoint("CENTER", root, "BOTTOMLEFT", cX + side * BTN_OFF, cY - 140)
    btn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    btn:SetScript("OnClick", onAnswer)
    btn:Show()
    btns[i] = btn
  end
  setAnswers()
end

-- Popup 7 — Hide & Seek Tier List
local function nhsTASPopupTierList()
  local root = CreateFrame("Frame", nil, UIParent)
  root:SetAllPoints(UIParent)
  root:SetFrameStrata("FULLSCREEN_DIALOG")
  root:SetFrameLevel(110)
  root:Show()

  local sw = GetScreenWidth()
  local sh = GetScreenHeight()
  local cX = sw * 0.5

  pcall(PlaySound, 6913, "Master")

  -- Seeker is "player"; everyone else in the party or raid is a hider
  local seekerClass, seekerTag = UnitClass("player")
  local hiders = {}
  local unitPrefix = IsInRaid() and "raid" or "party"
  for i = 1, GetNumGroupMembers() do
    local unit = unitPrefix .. i
    if UnitExists(unit) and not UnitIsUnit(unit, "player") then
      local localName, tag = UnitClass(unit)
      if tag then hiders[#hiders + 1] = { name = localName, tag = tag } end
    end
  end
  for i = #hiders, 2, -1 do    -- shuffle so tier assignment feels random
    local j = math.random(i)
    hiders[i], hiders[j] = hiders[j], hiders[i]
  end

  -- Round-robin hiders across S / A / B; C is always empty (intentional troll row)
  local slots  = { S = {}, A = {}, B = {}, C = {}, D = { { name = seekerClass, tag = seekerTag } } }
  local cycle  = { "S", "A", "B" }
  for i, cls in ipairs(hiders) do
    local t = cycle[((i - 1) % 3) + 1]
    slots[t][#slots[t] + 1] = cls
  end

  local title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  title:SetPoint("CENTER", root, "BOTTOMLEFT", cX, sh * 0.71)
  title:SetText("|cffffff00Hide & Seek Tier List|r")
  title:Show()

  local ROW_H   = 64
  local ICON_SZ = 48
  local LABEL_W = 52
  local FRAME_W = 560
  local ROW_GAP = 6
  local frameX  = cX - FRAME_W / 2
  local startY  = sh * 0.62

  local tierDefs = {
    { key = "S", lc = {1,   0.84, 0,   0.95}, bc = {0.35, 0.30, 0,    0.85} },
    { key = "A", lc = {0.2, 0.9,  0.2, 0.95}, bc = {0.07, 0.30, 0.07, 0.85} },
    { key = "B", lc = {0.2, 0.5,  1,   0.95}, bc = {0.07, 0.18, 0.40, 0.85} },
    { key = "C", lc = {0.9, 0.50, 0.1, 0.95}, bc = {0.36, 0.18, 0.04, 0.85} },
    { key = "D", lc = {0.6, 0.6,  0.6, 0.95}, bc = {0.22, 0.05, 0.05, 0.85} },
  }

  for rowIdx, td in ipairs(tierDefs) do
    local rowY   = startY - (rowIdx - 1) * (ROW_H + ROW_GAP)
    local lc, bc = td.lc, td.bc
    local classes = slots[td.key] or {}
    -- Large raids squeeze the icons together so a row never runs past the frame.
    local iconStep = math.min(ICON_SZ + 6,
        (FRAME_W - LABEL_W - 16 - ICON_SZ) / math.max(#classes - 1, 1))

    local lbg = root:CreateTexture(nil, "BACKGROUND")
    lbg:SetSize(LABEL_W, ROW_H)
    lbg:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", frameX, rowY)
    lbg:SetColorTexture(lc[1], lc[2], lc[3], lc[4])

    local ltxt = root:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ltxt:SetPoint("CENTER", root, "BOTTOMLEFT", frameX + LABEL_W / 2, rowY + ROW_H / 2)
    ltxt:SetText(td.key)
    ltxt:SetTextColor(0, 0, 0, 1)
    ltxt:Show()

    local cbg = root:CreateTexture(nil, "BACKGROUND")
    cbg:SetSize(FRAME_W - LABEL_W, ROW_H)
    cbg:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", frameX + LABEL_W, rowY)
    cbg:SetColorTexture(bc[1], bc[2], bc[3], bc[4])

    for ci, cls in ipairs(classes) do
      local entryX = frameX + LABEL_W + 8 + (ci - 1) * iconStep
      local entryY = rowY + (ROW_H - ICON_SZ) / 2
      local iconFrm = CreateFrame("Frame", nil, root)
      iconFrm:SetSize(ICON_SZ, ICON_SZ)
      iconFrm:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", entryX, entryY)
      local iconTex = iconFrm:CreateTexture(nil, "ARTWORK")
      iconTex:SetAllPoints()
      iconTex:SetTexture(CLASS_ICON_PATH[cls.tag] or "Interface\\Icons\\INV_Misc_QuestionMark")
      iconFrm:Show()
    end
  end

  nhsTASPopupClose(root, 6.0)
end

-- ─── Hindrance cleanup ────────────────────────────────────────────────────────
local function nhsTASHideNow(f)
  if not f then return end
  if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(f) end
  f:Hide()
end

-- Ends every running hindrance and drops queued ones. Blizzard panels the hindrances
-- opened (map, bags, achievements, chat) are left for the player to close.
local function nhsTASClearHindrances()
  nhsTASClearGen = nhsTASClearGen + 1
  nhsTASHindranceQueue = 0

  for _, root in ipairs(nhsTASActiveRoots) do nhsTASHideNow(root) end
  wipe(nhsTASActiveRoots)

  nhsCameraLockGen = nhsCameraLockGen + 1
  if nhsCameraLockTicker then
    nhsCameraLockTicker:Cancel()
    nhsCameraLockTicker = nil
  end
  nhsTASHideNow(nhsCameraLockLabel)

  wipe(nhsAchieveQueue)
  nhsAchieveActive = false
  nhsTASHideNow(nhsAchieveFrame)
  nhsTASHideNow(nhsTintFrame)
  nhsTASHideNow(nhsBlindFrame)
  if UIFrameFlashStop and LowHealthFrame then pcall(UIFrameFlashStop, LowHealthFrame) end
end

-- ─── Hindrance dispatcher ─────────────────────────────────────────────────────
-- 20 options: 13 effect hindrances + 7 art popups (each popup is its own slot).
-- History tracks the last 4 picks so no hindrance repeats too soon.
local function nhsTASFireHindrance()
  -- Avoid repeating any of the last 4 hindrances. With 20 options and 4
  -- excluded there are always at least 16 valid choices, so this loop exits fast.
  local pick
  repeat
    pick = math.random(20)
  until pick ~= nhsTASHindranceHistory[1] and pick ~= nhsTASHindranceHistory[2]
     and pick ~= nhsTASHindranceHistory[3] and pick ~= nhsTASHindranceHistory[4]
  nhsTASHindranceHistory[1] = nhsTASHindranceHistory[2]
  nhsTASHindranceHistory[2] = nhsTASHindranceHistory[3]
  nhsTASHindranceHistory[3] = nhsTASHindranceHistory[4]
  nhsTASHindranceHistory[4] = pick

  if     pick == 1  then nhsTASHindranceLowHealth()
  elseif pick == 2  then nhsTASHindranceColorTint()
  elseif pick == 3  then nhsTASHindranceFakeAchievement()
  elseif pick == 4  then nhsTASHindranceChicken()
  elseif pick == 5  then nhsTASHindranceWorldMap()
  elseif pick == 6  then nhsTASHindranceBlind()
  elseif pick == 7  then nhsTASHindranceAchievements()
  elseif pick == 8  then nhsTASHindranceOpenChat()
  elseif pick == 9  then nhsTASHindranceOpenBags()
  elseif pick == 10 then nhsTASHindranceToyInvite()
  elseif pick == 11 then nhsTASHindranceGrowingButton()
  elseif pick == 12 then nhsTASHindranceLockedCloseCamera()
  elseif pick == 13 then nhsTASHindranceLockedFarCamera()
  elseif pick == 14 then nhsTASPopupTurtle()
  elseif pick == 15 then nhsTASPopupLeeroy()
  elseif pick == 16 then nhsTASPopupXalatath()
  elseif pick == 17 then nhsTASPopupMurlocs()
  elseif pick == 18 then nhsTASPopupThunderfury()
  elseif pick == 19 then nhsTASPopupClassQuiz()
  elseif pick == 20 then nhsTASPopupTierList()
  end
end

-- ─── Strike broadcast / receive ───────────────────────────────────────────────
local function nhsTASBroadcastStrike()
  if not IsInGroup() then return end
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
  local ch = IsInRaid() and "RAID"
    or (LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT")
    or "PARTY"
  pcall(C_ChatInfo.SendAddonMessage, NHS.AddonMessagePrefix, "[NHS] Toy Strike:", ch)
end

-- Drain one hindrance from the queue, then schedule itself again if more remain.
-- Always reschedules via C_Timer so late-arriving strikes during the grace window
-- are handled without starting a second drain chain.
local function nhsTASQueueDrain()
  if nhsTASHindranceQueue <= 0 then
    nhsTASQueueDraining = false
    return
  end
  nhsTASHindranceQueue = nhsTASHindranceQueue - 1
  nhsTASFireHindrance()
  C_Timer.After(SEEKER_GLOBAL_CD, nhsTASQueueDrain)
end

-- Called by GroupSync for each "[NHS] Toy Strike:" message.
-- Enqueues the hindrance; starts the drain chain if one isn't already running.
local function nhsTASApplyStrike(senderName, text)
  if not text:match("^%[NHS%]%s*Toy Strike:") then return false end
  if not nhsTASIsSeeker() then return true end
  nhsTASHindranceQueue = nhsTASHindranceQueue + 1
  if not nhsTASQueueDraining then
    nhsTASQueueDraining = true
    nhsTASQueueDrain()
  end
  return true
end

-- ─── Hider button ─────────────────────────────────────────────────────────────
-- tasVisBtn IS the SecureActionButtonTemplate — the player clicks it directly so
-- WoW treats it as a hardware event and fires the secure action.
--
-- The button lives inside the session HUD so the player only needs to reposition
-- one frame. nhsTASInitHudButton is called from SessionHud.lua's nhsInitSessionHud.
-- Until that call happens, tasVisBtn and tasCooldown remain nil.

local tasVisBtn   = nil   -- assigned by nhsTASInitHudButton
local tasCooldown = nil   -- assigned by nhsTASInitHudButton

-- Pre-pick the toy and prime the button's macrotext.  SetAttribute is allowed from
-- tainted Lua outside combat lockdown, so this is safe in a housing zone.
-- Called on hover and after each successful press to keep the selection fresh.
local nhsTASBtnToy = nil
local function nhsTASRefreshBtnToy()
  if not tasVisBtn then return end  -- button not yet initialised
  if InCombatLockdown() then return end
  if GetTime() < btnCooldownEnd then
    -- Still on the hider cooldown; leave macrotext empty so a click does nothing.
    nhsTASBtnToy = nil
    tasVisBtn:SetAttribute("macrotext", "")
    return
  end
  nhsTASBtnToy = nhsTASPickToy()
  tasVisBtn:SetAttribute("macrotext",
      nhsTASBtnToy and ("/use item:" .. nhsTASBtnToy.id) or "")
end

-- Called from SessionHud.lua once the session HUD frame exists.
-- Creates tasVisBtn as a child of that frame so it moves with it.
--
-- Positioning note: SecureActionButtonTemplate frames cannot be repositioned from
-- tainted Lua via ClearAllPoints/SetPoint without producing a blank protection error
-- in modern WoW.  The button is given a FIXED anchor at creation time (safe — same
-- pattern as the original standalone frame).  nhsSessionHudUpdate only Show()/Hide()s
-- it; the HUD height calculation automatically reserves the correct amount of space.
-- The fixed anchor (BOTTOMLEFT of hud + padBottom) always puts the button at the
-- same relative spot: 8 px gap below the last visible element above it.
local function nhsTASInitHudButton(hud)
  tasVisBtn = CreateFrame("Button", "NHSToySeekBtn", hud,
      "SecureActionButtonTemplate,UIPanelButtonTemplate")
  tasVisBtn:SetSize(160, 24)
  -- Anchored to the HUD's BOTTOMLEFT so it rides at the bottom of the content area.
  -- padBottom = 14, so the button sits flush above the bottom padding.
  tasVisBtn:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 12, 14)
  tasVisBtn:SetText("Use Toy!")
  tasVisBtn:SetAttribute("type", "macro")
  tasVisBtn:SetAttribute("macrotext", "")  -- filled in by nhsTASRefreshBtnToy
  tasVisBtn:RegisterForClicks("AnyDown", "AnyUp")
  tasVisBtn:Hide()

  tasCooldown = CreateFrame("Cooldown", nil, tasVisBtn, "CooldownFrameTemplate")
  tasCooldown:SetAllPoints(tasVisBtn)
  tasCooldown:SetDrawEdge(true)
  tasCooldown:SetHideCountdownNumbers(false)

  -- PostClick fires after the hardware click has already triggered the secure macro,
  -- so updating cooldown and broadcasting here is safe.
  tasVisBtn:SetScript("PostClick", function(self, button, down)
    if down then return end                  -- only handle on button-up
    if not nhsTASIsHider() then return end
    if not nhsTASBtnToy then return end      -- macrotext was empty; no toy was sent
    local now = GetTime()
    if now < btnCooldownEnd then return end  -- edge-case guard
    btnCooldownEnd = now + HIDER_BTN_COOLDOWN
    CooldownFrame_Set(tasCooldown, now, HIDER_BTN_COOLDOWN, 1)
    -- Auto-prime the button the moment the cooldown expires so the player doesn't
    -- have to re-hover to get macrotext populated again.
    C_Timer.After(HIDER_BTN_COOLDOWN + 0.05, nhsTASRefreshBtnToy)
    nhsTASBroadcastStrike()
    nhsTASBtnToy = nil
    if not InCombatLockdown() then
      self:SetAttribute("macrotext", "")  -- cleared until next hover refresh
    end
  end)

  tasVisBtn:SetScript("OnEnter", function(self)
    nhsTASRefreshBtnToy()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Toying Around", 1, 1, 1)
    local count = 0
    for _, toy in ipairs(TOY_LIST) do
      if PlayerHasToy and PlayerHasToy(toy.id) then count = count + 1 end
    end
    if count == 0 then
      GameTooltip:AddLine("You don't own any compatible toys.", 1, 0.5, 0.5, true)
    else
      GameTooltip:AddLine(
        ("You own %d compatible toy(s). Click to use one and send a surprise to the seeker!"):format(count),
        nil, nil, nil, true
      )
    end
    GameTooltip:Show()
  end)

  tasVisBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  hud._toyBtn = tasVisBtn
end

-- ─── On mode selected (called for both leader and followers) ─────────────────
local function nhsTASOnModeSelected()
  btnCooldownEnd        = 0
  nhsTASHindranceQueue  = 0
  nhsTASQueueDraining   = false
  nhsTASHindranceHistory = {}
  nhsTASBtnToy           = nil
  C_Timer.After(0.1, nhsTASRefreshBtnToy)  -- prime once mode is fully initialised
end

-- ─── Sync function (called at every phase transition) ────────────────────────
function NHS.SyncToyAndSeekMode()
  -- Only act on the transition so test panel hindrances survive sync calls outside a round.
  local searching = nhsTASIsActive() and State.phase == Phase.SEARCHING
  if nhsTASWasSearching and not searching then
    nhsTASClearHindrances()
  end
  nhsTASWasSearching = searching

  -- Buff bar: hide for active hiders, restore otherwise.
  if nhsTASIsHider() then
    nhsTASHideBuffBar()
    nhsTASRefreshBtnToy()  -- pre-prime whenever hider status is confirmed (incl. after /reload)
  else
    -- Only restore buff bar when fully leaving the mode or the searching phase.
    if not nhsTASIsActive() or State.phase ~= Phase.SEARCHING then
      nhsTASShowBuffBar()
    end
  end
  -- Toy button visibility is managed by nhsSessionHudUpdate (button lives in the HUD).
  if NHS.SessionHudUpdate then
    NHS.SessionHudUpdate()
  end
end

-- ─── Module exports ───────────────────────────────────────────────────────────
NHS.ToyAndSeek = {
  OnModeSelected   = nhsTASOnModeSelected,
  ApplyStrike      = nhsTASApplyStrike,
  _broadcastStrike = nhsTASBroadcastStrike,
  IsHider          = nhsTASIsHider,       -- used by SessionHud to decide button visibility
  InitHudButton    = nhsTASInitHudButton, -- called once from nhsInitSessionHud

  -- TEST: individual hindrance functions exposed for the debug test panel.
  -- Accessible via NHS.ToyAndSeek.TEST; populated below after all locals are defined.
  TEST = {
    FireRandom      = nhsTASFireHindrance,
    ClearAll        = nhsTASClearHindrances,
    -- Hindrances
    LowHealth       = nhsTASHindranceLowHealth,
    ColorTint       = nhsTASHindranceColorTint,
    FakeAchievement = nhsTASHindranceFakeAchievement,
    Chicken         = nhsTASHindranceChicken,
    WorldMap        = nhsTASHindranceWorldMap,
    Blind           = nhsTASHindranceBlind,
    Achievements    = nhsTASHindranceAchievements,
    OpenChat        = nhsTASHindranceOpenChat,
    OpenBags        = nhsTASHindranceOpenBags,
    ToyInvite       = nhsTASHindranceToyInvite,
    GrowingButton   = nhsTASHindranceGrowingButton,
    LockedCloseCam  = nhsTASHindranceLockedCloseCamera,
    LockedFarCam    = nhsTASHindranceLockedFarCamera,
    -- Art popups (indexed 1–7)
    Popups = {
      nhsTASPopupTurtle,
      nhsTASPopupLeeroy,
      nhsTASPopupXalatath,
      nhsTASPopupMurlocs,
      nhsTASPopupThunderfury,
      nhsTASPopupClassQuiz,
      nhsTASPopupTierList,
      function() nhsTASPopupXalatath(true) end,
    },
    PopupLabels = { "Turtle", "Leeroy", "Xal'atath", "Murlocs", "Thunderfury", "ClassQuiz", "TierList", "Giant Xal" },
  },
}

-- ─── Bridge registration (same pattern as BloodhoundMode.lua) ─────────────────
local bmf = NHS.BuildMainFrameBridge
if bmf then
  bmf.nhsSyncToyAndSeekMode = NHS.SyncToyAndSeekMode
  bmf.nhsTASOnModeSelected  = nhsTASOnModeSelected
end

local gsb = NHS.GroupSyncBridge
if gsb then
  gsb.nhsSyncToyAndSeekMode  = NHS.SyncToyAndSeekMode
  gsb.nhsTASApplyStrike      = nhsTASApplyStrike
  gsb.nhsTASOnModeSelected   = nhsTASOnModeSelected
end

NHS.SyncToyAndSeekMode()
