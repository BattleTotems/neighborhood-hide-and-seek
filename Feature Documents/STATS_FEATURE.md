# Lifetime Stats Feature

Design document tracking decisions for the persistent, additive stats system.
Update this file as decisions are revisited or new findings emerge.

---

## 1. Storage Architecture

### Mechanism
WoW `SavedVariables` (the `NHSV` table) already persists across logouts automatically.
No new API is needed — the problem with the current data is scope and format, not persistence.

### Scope decisions
- **`NHSV` is account-wide** (`SavedVariables` in the `.toc`, not `SavedVariablesPerCharacter`).
- Stats will be **per-character**, keyed by a stable character identity string, stored inside `NHSV`.
- **Account-wide totals** will be computed dynamically at display time by summing all character
  entries — no separate account table to keep in sync.

```lua
-- Structure (never wiped; additive forever)
NHSV.charStats = NHSV.charStats or {}
NHSV.charStats["Name-Realm"] = {
  statsVersion = 1,   -- schema migration guard
  -- counters, maps, etc. (see Section 3)
}
```

Character identity key: built at addon load from `UnitName("player")` + `-` + `GetRealmName()`,
stored on `NHS.LocalCharacterKey`. This is the same format used elsewhere in the addon for sort
keys but always uses the full realm suffix for unambiguous cross-character keying.

### What is NOT changing
- `NHSV.gameRounds` — active session persistence (unchanged).
- `NHSV.lastCompletedPastRounds` — reload archive (unchanged).
- `State.pastRounds` — in-memory round history for the HUD (unchanged).

`NHSV.charStats` is a fourth, completely separate table that is never wiped by session events.

---

## 2. Data Collection Points

Stats are accumulated at **round end**, not round start or display time.

### Solo-session guard
Stats are only accumulated when the player is in a group (`IsInGroup()`). Solo sessions (not in
a group) run the full leader flow normally but produce no stat entries. This prevents test
sessions and solo exploration from polluting lifetime data. The guard appears at the top of
`nhsAccumulateRoundStats()` and wraps the session-timing blocks in `nhsLeaderStartSession()`,
`nhsLeaderEndSession()`, and `nhsResetGameSession()`. `State.statsSessionStartTime` is still
cleared on solo reset to avoid a stale timestamp if the player later joins a group.

### Leader path
`nhsAccumulateRoundStats()` fires alongside `nhsAppendPastRoundSnapshotIfActiveRound()`.
At that moment all raw data is available: house key, mode ID, seeker keys, found order, roster.

### Follower path
`nhsAccumulateRoundStats()` fires from the `[NHS] Round is over!` handler in `GroupSync.lua`,
at the same point where `nhsAppendPastRoundSnapshotIfActiveRound()` is already called.
Followers have less data (see Section 6) but can still accumulate most stats.

### Session start/end
- `nhsLeaderStartSession()` records `State.statsSessionStartTime = time()` (Unix timestamp) and
  increments `sessionsStarted`.
- `nhsLeaderEndSession()` increments `sessionsCompleted` then calls `nhsResetGameSession()`.
- `nhsResetGameSession()` accumulates elapsed = `time() - State.statsSessionStartTime` into
  `totalSessionSeconds` and clears the timestamp. This runs for both normal session-end AND
  group-disbanded teardown (abandoned sessions still count toward time; `sessionsCompleted` is
  not incremented for abandonments).
- Follower session timing: `[NHS] Game session started` sets `State.statsSessionStartTime = time()`
  and increments `sessionsStarted`.
- `[NHS] Game Over!` on followers accumulates session time, increments `sessionsCompleted`, and
  clears the timestamp before any state reset.

### Session-end round capture (ending while a round is still active)
If the leader calls "End Session" while still in the REVEALING phase (the last round was never
explicitly ended), the last round's data would be lost without a snapshot guard.

**Leader path**: `nhsLeaderEndSession()` calls `nhsAppendPastRoundSnapshotIfActiveRound()` first,
which in turn calls `nhsAccumulateRoundStats()`. Both fire before any state reset.

