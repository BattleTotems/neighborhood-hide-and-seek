# Changelog

All notable changes to Neighborhood Hide and Seek are documented in this file.

## [1.3.0]

### Added
- New icon!
- New Game Mode: Sardines
- New Game Mode: Hot Potato
- Game mode checkboxes next to each mode button let you control which modes are included in the Random pool for each round
- The last 2 game modes played this session are unchecked by default so Random picks something fresh
- Game Modes info panel now has per-mode checkboxes to set your personal default inclusion preferences, saved between sessions
- Addon version checker as an option and at the start of sessions so that you can know for sure people are running the same version

### Changed
- Previous rounds, houses, and seeker screens now live update as the data changes
- Seeker mode should now handle hiding party/raid frames for some other popular addons with their own frames
- Added additional callouts for when houses are not in the same neighborhood or subdivision as the previous house
- Chosen One game mode now reduces the search time by 15 seconds per seeker
- Overtime game mode search time values adjusted
- Bloodhound targeting logic has been changed and updates more frequently
- Selecting a random game mode will now use the random animation picker (unless disabled)

### Fixed
- Previous rounds now saves correctly even before the main view is opened
- Fixed issue with some gameplay logic being tied to the game control view
- Late player added during Chosen One are added to seekers
- Fixed a desync issue with players enter/leaving houses during certain game phases
- Applying a random seed on addon launch for better random values in the sessions


## [1.2.5]

### Added
- Back button during game setup
- Automatically end the searching phase if the seeker finds everyone
- Added more hindrances in Toying around (11 -> 18)

### Changed
- Removed a prison toy from Toying Around that would not allow the seeker to select the hider
- Updated logic on saving to the previous seeker, house, and rounds lists to be more consistent and reliable

### Fixed
- Fixed an issue for cross server players from seeing other players as marked ready during hiding
- Cleared the session HUD on login when there is no active game session or not in a group
- Group sync button now syncs game mode as well


## [1.2.4]

### Added
- Hiders now receive a low health frame warning when any seeker is within 10 yards while hiding
- Previous Rounds panel now has an "Export Rounds" button that opens the round history as selectable text (Ctrl+A, Ctrl+C to copy, e.g. into Discord)

### Changed
- Renamed game mode "Toy & Seek" to "Toying Around"
- How To Play screen now shows full minutes and seconds for house size preset times (e.g. "5 min 30 sec")

### Fixed
- Fixed the leader appearing in the hidden list on non-leader clients when the leader is a seeker (realm-format key mismatch)


## [1.2.3]

### Added
- Added a new game mode: Toy & Seek


## [1.2.2]

### Added
- Added a new game mode: Bloodhound


## [1.2.1]

### Added
- Added a new game mode: Overtime
- Added a ready up feature while hiding

### Changed
- Changed normal plus to cancel sleep animations and do a roar if not in a whistle-able form

### Fixed
- Fixed the description of the game modes to be the same throughout
- Fixed some minor UI issues


## [1.2.0]

### Added
- Added 6 new game modes for more exciting play
- New reveal phase added after searching
- Added an entering seeker popup to let the user know what is going on and to hide any custom UI
- Added an easier way to get back into seeker mode during gameplay if you get out of sync
- Added a quick info button in the gameplay session HUD to open the main window
- Added an option to update your saved list with all the newly reported data like neighborhood and subdivision

### Changed
- Found player list is now kept in order of when they were found
- Preset timers slightly reduced for searching
- Backend game phase logic cleaned up
- House list subdivision now manually set

### Fixed
- Enemy player names now auto hide when in seeker mode
- No longer always trigger cancel timers when leaving a group
- When using currenty neighborhood option during a game the cache is no longer cleared when changing zones
- Fixed an issue with going into hiding phase when the leader has BigWigs installed


## [1.1.0]

### Added

- Uniqueness for houses based on neighborhood and subdivision.
- More options in settings.
- Sync buttons to help new or desynced players during gameplay.
- Custom timer options during gameplay.
- Choice of which house list to use at the start of gameplay.
- Escape key now closes addon windows.

### Changed

- Previous round information now stays until you start a new session, so you can review it afterward.
- Cleaned up some leader gameplay UI.
- Disabled houses in the house list with no owner.

### Fixed

- Backend fixes to help keep all players synced during gameplay.
