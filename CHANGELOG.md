# Changelog

All notable changes to WindowSwitcher are documented here.

## [0.4.5] - 2026-11-07

### Added
- Launch at login toggle in **Settings → General** using Apple's `SMAppService.mainApp` API.
- Status handling for enabled and approval-pending login item states.
- A menu bar shortcut to open Login Items settings when macOS approval is pending.
- Explicit ServiceManagement framework linkage in the direct `swiftc` build script and Swift package manifest.

### Changed
- Window discovery now uses `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`, so regular windows from inactive Spaces are never added to the catalog or MRU history.
- The legacy `includeWindowsOnOtherSpaces` preference is retained for decoding older settings but is always forced to `false`.
- The Windows settings page explains current-Space-only behavior and the minimized-window exception.

### Compatibility and limitations
- Existing user preferences remain readable; launch-at-login defaults to off.
- Minimized windows remain an optional exception because macOS does not expose a reliable public Space identifier for them.
- Launch-at-login registration is per-user and does not require administrator privileges. macOS may request approval in System Settings.

## [0.4.4]

### Fixed
- Kept valid Core Graphics windows when Accessibility metadata could not be matched, improving browser window discovery.
- Retained per-window identity based on owner PID and CGWindowID.
- Updated build script to invoke the selected Swift compiler directly and avoid invalid SwiftPM linker search paths.

## [0.4.3]

### Fixed
- Changed active-window exclusion to target a specific window rather than the entire application.
- Preserved other windows from the same app, including separate normal and private browser windows.

## [0.4.2]

### Fixed
- Improved active-window identification using process and bundle information.
- Removed noisy invalid linker search paths from the build path.

## [0.4.1]

### Added
- Option to exclude the currently active window from the switcher.

## [0.4.0]

### Added
- Session-level MRU ordering based on observed focus changes.
- Per-window focus tracking within the same application.

## [0.3.9]

### Added
- Window discovery polling and insertion-time tracking as a basis for ordering.
- Updated GitHub mockups and README.

## [0.3.8]

### Added
- Setting to disable mouse hover and click interaction while retaining keyboard navigation.

## [0.3.7]

### Fixed
- Corrected Core Foundation type handling for Accessibility window elements.

## [0.3.6]

### Fixed
- Stabilized switcher ordering and improved matching between Core Graphics and Accessibility window records.
- Reworked the settings layout.

## [0.3.5]

### Fixed
- Replaced an unavailable `NSImage.withTintColor` call in the app icon generator with compatible bitmap rendering.
- Added GitHub-ready English documentation.

## [0.3.4]

### Added
- Generated an app icon matching the menu bar symbol.

## [0.3.3]

### Fixed
- Increased settings window size and improved layout constraints.

## [0.3.2]

### Fixed
- Stabilized window ordering and reduced duplicate window entries.

## [0.3.1]

### Fixed
- Replaced SwiftUI settings with AppKit controls for better compatibility with Command Line Tools builds.
- Corrected the `acceptsFirstMouse` override signature.

## [0.3.0]

### Added
- First extended version with settings, window filtering, multiple visual styles, and mouse navigation.