**Follower path**: The `[NHS] Game Over!` handler calls `C.nhsAppendPastRoundSnapshotIfActiveRound()`
before clearing state. If the follower is still in a round phase (e.g., REVEALING), this captures
and accumulates the last round.

The guard inside `nhsAppendPastRoundSnapshotIfActiveRound` (`phase == PENDING` returns early) means
sessions ended in non-round phases (e.g., PICK_HOUSE) do not produce spurious stat entries.

---

## 3. Stats Catalogue

### Personal performance
| Stat | Notes |
|---|---|
| `roundsPlayed` | Every round the player participated in |
| `roundsAsSeeker` | Initial role was seeker (see Section 5 on modes) |
| `roundsAsHider` | Initial role was hider |
| `seekerWins` | Seeker round + all hiders found at reveal |
| `hiderSurvivals` | Hider round + player NOT in foundOrder at reveal |
| `timesFirstFound` | Player's key is `foundOrder[1]` in a hider round |
| `timesLastFound` | Player's key is `foundOrder[#foundOrder]` in a hider round AND all hiders found (i.e., you were the last found, not a survivor) |
| `hotPotatoLosses` | Hot Potato rounds where local player was holding the potato at reveal |
| `hotPotatoWins` | Hot Potato rounds where local player successfully passed the potato |

### Social
| Stat | Notes |
|---|---|
| `playerEncounters` | `{ ["Name-Realm"] = { display="Name", count=N } }` — rounds played alongside each player |

### Location
| Stat | Notes |
|---|---|
| `houseCounts` | `{ ["persistenceKey"] = N }` — integer count per full persistence key (see Section 4) |
| `neighborhoodCounts` | `{ ["Neighborhood Name"] = N }` — integer count, bucketed from house key's neighborhood component |

### Mode breakdown
| Stat | Notes |
|---|---|
| `modeCounts` | `{ ["Mode Name"] = N }` — rounds per mode |
| `modeSeekerWins` | `{ ["Mode Name"] = N }` — seeker wins per mode |
| `modeHiderSurvivals` | `{ ["Mode Name"] = N }` — survivals per mode |

### Time
| Stat | Notes |
|---|---|
| `secondsSearching` | Cumulative search-phase seconds when local player was a seeker |
| `secondsHiding` | Cumulative search-phase seconds when local player was a hider (decision: only searching phase counts, not hiding-countdown phase) |
| `totalSessionSeconds` | Sum of all game session wall-clock durations |

### Session
| Stat | Notes |
|---|---|
| `sessionsStarted` | Every time a session begins (leader or follower) |
| `sessionsCompleted` | Sessions that reached Game Over (not abandoned / reload) |
| `totalRoundCount` | Redundant with `roundsPlayed` but useful as a quick total |

---

## 4. House Keys

### Key format (from `SavedHouses.lua`)
```
persistenceKey = stableKey .. "\1" .. tail
tail           = neighborhoodName .. "\2" .. subdivisionName .. "\3" .. playerName
```

The `stableKey` is a stable housing API identifier (plot GUID or similar). The tail encodes
the neighborhood and optional subdivision/player so the same plot in two neighborhoods doesn't
collide in `NHSV`.

Available helpers:
- `S.BaseStableKeyFromPersistenceKey(key)` → strips to bare stable ID
- `S.NeighborhoodAndSubFromKey(key)` → returns `(neighborhoodName, subdivisionName)`
- `S.PersistenceKeyFromStableNeighborhoodSubdivision(...)` → builds the key

### Usage for stats
The **full persistence key** is the right stat key for `houseCounts` — it distinguishes the same
physical plot across different neighborhoods. The display name is stored alongside it and updated
each time the house appears (handles renames).

**Leader** has `State.gameLockedHouseKey` (the raw persistence key) — ideal.
**Follower** has only `State.remoteHouseDisplay` (a string) — no key. See Section 6.

---

## 5. Game Mode Edge Cases

### Roles can change mid-round
For all role-tracking stats, use the **initial role** assigned at round start, not the role
held at reveal time.

To enable this: add `State.gameRoundInitialSeekerKeys = {}` maintained in two steps inside
`nhsLeaderBroadcastRoundPhase`:

