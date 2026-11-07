import AppKit
import CoreGraphics

final class SwitcherCoordinator {
    private let catalog = WindowCatalog()
    private let panel = SwitcherPanelController()
    private let thumbnailProvider = WindowThumbnailProvider()
    private var windows: [WindowInfo] = []
    private var thumbnails: [CGWindowID: NSImage] = [:]
    private var thumbnailTargetIDs: [CGWindowID] = []
    // Windows are ordered by first observation (newest first), not by current
    // activation/Z-order. A background discovery timer records newly opened
    // windows before the user invokes the switcher.
    private struct StableWindowGroup: Equatable {
        let bundleIdentifier: String
        let title: String
    }

    private struct StableWindowEntry {
        var identity: WindowIdentity
        let group: StableWindowGroup
        var lastBounds: CGRect
        var lastSeenAt: Date
    }

    /// Entries are kept newest-first. Missing entries remain as short-lived
    /// tombstones so brief Window Server/AX gaps do not reset their age/order.
    private var stableWindowEntries: [StableWindowEntry] = []
    private var discoveryTimer: Timer?
    private let discoveryInterval: TimeInterval = 0.75
    private let identityRebindGrace: TimeInterval = 5.0
    private let staleEntryLifetime: TimeInterval = 60 * 60 * 24 * 30
    private var selectedIndex = 0
    private var isVisible = false
    private var previewHideWorkItem: DispatchWorkItem?

    init() {
        panel.onHoverSelection = { [weak self] index in self?.select(index: index) }
        panel.onClickSelection = { [weak self] index in self?.commit(at: index) }
    }

