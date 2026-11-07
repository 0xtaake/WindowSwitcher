import AppKit
import ApplicationServices
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Keep this symbol in sync with scripts/generate-app-icon.swift.
    private let appSymbolName = "rectangle.on.rectangle"
    private var statusItem: NSStatusItem?
    private let keyboardMonitor = KeyboardEventMonitor()
    private let switcher = SwitcherCoordinator()
    private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        switcher.startWindowDiscovery()

        keyboardMonitor.shortcut = ShortcutConfiguration(settings: AppSettingsStore.shared.settings)
        keyboardMonitor.onBegin = { [weak self] reverse in
            DispatchQueue.main.async { self?.switcher.begin(reverse: reverse) }
        }
        keyboardMonitor.onStep = { [weak self] reverse in
            DispatchQueue.main.async { self?.switcher.step(reverse: reverse) }
        }
        keyboardMonitor.onCommit = { [weak self] in
            DispatchQueue.main.async { self?.switcher.commit() }
        }
        keyboardMonitor.onCancel = { [weak self] in
            DispatchQueue.main.async { self?.switcher.cancel() }
        }

        let started = keyboardMonitor.start()
        updateStatusMenu(eventTapReady: started)
        if !started { keyboardMonitor.requestAccessibilityPermission() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor.stop()
        switcher.stopWindowDiscovery()
    }

    @objc private func requestPermissions() {
        keyboardMonitor.requestAccessibilityPermission()
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(settingsURL)
        let started = keyboardMonitor.start()
        updateStatusMenu(eventTapReady: started)
    }

    @objc private func openScreenRecordingSettings() {
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(settingsURL)
    }

    @objc private func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
        openScreenRecordingSettings()
    }

    @objc private func retryKeyboardMonitor() {
        let started = keyboardMonitor.start()
        updateStatusMenu(eventTapReady: started)
        if !started { requestPermissions() }
    }

    @objc private func showOverviewForDiagnostics() { switcher.previewOverviewForDiagnostics() }

    @objc private func openPreferences() {
        var settings = AppSettingsStore.shared.settings
        settings.launchAtLoginEnabled = LoginItemManager.isEnabledOrPendingApproval
        settings.includeWindowsOnOtherSpaces = false
        settingsWindow.show(settings: settings) { [weak self] newSettings in
            guard let self else { return }
            var settingsToSave = newSettings
            settingsToSave.includeWindowsOnOtherSpaces = false

            do {
                try LoginItemManager.setEnabled(newSettings.launchAtLoginEnabled)
            } catch {
                settingsToSave.launchAtLoginEnabled = LoginItemManager.isEnabledOrPendingApproval
                self.presentLoginItemError(error)
            }

            settingsToSave.launchAtLoginEnabled = LoginItemManager.isEnabledOrPendingApproval
            AppSettingsStore.shared.save(settingsToSave)
            self.keyboardMonitor.shortcut = ShortcutConfiguration(settings: settingsToSave)
            self.updateStatusMenu(eventTapReady: self.keyboardMonitor.isRunning)
        }
    }

    private func presentLoginItemError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Autostart konnte nicht geändert werden"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Anmeldeobjekte öffnen")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            LoginItemManager.openSystemSettings()
        }
    }

    @objc private func openLoginItemsSettings() {
        LoginItemManager.openSystemSettings()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: appSymbolName, accessibilityDescription: "WindowSwitcher")
        item.button?.toolTip = "WindowSwitcher – Fenster wechseln"
        statusItem = item
    }

    private func updateStatusMenu(eventTapReady: Bool) {
        let menu = NSMenu()
        let title = NSMenuItem(
            title: eventTapReady ? "Tastatursteuerung aktiv" : "Bedienungshilfen erforderlich",
            action: nil,
            keyEquivalent: ""
        )
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let overviewItem = NSMenuItem(title: "Fensterübersicht testen", action: #selector(showOverviewForDiagnostics), keyEquivalent: "")
        overviewItem.target = self
        menu.addItem(overviewItem)

        let preferencesItem = NSMenuItem(title: "Einstellungen …", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        if LoginItemManager.requiresApproval {
            let loginItem = NSMenuItem(title: "Anmeldeobjekte in Systemeinstellungen prüfen …", action: #selector(openLoginItemsSettings), keyEquivalent: "")
            loginItem.target = self
            menu.addItem(loginItem)
        }

        let permissionItem = NSMenuItem(title: "Bedienungshilfen öffnen …", action: #selector(requestPermissions), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let screenRecordingItem = NSMenuItem(title: "Bildschirmaufnahme-Berechtigung öffnen …", action: #selector(requestScreenRecordingPermission), keyEquivalent: "")
        screenRecordingItem.target = self
        menu.addItem(screenRecordingItem)

        let retryItem = NSMenuItem(title: "Tastatursteuerung erneut versuchen", action: #selector(retryKeyboardMonitor), keyEquivalent: "")
        retryItem.target = self
        menu.addItem(retryItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "WindowSwitcher beenden", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }
}
