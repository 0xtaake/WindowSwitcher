# Changelog

All notable changes to WindowSwitcher are documented in this file.

## [0.4.0] - 2026-11-07

### Added

- Added most-recently-used (MRU) ordering for individual windows. The currently focused window is shown first, followed by previously focused windows in descending recency.
- Added per-application `AXObserver` registrations for `kAXFocusedWindowChangedNotification`, allowing focus changes between windows of the same app to update MRU order.
- Added `NSWorkspace.didActivateApplicationNotification` handling for application-level activation changes.
- Added a 350 ms foreground-window polling fallback for applications that do not reliably emit Accessibility focus notifications.
- Added immediate MRU promotion when the user commits a switch, so the next switcher invocation reflects the selected window without waiting for a later notification.
- Added a new GitHub mockup illustrating MRU ordering.

### Changed

- Replaced the 0.3.9 newest-opened-first/discovery ordering with actual most-recently-used ordering.
- Newly discovered background windows are appended to the tracked catalog; they move to the front when they become the focused window.
- Initial ordering puts the currently focused window first and uses the Window Server's front-to-back order as a best-effort seed for other windows already open at startup.
- Preserved the existing duplicate filtering, window identity rebinding, window filters, mouse-control preference, and settings UI.

### Notes and limitations

- macOS does not expose a complete historical MRU timeline for windows that were already open before WindowSwitcher starts. Their initial order after the current focused window is best effort.
- Per-app focus tracking depends on Accessibility notifications. Some apps may rely on the polling fallback, which can introduce a short delay.
- MRU history remains session-local and is rebuilt when WindowSwitcher is relaunched.

### Build

- Updated the app version to 0.4.0 and build number to 15.

## [0.3.9] - 2026-11-07

### Added

- Added newest-opened-first ordering for individual windows.
- Added a background discovery timer that samples the window list every 750 ms while the switcher is hidden.
- Added application launch-date metadata to seed a best-effort initial order for windows already open when WindowSwitcher starts.
- Added a GitHub mockup illustrating the opened-time order.

### Changed

- Newly discovered windows are inserted at the beginning of the switcher list.
- Activating or switching to an existing window no longer changes the visible list order.
- Limited Accessibility identity-rebinding to recently seen windows, reducing the chance that a newly opened same-title window inherits an old entry's position.
- The discovery loop pauses while the switcher overlay is visible to keep the displayed list stable during navigation.

### Notes and limitations

- macOS does not expose a reliable per-window creation timestamp for arbitrary existing windows. The order of windows already open at startup is seeded using application launch dates where possible and a deterministic title/geometry fallback.
- Windows first detected in the same 750 ms polling pass use a deterministic tie-break; their exact chronological order may not be recoverable.
- This was opened-time/discovery ordering, not most-recently-activated (MRU) ordering.
- The discovery sequence was session-local and rebuilt when WindowSwitcher was relaunched.

### Build

- Updated the app version to 0.3.9 and build number to 14.

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

## [0.3.7] - 2026-11-07

### Fixed

- Removed the conditional cast `focusedValue as? AXUIElement`. `AXUIElement` is a Core Foundation type, and Swift diagnoses this conditional cast as always succeeding.
- The value is now checked using `CFGetTypeID(value) == AXUIElementGetTypeID()` before being bridged to `AXUIElement` with `unsafeBitCast`.
- The existing Core Graphics fallback detection remains available when the focused-window value is missing or is not the expected type.

### Build

- Updated the app version to 0.3.7 and build number to 12.

## [0.3.6] - 2026-11-07

### Fixed

- Replaced the compressed `NSTabView` settings layout with segmented navigation for General, Windows, and Keyboard pages.
- Constrained settings-page content to the available window area and gave labels and help text a defined width.
- Set the settings window's initial size to 800 × 620 pt and its minimum size to 760 × 580 pt.
- Prevented window cards from changing positions during repeated `Option + Tab` presses due to the current Window Server order.
- Prevented a temporarily empty Window Server or Accessibility snapshot from resetting the existing sort order.
- Preserved a window's list position when macOS assigns a new `CGWindowID` to the same window. Matching uses the bundle identifier, window title, and last known window position.
- Removed duplicate Accessibility entries with the same window ID.
- Limited each Accessibility window to at most one matched Core Graphics entry.

### Changed

- Kept the sort order stable for the lifetime of the application and independent of which window was active.
- Newly detected windows were appended deterministically to the existing order.
- Distinct windows belonging to the same application remained visible as separate entries.

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
