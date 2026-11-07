# WindowSwitcher

This application was vibecoded with ChatGPT Go.

A native macOS window switcher built with Swift and AppKit. WindowSwitcher provides an `Option + Tab` workflow with per-window MRU ordering, optional window previews, keyboard navigation, configurable filters, and a menu bar interface.

## What's new in 0.4.5

- **Current Space only:** windows from inactive Spaces are excluded from the switcher. The legacy preference that allowed other Spaces is ignored so existing settings cannot re-enable off-Space windows.
- **Launch at login:** enable or disable automatic startup from Settings → General. This uses Apple's `SMAppService.mainApp` API and is a per-user login item; administrator privileges are not required. macOS may ask the user to approve the item in System Settings → General → Login Items.
- **Backward-compatible preferences:** existing settings remain readable. The old all-Spaces preference is forced off.

## Features

- Global `Option + Tab` window switcher
- Reverse navigation with `Shift + Option + Tab`
- MRU ordering across individual windows, including windows from the same application
- Optional exclusion of only the currently active window
- Multiple windows from the same app remain independent entries (for example, normal and private Brave windows)
- Current-Space-only window listing
- Optional inclusion of minimized windows
- Optional filtering of hidden applications and excluded bundle identifiers
- Window thumbnails, app-icon view, and compact list view
- Keyboard navigation and optional mouse hover/click interaction
- Configurable appearance and shortcut
- Menu bar integration
- Optional launch at user login

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac
- Xcode Command Line Tools or full Xcode
- Accessibility permission for global shortcut handling, focused-window observation, and activating a specific window
- Screen Recording permission only when window thumbnails are used

## Build

From the project directory:

```bash
chmod +x scripts/build-app.sh
rm -rf .build build
./scripts/build-app.sh
```

The app bundle is created at `build/WindowSwitcher.app`:

```bash
open build/WindowSwitcher.app
```

The build script uses the selected `xcrun swiftc` and active macOS SDK directly. It links AppKit, ApplicationServices, CoreGraphics, ScreenCaptureKit, and ServiceManagement. This avoids invalid linker search paths emitted by some SwiftPM/Command Line Tools combinations.

The app bundle is locally ad-hoc signed. No administrator privileges are needed to build or run the app.

## Install in a stable location

For reliable launch-at-login behavior, keep the app bundle in a stable location. You can copy it to your per-user Applications folder without administrator privileges:

```bash
mkdir -p "$HOME/Applications"
cp -R build/WindowSwitcher.app "$HOME/Applications/WindowSwitcher.app"
open "$HOME/Applications/WindowSwitcher.app"
```

Then enable **Settings → General → Launch at login**. macOS may require approval under **System Settings → General → Login Items**. The app opens this panel when approval is pending.

## Settings

### General

- Visual style: thumbnails, app icons, or compact list
- Appearance: System, Light, or Dark
- Grid column count
- Optional mouse interaction
- **Launch at login** using `SMAppService.mainApp`

### Windows

- Include minimized windows (optional)
- Include hidden applications when they have a window that qualifies for the current-Space list
- Exclude the currently active window without excluding other windows from the same application
- Exclude applications by bundle identifier
- Windows on inactive Spaces are always excluded

### Keyboard

- Configure the trigger key and modifier keys
- `Shift` is reserved for reverse traversal

## Space filtering behavior

Window discovery uses `CGWindowListCopyWindowInfo` with `.optionOnScreenOnly`. The Window Server therefore returns only windows currently visible on the active Spaces across the connected displays. Windows on inactive Spaces are not added to the discovery catalog or MRU history. Minimized windows are a separate opt-in exception and are discovered through Accessibility because macOS does not provide a reliable public Space identifier for minimized windows.

The old `includeWindowsOnOtherSpaces` preference is retained only for decoding compatibility. It is always forced to `false`, even if an older settings file stored `true`.

## Login item behavior

The launch-at-login toggle uses `SMAppService.mainApp` (macOS 13+). Registration is scoped to the current user and does not install a root daemon or require administrator credentials. Depending on macOS security state, the user may need to approve WindowSwitcher in **System Settings → General → Login Items**. The setting reflects both enabled and approval-pending states.

## Keyboard controls

| Shortcut | Action |
| --- | --- |
| `Option + Tab` | Open switcher / advance in MRU order |
| `Shift + Option + Tab` | Reverse MRU traversal |
| Arrow keys | Move selection |
| `Escape` | Cancel |
| Release `Option` | Activate selected window |

## Permissions

- **Accessibility:** global shortcut, Accessibility focus notifications, and activating a selected window
- **Input Monitoring:** may be requested by the global keyboard event monitor on some macOS configurations
- **Screen Recording:** only required to capture thumbnail previews; app icons and titles can still be displayed without it

Manage permissions in **System Settings → Privacy & Security**.

## Known limitations

- Current-Space detection is based on the Window Server's on-screen flag. macOS does not expose a simple public Space ID for every window.
- Minimized windows may be included as an explicit exception; their original Space cannot be reliably determined.
- A hidden application whose windows are not on-screen may not appear even when the hidden-application filter is enabled, because inactive-Space windows are excluded first.
- Some apps expose incomplete Accessibility metadata. Core Graphics windows are retained when AX metadata cannot be matched.
- The initial MRU ordering of windows that were already open before WindowSwitcher launched is an approximation; macOS does not expose their full historical focus sequence.
- Launch-at-login registration is controlled by macOS. A pending approval must be accepted in System Settings.

## Interface mockups

The images in `docs/images` are illustrative UI mockups, not screenshots captured from a running build.

![WindowSwitcher overview](docs/images/00-overview-board.png)

![MRU window ordering](docs/images/07-mru-order-v0.4.0.png)

## Documentation

- [CHANGELOG.md](CHANGELOG.md)
- [Mockup notes](docs/images/README.md)
