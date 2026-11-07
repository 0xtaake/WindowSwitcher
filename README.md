# WindowSwitcher
Vibe coded alternative to Alt-tab for MacOS

# WindowSwitcher 0.3.5

Eigenständiger, nativer macOS-Fensterumschalter in Swift und AppKit. Das Projekt orientiert sich am Bedienmodell von AltTab für macOS, übernimmt aber keinen Code aus dem Originalprojekt.

## Neu in Version 0.3.5

- Behebt den Build-Fehler im App-Icon-Generator: `NSImage.withTintColor(_:)` wurde durch eine AppKit-kompatible Bitmap-Maskenfärbung mit `sourceIn`-Compositing ersetzt.
- Das weiße SF Symbol wird zunächst auf einem transparenten Bitmap gerendert und anschließend in Weiß eingefärbt. So bleibt das App-Icon-Motiv identisch zum Menüleistensymbol, ohne auf eine nicht verfügbare `NSImage`-Methode angewiesen zu sein.
- Build-Metadaten auf Version `0.3.5` (Build `9`) aktualisiert.

## Neu in Version 0.3.4

- App-Icon für Finder und App-Bundle: verwendet dasselbe SF Symbol (`rectangle.on.rectangle`) wie das Menüleistensymbol.
- Das Build-Skript erzeugt daraus automatisch `AppIcon.icns` in allen benötigten Auflösungen.

## Funktionen aus Version 0.3

- Minimierte Fenster werden über Accessibility-Metadaten erkannt und vor dem Aktivieren wiederhergestellt (soweit die jeweilige App die entsprechenden AX-Attribute bereitstellt).
- Ausgeblendete Anwendungen können einbezogen werden.
- Fenster außerhalb des sichtbaren Desktops werden aus `CGWindowListCopyWindowInfo(.optionAll)` übernommen. Das kann Fenster auf anderen Spaces erfassen; die Space-Zuordnung ist eine Best-Effort-Erkennung und nicht in jedem Fall eindeutig.
- Maus-Hover ändert die Auswahl; ein Klick auf eine Fensterkarte aktiviert das Fenster.
- Einstellungsfenster mit drei Ansichten: Karten mit Vorschau, App-Symbole und kompakte Liste.
- Spaltenzahl und Erscheinungsbild (System/Hell/Dunkel) konfigurierbar.
- Filter zum Ein-/Ausschließen minimierter Fenster, ausgeblendeter Apps und Fenster außerhalb des aktuellen Desktops.
- Ausschlussliste anhand von App-Bundle-Identifiern.
- Konfigurierbarer globaler Hotkey: Tab, Leertaste, A, S oder D kombiniert mit Option, Command und/oder Control. Shift bleibt für Navigation rückwärts reserviert.
- MRU-Reihenfolge (Most Recently Used) wird über Sitzungen hinweg in `UserDefaults` gespeichert.
- ScreenCaptureKit-Aufnahmen werden nur für sichtbare, nicht minimierte Fenster angefordert.

## Voraussetzungen

- macOS 13 oder neuer
- Xcode oder Xcode Command Line Tools (Swift 5.9 oder neuer)
- Für diesen Stand wird die Einstellungsoberfläche vollständig mit AppKit erstellt; SwiftUI-Makro-Plugins sind nicht erforderlich.
- Bedienungshilfen-Berechtigung für globalen Event Tap und das gezielte Aktivieren einzelner Fenster
- Bildschirmaufnahme-Berechtigung für Fenster-Thumbnails (optional; App-Icons und Listenansicht funktionieren ohne sie)
- Für ScreenCaptureKit-Einzelfensterbilder ist macOS 14 oder neuer erforderlich

## Öffnen und bauen

1. Archiv entpacken.
2. `Package.swift` in Xcode öffnen.
3. Schema `WindowSwitcher` und Ziel `My Mac` auswählen.
4. Alternativ im Terminal:

```bash
swift build
```

