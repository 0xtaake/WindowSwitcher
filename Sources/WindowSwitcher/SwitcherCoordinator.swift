import AppKit
import CoreGraphics

final class SwitcherCoordinator {
    private let catalog = WindowCatalog()
    private let panel = SwitcherPanelController()
    private let thumbnailProvider = WindowThumbnailProvider()
    private var windows: [WindowInfo] = []
    private var thumbnails: [CGWindowID: NSImage] = [:]
    private var thumbnailTargetIDs: [CGWindowID] = []
    // Session-stable slots preserve visual order independently of the current
    // front-to-back Window Server order. Exact WindowIdentity matches are used
    // first; if macOS recreates a window ID, a same-app/same-title window is
    // matched to its previous slot by nearest frame.
    private struct StableWindowGroup: Equatable {
        let bundleIdentifier: String
        let title: String
    }

    private struct StableWindowEntry {
        var identity: WindowIdentity
        let group: StableWindowGroup
        var lastBounds: CGRect
    }

    private var stableWindowEntries: [StableWindowEntry] = []
    private var selectedIndex = 0
    private var isVisible = false
    private var previewHideWorkItem: DispatchWorkItem?

    init() {
        panel.onHoverSelection = { [weak self] index in self?.select(index: index) }
        panel.onClickSelection = { [weak self] index in self?.commit(at: index) }
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
        let snapshot = catalog.snapshot(settings: AppSettingsStore.shared.settings)
        guard !snapshot.isEmpty else {
            // Keep the previous order through transient empty snapshots. This
            // prevents a temporary AX/Window Server gap from resetting the UI.
            return []
        }

        var uniqueByIdentity: [WindowIdentity: WindowInfo] = [:]
        for window in snapshot {
            uniqueByIdentity[window.identity] = window
        }
        var unmatched = Array(uniqueByIdentity.values)
        var slotWindows: [Int: WindowInfo] = [:]

        // 1. Preserve exact window identities whenever macOS keeps the same ID.
        for slot in stableWindowEntries.indices {
            guard let matchIndex = unmatched.firstIndex(where: {
                $0.identity == stableWindowEntries[slot].identity
            }) else { continue }
            let window = unmatched.remove(at: matchIndex)
            stableWindowEntries[slot].lastBounds = window.bounds
            slotWindows[slot] = window
        }

        // 2. If a CGWindowID changed, reuse the old slot for the same app/title.
        // The nearest previous frame disambiguates multiple same-title windows.
        for slot in stableWindowEntries.indices where slotWindows[slot] == nil {
            let oldEntry = stableWindowEntries[slot]
            let candidates = unmatched.indices.filter {
                stableGroup(for: unmatched[$0]) == oldEntry.group
            }
            guard let matchIndex = candidates.min(by: {
                frameDistance(unmatched[$0].bounds, oldEntry.lastBounds)
                    < frameDistance(unmatched[$1].bounds, oldEntry.lastBounds)
            }) else { continue }

            let window = unmatched.remove(at: matchIndex)
            stableWindowEntries[slot].identity = window.identity
            stableWindowEntries[slot].lastBounds = window.bounds
            slotWindows[slot] = window
        }

        // 3. Only brand-new logical windows are sorted, then appended. Existing
        // entries never move just because another window became frontmost.
        let newWindows = unmatched.sorted(by: stableNewWindowSort)
        for window in newWindows {
            let entry = StableWindowEntry(
                identity: window.identity,
                group: stableGroup(for: window),
                lastBounds: window.bounds
            )
            stableWindowEntries.append(entry)
            slotWindows[stableWindowEntries.count - 1] = window
        }

        return stableWindowEntries.indices.compactMap { slotWindows[$0] }
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
