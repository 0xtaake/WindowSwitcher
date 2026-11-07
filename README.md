# WindowSwitcher 
This application was vibecoded with ChatGPT Go.
A standalone macOS window switcher built with Swift and AppKit. WindowSwitcher displays individual windows in a visual overview and can be controlled with the keyboard or mouse.

## Highlights in 0.3.7

- **Settings window rebuilt:** the previous compressed `NSTabView` layout has been replaced with a more robust segmented navigation containing three settings pages.
- **Usable settings window size:** the initial size is 800 × 620 pt, and the window can be resized.
- **Stable window order:** the current Window Server front-to-back (Z) order is no longer used as the visible sorting order.
- **Existing windows keep their positions:** newly detected windows are appended in deterministic order.
- **Window ID changes are handled:** when macOS assigns a new `CGWindowID`, WindowSwitcher attempts to match the window to its previous list entry using the app bundle identifier, window title, and last known window position.
- **Accessibility windows are deduplicated:** each Accessibility (AX) entry can be matched to at most one Window Server entry.
- **Ambiguous matches are discarded:** uncertain matches are ignored rather than creating additional cards for the same application.

## Compiler fix in 0.3.7

- The focused-window lookup no longer uses the conditional cast `as? AXUIElement`.
- The value returned by `AXUIElementCopyAttributeValue` is first checked using `CFGetTypeID` against `AXUIElementGetTypeID()` and is then bridged to `AXUIElement`.
- This addresses the Swift compiler error: `conditional downcast to CoreFoundation type AXUIElement will always succeed`.

## Features

- Window overview using `Option + Tab`
- Reverse navigation using `Shift + Option + Tab`
- Keyboard navigation
- Selection by mouse hover and click
- Window cards with thumbnails, app icons, and titles
- Alternative views: app icons and compact list
- Settings for appearance, window filters, and keyboard shortcuts
- Filters for minimized and hidden windows
- Exclusion list based on bundle identifiers
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

## Documentation

- Version history: [CHANGELOG.md](CHANGELOG.md)
