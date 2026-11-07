import AppKit
import ApplicationServices
import CoreGraphics

/// Uses Core Graphics Window Server records as the canonical source for
/// top-level windows and enriches them with Accessibility attributes when a
/// reliable match exists. AX metadata is optional: an incomplete AX tree must
/// never make an otherwise valid app window disappear from the switcher.
final class WindowCatalog {
    private struct AXWindowDescriptor {
        let element: AXUIElement
        let number: CGWindowID?
        let title: String?
        let minimized: Bool
        let position: CGPoint?
        let size: CGSize?
    }

    func snapshot(settings: AppSettings) -> [WindowInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // Query only the windows currently on-screen. `optionAll` also returns
        // windows from inactive Spaces and can inflate the switcher with dozens
        // of windows that are not part of the user's current desktop.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let runningApps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != ownPID && $0.activationPolicy == .regular
        }
        let appsByPID = Dictionary(uniqueKeysWithValues: runningApps.map { ($0.processIdentifier, $0) })
        let axByPID = Dictionary(uniqueKeysWithValues: runningApps.map {
            ($0.processIdentifier, accessibilityWindows(for: $0.processIdentifier))
        })

        var result: [WindowInfo] = []
        var seenCGWindowIDs = Set<CGWindowID>()
        var usedAXDescriptorIndices: [pid_t: Set<Int>] = [:]

        for dictionary in rawWindows {
            guard
                let number = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                number != 0,
                !seenCGWindowIDs.contains(number),
                let pidNumber = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
                let layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue,
                layer == 0
            else { continue }

            let pid = pid_t(pidNumber.int32Value)
            guard let application = appsByPID[pid] else { continue }

            let bundleIdentifier = application.bundleIdentifier
            if settings.excludedBundleIdentifiers.contains(bundleIdentifier ?? "") { continue }

            let isHidden = application.isHidden
            if isHidden && !settings.includeHiddenApplications { continue }

            let cgTitle = dictionary[kCGWindowName as String] as? String
            let cgBounds = bounds(from: dictionary)
            // The query is `.optionOnScreenOnly`; default to true if this
            // optional metadata key is absent.
            let onScreen = (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            let descriptors = axByPID[pid] ?? []
            let usedIndices = usedAXDescriptorIndices[pid] ?? []

            let descriptorIndex = bestDescriptorIndex(
                for: number,
                title: cgTitle,
                bounds: cgBounds,
                descriptors: descriptors,
                excluding: usedIndices
            )

            let descriptor: AXWindowDescriptor?
            if let descriptorIndex {
                // Accessibility enriches a Window Server record when a reliable
                // match exists. It is deliberately not a prerequisite for
                // displaying the window: Chromium-based browsers (including
                // Brave) can expose AX titles/frames that differ from the
                // corresponding CG metadata, which previously caused every
                // unmatched CG window to be dropped.
                usedAXDescriptorIndices[pid, default: []].insert(descriptorIndex)
                descriptor = descriptors[descriptorIndex]
            } else {
                // Core Graphics is the source of truth for visible top-level
                // windows. Keep a valid layer-0 CG window even when AX cannot
                // be paired with it. CGWindowID already provides per-window
                // identity, so do not collapse two real windows merely because
                // their titles and geometries happen to be identical.
                descriptor = nil
            }

            let minimized = descriptor?.minimized ?? false
            if minimized && !settings.includeMinimizedWindows { continue }
            // The switcher is intentionally limited to windows currently reported
            // as on-screen by Window Server. Off-space windows are never shown.
            // Minimized windows remain a separate opt-in exception because macOS
            // does not expose their former Space reliably.
            if !onScreen && !minimized { continue }

            let alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            if alpha <= 0.001 && !minimized && !isHidden { continue }

            let windowBounds = cgBounds ?? bounds(from: descriptor) ??
                CGRect(x: 0, y: 0, width: 640, height: 420)
            if windowBounds.width < 40 || windowBounds.height < 30 { continue }

            let appName = application.localizedName
                ?? (dictionary[kCGWindowOwnerName as String] as? String)
                ?? "Unbekannte Anwendung"
            let rawTitle = (cgTitle?.isEmpty == false) ? cgTitle : descriptor?.title
            let title = (rawTitle?.isEmpty == false) ? rawTitle! : appName

            result.append(WindowInfo(
                id: number,
                ownerPID: pid,
                bundleIdentifier: bundleIdentifier,
                appName: appName,
                title: title,
                icon: application.icon,
                applicationLaunchDate: application.launchDate,
                bounds: windowBounds,
                isMinimized: minimized,
                isApplicationHidden: isHidden,
                isOnCurrentSpace: onScreen
            ))
            seenCGWindowIDs.insert(number)
        }

        // Accessibility can expose minimized windows even when the Window
        // Server's all-spaces query omits them. Add only AX entries that were
        // not already matched to a Core Graphics window above.
        if settings.includeMinimizedWindows {
            for application in runningApps where !settings.excludedBundleIdentifiers.contains(application.bundleIdentifier ?? "") {
                let pid = application.processIdentifier
                let isHidden = application.isHidden
                if isHidden && !settings.includeHiddenApplications { continue }

                let descriptors = axByPID[pid] ?? []
                let alreadyUsed = usedAXDescriptorIndices[pid] ?? []
                for index in descriptors.indices where !alreadyUsed.contains(index) {
                    let descriptor = descriptors[index]
                    guard descriptor.minimized,
                          let number = descriptor.number,
                          number != 0,
                          !seenCGWindowIDs.contains(number)
                    else { continue }

                    let appName = application.localizedName ?? "Unbekannte Anwendung"
                    let windowBounds = bounds(from: descriptor) ?? CGRect(x: 0, y: 0, width: 640, height: 420)
                    result.append(WindowInfo(
                        id: number,
                        ownerPID: pid,
                        bundleIdentifier: application.bundleIdentifier,
                        appName: appName,
                        title: descriptor.title?.isEmpty == false ? descriptor.title! : appName,
                        icon: application.icon,
                        applicationLaunchDate: application.launchDate,
                        bounds: windowBounds,
                        isMinimized: true,
                        isApplicationHidden: isHidden,
                        isOnCurrentSpace: false
                    ))
                    seenCGWindowIDs.insert(number)
                }
            }
        }

        return result
    }