1. **Set at `Phase.HIDING` start** — initial capture, matches `gameSeekerHistory` entry timing.
2. **Overwrite at `Phase.SEARCHING` start** — picks up any players who joined during the hiding
   countdown and were added as seekers by `nhsLeaderHiderModeAddLateJoiners()`. Conquer mid-round
   adds and Hot Potato swaps have not happened yet, so this is still "initial" for those modes.

Using both ensures there is always a value even if a round skips SEARCHING (leader jumps to
REVEALING), while still capturing late joiners. Cleared at round reset. The stats accumulator
reads this, not `gameLockedSeekerKeys`, to determine original seeker set.

### Mode-by-mode analysis

| Mode | Role complexity | foundOrder meaning | Stat notes |
|---|---|---|---|
| **Normal / Normal Plus / Hot&Cold / Bloodhound / Lightning / Overtime / Toy&Seek** | Static | Hiders found, in order | Standard accumulation |
| **Paired** | Two seekers (static) | Same as normal | Track both initial seekers |
| **Conquer** | Found hiders join seeker team mid-round | Hiders found/converted, in order | Use initial seeker; `gameLockedSeekerKeys` grows during round |
| **Chosen One** | One hider; everyone else seeks from the start | Seekers who found the hider (reversed) | `gameLockedHiderKey` = the one hider |
| **Sardines** | One sardine (hider); seekers who find sardine join it | Seekers who joined the sardine (NOT hiders found) | `foundOrder` meaning is inverted — joining seekers are added, not the sardine. Sardine "wins" if not everyone joins before time. Treat joining seekers as "found by sardine." |
| **Hot Potato** | Seeker swaps on tag; no tagbacks | Old seekers (in pass order) | Final seeker = `gameLockedSeekerKeys[1]` at REVEALING = loser. Track `hotPotatoLosses` / `hotPotatoWins` separately. |

### "Times you were the last hider found" definition
This stat means: you were a hider, you were found (your key appears in `foundOrder`), AND your
key is the last entry in `foundOrder`, AND `unfoundCount == 0` at reveal (everyone was found —
no survivors). If there are survivors, the last found is not meaningfully "last" in the dramatic
sense. Not tracked for Sardines or Hot Potato (different semantics).

---

## 6. Follower vs. Leader Data Gaps

| Data | Leader | Follower |
|---|---|---|
| House persistence key | `State.gameLockedHouseKey` ✓ | Not synced — display string only |
| House display name | `State.gameLockedHouseDisplay` ✓ | `State.remoteHouseDisplay` ✓ |
| Mode ID | `State.gameMode` ✓ | `State.remoteGameMode` ✓ (synced) |
| Initial seeker keys | `State.gameLockedSeekerKeys` + new `gameRoundInitialSeekerKeys` ✓ | `State.remoteSeekerKeys` ✓ (synced) |
| Found order | `State.foundOrder` ✓ | `State.foundOrder` ✓ (synced via Found messages) |
| Full roster | `nhsGetGroupRoster()` ✓ | `nhsGetGroupRoster()` ✓ |
| "All found" check | Roster vs. foundSet ✓ | Roster vs. foundSet ✓ (can compute) |
| Search phase start time | `State.searchPhaseStartTime` ✓ | Not set — must derive from SEEKING message receipt |
| Search phase duration | `State.searchPhaseDuration` ✓ | Not set — must be inferred or broadcast |

### Follower house key
Followers receive the house persistence key via the updated `[NHS] House:` addon payload.
The addon message now carries `<key>\31<display>` (unit separator `\31`); followers split on
it to extract both. Chat message is unchanged — humans still see the plain display name.

`State.remoteHouseKey` is populated on receipt and cleared at ROUND_OVER, GAME_OVER,
SESSION_START, and group-disbanded. Old clients (pre-update) receive the combined payload
and store it verbatim as `remoteHouseDisplay` (garbled display, accepted trade-off).
Old leaders (pre-update) send no separator; new followers detect this and set `remoteHouseKey = nil`
falling back to display-only house tracking for that session.

