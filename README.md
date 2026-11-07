# WindowSwitcher

This application was vibecoded with ChatGPT Go.


A native macOS window switcher built with Swift and AppKit. WindowSwitcher presents individual application windows in a keyboard-driven overview, with optional mouse selection, configurable appearance, window filters, and most-recently-used (MRU) ordering.

> **UI mockups:** Images in this repository are illustrative, AI-assisted design mockups. They are not screenshots captured from a running build and may show sample content or visual details that differ from the current implementation.

## What's new in 0.4.2

- **Active-application exclusion:** the setting under **Settings → Windows** now hides every switcher entry belonging to the application that was frontmost when the shortcut was pressed.
- **Brave / Chromium compatibility:** the active app is matched by process ID and bundle identifier. Exclusion no longer depends on the focused window exposing an `AXWindowNumber` that matches a Window Server window.
- **Clean Command Line Tools build:** the app build script invokes the selected `swiftc` directly with the active macOS SDK and required frameworks, avoiding invalid `CommandLineTools/Developer/...` linker search paths emitted by some SwiftPM `swiftbuild` + CLT combinations.
- **Backward-compatible preferences:** the old `excludeCurrentWindowFromSwitcher` preference key is retained, so an already-enabled setting remains enabled. Its behavior is now application-wide.

## Active-application exclusion

Enable **Settings → Windows → Active application exclusion** to remove all windows belonging to the application that was frontmost when `Option + Tab` was pressed.

WindowSwitcher matches the active app using:

1. the process ID of `NSWorkspace.shared.frontmostApplication`; and
2. the application's bundle identifier, which also catches regular windows reported under another process belonging to the same app bundle.

This is deliberately independent of Accessibility's focused-window identity. Some browsers, including Brave and other Chromium-based applications, may not provide a focused AX window number that maps consistently to the Window Server entry. Matching the app itself fixes that failure mode and excludes all of its windows, not just one document window.

If the option is enabled but the active application cannot be identified or no matching catalog entries exist, WindowSwitcher fails open and leaves the list unchanged. A diagnostic message is written to the system log. The setting is disabled by default.

> **Preference compatibility:** versions up to 0.4.1 described this preference as excluding the current window and stored it under `excludeCurrentWindowFromSwitcher`. Version 0.4.2 retains that key to preserve existing preferences, but the enabled behavior now excludes the entire active application.

## MRU window ordering

WindowSwitcher keeps a session-level MRU list for individual windows. The most recently focused window is displayed first. Older windows follow in descending order of their last focus/activation.

When you press `Option + Tab`, the currently focused window remains at the first position and the next-most-recent eligible window is selected. Releasing `Option` activates the selected window. The next invocation reflects that activation immediately. `Shift + Option + Tab` starts in the reverse direction.

MRU updates are based on actual focus changes, not on window creation time or the current Window Server stacking order:

1. `NSWorkspace.didActivateApplicationNotification` detects changes between applications.
2. An `AXObserver` listens for `kAXFocusedWindowChangedNotification` for each regular application, allowing WindowSwitcher to detect focus changes between windows in the same app.
3. A 350 ms foreground-window check acts as a fallback for apps that do not publish the expected Accessibility notifications.
4. A 750 ms discovery pass adds newly created windows to the catalog. A newly opened window moves to the front when it becomes the focused window.

## Features

- Window overview using `Option + Tab`
- Reverse navigation using `Shift + Option + Tab`
- MRU ordering across individual windows, including windows within the same application
- Optional exclusion of all windows belonging to the currently active application
- Keyboard navigation with arrow keys
- Optional mouse hover selection and click-to-activate
- Window cards with thumbnails, app icons, and titles
- Alternative views: app icons and compact list
- Settings for appearance, window filters, and keyboard shortcuts
- Filters for minimized windows, hidden applications, and other Spaces
- Exclusion list based on bundle identifiers
- Duplicate filtering between Core Graphics and Accessibility window records
- Menu bar integration

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- Xcode Command Line Tools or full Xcode
- Swift compiler supplied by the selected developer tools

