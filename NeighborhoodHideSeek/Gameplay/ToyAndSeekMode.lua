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

-- ─── Toy list (54 items — all require player ownership) ──────────────────────
-- Item IDs sourced from Wowhead; verify any marked "?" in-game.
local TOY_LIST = {
  { id = 118937, name = "Gamon's Braid" },
  { id = 233202, name = "G.O.L.E.M. Jr." },
  { id = 191891, name = "Professor Chirpsnide's Im-PECK-able Harpy Disguise" },
  { id = 230924, name = "Spotlight Materializer 1000" },
  { id = 37254,  name = "Super Simian Sphere" },
  { id = 129165, name = "Barnacle-Encrusted Gem" },
  { id = 113096, name = "Bloodmane Charm" },
  { id = 64646,  name = "Bones of Transformation" },
  { id = 170154, name = "Book of the Unshackled" },
  { id = 228698, name = "Candleflexer's Dumbbell" },
  { id = 130171, name = "Cursed Orb" },
  { id = 166544, name = "Dark Ranger's Spare Cowl" },
  { id = 129149, name = "Death's Door Charm" },
  { id = 108743, name = "Deceptia's Smoldering Boots" },
  { id = 212523, name = "Delicate Jade Parasol" },
  { id = 164373, name = "Enchanted Soup Stone" },
  { id = 244470, name = "Etheric Victory" },
  { id = 129113, name = "Faintly Glowing Flagon of Mead" },
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
  { id = 118938, name = "Manastorm's Duplicator" },
  { id = 119092, name = "Moroes' Famous Polish" },
  { id = 141862, name = "Mote of Light" },
  { id = 138873, name = "Mystical Frosh Hat" },
  { id = 35275,  name = "Orb of the Sin'dorei" },
  { id = 130158, name = "Path of Elothir" },
  { id = 198409, name = "Personal Shell" },
  { id = 127864, name = "Personal Spotlight" },
  { id = 225910, name = "Pileus Delight" },
  { id = 108739, name = "Pretty Draenor Pearl" },
  { id = 200198, name = "Primalist Prison" },
  { id = 119215, name = "Robo-Gnomebulator" },
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
local nhsTASHindranceHistory = {}  -- last 2 hindrance picks; avoids immediate repeats
local buffBarHidden  = false

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
    local _, dur = GetItemCooldown(toy.id)
    if not (dur and dur > 1.5) then return toy end
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
local nhsTintFrame
local function nhsTASHindranceColorTint()
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
  C_Timer.After(6.0, function()
    UIFrameFadeOut(nhsTintFrame, 2.0, 1, 0)
    C_Timer.After(2.1, function() nhsTintFrame:Hide() end)
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
    f:SetSize(420, 80)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(96)
    f:SetBackdrop({
      bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\AchievementFrame\\UI-Achievement-Category-Border",
      tile = true, tileSize = 32, edgeSize = 16,
      insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    f:SetBackdropColor(0.07, 0.05, 0.01, 0.96)
    f:SetBackdropBorderColor(1, 0.82, 0, 1)
    local iconBorder = f:CreateTexture(nil, "BACKGROUND")
    iconBorder:SetSize(60, 60)
    iconBorder:SetPoint("LEFT", f, "LEFT", 8, 0)
    iconBorder:SetTexture("Interface\\AchievementFrame\\UI-Achievement-IconFrame")
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\Achievement_General_StayClassy")
    local hdr = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    hdr:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -4)
    hdr:SetText("|cffffdd00Achievement Earned!|r")
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -4)
    f._sub = sub
    f:Hide()
    nhsAchieveFrame = f
  end
  nhsAchieveFrame._sub:SetText(taunt)
  nhsAchieveFrame:SetAlpha(1)
  nhsAchieveFrame:Show()
  -- Play achievement toast sound (or level-up ding as fallback)
  local acheiveSound = (SOUNDKIT and SOUNDKIT.UI_ACHIEVEMENT_TOAST) or 888
  pcall(PlaySound, acheiveSound, "Master")
  C_Timer.After(4.0, function()
    UIFrameFadeOut(nhsAchieveFrame, 0.8, 1, 0)
    C_Timer.After(0.9, function()
      nhsAchieveFrame:Hide()
      nhsAchieveShowNext()
    end)
  end)
end
local function nhsTASHindranceFakeAchievement()
  nhsAchieveQueue[#nhsAchieveQueue + 1] = ACHIEVE_TAUNTS[math.random(#ACHIEVE_TAUNTS)]
  if not nhsAchieveActive then nhsAchieveShowNext() end
end

-- Hindrance: /chicken emote on the seeker (visible to everyone nearby).
local function nhsTASHindranceChicken()
  if not InCombatLockdown() then pcall(DoEmote, "CHICKEN") end
end

-- Hindrance: Force world map open.
local function nhsTASHindranceWorldMap()
  if not InCombatLockdown() then pcall(ToggleWorldMap) end
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
  C_Timer.After(2.0, function()      -- black screen 2 s after the voice line starts
    nhsBlindFrame:SetAlpha(0)
    nhsBlindFrame:Show()
    UIFrameFadeIn(nhsBlindFrame, 0.25, 0, 1)
    C_Timer.After(1.2, function()    -- hold full black 0.5 s longer (was 0.7)
      UIFrameFadeOut(nhsBlindFrame, 1.0, 1, 0)
      C_Timer.After(1.1, function() nhsBlindFrame:Hide() end)
    end)
  end)
end


-- ─── Silly art popups ─────────────────────────────────────────────────────────
-- Each popup creates a fresh root frame so cleanup is trivial (just hide the root).

-- Shared fade-out and cleanup after a popup has run.
local function nhsTASPopupClose(root, delay)
  C_Timer.After(delay or 3.0, function()
    if root then
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

  -- Turtle icon (128x128) — file data ID 1738657 (verified in-game).
  local iconFrm = CreateFrame("Frame", nil, root)
  iconFrm:SetSize(128, 128)
  iconFrm:SetPoint("LEFT", root, "LEFT", 40, sh * 0.42 - 64)
  local iconTex = iconFrm:CreateTexture(nil, "ARTWORK")
  iconTex:SetAllPoints()
  iconTex:SetTexture(1738657)
  iconFrm:Show()

  -- Wall of water icons arranged in a vertical column at the destination X.
  local targetPct = 0.72
  local WALL_COUNT = 7
  local WALL_SIZE  = 80
  local wallX = sw * targetPct
  for j = 1, WALL_COUNT do
    local wf = CreateFrame("Frame", nil, root)
    wf:SetSize(WALL_SIZE, WALL_SIZE)
    -- Spread from near bottom to near top, leaving a small margin
    local wy = sh * 0.05 + (j - 1) * ((sh * 0.9) / (WALL_COUNT - 1)) - WALL_SIZE / 2
    wf:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", wallX - WALL_SIZE / 2, wy)
    local wt = wf:CreateTexture(nil, "ARTWORK")
    wt:SetAllPoints()
    wt:SetTexture(135861)  -- water icon — file data ID verified in-game
    wf:Show()
  end

  -- Slide turtle from left toward the wall of water
  local duration = 2.8
  local elapsed  = 0
  iconFrm:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    local pct  = math.min(elapsed / duration, 1)
    local ease = 1 - (1 - pct) * (1 - pct)  -- ease-out
    self:ClearAllPoints()
    self:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 40 + (wallX - 40) * ease, sh * 0.42)
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

-- Popup 3 — Xal'atath Whispers
local function nhsTASPopupXalatath()
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

  -- Xal'atath's artifact dagger (item 128827 — Xal'atath, Blade of the Black Empire).
  -- Lazy-loads via GET_ITEM_INFO_RECEIVED so it appears correctly even on first trigger.
  -- The icon slowly rotates for a mystical void-weapon feel.
  local XAL_ITEM_ID = 128827
  local XAL_FALLBACK = "Interface\\Icons\\inv_weapon_shortblade_92"
  local mainFrm = CreateFrame("Frame", nil, root)
  mainFrm:SetSize(160, 160)
  mainFrm:SetPoint("CENTER", root, "BOTTOMLEFT", cX, cY)
  local mainTex = mainFrm:CreateTexture(nil, "ARTWORK")
  mainTex:SetAllPoints()
  C_Item.RequestLoadItemDataByID(XAL_ITEM_ID)
  local _, _, _, _, _, _, _, _, _, xalIcon = GetItemInfo(XAL_ITEM_ID)
  mainTex:SetTexture(xalIcon or XAL_FALLBACK)
  if not xalIcon then
    local xalEvt = CreateFrame("Frame", nil, root)
    xalEvt:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    xalEvt:SetScript("OnEvent", function(self, _, id)
      if id == XAL_ITEM_ID then
        local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(XAL_ITEM_ID)
        if icon then mainTex:SetTexture(icon) end
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
      end
    end)
  end
  mainFrm:SetAlpha(0)
  mainFrm:Show()
  UIFrameFadeIn(mainFrm, 0.8, 0, 1)

  -- Orbiting void icons
  local ORB_COUNT  = 6
  local ORB_RADIUS = 110
  local ORB_SIZE   = 36
  local ORB_ICONS  = {
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Spell_Shadow_Lifedrain",
    "Interface\\Icons\\Spell_Shadow_Painspike",
    "Interface\\Icons\\Spell_Shadow_AbominationExplosion",
    "Interface\\Icons\\Spell_Shadow_MindBlast",
    "Interface\\Icons\\Spell_Shadow_Possession",
  }
  local orbs = {}
  for i = 1, ORB_COUNT do
    local of = CreateFrame("Frame", nil, root)
    of:SetSize(ORB_SIZE, ORB_SIZE)
    of:SetPoint("CENTER", root, "BOTTOMLEFT", cX, cY)
    local ot = of:CreateTexture(nil, "ARTWORK")
    ot:SetAllPoints()
    ot:SetTexture(ORB_ICONS[i] or "Interface\\Icons\\Spell_Shadow_ShadowWordPain")
    ot:SetVertexColor(0.6, 0.2, 0.9)
    of:SetAlpha(0)
    of:Show()
    UIFrameFadeIn(of, 0.5, 0, 0.85)
    orbs[i] = { frame = of, angle = (i - 1) * (2 * math.pi / ORB_COUNT) }
  end

  -- Pulse main + orbit orbs
  local pulse     = 0
  local ORB_SPEED = 0.7  -- radians per second
  mainFrm:SetScript("OnUpdate", function(self, dt)
    pulse = pulse + dt
    self:SetScale(1 + 0.06 * math.sin(pulse * 2.5))
    mainTex:SetRotation(pulse * 0.35)  -- slow mystical rotation on the dagger icon
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
  lbl:SetPoint("CENTER", root, "BOTTOMLEFT", cX, cY - 175)
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
  local _, _, _, _, _, _, _, _, _, sfP = GetItemInfo(19019)
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
        UIFrameFadeIn(sfFrm, 0.4, 0, 1)
        C_Timer.After(0.5, function()
          typeOut(FULL_TEXT, mainLbl)
        end)
      end)
    end)
  end)

  nhsTASPopupClose(root, 9.5)
end


-- ─── Hindrance dispatcher ─────────────────────────────────────────────────────
-- 11 options: 6 effect hindrances + 5 art popups (each popup is its own slot).
-- History tracks the last 2 picks so no hindrance repeats twice in a row.
local function nhsTASFireHindrance()
  -- Avoid repeating either of the last 2 hindrances. With 11 options and 2
  -- excluded there are always at least 9 valid choices, so this loop exits fast.
  local pick
  repeat
    pick = math.random(11)
  until pick ~= nhsTASHindranceHistory[1] and pick ~= nhsTASHindranceHistory[2]
  nhsTASHindranceHistory[1] = nhsTASHindranceHistory[2]
  nhsTASHindranceHistory[2] = pick

  if     pick == 1  then nhsTASHindranceLowHealth()
  elseif pick == 2  then nhsTASHindranceColorTint()
  elseif pick == 3  then nhsTASHindranceFakeAchievement()
  elseif pick == 4  then nhsTASHindranceChicken()
  elseif pick == 5  then nhsTASHindranceWorldMap()
  elseif pick == 6  then nhsTASHindranceBlind()
  elseif pick == 7  then nhsTASPopupTurtle()
  elseif pick == 8  then nhsTASPopupLeeroy()
  elseif pick == 9  then nhsTASPopupXalatath()
  elseif pick == 10 then nhsTASPopupMurlocs()
  elseif pick == 11 then nhsTASPopupThunderfury()
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
    GameTooltip:SetText("Toy & Seek", 1, 1, 1)
    local count = 0
    for _, toy in ipairs(TOY_LIST) do
      if PlayerHasToy and PlayerHasToy(toy.id) then count = count + 1 end
    end
    if count == 0 then
      GameTooltip:AddLine("You don't own any Toy & Seek toys.", 1, 0.5, 0.5, true)
    else
      GameTooltip:AddLine(
        ("You own %d Toy & Seek toy(s). Click to use one and send a surprise to the seeker!"):format(count),
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
    -- Hindrances
    LowHealth       = nhsTASHindranceLowHealth,
    ColorTint       = nhsTASHindranceColorTint,
    FakeAchievement = nhsTASHindranceFakeAchievement,
    Chicken         = nhsTASHindranceChicken,
    WorldMap        = nhsTASHindranceWorldMap,
    Blind           = nhsTASHindranceBlind,
    -- Art popups (indexed 1–5)
    Popups = {
      nhsTASPopupTurtle,
      nhsTASPopupLeeroy,
      nhsTASPopupXalatath,
      nhsTASPopupMurlocs,
      nhsTASPopupThunderfury,
    },
    PopupLabels = { "Turtle", "Leeroy", "Xal'atath", "Murlocs", "Thunderfury" },
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
