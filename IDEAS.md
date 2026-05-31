Game Modes:

- Toy & Seek — Hiders get a button with a 30-second cooldown during the searching phase. Pressing
  it does two things: (1) activates a SecureActionButton to use a random toy from the common pool,
  changing the hider's appearance; (2) fires a random hindrance at the seeker. The seeker has a
  5-second global cooldown on receiving effects, so rapid presses from multiple hiders don't flood
  them — this also rewards hiders who coordinate timing.

  Before the round starts, every player's client scans their toy box (PlayerHasToy) and broadcasts
  the results via addon message ("[NHS] Toy Owned: id1,id2,..."). Only toys owned by every group
  member enter the pool. If no common toys exist, the mode refuses to start.

  The seeker is kept in the dark — they don't know which toy or effect is coming.

  During the searching phase, hiders' buff bars are hidden (BuffFrame:Hide()) so they cannot
  accidentally right-click their transformation off. The buff bar is restored when the round ends
  (BuffFrame:Show()). Needs a test pass to confirm no re-show behavior from Blizzard UI events.

  Multi-seeker modes (Paired, Conquer): all seekers receive the effect simultaneously.

  ---

  Seeker hindrances (random, one fires per button press subject to 5s global cooldown):
  1. Random sound effect (1 of 6, see list below)
  2. Low health flash — UIFrameFlash(LowHealthFrame, ...)
  3. Silly art popup — random scene (1 of 5, see list below), centered, fades after ~3 seconds
  4. Screen color tint — full-size colored frame flashes and fades
  5. Fake achievement banner — uses built-in WoW achievement textures, custom taunting text
  6. /chicken emote — DoEmote("CHICKEN") fires on the seeker's character (visible to everyone)
  7. World map forced open — ToggleWorldMap() (needs testing; may be combat-lockdown restricted)
  8. Screen blind — full-size white overlay fades in and out over ~2 seconds (needs testing)
  9. Screen shake — Camera_OscillateUIShake() (needs testing)

  ---

  Sound effects (6 total — played on the seeker's client):
  1. Murloc Aggro — "Mrglglglgl!"                          SoundKit ID: 416
  2. Illidan — "You are not prepared!"                     Wowhead sound ID: 11466
  3. Xal'atath whisper (pick best line at implementation)  Wowhead sound ID: 126854 (and others)
  4. Doomwalker howl/roar                                  FileDataID: TBD via wow.tools
  5. Raid Warning Siren                                    SOUNDKIT.RAID_WARNING constant
  6. Malfurion — "So says the shadow of Xavius."          Wowhead sound ID: 54460
                                                           (NPC 100652, Darkheart Thicket)

  ---

  Silly art popups (5 total — in-game assets only, resolved at runtime via GetItemInfo/GetSpellInfo):

  1. "A Turtle Made It to the Water"
     Sea Turtle mount icon (item 46109) slowly slides right toward a water/fishing icon.
     Text: "A turtle made it to the water!"

  2. "LEEEEEEROY JENKINS!"
     Big text slams in first. Warrior class icon charges from the left into a cluster of whelp
     pet icons on the right — whelps scatter outward with random velocity on impact.

  3. Xal'atath Whispers
     Screen dims. Xal'atath dagger icon (item 128827) pulses in the center surrounded by
     swirling void/shadow spell icons. Creepy italic text fades in:
     "Xal'atath whispers: They cannot hide from you forever... or can they?"

  4. March of the Murlocs
     A single-file line of murloc pet icons marches left to right across the full screen width
     with a slight staggered vertical bob. Text bounces above: "Mrglglglgl!"

  5. [Thunderfury, Blessed Blade of the Windseeker]
     The legendary sword icon (item 19019) rotates slowly in the center with a golden glow.
     Below it, the item link text types out character by character:
     "[Thunderfury, Blessed Blade of the Windseeker]"
     Optional second line: "Does anyone have the other half?"

  ---

  Toy pool (46 toys — all require player to own them):
  - Gamon's Braid
  - G.O.L.E.M. Jr.
  - Professor Chipsnide's Im-PECK-able Harpy Disguise
  - Spotlight Materializer
  - Super Simian Sphere
  - Barnacle-Encrusted Gem
  - Bloodman Charm
  - Bones of Transformation
  - Book of the Unshackled
  - Candleflexer's Dumbbell
  - Dark Ranger's Spare Cowl
  - Death's Door Charm
  - Deceptia's Smoldering Boots
  - Etheric Victory
  - Faintly Glowing Flagon of Mead
  - Heartsbane Grimoire
  - Helm of the Dominated
  - Hexed Potatoed Mucus
  - Home Made Party Mask
  - Illusive Kobyss Lure
  - Iron Boot Flask
  - Klikixx's Webspinner
  - Kovork Kostume
  - Krastinov's Bag of Horrors
  - Lampyridae Lure
  - Manastorm's Duplicator
  - Moroes' Famous Polish
  - Mote of Light
  - Mystical Frosh Hat
  - Orb of the Sin'dorei
  - Path of Elothir
  - Personal Shell
  - Personal Spotlight
  - Pileus Delight
  - Pretty Draenor Pearl
  - Robo-Gnomebulator
  - Sira's Extra Cloak
  - Spore-Bound Essence
  - Stormforged Vrykul Horn
  - Talisman of Sargha
  - Thistleleaf Branch
  - Vindicator's Armor Polish Kit
  - Vixx's Chest of Tricks
  - Whole-Body Shrinka'
  - Wisp Amulet
  - Yennu's Kite

  Excluded from pool (would disrupt gameplay):
  - Set of Matches       <- forced movement
  - Jar of Excess Slime  <- forced movement
  - Stasis Sand          <- 1 min stun