    /// Resolves the exact frontmost window that should be excluded from the
    /// switcher. This is deliberately window-specific: sibling windows of the
    /// same application must remain visible (e.g. a private Brave window).
    ///
    /// The Window Server's front-to-back order is preferred for the active
    /// process because Chromium-based apps may not expose a reliable
    /// AXWindowNumber for AXFocusedWindow. Accessibility is used as a validated
    /// fallback, never as an unchecked application-wide match.
    func frontmostWindowIdentity(in candidates: [WindowInfo]) -> WindowIdentity? {
        guard !candidates.isEmpty,
              let application = NSWorkspace.shared.frontmostApplication else { return nil }

        let candidateIdentities = Set(candidates.map(\.identity))
        let activePID = application.processIdentifier

        if let identity = windowServerFrontmostIdentity(for: Set([activePID])),
           candidateIdentities.contains(identity) {
            return identity
        }

        if let identity = focusedWindowIdentity(for: activePID),
           candidateIdentities.contains(identity) {
            return identity
        }

        // Some browsers expose their top-level window under a regular helper
        // process with the same bundle identifier. Only use this fallback when
        // no window owned by the frontmost application's PID was resolvable.
        if let bundleIdentifier = application.bundleIdentifier, !bundleIdentifier.isEmpty {
            let siblingPIDs = Set(NSWorkspace.shared.runningApplications.compactMap { candidate -> pid_t? in
                guard candidate.activationPolicy == .regular,
                      candidate.bundleIdentifier == bundleIdentifier else { return nil }
                return candidate.processIdentifier
            })
            if let identity = windowServerFrontmostIdentity(for: siblingPIDs),
               candidateIdentities.contains(identity) {
                return identity
            }
        }

        // Fail open when the active window cannot be identified exactly.
        // Choosing an arbitrary window from the MRU list could hide the wrong
        // Brave window, so never guess based only on the application PID.
        return nil
    }

    private func windowServerFrontmostIdentity(for processIDs: Set<pid_t>) -> WindowIdentity? {
        guard !processIDs.isEmpty,
              let dictionaries = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
              ) as? [[String: Any]] else { return nil }

