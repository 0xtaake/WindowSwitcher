# WindowSwitcher

This application was vibecoded with ChatGPT Go. 
A standalone macOS window switcher built with Swift and AppKit. WindowSwitcher displays individual windows in a visual overview and can be controlled with the keyboard. Mouse-based selection can now be disabled in Settings.

## Highlights in 0.3.8

- **Optional mouse control:** a setting in **Settings → General → Mouse Control** enables or disables hover selection and click-to-activate for window cards.
- **Keyboard remains fully available:** disabling mouse control does not affect `Option + Tab`, reverse navigation, arrow-key navigation, commit, or cancel.
- **No pointer-based monitor placement when disabled:** the switcher uses the main screen instead of choosing a screen based on the mouse pointer.
- **Settings migration:** preferences written by versions before 0.3.8 are still loaded. The new mouse setting defaults to enabled so existing behavior is preserved until the user changes it.

## Features

- Window overview using `Option + Tab`
- Reverse navigation using `Shift + Option + Tab`
- Keyboard navigation
- Optional mouse hover and click selection
- Window cards with thumbnails, app icons, and titles
- Alternative views: app icons and compact list
- Settings for appearance, window filters, and keyboard shortcuts
- Filters for minimized and hidden windows
- Exclusion list based on bundle identifiers
- Stable session ordering for recognized windows
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

## Mouse control

Mouse control is enabled by default. To disable it:

1. Open the WindowSwitcher menu bar menu.
2. Choose **Settings…**.
3. On the **General** page, find **Mouse Control**.
4. Turn off **Enable mouse control (hover and click)** and save.

When disabled:

- Moving the pointer over a card does not change the selected window.
- Clicking a card does not activate it.
- The switcher does not use the pointer position to choose which display should show the overlay; it uses the main display.
- Keyboard shortcuts and keyboard navigation continue to work normally.

Turn the option back on to restore hover and click selection.

## macOS permissions

- **Accessibility:** required to activate a specific window and read window attributes.
- **Input Monitoring:** may be required by the global keyboard monitor.
- **Screen Recording:** required only for window thumbnails. Without this permission, app icons and window titles remain available where macOS provides them.

Manage these permissions under **System Settings → Privacy & Security**.

## Window ordering and deduplication

WindowSwitcher does not use the changing front-to-back/Z order reported by the Window Server as its visible sorting order. Instead, each recognized window receives a stable position in the list. The known window ID is used first. If macOS assigns a new ID, WindowSwitcher attempts to identify the existing window using the app bundle identifier, normalized window title, and last known window position.

Window discovery combines Core Graphics and Accessibility. When an application provides Accessibility window information, each recognized AX entry is matched to no more than one Core Graphics window. Duplicate AX entries with the same window ID are removed. Entries without a window ID are checked for duplicates using their title and geometry. A Window Server entry that cannot be matched unambiguously is not displayed as an additional card.

Distinct document windows belonging to the same application remain separate entries. Deduplication is intended to remove multiple technical representations of the same window, not to combine all windows belonging to one application.

## Known limitations

- The public macOS APIs used by the app do not provide a simple, reliable Space ID for every window. Detection of windows on other Spaces is therefore best effort.
- Some applications provide incomplete Accessibility metadata. In those cases, a conservative title/geometry match is used; ambiguous windows may be omitted.
- If an application has multiple real windows with the same title and exactly the same position and size, and does not provide a window ID through Accessibility, it may not be technically possible to distinguish them with complete reliability.
- Mouse control currently covers card hover selection and click-to-activate. It does not change the keyboard monitor or other macOS pointer behavior outside the switcher.

## Documentation

- Version history: [CHANGELOG.md](CHANGELOG.md)
