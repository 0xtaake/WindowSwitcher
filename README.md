# WindowSwitcher

A native macOS window switcher built with Swift and AppKit. WindowSwitcher presents individual application windows in a keyboard-driven overview, with optional mouse selection, configurable appearance, and window filters.

> **UI mockups:** The images below are illustrative, AI-assisted design mockups. They are not screenshots captured from a running build and may contain visual details that differ from the current implementation.

## What's new in 0.3.9

- **Newest-opened-first ordering:** newly discovered windows are placed at the beginning of the switcher list.
- **No reordering on activation:** switching to an existing window does not change its position in the list.
- **Background discovery:** WindowSwitcher checks for newly opened windows every 750 ms while the switcher is hidden, so new windows are detected before the next `Option + Tab` invocation.
- **Initial ordering fallback:** for windows already open when WindowSwitcher starts, the app uses the owning application's launch date where available, followed by a deterministic fallback order.

## Open-time ordering

WindowSwitcher keeps a session-level discovery order for individual windows. The newest newly discovered window is shown first, followed by older windows in descending discovery order. The list is independent of the frontmost-window/Z-order changes caused by activating or switching between existing windows.

The discovery loop starts with the app and samples the macOS window list every 750 ms. A newly detected window is inserted at the front. If several windows appear between two samples, WindowSwitcher uses a deterministic tie-break for that batch; macOS does not publish an exact creation timestamp for every window. The tracked discovery sequence is held in memory for the current WindowSwitcher session and is not persisted across app restarts.

### macOS limitation

Public macOS APIs do not provide a reliable creation timestamp for every existing window. Therefore:

- Windows opened **after WindowSwitcher starts** are ordered by when WindowSwitcher first detects them. In ordinary use, this tracks opening order closely.
- Windows already open **before WindowSwitcher starts** are seeded using the owning application's launch date where available. Multiple pre-existing windows from the same app use a stable title/geometry fallback, not a guaranteed historical creation order.
- If several windows are opened within the same 750 ms discovery interval, their exact order cannot always be determined. A deterministic tie-break is used instead.

This is an open-time/discovery order, not a most-recently-activated (MRU) order. Activating an older window does not move it to the front.

## Interface mockups

### Newest-opened-first ordering (0.3.9)

![WindowSwitcher newest-opened-first ordering](docs/images/06-opened-order-v0.3.9.png)

### Main switcher and other views

![WindowSwitcher overview](docs/images/00-overview-board.png)

<details>
<summary>More UI concepts</summary>

#### Main window switcher

![Main window switcher](docs/images/01-main-window-switcher.png)

#### Compact view

![Compact view](docs/images/02-compact-view.png)

#### General settings

![General settings](docs/images/03-settings-general.png)

#### Window settings

![Window settings](docs/images/04-settings-windows.png)

#### Keyboard settings

![Keyboard settings](docs/images/05-settings-keyboard.png)

</details>

## Features

- Window overview using `Option + Tab`
- Reverse navigation using `Shift + Option + Tab`
- Keyboard navigation with arrow keys
- Optional mouse hover selection and click-to-activate
- Window cards with thumbnails, app icons, and titles
- Alternative views: app icons and compact list
- Settings for appearance, window filters, and keyboard shortcuts
- Filters for minimized windows, hidden applications, and other Spaces
- Exclusion list based on bundle identifiers
- Duplicate filtering between Core Graphics and Accessibility window records
- Newest-opened-first discovery ordering
- Menu bar integration

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- Swift 5.9 or later
- Xcode or Xcode Command Line Tools

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

The build script creates a local app bundle, generates `AppIcon.icns`, and applies ad-hoc signing. Administrator privileges are not required.

## Keyboard controls

| Shortcut | Action |
| --- | --- |
| `Option + Tab` | Open the switcher / move forward |
| `Shift + Option + Tab` | Move backward |
| Arrow keys | Move the selection |
| `Escape` | Cancel |
| Release `Option` | Activate the selected window |

The shortcut can be configured in the app's settings.

## Mouse control

Mouse control can be enabled or disabled in **Settings → General**. When disabled, hover and click interactions on window cards are ignored; keyboard navigation remains available.

## macOS permissions

- **Accessibility:** required to activate a specific window and read window attributes.
- **Input Monitoring:** may be required by the global keyboard monitor.
- **Screen Recording:** required only for window thumbnails. Without this permission, app icons and window titles remain available where macOS provides them.

Manage these permissions under **System Settings → Privacy & Security**.

## Window detection and duplicate filtering

Window discovery combines Core Graphics and Accessibility metadata. When an app provides Accessibility window information, each recognized AX entry is matched to no more than one Core Graphics window. Duplicate AX entries with the same window ID are removed. Entries without a window ID are checked for duplicates using title and geometry. Ambiguous Window Server entries are omitted rather than displayed as extra cards.

Distinct document windows belonging to the same application remain separate entries. Deduplication is intended to remove multiple technical representations of the same window, not to combine all windows belonging to one app.

## Known limitations

- The public macOS APIs used by the app do not provide a simple, reliable Space ID for every window. Detection of windows on other Spaces is best effort.
- Some applications provide incomplete Accessibility metadata. Ambiguous windows may be omitted to avoid duplicate cards.
- Exact creation order cannot be reconstructed for all windows that were already open before WindowSwitcher started, or for multiple windows first discovered during the same 750 ms polling interval.
- The discovery sequence is session-local and is rebuilt when WindowSwitcher is relaunched.
- The switcher's visible list is ordered by discovery/open time; activation does not change this order.

## Documentation

- Version history: [CHANGELOG.md](CHANGELOG.md)
- Mockup image notes: [docs/images/README.md](docs/images/README.md)
