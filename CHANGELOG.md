# Changelog

All notable changes to WindowSwitcher are documented in this file.

## [0.3.8] - 2026-11-07

### Added

- Added an **Enable mouse control (hover and click)** checkbox to the General settings page.
- Added a short explanation describing which mouse interactions are disabled.
- Updated the switcher subtitle to indicate when mouse control is disabled.

### Changed

- Window cards only install mouse-tracking areas when mouse control is enabled.
- Hover selection and click-to-activate callbacks are disabled when the setting is off.
- With mouse control disabled, the overlay uses the main display instead of using the pointer position to choose a display.
- Keyboard navigation remains unchanged and fully functional when mouse control is disabled.

### Compatibility

- Added backward-compatible decoding for existing settings files. If the new `mouseControlEnabled` key is absent, it defaults to `true`, preserving the previous behavior and retaining other saved preferences.

### Build

- Updated the app version to 0.3.8 and build number to 13.

### Validation

- Parsed all Swift source files using the Swift compiler frontend.
- Validated the Swift package manifest.
- Checked the build script with `bash -n`.
- A complete AppKit build still needs to be run on macOS.

## [0.3.7] - 2026-11-07

### Fixed

- Removed the conditional cast `focusedValue as? AXUIElement`. `AXUIElement` is a Core Foundation type, and Swift diagnoses this conditional cast as always succeeding, which caused the build to fail.
- The value is now checked using `CFGetTypeID(value) == AXUIElementGetTypeID()` before being bridged to `AXUIElement` with `unsafeBitCast`.
- The existing Core Graphics fallback detection remains available when the focused-window value is missing or is not the expected type.

### Build

- Updated the app version to 0.3.7 and the build number to 12.

## [0.3.6] - 2026-11-07

### Fixed

- Replaced the compressed `NSTabView` settings layout. The **General**, **Windows**, and **Keyboard** pages are now switched using segmented navigation.
- Constrained settings-page content to the available window area and gave labels and help text a defined width.
- Set the settings window's initial size to 800 × 620 pt and its minimum size to 760 × 580 pt.
- Prevented window cards from changing positions during repeated `Option + Tab` presses due to the current Window Server order.
- Prevented a temporarily empty Window Server or Accessibility snapshot from resetting the existing sort order.
- Preserved a window's list position when macOS assigns a new `CGWindowID` to the same window. Matching uses the bundle identifier, window title, and last known geometry.
- Removed duplicate Accessibility entries with the same window ID.
- Checked Accessibility entries without a window ID for obvious duplicates using title and geometry.
- Limited each Accessibility window to at most one matched Core Graphics entry. Ambiguous matches are discarded to avoid creating extra cards for helper windows.

### Changed

- The sort order now remains stable for the lifetime of the application and is independent of which window is currently active.
- Newly detected windows are appended deterministically to the existing order.
- Distinct windows belonging to the same application remain visible as separate entries.

### Notes

- Space detection remains best effort because of limitations in the public macOS APIs.

## [0.3.5]

### Fixed

- Removed use of the unavailable `NSImage.withTintColor` method from icon generation.

### Documentation

- Added standalone, GitHub-compatible README and changelog Markdown files.

## [0.3.4]

### Added

- Added a macOS app icon based on the menu bar icon.
- Updated the build script to generate the app icon and include it in the app bundle.

## [0.3.3]

### Fixed

- Increased the settings window size and made it resizable.
- Adjusted the minimum window size and layout spacing.

## [0.3.2]

### Fixed

- First round of fixes for stable window ordering and deduplication of Window Server and Accessibility entries.

## [0.3.1]

### Fixed

- Removed the SwiftUI `@State` dependency from the settings interface.
- Corrected the AppKit override signature for `acceptsFirstMouse(for:)`.

## [0.3.0]

### Added

- Initial implementation of window filters, display styles, mouse navigation, and a settings interface.