        for dictionary in dictionaries {
            guard
                let owner = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                processIDs.contains(pid_t(owner)),
                (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                let number = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                number != 0
            else { continue }

            let alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            guard alpha > 0.001 else { continue }
            return WindowIdentity(ownerPID: pid_t(owner), windowID: number)
        }
        return nil
    }

    /// Returns the focused window for a specific process. This is also used by
    /// AXObserver callbacks so focus changes between windows of one app can be
    /// recorded without relying only on application-activation notifications.
    func focusedWindowIdentity(for pid: pid_t) -> WindowIdentity? {
        let appElement = AXUIElementCreateApplication(pid)
        // Keep focus polling bounded so a temporarily unresponsive app cannot
        // hold up the switcher UI indefinitely.
        _ = AXUIElementSetMessagingTimeout(appElement, 0.25)

        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedValue
        ) == .success, let focusedWindow = axUIElement(from: focusedValue) {
            var numberValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(
                focusedWindow,
                "AXWindowNumber" as CFString,
                &numberValue
            )
            if let number = (numberValue as? NSNumber)?.uint32Value, number != 0 {
                return WindowIdentity(ownerPID: pid, windowID: number)
            }
        }

        // Fallback for apps that do not expose AXFocusedWindow reliably: the
        // front-to-back Window Server list usually places the focused app's
        // key window first among its normal layer-0 windows.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for dictionary in windows {
            guard
                let owner = (dictionary[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                owner == pid,
                (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                let number = (dictionary[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                number != 0
            else { continue }
            return WindowIdentity(ownerPID: pid, windowID: number)
        }
        return nil
    }

    func activate(_ window: WindowInfo) {
        guard let application = NSRunningApplication(processIdentifier: window.ownerPID) else { return }

        if application.isHidden { application.unhide() }
        _ = application.activate(options: [.activateIgnoringOtherApps])

        let appElement = AXUIElementCreateApplication(window.ownerPID)
        guard let axWindows = axWindowElements(for: appElement), !axWindows.isEmpty else { return }

        let matchingWindow = bestAccessibilityMatch(in: axWindows, for: window)
        guard let matchingWindow else { return }

        _ = AXUIElementSetAttributeValue(
            matchingWindow,
            kAXMinimizedAttribute as CFString,
            kCFBooleanFalse
        )
        _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, matchingWindow)
        _ = AXUIElementPerformAction(matchingWindow, kAXRaiseAction as CFString)
    }

    private func accessibilityWindows(for pid: pid_t) -> [AXWindowDescriptor] {
        let appElement = AXUIElementCreateApplication(pid)
        guard let elements = axWindowElements(for: appElement) else { return [] }

        var descriptors: [AXWindowDescriptor] = []
        var seenNumbers = Set<CGWindowID>()
        var seenFingerprints = Set<String>()

        for element in elements {
            let descriptor = makeDescriptor(from: element)
            if let number = descriptor.number, number != 0 {
                guard seenNumbers.insert(number).inserted else { continue }
            } else if let fingerprint = accessibilityFingerprint(for: descriptor) {
                // Some applications do not expose AXWindowNumber. In that
                // case remove duplicate AX wrappers with identical title and
                // exact geometry. Distinct document windows at different
                // positions or sizes remain separate entries.
                guard seenFingerprints.insert(fingerprint).inserted else { continue }
            }
            descriptors.append(descriptor)
        }
        return descriptors
    }

    private func makeDescriptor(from element: AXUIElement) -> AXWindowDescriptor {
        var numberValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &numberValue)
        let number = (numberValue as? NSNumber)?.uint32Value

        var titleValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)

        var minimizedValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedValue)
        let minimized = (minimizedValue as? NSNumber)?.boolValue ?? false

        var position: CGPoint?
        var positionValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
           let value = positionValue, CFGetTypeID(value) == AXValueGetTypeID() {
            var point = CGPoint.zero
            if AXValueGetValue(value as! AXValue, .cgPoint, &point) { position = point }
        }

        var size: CGSize?
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let value = sizeValue, CFGetTypeID(value) == AXValueGetTypeID() {
            var measured = CGSize.zero
            if AXValueGetValue(value as! AXValue, .cgSize, &measured) { size = measured }
        }

