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

### Leader path
`nhsAccumulateRoundStats()` fires alongside `nhsAppendPastRoundSnapshotIfActiveRound()`.
At that moment all raw data is available: house key, mode ID, seeker keys, found order, roster.

### Follower path
`nhsAccumulateRoundStats()` fires from the `[NHS] Round is over!` handler in `GroupSync.lua`,
at the same point where `nhsAppendPastRoundSnapshotIfActiveRound()` is already called.
Followers have less data (see Section 6) but can still accumulate most stats.

### Session start/end
- `nhsLeaderStartSession()` records `State.statsSessionStartTime = time()` (Unix timestamp).
- `nhsResetGameSession()` computes elapsed = `time() - State.statsSessionStartTime` and
  adds it to the character stats before resetting.
- Follower session timing: `[NHS] Game session started` sets follower session start time;
  `[NHS] Game Over!` finalizes it.

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
| `uniquePlayersCount` | Derived at display time from `#playerEncounters` |
| `playerFoundByMe` | `{ key = count }` — hiders found by local player as seeker |
| `playerFoundMe` | `{ key = count }` — times each player found the local player (leader only; follower can infer from `foundOrder` sender) |

### Location
| Stat | Notes |
|---|---|
| `houseCounts` | `{ ["persistenceKey"] = { display="...", count=N } }` — full persistence key used (see Section 4); display is most-recently-seen label |
| `uniqueHousesCount` | Derived at display time |
| `neighborhoodCounts` | Bucketed from house persistence key's neighborhood component |

### Mode breakdown
| Stat | Notes |
|---|---|
| `modeCounts` | `{ ["normal"] = N, ... }` — rounds per mode ID |
| `modeSeekerWins` | `{ ["normal"] = N, ... }` — seeker wins per mode |
| `modeHiderSurvivals` | `{ ["normal"] = N, ... }` — survivals per mode |

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

### Follower house key workaround
Followers can only store stats keyed by **display name string** for houses, not by persistence key.
This means the same house under a renamed display could split into two entries over time.
**Decision: accept this limitation for follower house stats.** A future enhancement could sync
the house key via an addon message, but that is out of scope for v1.

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

### "Play Again" feature (planned)
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

- **Display UI**: Stats will need a new tab or panel in the main frame. Layout TBD.
- **Stats reset command**: Should there be a way to reset a character's stats (opt-in)? TBD.
- **Follower house key sync**: Could broadcast a compact house key via addon message so followers get the full key. Out of scope for v1.
- **`statsVersion` migration**: When new stat fields are added, `ensureCharStats()` adds them with
  zero defaults. No destructive migration needed for additive counters.
- **Hot Potato initial role**: The initial "seeker" in Hot Potato starts the round as seeker — they should be counted as a seeker round. But the outcome stat is `hotPotatoLoss` (bad) vs. successfully passing the potato (good). Normal `seekerWins` / `hiderSurvivals` do not apply to Hot Potato rounds.
- **Sardines "winner"**: The sardine (hider) wins if everyone joins. Seekers who find and join the sardine are not "losers." Only seekers who never find the sardine "fail." Track separately from normal seeker/hider win rates? TBD.