House stats now use the persistence key as the stat key on both leader and follower clients,
so data merges correctly across sessions regardless of which role the player held.

### Follower search time tracking
Followers record `State.followerSearchPhaseStartTime = GetTime()` when they receive the
`[NHS] The Seeking Begins!` addon message, **only if** current phase is not already `SEARCHING`
(guard against re-syncs resetting the timer). Duration is computed at ROUND_OVER:
`math.floor(GetTime() - State.followerSearchPhaseStartTime)`.

---

## 7. Sync Message Safety

### Messages that affect round state (and how stats are protected)

| Message | Effect on followers | Stats impact |
|---|---|---|
| `[NHS] Game session started` | Wipes `pastRounds`, `gameSeekerHistory`, `gameHouseHistory` | `NHSV.charStats` is a separate table — unaffected |
| `[NHS] Round Start: <keys>` (same seeker) | `sameRound = true`, `clearFound()` NOT called | No stat accumulation triggered; foundOrder preserved |
| `[NHS] Round Start: <keys>` (new seeker) | `clearFound()` called, new round begins | Prior round stats already accumulated at ROUND_OVER |
| `[NHS] Round is over!` | `nhsAppendPastRoundSnapshotIfActiveRound()` fires FIRST, then `nhsClearRemoteRoundSync()` | Stat accumulation fires at the same point — before the wipe |
| `[NHS] Game Over!` | Wipes all remote session state | Session duration finalized before wipe |
| `[NHS] The Seeking Begins!` (re-sync) | Follower may receive this again after leader reload | Use phase guard: only set `followerSearchPhaseStartTime` if not already in SEARCHING |

### Manual group sync / leader reload
If the leader `/reload`s during SEARCHING, they will re-broadcast HIDING and SEEKING.
Follower sees these again. The seeker keys will be the same, so `sameRound = true` and
`clearFound()` is NOT called — found list is preserved. The follower search timer is
protected by the phase guard above.

### "Restart Round" feature
A play-again action during REVEALING that reuses the same house, mode, and seeker must
**always broadcast `[NHS] Round is over!` first**, even though a new round immediately follows.

Without it, followers are still mid-round (`IsRoundPhase` is true), see the same seeker key in
the incoming `Round Start`, flag it as `sameRound = true`, and skip `clearFound()`. The
previous round is never snapshotted on followers and the found list carries over incorrectly.

After ROUND_OVER, the follower sets `phase = PICK_HOUSE` (not a round phase), so the
subsequent `Round Start` with the same seeker keys is correctly treated as a new round.

Required broadcast sequence for play-again:
1. `[NHS] Round is over!` — snapshot + clear on all clients
2. `[NHS] House: <display>` — re-lock house for followers
3. `[NHS] Game mode: <modeId>` — re-set mode for followers
4. `[NHS] Round Start: <seekerKeys>` — set seeker(s) → PENDING on all clients

Stats impact: none, as long as the sequence above is followed. `gameRoundInitialSeekerKeys`
is set fresh when HIDING fires for the new round. Session timing and `sessionsStarted` are
unaffected. Seeker rotation: re-adding the same seeker key to `gameRotationUsed` is a no-op
(boolean set); their name appends to `gameSeekerHistory` a second time, which is correct.

### New player joining mid-session
When a new player joins, the leader re-broadcasts round state. Same re-sync rules apply —
same seeker key → `clearFound()` not called. The new player's client starts fresh (no history),
which is correct.

---

## 8. Time Tracking

### What counts
- **"Search phase time"** is the only time that counts toward per-role time stats (search phase
  only, not the hiding-countdown phase). This was an explicit decision.
- **"Session time"** = full wall-clock duration of the session (from session start to Game Over
  or session end), used for `totalSessionSeconds`.

### Implementation

```lua
-- Session timing: use time() (Unix timestamp) so it survives logout
State.statsSessionStartTime = time()   -- set in nhsLeaderStartSession / SESSION_START handler
-- At session end: elapsed = time() - State.statsSessionStartTime

-- Search phase timing (leader)
State.searchPhaseStartTime = GetTime()  -- already exists; set in nhsLeaderStartPhaseCountdown
State.searchPhaseDuration = sec         -- already exists

-- Search phase timing (follower)
-- Set on receipt of [NHS] The Seeking Begins! if phase ~= SEARCHING
State.followerSearchPhaseStartTime = GetTime()
```

