# Changelog

All notable changes to WindowSwitcher are documented in this file.

## [0.4.2] - 2026-11-07

### Fixed

- Active-app exclusion now removes **all windows belonging to the frontmost application**, rather than trying to match only one focused window.
- Match the active app by process ID and bundle identifier. This avoids relying on `AXWindowNumber` and fixes the failure mode where Brave or another Chromium-based browser does not provide a focused AX window number that matches its Window Server entry.
- If the active app cannot be identified or no matching windows are in the current catalog, fail open and leave the switcher list unchanged. A diagnostic message is emitted.
- Retain the existing `excludeCurrentWindowFromSwitcher` preference key so saved configurations from 0.4.1 remain readable. The enabled behavior is now application-wide.

### Build

- Replace SwiftPM's `swift build -c release` app build with direct `xcrun swiftc` compilation using the selected macOS SDK.
- Link AppKit, ApplicationServices, CoreGraphics, and ScreenCaptureKit explicitly.
- Avoid the invalid `CommandLineTools/Developer/usr/lib` and `CommandLineTools/Developer/Library/Frameworks` search paths emitted by some SwiftPM `swiftbuild` + standalone Command Line Tools combinations.
- Keep `Package.swift` for IDE and package integration; `scripts/build-app.sh` is the supported app-bundle build path.

### Documentation

- Update README to describe app-wide exclusion, Brave/Chromium handling, preference compatibility, and the direct compiler build path.

## [0.4.1] - 2026-11-07

### Added

- Added an optional setting to exclude the currently focused window from the switcher.
- When enabled, the next-most-recent window becomes the first selectable item.
- Existing settings files default the new option to `false`.

## [0.4.0] - 2026-11-07

### Added

- Added most-recently-used (MRU) ordering for individual windows.
- Added intra-application focus tracking through Accessibility notifications.
- Added application activation tracking through `NSWorkspace` notifications.
- Added a polling fallback for applications that do not publish focus notifications reliably.
- Added an MRU ordering UI mockup.

## [0.3.9] - 2026-11-07

### Changed

- Added an initial opened-time ordering concept with background discovery of newly opened windows.
- Updated README and mockups to explain the opened-time ordering model.

## [0.3.8] - 2026-11-07

### Added

- Added a setting to enable or disable mouse hover selection and click-to-activate.
- Preserved keyboard navigation when mouse control is disabled.

## [0.3.7] - 2026-11-07

### Fixed

- Replaced a conditional `AXUIElement` downcast with an explicit Core Foundation type-ID check.

## [0.3.6] - 2026-11-07

### Fixed

- Reworked the settings page layout to avoid compressed controls.
- Stabilized window ordering and reduced duplicate Core Graphics / Accessibility entries.

## [0.3.5] - 2026-11-07

### Fixed

- Replaced unavailable `NSImage.withTintColor` usage in app icon generation.

### Documentation

- Added GitHub-compatible README and changelog files.

## [0.3.4] - 2026-11-07

### Added

- Added an app icon based on the menu bar symbol.

## [0.3.3] - 2026-11-07

### Fixed

- Increased and made the settings window resizable.

## [0.3.2] - 2026-11-07

### Fixed

- Improved Core Graphics / Accessibility window deduplication and stable ordering.

## [0.3.1] - 2026-11-07

### Fixed

- Replaced the SwiftUI settings view with AppKit controls.
- Corrected the `acceptsFirstMouse(for:)` override signature.

## [0.3.0] - 2026-11-07

### Added

- Initial implementation of the native macOS window switcher, window filters, appearance settings, thumbnails, and keyboard/mouse navigation.