## Als App bauen

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open build/WindowSwitcher.app
```

Das Skript erzeugt `build/WindowSwitcher.app`, generiert das App-Icon aus dem identischen SF Symbol wie in der Menüleiste und signiert ad hoc. Für eine dauerhafte Installation und stabile macOS-Berechtigungen empfiehlt sich später eine konsistente Signierung mit einer Apple-Entwickleridentität. Ein Neubau mit Ad-hoc-Signatur kann dazu führen, dass macOS Berechtigungen erneut verlangt.

## Bedienung

Der Standard-Hotkey ist `⌥ + Tab`.

| Aktion | Bedienung |
|---|---|
| Switcher öffnen / vorwärts | `⌥ + Tab` |
| Rückwärts | `⇧ + ⌥ + Tab` |
| Weiter / zurück | Tab oder Pfeiltasten rechts/links |
| Auswahl übernehmen | Hotkey-Modifikatortaste(n) loslassen |
| Abbrechen | `Esc` |
| Fenster direkt auswählen | Maus-Hover |
| Fenster aktivieren | Fensterkarte anklicken |

Der Hotkey lässt sich im Menüleistensymbol unter **Einstellungen … → Tastatur** ändern. Shift bleibt als Richtungsumkehr reserviert.

## Einstellungen

- **Allgemein:** visuelle Darstellung, Spaltenzahl und Erscheinungsbild.
- **Fenster:** minimierte Fenster, ausgeblendete Apps, Fenster außerhalb des sichtbaren Desktops und Ausschlussliste.
- **Tastatur:** eine konfigurierbare globale Tastenkombination.

Für die Ausschlussliste werden Bundle-Identifier verwendet, z. B. `com.apple.finder` oder `com.apple.Terminal`.

## Berechtigungen

- **Bedienungshilfen:** erforderlich, um einen globalen Core Graphics Event Tap zu installieren und ein bestimmtes fremdes Fenster über Accessibility zu aktivieren.
- **Bildschirmaufnahme:** nur für die Vorschaubilder. Ohne Freigabe zeigt die App-Symbol-Ansicht weiterhin Icons; die Listenansicht bleibt ebenfalls nutzbar.

Die Anwendung benötigt keine Administratorrechte. macOS-Berechtigungen müssen jedoch vom angemeldeten Benutzer in den Systemeinstellungen erteilt werden.

## Wichtige technische Einschränkungen

1. **Spaces:** macOS bietet keine einfache öffentliche API, die für jedes Fenster eine definitive Space-ID liefert. Wir nutzen die Window-Server-Liste mit `.optionAll` und den On-Screen-Status. Ein nicht sichtbares Fenster kann sich auf einem anderen Space befinden, minimiert sein oder aus einem anderen Grund nicht sichtbar sein. Die Anzeige „Anderer Space / nicht sichtbar“ ist deshalb bewusst als Näherung gekennzeichnet.
2. **Minimierte Fenster:** Die Erkennung nutzt `kAXMinimizedAttribute` und versucht, Fenster über das Accessibility-Attribut `AXWindowNumber` mit Core Graphics zu verknüpfen. Nicht jede App stellt alle Attribute bereit. Ein minimiertes Fenster, das weder in der Window-Server-Liste noch mit einer Fenster-ID über Accessibility verfügbar ist, kann nicht zuverlässig aufgeführt werden.
3. **Aktivierung:** Das gezielte Anheben eines Fensters erfolgt über Accessibility. Manche Apps reagieren verzögert oder stellen mehrere Fenster mit identischen Titeln bereit; bei diesen Fällen bleibt die Zuordnung best effort.
4. **Thumbnails:** ScreenCaptureKit kann nur geeignete, freigegebene Fenster erfassen. Minimierte, ausgeblendete, nicht sichtbare und DRM-geschützte Fenster verwenden deshalb das App-Icon als Fallback.
5. **Hotkeys:** Es gibt in v0.3 einen konfigurierbaren Hotkey. Mehrere unabhängige Hotkey-Profile (wie die bis zu neun Shortcuts in AltTab Pro) sind noch nicht implementiert.
6. **Maus:** Hover markiert eine Karte; Klick aktiviert sie. Aktionen zum Schließen, Minimieren oder Vollbildschalten direkt auf einer Hover-Karte sind noch nicht implementiert.
7. **Suche und Auto-Size:** Titelsuche und automatische dynamische Kachelgrößen sind noch nicht implementiert. Die Kachelansicht zeigt maximal zwölf Einträge gleichzeitig; weitere Einträge werden beim Navigieren eingeblendet.

## Quellcode

```text
Sources/WindowSwitcher/
├── AppDelegate.swift                 # Menüleisten-App und Menü
├── AppSettings.swift                 # Persistente Einstellungen und Hotkey-Modell
├── KeyboardEventMonitor.swift        # Globaler Option/Command/Control-Hotkey
├── SettingsView.swift                # AppKit-Einstellungen (ohne SwiftUI-Makros)
├── SettingsWindowController.swift    # Einstellungsfenster
├── SwitcherCoordinator.swift         # Auswahl, MRU, Navigation und Commit/Cancel
├── SwitcherPanelController.swift     # Fensterkarten, Hover und Klick
├── WindowCatalog.swift               # Fenstererkennung, Filter und Aktivierung
├── WindowInfo.swift                  # Fenstermodell und Statuskennzeichen
├── WindowThumbnailProvider.swift     # ScreenCaptureKit-Vorschaubilder
└── main.swift                        # AppKit-Einstiegspunkt
```

## Nächste sinnvolle Ausbaustufen

- Zuverlässigere Fenster-/AX-Zuordnung und Tests auf mehreren macOS-Versionen.
- Suchfeld für App-Namen und Fenstertitel.
- Mehrere Hotkey-Profile mit eigenen Filtern.
- Dynamische Auto-Size-Layouts.
- Aktionen zum Schließen/Minimieren/Vollbildschalten auf Hover.
- Drag-and-drop und Trackpad-Gesten.
- Launch-at-login über `SMAppService` (opt-in, ohne Root-Rechte).

## Build-Fix für 0.3.1

- Die Einstellungen wurden von SwiftUI auf AppKit umgestellt. Dadurch entfällt die Abhängigkeit vom SwiftUI-Compiler-Makro `SwiftUIMacros.StateMacro`, das bei manchen reinen Command Line Tools-Installationen nicht gefunden wird.
- `acceptsFirstMouse(for:)` verwendet die korrekte optionale `NSEvent?`-Signatur des AppKit-Overrides.


## App-Icon

Beim Build erzeugt `scripts/generate-app-icon.swift` ein 1024×1024-PNG mit dem SF Symbol `rectangle.on.rectangle`. Das Build-Skript skaliert es in die von macOS erwarteten Icon-Größen und erstellt `Contents/Resources/AppIcon.icns`. Dadurch bleibt das Motiv des Finder-/App-Icons mit dem Menüleistensymbol identisch.