At ROUND_OVER, compute actual search seconds from start time, capped to the round duration.
If the timer was reset (re-sync guard worked), this may be slightly short — acceptable.

---

## 9. Open Questions / TBD

- **`statsVersion` migration**: When new stat fields are added, `nhsEnsureCharStats()` adds them with
  zero defaults. No destructive migration needed for additive counters.
- **Hot Potato initial role**: The initial "seeker" in Hot Potato starts the round as seeker — they should be counted as a seeker round. But the outcome stat is `hotPotatoLoss` (bad) vs. successfully passing the potato (good). Normal `seekerWins` / `hiderSurvivals` do not apply to Hot Potato rounds. `hotPotatoWins` also feeds `modeSeekerWins["hot_potato"]` for per-mode display.
- **Sardines "winner"** (resolved): Sardine wins = time ran out before all seekers joined (`not allSeekersJoined`). This maps to `hiderSurvivals` (consistent with hider role across all modes). Seekers win if they found and joined the sardine (key is in `foundOrder`), incrementing `seekerWins` and `modeSeekerWins["sardines"]`. Seekers who never found the sardine get no win credit. Both counters feed into the generic `seekerWins` / `hiderSurvivals` totals.
- **Unimplemented social stats**: `playerFoundByMe`, `playerFoundMe`, `uniquePlayersCount`, `uniqueHousesCount` were considered during design but not implemented in v1. If added later, `nhsEnsureCharStats()` can initialize them with zero defaults and the accumulator extended.

---

## 10. Display UI

### Entry point
"Your Stats" button (308×26) in the MainFrame History section, anchored between "Previous Rounds" and the "Previous Seekers / Previous Houses" row.

### Frame (`Ui/StatsFrame.lua`)
- `NHS.CreateStatsFrame()` returns `{ frame, refresh }` — same satellite-popup pattern as other history frames.
- Frame: 320×460, draggable, position persisted in `NHSV.statsFramePoint`.
- Scroll area: 288×370, set up with `NHS.SetupScrollFrameMouseWheel`.
- Single `FontString` body inside a `ScrollFrame`, built fresh on each `refresh` call.
- "Reset Stats" button (150×24) at `BOTTOM +0 +12` — always visible below the scroll area.
- Integrated into `AnyMainFloatingPanelOpen`, `HideMainFloatingPanels`, and `RegisterEscapeProxyFrameHooks` in `MainFrameToggle.lua`.

### Sections displayed (conditional — only shown when data exists)
| Section | Source fields |
|---|---|
| Character name (header) | `NHS.LocalCharacterKey` via `Ambiguate` |
| ROUNDS | `roundsPlayed`, `roundsAsSeeker`, `roundsAsHider` |
| WINS & SURVIVALS | `seekerWins`, `hiderSurvivals`, `timesFirstFound`, `timesLastFound`, `hotPotatoWins`, `hotPotatoLosses` |
| TIME | `secondsSearching`, `secondsHiding`, `totalSessionSeconds` |
| SESSIONS | `sessionsStarted`, `sessionsCompleted` |
| BY GAME MODE | `modeCounts` top 8, sorted by count |
| BY NEIGHBORHOOD | `neighborhoodCounts` top 5, sorted by count |
| BY HOUSE | `houseCounts` top 5; display via `NHSV.houseLabels[key]` with fallback to parsing the `\3`-delimited persistence key |
| PLAYED WITH | `playerEncounters` top 8, sorted by count |

### Reset Stats
`StaticPopupDialogs["NHS_CONFIRM_RESET_STATS"]` registered at module scope in `StatsFrame.lua`.
Clicking "Reset Stats" calls `StaticPopup_Show(...)` with the character's short name in the prompt.
On confirm: `NHSV.charStats[charKey] = nil` — wipes the entire entry. `nhsEnsureCharStats` will
re-initialize it from zeroes the next time a round is played.