        return AXWindowDescriptor(
            element: element,
            number: number,
            title: titleValue as? String,
            minimized: minimized,
            position: position,
            size: size
        )
    }

    /// Safely bridges a Core Foundation result to AXUIElement.
    /// AXUIElement is a CFTypeRef, so a conditional Swift cast is not a
    /// meaningful runtime check and is diagnosed as always succeeding. Verify
    /// the Core Foundation type identifier before performing the bridge.
    private func axUIElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func axWindowElements(for appElement: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else { return nil }
        return windows
    }

    private func bestDescriptorIndex(
        for number: CGWindowID,
        title: String?,
        bounds: CGRect?,
        descriptors: [AXWindowDescriptor],
        excluding usedIndices: Set<Int>
    ) -> Int? {
        if let exactIndex = descriptors.indices.first(where: {
            !usedIndices.contains($0) && descriptors[$0].number == number
        }) {
            return exactIndex
        }

        let candidates = descriptors.indices.filter { !usedIndices.contains($0) }
        guard let bestIndex = candidates.min(by: {
            descriptorScore(descriptors[$0], title: title, bounds: bounds)
                < descriptorScore(descriptors[$1], title: title, bounds: bounds)
        }) else { return nil }

        // Only use AX metadata when the match is sufficiently plausible. The
        // caller still keeps the Core Graphics window when this returns nil.
        return descriptorScore(descriptors[bestIndex], title: title, bounds: bounds) < 45_000
            ? bestIndex
            : nil
    }

    private func descriptorScore(_ descriptor: AXWindowDescriptor, title: String?, bounds: CGRect?) -> Double {
        var score = 0.0
        let cgTitle = normalized(title)
        let axTitle = normalized(descriptor.title)
        if !cgTitle.isEmpty && !axTitle.isEmpty {
            // Window Server and Accessibility titles are not always byte-for-
            // byte identical (notably in Chromium browsers). Prefer equal
            // titles, but let geometry establish a valid metadata match when
            // the title strings differ.
            if cgTitle != axTitle { score += 25_000 }
        } else {
            score += 12_000
        }

        if let bounds, let size = descriptor.size {
            score += abs(bounds.width - size.width) + abs(bounds.height - size.height)
        } else {
            score += 10_000
        }

        if let bounds, let position = descriptor.position {
            score += (abs(bounds.origin.x - position.x) + abs(bounds.origin.y - position.y)) * 0.25
        } else {
            score += 5_000
        }
        return score
    }

    private func accessibilityFingerprint(for descriptor: AXWindowDescriptor) -> String? {
        guard descriptor.position != nil || descriptor.size != nil || !normalized(descriptor.title).isEmpty else {
            return nil
        }
        let title = normalized(descriptor.title)
        let position = descriptor.position ?? .zero
        let size = descriptor.size ?? .zero
        return "\(title)|\(Int(position.x.rounded()))|\(Int(position.y.rounded()))|\(Int(size.width.rounded()))|\(Int(size.height.rounded()))"
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private func bestAccessibilityMatch(in windows: [AXUIElement], for target: WindowInfo) -> AXUIElement? {
        var candidates: [(element: AXUIElement, score: Double)] = []
        for element in windows {
            var numberValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, "AXWindowNumber" as CFString, &numberValue)
            if (numberValue as? NSNumber)?.uint32Value == target.id { return element }

            var titleValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String

            var sizeValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)

            var score = normalized(title) == normalized(target.title) ? 0.0 : 1_000_000.0
            if let value = sizeValue, CFGetTypeID(value) == AXValueGetTypeID() {
                var size = CGSize.zero
                if AXValueGetValue(value as! AXValue, .cgSize, &size) {
                    score += abs(size.width - target.bounds.width) + abs(size.height - target.bounds.height)
                }
            }
            candidates.append((element, score))
        }
        guard let best = candidates.min(by: { $0.score < $1.score }), best.score < 250_000 else {
            return nil
        }
        return best.element
    }

    private func bounds(from dictionary: [String: Any]) -> CGRect? {
        guard let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return nil }
        return rect
    }

    private func bounds(from descriptor: AXWindowDescriptor?) -> CGRect? {
        guard let descriptor, let size = descriptor.size else { return nil }
        return CGRect(origin: descriptor.position ?? .zero, size: size)
    }
}