    /// Start observing the window list before the first switcher invocation.
    /// This lets WindowSwitcher detect newly opened windows instead of trying
    /// to infer their creation order from the changing front-to-back Z-order.
    func startWindowDiscovery() {
        guard discoveryTimer == nil else { return }
        _ = orderedSnapshot() // Seed windows that were already open.

        let timer = Timer(timeInterval: discoveryInterval, repeats: true) { [weak self] _ in
            guard let self, !self.isVisible else { return }
            _ = self.orderedSnapshot()
        }
        discoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopWindowDiscovery() {
        discoveryTimer?.invalidate()
        discoveryTimer = nil
    }

    func begin(reverse: Bool) {
        previewHideWorkItem?.cancel()
        windows = orderedSnapshot()
        guard !windows.isEmpty else {
            NSLog("WindowSwitcher: Keine geeigneten Fenster gefunden.")
            return
        }

        thumbnails = [:]
        thumbnailTargetIDs = []
        isVisible = true
        if let activeIdentity = catalog.frontmostWindowIdentity(),
           let activeIndex = windows.firstIndex(where: { $0.identity == activeIdentity }),
           windows.count > 1 {
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

    private func orderedSnapshot() -> [WindowInfo] {
        let visibleSettings = AppSettingsStore.shared.settings
        var discoverySettings = visibleSettings
        // Keep tracking all regular-app windows even when the user currently
        // filters some categories out of the switcher. This avoids treating a
        // previously hidden/minimized/excluded window as newly opened later.
        discoverySettings.includeMinimizedWindows = true
        discoverySettings.includeHiddenApplications = true
        discoverySettings.includeWindowsOnOtherSpaces = true
        discoverySettings.excludedBundleIdentifiers = []
        let snapshot = catalog.snapshot(settings: discoverySettings)
        guard !snapshot.isEmpty else {
            // Keep the tracked ordering through transient empty snapshots.
            return []
        }

        var uniqueByIdentity: [WindowIdentity: WindowInfo] = [:]
        for window in snapshot {
            uniqueByIdentity[window.identity] = window
        }
        let now = Date()
        var unmatched = Array(uniqueByIdentity.values)

        // First run: macOS does not expose per-window creation timestamps.
        // Use process launch dates where available, then a stable fallback for
        // multiple windows belonging to the same already-running application.
        if stableWindowEntries.isEmpty {
            let baseline = unmatched.sorted(by: initialWindowSort)
            stableWindowEntries = baseline.map { window in
                return StableWindowEntry(
                    identity: window.identity,
                    group: stableGroup(for: window),
                    lastBounds: window.bounds,
                    lastSeenAt: now
                )
            }
            return baseline.filter { shouldDisplay($0, settings: visibleSettings) }
        }

        let previousEntries = stableWindowEntries
        var updatedEntries = previousEntries
        var matchedEntryIndices = Set<Int>()
        var existingWindowsBySlot: [Int: WindowInfo] = [:]

        // 1. Match exact identities. Existing entries never move when activated.
        for index in previousEntries.indices {
            guard let matchIndex = unmatched.firstIndex(where: {
                $0.identity == previousEntries[index].identity
            }) else { continue }

            let window = unmatched.remove(at: matchIndex)
            updatedEntries[index].lastBounds = window.bounds
            updatedEntries[index].lastSeenAt = now
            matchedEntryIndices.insert(index)
            existingWindowsBySlot[index] = window
        }

        // 2. If macOS recreated a window ID, only reuse a recently seen slot.
        // Limiting this grace period prevents a newly opened same-title window
        // from inheriting the age of an older, already closed window.
        for index in previousEntries.indices where !matchedEntryIndices.contains(index) {
            let oldEntry = previousEntries[index]
            guard now.timeIntervalSince(oldEntry.lastSeenAt) <= identityRebindGrace else { continue }
            let candidates = unmatched.indices.filter {
                stableGroup(for: unmatched[$0]) == oldEntry.group
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
            existingWindowsBySlot[index] = window
        }

        // 3. Every newly discovered window is inserted at the front. Sorting
        // only breaks ties for windows first observed in the same polling pass;
        // it never uses current activation order as the persistent list order.
        let newWindows = unmatched.sorted(by: stableNewWindowSort)
        let newEntries = newWindows.map { window in
            StableWindowEntry(
                identity: window.identity,
                group: stableGroup(for: window),
                lastBounds: window.bounds,
                lastSeenAt: now
            )
        }

        // Prune long-expired tombstones, but keep entries hidden by a transient
        // snapshot gap long enough to preserve their original slot.
        let retainedOldEntries = updatedEntries.filter {
            now.timeIntervalSince($0.lastSeenAt) <= staleEntryLifetime
        }
        stableWindowEntries = newEntries + retainedOldEntries

        let stillPresentOldWindows = previousEntries.indices.compactMap { index -> WindowInfo? in
            guard matchedEntryIndices.contains(index) else { return nil }
            return existingWindowsBySlot[index]
        }
        return (newWindows + stillPresentOldWindows).filter {
            shouldDisplay($0, settings: visibleSettings)
        }
    }

    private func shouldDisplay(_ window: WindowInfo, settings: AppSettings) -> Bool {
        if settings.excludedBundleIdentifiers.contains(window.bundleIdentifier ?? "") { return false }
        if window.isMinimized && !settings.includeMinimizedWindows { return false }
        if window.isApplicationHidden && !settings.includeHiddenApplications { return false }
        if !window.isOnCurrentSpace && !window.isMinimized && !window.isApplicationHidden
            && !settings.includeWindowsOnOtherSpaces {
            return false
        }
        return true
    }

    /// On the first snapshot, use application launch time as the best public
    /// approximation for app ordering. The order of multiple windows from the
    /// same pre-existing app cannot be recovered exactly from public macOS APIs.
    private func initialWindowSort(_ lhs: WindowInfo, _ rhs: WindowInfo) -> Bool {
        let lhsDate = lhs.applicationLaunchDate ?? .distantPast
        let rhsDate = rhs.applicationLaunchDate ?? .distantPast
        if lhsDate != rhsDate { return lhsDate > rhsDate }
        return stableNewWindowSort(lhs, rhs)
    }

    private func stableGroup(for window: WindowInfo) -> StableWindowGroup {
        let bundle = window.bundleIdentifier ?? "pid:\(window.ownerPID)"
        let title = window.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        return StableWindowGroup(bundleIdentifier: bundle, title: title)
    }

    private func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.origin.x - rhs.origin.x)
            + abs(lhs.origin.y - rhs.origin.y)
            + abs(lhs.size.width - rhs.size.width)
            + abs(lhs.size.height - rhs.size.height)
    }

    private func stableNewWindowSort(_ lhs: WindowInfo, _ rhs: WindowInfo) -> Bool {
        let lhsGroup = stableGroup(for: lhs)
        let rhsGroup = stableGroup(for: rhs)
        if lhsGroup.bundleIdentifier != rhsGroup.bundleIdentifier {
            return lhsGroup.bundleIdentifier.localizedStandardCompare(rhsGroup.bundleIdentifier) == .orderedAscending
        }
        if lhsGroup.title != rhsGroup.title {
            return lhsGroup.title.localizedStandardCompare(rhsGroup.title) == .orderedAscending
        }
        if lhs.bounds.origin.y != rhs.bounds.origin.y { return lhs.bounds.origin.y < rhs.bounds.origin.y }
        if lhs.bounds.origin.x != rhs.bounds.origin.x { return lhs.bounds.origin.x < rhs.bounds.origin.x }
        if lhs.bounds.size.width != rhs.bounds.size.width { return lhs.bounds.size.width < rhs.bounds.size.width }
        if lhs.bounds.size.height != rhs.bounds.size.height { return lhs.bounds.size.height < rhs.bounds.size.height }
        if lhs.ownerPID != rhs.ownerPID { return lhs.ownerPID < rhs.ownerPID }
        return lhs.id < rhs.id
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
