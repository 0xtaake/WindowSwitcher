import AppKit
import ApplicationServices

/// Per-process context passed to the C Accessibility callback. The entry keeps
/// it alive for as long as its AXObserver remains registered.
private final class WindowFocusObserverContext {
    weak var owner: WindowFocusObserver?
    let processIdentifier: pid_t

    init(owner: WindowFocusObserver, processIdentifier: pid_t) {
        self.owner = owner
        self.processIdentifier = processIdentifier
    }
}

/// Observes per-application Accessibility focus notifications. NSWorkspace
/// tells us when the active application changes; AXObserver supplements that
/// with focus changes between windows belonging to the same application.
final class WindowFocusObserver {
    var onFocusedWindowChanged: ((pid_t) -> Void)?

    private struct Entry {
        let observer: AXObserver
        let applicationElement: AXUIElement
        let context: WindowFocusObserverContext
    }

    private var entries: [pid_t: Entry] = [:]
    private var retryAfter: [pid_t: Date] = [:]
    private let retryDelay: TimeInterval = 10

    deinit {
        stop()
    }

    func sync(with applications: [NSRunningApplication]) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let eligible = applications.filter {
            $0.processIdentifier != ownPID && $0.activationPolicy == .regular && !$0.isTerminated
        }
        let eligiblePIDs = Set(eligible.map(\.processIdentifier))

        for pid in Array(entries.keys) where !eligiblePIDs.contains(pid) {
            removeObserver(for: pid)
        }
        for pid in Array(retryAfter.keys) where !eligiblePIDs.contains(pid) {
            retryAfter.removeValue(forKey: pid)
        }

        let now = Date()
        for application in eligible where entries[application.processIdentifier] == nil {
            let pid = application.processIdentifier
            if let retryDate = retryAfter[pid], retryDate > now { continue }
            if !addObserver(for: pid) {
                retryAfter[pid] = now.addingTimeInterval(retryDelay)
            }
        }
    }

    func stop() {
        for pid in Array(entries.keys) {
            removeObserver(for: pid)
        }
        retryAfter.removeAll()
    }

    @discardableResult
    private func addObserver(for pid: pid_t) -> Bool {
        var createdObserver: AXObserver?
        let callback: AXObserverCallback = windowFocusObserverCallback
        guard AXObserverCreate(pid, callback, &createdObserver) == .success,
              let observer = createdObserver else {
            return false
        }

        let applicationElement = AXUIElementCreateApplication(pid)
        let context = WindowFocusObserverContext(owner: self, processIdentifier: pid)
        let addResult = AXObserverAddNotification(
            observer,
            applicationElement,
            kAXFocusedWindowChangedNotification as CFString,
            Unmanaged.passUnretained(context).toOpaque()
        )

        guard addResult == .success || addResult == .notificationAlreadyRegistered else {
            return false
        }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        entries[pid] = Entry(
            observer: observer,
            applicationElement: applicationElement,
            context: context
        )
        retryAfter.removeValue(forKey: pid)
        return true
    }

    private func removeObserver(for pid: pid_t) {
        guard let entry = entries.removeValue(forKey: pid) else { return }
        _ = AXObserverRemoveNotification(
            entry.observer,
            entry.applicationElement,
            kAXFocusedWindowChangedNotification as CFString
        )
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(entry.observer),
            .commonModes
        )
    }

    fileprivate func receivedFocusChange(for pid: pid_t) {
        onFocusedWindowChanged?(pid)
    }
}

private func windowFocusObserverCallback(
    observer: AXObserver,
    element: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let context = Unmanaged<WindowFocusObserverContext>.fromOpaque(refcon).takeUnretainedValue()
    context.owner?.receivedFocusChange(for: context.processIdentifier)
}
