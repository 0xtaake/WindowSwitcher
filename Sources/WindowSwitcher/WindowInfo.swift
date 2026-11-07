import AppKit
import CoreGraphics

struct WindowIdentity: Hashable {
    let ownerPID: pid_t
    let windowID: CGWindowID
}

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let ownerPID: pid_t
    let bundleIdentifier: String?
    let appName: String
    let title: String
    let icon: NSImage?
    let applicationLaunchDate: Date?
    let bounds: CGRect
    var thumbnail: NSImage? = nil
    var isMinimized = false
    var isApplicationHidden = false
    var isOnCurrentSpace = true

    var identity: WindowIdentity {
        WindowIdentity(ownerPID: ownerPID, windowID: id)
    }

    var statusLabel: String? {
        if isMinimized { return "Minimiert" }
        if isApplicationHidden { return "App ausgeblendet" }
        if !isOnCurrentSpace { return "Anderer Space / nicht sichtbar" }
        return nil
    }
}
