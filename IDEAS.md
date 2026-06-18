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

  Sound effects (5 total — played on the seeker's client):
  1. Murloc Aggro — "Mrglglglgl!"                          SoundKit ID: 416
  2. Illidan — "You are not prepared!"                     Wowhead sound ID: 11466
  3. Xal'atath whisper (pick best line at implementation)  Wowhead sound ID: 126854 (and others)
  4. Raid Warning Siren                                    SOUNDKIT.RAID_WARNING constant
  5. Fel Reaver horn                                       FileDataID: 548880

  Considered but not used:
  - Malfurion — "So says the shadow of Xavius."           SoundKit ID: 54460
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

  Toy pool (54 toys — all require player to own them):
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
  - Cursed Orb
  - Dark Ranger's Spare Cowl
  - Death's Door Charm
  - Deceptia's Smoldering Boots
  - Delicate Jade Parasol
  - Enchanted Soup Stone
  - Etheric Victory
  - Faintly Glowing Flagon of Mead
  - Heartsbane Grimoire
  - Helm of the Dominated
  - Hexed Potatoed Mucus
  - Home Made Party Mask
  - Illusive Kobyss Lure
  - Iron Boot Flask
  - Jar of Excess Slime
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
  - Primalist Prison
  - Robo-Gnomebulator
  - Set of Matches
  - Sira's Extra Cloak
  - Spectral Visage
  - Spore-Bound Essence
  - Stasis Sand
  - Stormforged Vrykul Horn
  - Talisman of Sargha
  - Thistleleaf Branch
  - Vindicator's Armor Polish Kit
  - Vixx's Chest of Tricks
  - Whole-Body Shrinka'
  - Wisp Amulet
  - Yennu's Kite

  Excluded from pool:
  (none currently)

- Cursed & Seek (working title) — Each hider is assigned a random visual effect role at round
  start. The effect runs persistently on their client for the full hiding phase, impairing their
  ability to navigate and find a good spot. When the seeker finds a hider, that hider's effect
  transfers immediately to the seeker's client and stays until they find the next hider, at which
  point it is replaced. The final hider's effect fires on the seeker as normal but the round ends
  immediately after, so it has no practical impact.

  Effects are assigned without replacement per round — no two hiders share the same effect.
  Where pool size allows, prevent the seeker from receiving the same effect back-to-back across
  consecutive finds.

  Hiders are told their assigned effect at round start. The seeker is notified that an effect is
  incoming on each find, but not which one until it applies.

  No button or cooldown mechanic — effects are passive and automatic. This mode is self-contained
  and does not interact with the Toy & Seek toy pool or hindrance system.

  ---

  Visual effects (all applied via persistent full-screen addon UI frames):

  1. Spotlight — black full-screen overlay with a small transparent circle centred on screen.
     Achievable by layering two frames with a gap, or via stencil mask. Circle radius to be
     determined by playtesting; too small is unplayable, too large is trivial. (Needs
     implementation testing for the cutout approach.)

  2. Tunnel vision — heavy vignette frame that crushes the outer edges of the screen down to a
     narrow central band. Less severe than Spotlight; still meaningfully restricts peripheral
     awareness.

  3. Colour tint — strong persistent single-colour overlay (red, deep blue, or green). Related to
     the Toy & Seek tint hindrance but runs for the full phase rather than flashing and fading.

  4. Static noise — semi-transparent animated noise/static texture tiled across the screen.
     Requires an animated texture or frame animation built from static assets; confirm feasibility
     at implementation.

  5. Locked close camera — forces camera distance to minimum for the phase. (Needs testing;
     CameraZoomIn() may conflict with combat lockdown or player override.)

  6. Locked far camera — forces camera distance to maximum for the phase. Same lockdown caveat
     as above.

  7. Distraction overlay — a large absurd image pinned to the centre of the screen, partially
     obscuring central vision. Can reuse art assets from the Toy & Seek silly art popup pool to
     avoid duplicating work.

  8. High contrast — black and white desaturation overlay. Removes colour information from the
     visible scene without fully blocking vision.

  ---

  Open questions:
  - Final name. "Cursed & Seek" is a placeholder.
  - Minimum player count before the effect pool has to wrap. With 8 effects and e.g. 4 hiders,
    only 4 effects fire per round — decide whether unused effects rotate in next round or stay
    fully random each time.
  - Whether to weight effect assignment so the harshest effects (Spotlight, Locked close camera)
    are rarer, or keep it fully random as a chaos feature.