import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures one still image per visible window for the switcher cards.
/// Screen recording permission is required by macOS. The switcher remains
/// usable without it; cards then fall back to the owning application's icon.
final class WindowThumbnailProvider {
    func captureThumbnails(
        for windows: [WindowInfo],
        completion: @escaping ([CGWindowID: NSImage]) -> Void
    ) {
        guard #available(macOS 14.0, *) else {
            completion([:])
            return
        }

        // Only capture the portion normally visible in the grid view.
        // This keeps Option+Tab responsive even with many open windows.
        let targets = Array(windows.prefix(12))

        Task { @MainActor in
            do {
                let shareableContent = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: true
                )
                let shareableWindows = Dictionary(
                    shareableContent.windows.map { ($0.windowID, $0) },
                    uniquingKeysWith: { first, _ in first }
                )

                var images: [CGWindowID: NSImage] = [:]
                for target in targets {
                    guard let shareableWindow = shareableWindows[target.id] else { continue }

                    let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
                    let configuration = SCStreamConfiguration()
                    configuration.width = 480
                    let aspectRatio = max(
                        shareableWindow.frame.width / max(shareableWindow.frame.height, 1),
                        0.5
                    )
                    configuration.height = max(180, Int(480 / aspectRatio))
                    configuration.showsCursor = false

                    do {
                        let cgImage = try await SCScreenshotManager.captureImage(
                            contentFilter: filter,
                            configuration: configuration
                        )
                        images[target.id] = NSImage(
                            cgImage: cgImage,
                            size: NSSize(width: cgImage.width, height: cgImage.height)
                        )
                    } catch {
                        // A protected or non-capturable window simply keeps
                        // its fallback icon; it must not break the switcher.
                        NSLog("WindowSwitcher: Thumbnail für Fenster %u nicht verfügbar: %@", target.id, error.localizedDescription)
                    }
                }

                completion(images)
            } catch {
                NSLog("WindowSwitcher: ScreenCaptureKit nicht verfügbar: %@", error.localizedDescription)
                completion([:])
            }
        }
    }
}