## Build

Run the following commands from the project directory:

```bash
chmod +x scripts/build-app.sh
rm -rf .build build
./scripts/build-app.sh
```

The app bundle is created at `build/WindowSwitcher.app`. Launch it with:

```bash
open build/WindowSwitcher.app
```

The build script calls `xcrun swiftc` directly with the selected macOS SDK and links AppKit, ApplicationServices, CoreGraphics, and ScreenCaptureKit. It intentionally does not use SwiftPM's default `swiftbuild` backend. Some Swift 6.4 / Command Line Tools-only installations have emitted invalid search paths under `CommandLineTools/Developer/...` during `swift build`; those warnings originate in SwiftPM's build backend, not in this project's source or linker settings. Direct `swiftc` compilation avoids those synthetic paths. `Package.swift` remains in the repository for IDE/package integration, but `scripts/build-app.sh` is the supported app-bundle build path.

The script creates the app bundle locally, generates `AppIcon.icns`, and applies ad-hoc signing. Administrator privileges are not required.

## Keyboard controls

| Shortcut | Action |
| --- | --- |
| `Option + Tab` | Open the switcher / select the next-most-recent eligible window |
| `Shift + Option + Tab` | Start switching in reverse MRU order |
| Arrow keys | Move the selection |
| `Escape` | Cancel without changing the MRU order |
| Release `Option` | Activate the selected window and promote it to MRU position 1 |

The shortcut can be configured in the app's settings.

## Mouse control

Mouse control can be enabled or disabled in **Settings → General**. When disabled, hover and click interactions on window cards are ignored; keyboard navigation remains available.

## macOS permissions

- **Accessibility:** required to activate a specific window, read window attributes, and subscribe to per-app focused-window notifications.
- **Input Monitoring:** may be required by the global keyboard monitor.
- **Screen Recording:** required only for window thumbnails. Without this permission, app icons and window titles remain available where macOS provides them.

Manage these permissions under **System Settings → Privacy & Security**.

## Window detection and duplicate filtering

Window discovery combines Core Graphics and Accessibility metadata. When an app provides Accessibility window information, each recognized AX entry is matched to no more than one Core Graphics window. Duplicate AX entries with the same window ID are removed. Entries without a window ID are checked for duplicates using title and geometry. Ambiguous Window Server entries are omitted rather than displayed as extra cards.

Distinct document windows belonging to the same application remain separate entries. Deduplication is intended to remove multiple technical representations of the same window, not to combine all windows belonging to one app.

## Known limitations

- The public macOS APIs used by the app do not provide a simple, reliable Space ID for every window. Detection of windows on other Spaces is best effort.
- Some applications provide incomplete Accessibility metadata. Ambiguous windows may be omitted to avoid duplicate cards.
- Initial MRU order for windows that were already open before WindowSwitcher starts is approximate after the current focused window; macOS does not expose their complete historical focus order.
- Apps that do not emit focused-window Accessibility notifications rely on the foreground polling fallback, so intra-app MRU changes may be delayed by up to roughly one polling interval.
- MRU history is session-local and is rebuilt when WindowSwitcher is relaunched.

## Interface mockups

The `docs/images` folder contains illustrative UI concepts. These are mockups rather than captures from a running application.

![WindowSwitcher overview](docs/images/00-overview-board.png)

### Most-recently-used ordering

![WindowSwitcher MRU ordering](docs/images/07-mru-order-v0.4.0.png)

### Settings concepts

![General settings](docs/images/03-settings-general.png)

![Window settings](docs/images/04-settings-windows.png)

![Keyboard settings](docs/images/05-settings-keyboard.png)

## Documentation

- Version history: [CHANGELOG.md](CHANGELOG.md)
- Mockup image notes: [docs/images/README.md](docs/images/README.md)
