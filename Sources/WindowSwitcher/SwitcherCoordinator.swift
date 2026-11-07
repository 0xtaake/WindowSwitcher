import AppKit
import CoreGraphics

final class SwitcherCoordinator {
    private let catalog = WindowCatalog()
    private let panel = SwitcherPanelController()
    private let thumbnailProvider = WindowThumbnailProvider()
    private let focusObserver = WindowFocusObserver()
    private var windows: [WindowInfo] = []
    private var thumbnails: [CGWindowID: NSImage] = [:]
    private var thumbnailTargetIDs: [CGWindowID] = []

    private struct WindowGroup: Equatable {
        let bundleIdentifier: String
        let title: String
    }

    private struct MRUWindowEntry {
        var identity: WindowIdentity
        let group: WindowGroup
        var lastBounds: CGRect
        var lastSeenAt: Date
    }

    /// Most-recently-used order: index 0 is the last focused window.
    /// Activating a window moves its entry to the front; opening a background
    /// window alone does not change the activation history.
    private var mruWindowEntries: [MRUWindowEntry] = []

    private var discoveryTimer: Timer?
    private var focusTrackingTimer: Timer?
    private var applicationActivationObserver: NSObjectProtocol?
    private let discoveryInterval: TimeInterval = 0.75
    private let focusTrackingInterval: TimeInterval = 0.35
    private let identityRebindGrace: TimeInterval = 5.0
    private let staleEntryLifetime: TimeInterval = 60 * 60 * 24 * 30
    private var lastUnknownFocusRefreshAt = Date.distantPast

    /// After committing a switch, ignore the old frontmost-window value briefly
    /// while macOS completes activation of the selected target.
    private var pendingActivationIdentity: WindowIdentity?
    private var pendingActivationDeadline: Date?

    private var selectedIndex = 0
    private var isVisible = false
    private var previewHideWorkItem: DispatchWorkItem?

    init() {
        panel.onHoverSelection = { [weak self] index in self?.select(index: index) }
        panel.onClickSelection = { [weak self] index in self?.commit(at: index) }
        focusObserver.onFocusedWindowChanged = { [weak self] pid in
            self?.trackFrontmostWindow(for: pid)
        }
    }

