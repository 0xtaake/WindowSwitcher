import AppKit

final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(settings: AppSettings, onSave: @escaping (AppSettings) -> Void) {
        if let window {
            window.setContentSize(NSSize(width: 800, height: 620))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let viewController = SettingsViewController(
            settings: settings,
            onSave: { [weak self] newSettings in
                onSave(newSettings)
                self?.window?.close()
            },
            onCancel: { [weak self] in self?.window?.close() }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WindowSwitcher – Einstellungen"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 580)
        window.contentViewController = viewController
        window.setContentSize(NSSize(width: 800, height: 620))
        window.center()
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { window = nil }
}
