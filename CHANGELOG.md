# Changelog

All notable changes to Neighborhood Hide and Seek are documented in this file.

## [1.2.1]

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