    /// Start both window discovery and focused-window tracking. A short focus
    /// poll captures switches between windows of the same app; the slower
    /// discovery poll detects windows that have just been created.
    func startWindowDiscovery() {
        guard discoveryTimer == nil else { return }
        _ = orderedSnapshot() // Seed the MRU list with the current frontmost window.

        let discovery = Timer(timeInterval: discoveryInterval, repeats: true) { [weak self] _ in
            guard let self, !self.isVisible else { return }
            _ = self.orderedSnapshot()
        }
        discoveryTimer = discovery
        RunLoop.main.add(discovery, forMode: .common)

        let focus = Timer(timeInterval: focusTrackingInterval, repeats: true) { [weak self] _ in
            self?.trackFrontmostWindow()
        }
        focusTrackingTimer = focus
        RunLoop.main.add(focus, forMode: .common)

        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // NSWorkspace posts the app-activation notification as part of the
            // activation sequence. Defer one main-loop turn so AX reports the
            // newly focused window rather than the previous app's window.
            DispatchQueue.main.async {
                guard let self, !self.isVisible else { return }
                self.trackFrontmostWindow(forceRefreshIfUnknown: true)
            }
        }
    }

    func stopWindowDiscovery() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
        focusTrackingTimer?.invalidate()
        focusTrackingTimer = nil
        focusObserver.stop()
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
            self.applicationActivationObserver = nil
        }
    }

    func begin(reverse: Bool) {
        previewHideWorkItem?.cancel()

        // Resolve the exact focused window before the overlay becomes
        // frontmost. Exclusion is based on (PID, CGWindowID), not the bundle ID
        // or application PID alone: another window of the same app must remain
        // in the list (e.g. normal and private Brave windows).
        let settings = AppSettingsStore.shared.settings
        let orderedWindows = orderedSnapshot()
        let activeIdentity = catalog.frontmostWindowIdentity(in: orderedWindows)
        let didExcludeActiveWindow = settings.excludeActiveWindowFromSwitcher
            && activeIdentity.map { identity in orderedWindows.contains { $0.identity == identity } } == true

        if didExcludeActiveWindow, let activeIdentity {
            windows = orderedWindows.filter { $0.identity != activeIdentity }
            NSLog(
                "WindowSwitcher: Aktuelles Fenster ausgeblendet (PID \(activeIdentity.ownerPID), WindowID \(activeIdentity.windowID)). Andere Fenster derselben Anwendung bleiben sichtbar."
            )
        } else {
            windows = orderedWindows
            if settings.excludeActiveWindowFromSwitcher {
                NSLog(
                    "WindowSwitcher: Aktives Fenster konnte nicht eindeutig identifiziert werden; Liste bleibt unverändert."
                )
            }
        }

        guard !windows.isEmpty else {
            NSLog("WindowSwitcher: Keine geeigneten Fenster gefunden.")
            return
        }

        thumbnails = [:]
        thumbnailTargetIDs = []
        isVisible = true

        if didExcludeActiveWindow {
            // The active window alone is absent. Since MRU index 0 was the
            // active window, the next-most-recent window (including another
            // window of the same application) is now the first selectable one.
            selectedIndex = reverse ? windows.count - 1 : 0
        } else if let activeIdentity,
                  let activeIndex = windows.firstIndex(where: { $0.identity == activeIdentity }),
                  windows.count > 1 {
            // Default behavior: keep the active window visible at index zero;
            // the first Option+Tab press selects the next MRU entry.
            selectedIndex = (activeIndex + (reverse ? -1 : 1) + windows.count) % windows.count
        } else {
            selectedIndex = reverse ? max(windows.count - 1, 0) : 0
        }
        render()
        loadThumbnails()
    }

    func previewOverviewForDiagnostics() {
        windows = orderedSnapshot()
        guard !windows.isEmpty else {
            NSLog("WindowSwitcher: Keine Fenster zum Anzeigen gefunden.")
            return
        }

        thumbnails = [:]
        thumbnailTargetIDs = []
        selectedIndex = 0
        isVisible = true
        render()
        loadThumbnails()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isVisible = false
            self.panel.hide()
            self.clearTransientState()
        }
        previewHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    func step(reverse: Bool) {
        guard isVisible, !windows.isEmpty else { return }
        previewHideWorkItem?.cancel()
        let count = windows.count
        selectedIndex = (selectedIndex + (reverse ? -1 : 1) + count) % count
        render()
        loadThumbnailsIfVisibleRangeChanged()
    }

    func select(index: Int) {
        guard isVisible, windows.indices.contains(index), selectedIndex != index else { return }
        selectedIndex = index
        render()
        loadThumbnailsIfVisibleRangeChanged()
    }

    func commit() { commit(at: selectedIndex) }

    func commit(at index: Int) {
        guard isVisible else { return }
        previewHideWorkItem?.cancel()
        let selected = windows.indices.contains(index) ? windows[index] : nil
        isVisible = false
        panel.hide()
        if let selected {
            // Promote immediately so the next invocation already reflects the
            // target window, even before macOS posts its activation notification.
            promoteWindow(selected.identity)
            pendingActivationIdentity = selected.identity
            pendingActivationDeadline = Date().addingTimeInterval(1.0)
            catalog.activate(selected)
        }
        clearTransientState()
    }

    func cancel() {
        guard isVisible else { return }
        previewHideWorkItem?.cancel()
        isVisible = false
        panel.hide()
        clearTransientState()
    }

    /// Updates the MRU order from the actual focused window, not from the
    /// current Window Server stacking order. AXObserver callbacks detect
    /// same-app window switches; the timer is a fallback for unsupported apps.
    private func trackFrontmostWindow(
        for observedPID: pid_t? = nil,
        forceRefreshIfUnknown: Bool = false
    ) {
        guard !isVisible,
              let frontmostApplication = NSWorkspace.shared.frontmostApplication else { return }

        let frontmostPID = frontmostApplication.processIdentifier
        // An inactive app can occasionally emit a delayed AX notification. It
        // must not be promoted while another app owns the foreground focus.
        if let observedPID, observedPID != frontmostPID { return }
        guard let identity = catalog.focusedWindowIdentity(for: frontmostPID) else { return }
        let now = Date()

        if let pending = pendingActivationIdentity,
           let deadline = pendingActivationDeadline,
           now < deadline {
            if identity == pending {
                pendingActivationIdentity = nil
                pendingActivationDeadline = nil
            } else {
                // Avoid moving the previously active window back to the front
                // while the newly selected target is still being raised.
                return
            }
        } else {
            pendingActivationIdentity = nil
            pendingActivationDeadline = nil
        }

        if promoteWindow(identity) { return }

        // A newly opened or newly revealed window may not be in the last
        // snapshot yet. Refresh at a bounded rate rather than repeatedly
        // querying every application's Accessibility tree on each focus tick.
        let shouldRefresh = forceRefreshIfUnknown
            || now.timeIntervalSince(lastUnknownFocusRefreshAt) >= discoveryInterval
        if shouldRefresh {
            lastUnknownFocusRefreshAt = now
            _ = orderedSnapshot()
        }
    }

    @discardableResult
    private func promoteWindow(_ identity: WindowIdentity) -> Bool {
        guard let index = mruWindowEntries.firstIndex(where: { $0.identity == identity }) else {
            return false
        }
        if index > 0 {
            let entry = mruWindowEntries.remove(at: index)
            mruWindowEntries.insert(entry, at: 0)
        }
        mruWindowEntries[0].lastSeenAt = Date()
        return true
    }

    private func orderedSnapshot() -> [WindowInfo] {
        let visibleSettings = AppSettingsStore.shared.settings
        var discoverySettings = visibleSettings
        // Track every regular-app window even when the user currently filters
        // some categories out. It can still participate in MRU history.
        discoverySettings.includeMinimizedWindows = true
        discoverySettings.includeHiddenApplications = true
        // Never seed the MRU catalog with windows from inactive Spaces.
        discoverySettings.includeWindowsOnOtherSpaces = false
        discoverySettings.excludedBundleIdentifiers = []

        let snapshot = catalog.snapshot(settings: discoverySettings)
        focusObserver.sync(with: NSWorkspace.shared.runningApplications)
        guard !snapshot.isEmpty else {
            // Do not discard MRU state during a transient empty Window Server snapshot.
            return []
        }

        // Preserve the order returned by Core Graphics while removing duplicate
        // identities. Do not convert to Dictionary.values: that has no ordering.
        var snapshotWindows: [WindowInfo] = []
        var seenIdentities = Set<WindowIdentity>()
        for window in snapshot where seenIdentities.insert(window.identity).inserted {
            snapshotWindows.append(window)
        }

        let now = Date()
        let activeIdentity = catalog.frontmostWindowIdentity(in: snapshotWindows)

        if mruWindowEntries.isEmpty {
            // For windows already open at app launch, the Window Server list is
            // the best available initial front-to-back approximation. Explicitly
            // move the focused window to the first position when it is known.
            if let activeIdentity,
               let activeIndex = snapshotWindows.firstIndex(where: { $0.identity == activeIdentity }) {
                let active = snapshotWindows.remove(at: activeIndex)
                snapshotWindows.insert(active, at: 0)
            }

            mruWindowEntries = snapshotWindows.map { window in
                MRUWindowEntry(
                    identity: window.identity,
                    group: windowGroup(for: window),
                    lastBounds: window.bounds,
                    lastSeenAt: now
                )
            }
            return snapshotWindows.filter { shouldDisplay($0, settings: visibleSettings) }
        }

        let previousEntries = mruWindowEntries
        var updatedEntries = previousEntries
        var unmatched = snapshotWindows
        var matchedEntryIndices = Set<Int>()
        var currentWindowsByIdentity: [WindowIdentity: WindowInfo] = [:]

        // 1. Preserve exact window identities in their existing MRU slots.
        for index in previousEntries.indices {
            guard let matchIndex = unmatched.firstIndex(where: {
                $0.identity == previousEntries[index].identity
            }) else { continue }

            let window = unmatched.remove(at: matchIndex)
            updatedEntries[index].lastBounds = window.bounds
            updatedEntries[index].lastSeenAt = now
            matchedEntryIndices.insert(index)
            currentWindowsByIdentity[window.identity] = window
        }

        // 2. If macOS has recreated a CGWindowID, rebind it to a recently seen
        // entry using app, title, and nearest previous geometry.
        for index in previousEntries.indices where !matchedEntryIndices.contains(index) {
            let oldEntry = previousEntries[index]
            guard now.timeIntervalSince(oldEntry.lastSeenAt) <= identityRebindGrace else { continue }
            let candidates = unmatched.indices.filter {
                windowGroup(for: unmatched[$0]) == oldEntry.group
            }
            guard let matchIndex = candidates.min(by: {
                frameDistance(unmatched[$0].bounds, oldEntry.lastBounds)
                    < frameDistance(unmatched[$1].bounds, oldEntry.lastBounds)
            }) else { continue }

            let window = unmatched.remove(at: matchIndex)
            updatedEntries[index].identity = window.identity
            updatedEntries[index].lastBounds = window.bounds
            updatedEntries[index].lastSeenAt = now
            matchedEntryIndices.insert(index)
            currentWindowsByIdentity[window.identity] = window
        }

        // 3. Newly discovered windows are appended to the MRU history. If the
        // new window is currently focused, the focus promotion below moves it
        // immediately to position 0. Background windows do not become MRU just
        // because they appeared in a snapshot.
        let newEntries = unmatched.map { window in
            currentWindowsByIdentity[window.identity] = window
            return MRUWindowEntry(
                identity: window.identity,
                group: windowGroup(for: window),
                lastBounds: window.bounds,
                lastSeenAt: now
            )
        }

        let retainedEntries = updatedEntries.filter {
            now.timeIntervalSince($0.lastSeenAt) <= staleEntryLifetime
        }
        mruWindowEntries = retainedEntries + newEntries

        if let activeIdentity {
            _ = promoteWindow(activeIdentity)
        }

        return mruWindowEntries.compactMap { currentWindowsByIdentity[$0.identity] }
            .filter { shouldDisplay($0, settings: visibleSettings) }
    }

    private func shouldDisplay(_ window: WindowInfo, settings: AppSettings) -> Bool {
        if settings.excludedBundleIdentifiers.contains(window.bundleIdentifier ?? "") { return false }
        if window.isMinimized && !settings.includeMinimizedWindows { return false }
        if window.isApplicationHidden && !settings.includeHiddenApplications { return false }
        // Enforce the active-Space scope even if a legacy preferences file
        // contains includeWindowsOnOtherSpaces = true.
        if !window.isOnCurrentSpace && !window.isMinimized { return false }
        return true
    }

    private func windowGroup(for window: WindowInfo) -> WindowGroup {
        let bundle = window.bundleIdentifier ?? "pid:\(window.ownerPID)"
        let title = window.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        return WindowGroup(bundleIdentifier: bundle, title: title)
    }

    private func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.size.width - rhs.size.width)
            + abs(lhs.size.height - rhs.size.height)
    }

    private func loadThumbnails() {
        guard AppSettingsStore.shared.settings.visualStyle == .thumbnails else { return }
        let targets = visibleWindowsForCurrentSelection().filter {
            !$0.isMinimized && !$0.isApplicationHidden && $0.isOnCurrentSpace
        }
        let targetIDs = targets.map(\.id)
        guard targetIDs != thumbnailTargetIDs else { return }
        thumbnailTargetIDs = targetIDs
        guard !targets.isEmpty else { return }

        thumbnailProvider.captureThumbnails(for: targets) { [weak self] images in
            guard let self, self.isVisible else { return }
            let currentIDs = self.visibleWindowsForCurrentSelection()
                .filter { !$0.isMinimized && !$0.isApplicationHidden && $0.isOnCurrentSpace }
                .map(\.id)
            guard targetIDs == currentIDs else { return }
            self.thumbnails = images
            self.render()
        }
    }

    private func loadThumbnailsIfVisibleRangeChanged() { loadThumbnails() }

    private func visibleWindowsForCurrentSelection() -> [WindowInfo] {
        let capacity = min(12, windows.count)
        guard capacity > 0 else { return [] }
        let startIndex = min(
            max(selectedIndex - capacity / 2, 0),
            max(windows.count - capacity, 0)
        )
        let endIndex = min(startIndex + capacity, windows.count)
        return Array(windows[startIndex..<endIndex])
    }

    private func render() {
        panel.show(
            windows: windows,
            selectedIndex: selectedIndex,
            thumbnails: thumbnails,
            settings: AppSettingsStore.shared.settings
        )
    }

    private func clearTransientState() {
        windows.removeAll(keepingCapacity: true)
        thumbnails.removeAll(keepingCapacity: true)
        thumbnailTargetIDs.removeAll(keepingCapacity: true)
    }
}
