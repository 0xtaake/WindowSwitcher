import AppKit
import Foundation

// Draws the same SF Symbol used by the menu-bar item into a macOS app icon.
// The build script converts this 1024px PNG into the required .icns sizes.

let outputPath = CommandLine.arguments.dropFirst().first ?? ""
guard !outputPath.isEmpty else {
    fputs("Usage: swift generate-app-icon.swift <output.png>\n", stderr)
    exit(2)
}

let canvasSize = 1024
let canvasRect = NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Could not create the app-icon bitmap.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high

// Rounded, full-bleed macOS icon background.
let backgroundRect = NSRect(x: 24, y: 24, width: 976, height: 976)
let backgroundPath = NSBezierPath(
    roundedRect: backgroundRect,
    xRadius: 218,
    yRadius: 218
)
let backgroundGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.12, green: 0.36, blue: 0.78, alpha: 1.0),
    NSColor(calibratedRed: 0.25, green: 0.22, blue: 0.66, alpha: 1.0)
])!
backgroundGradient.draw(in: backgroundPath, angle: 135)

// Subtle border to keep the shape crisp against light and dark Finder backgrounds.
NSColor.white.withAlphaComponent(0.18).setStroke()
backgroundPath.lineWidth = 5
backgroundPath.stroke()

// This is intentionally the exact SF Symbol name used by AppDelegate.swift.
guard let menuBarSymbol = NSImage(
    systemSymbolName: "rectangle.on.rectangle",
    accessibilityDescription: "WindowSwitcher"
) else {
    fputs("SF Symbol 'rectangle.on.rectangle' is unavailable on this macOS version.\n", stderr)
    exit(1)
}

let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium)
let configuredSymbol = menuBarSymbol.withSymbolConfiguration(symbolConfiguration) ?? menuBarSymbol

let symbolSide: CGFloat = 590
let symbolRect = NSRect(
    x: (CGFloat(canvasSize) - symbolSide) / 2,
    y: (CGFloat(canvasSize) - symbolSide) / 2,
    width: symbolSide,
    height: symbolSide
)

// Render the SF Symbol into a separate transparent bitmap first. Then use
// source-in compositing to color its alpha mask white. This avoids NSImage
// tint helpers that are unavailable in some AppKit SDK/toolchain versions.
guard let symbolBitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasSize,
    pixelsHigh: canvasSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let symbolGraphics = NSGraphicsContext(bitmapImageRep: symbolBitmap) else {
    fputs("Could not create the SF Symbol bitmap.\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = symbolGraphics
symbolGraphics.imageInterpolation = .high
symbolGraphics.compositingOperation = .copy
NSColor.clear.setFill()
NSBezierPath(rect: canvasRect).fill()
symbolGraphics.compositingOperation = .sourceOver
configuredSymbol.draw(
    in: symbolRect,
    from: .zero,
    operation: .sourceOver,
    fraction: 1.0,
    respectFlipped: false,
    hints: nil
)
symbolGraphics.compositingOperation = .sourceIn
NSColor.white.setFill()
NSBezierPath(rect: canvasRect).fill()
symbolGraphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let whiteSymbolCGImage = symbolBitmap.cgImage else {
    fputs("Could not create the white SF Symbol image.\n", stderr)
    exit(1)
}
let whiteSymbol = NSImage(
    cgImage: whiteSymbolCGImage,
    size: NSSize(width: canvasSize, height: canvasSize)
)
whiteSymbol.draw(in: canvasRect)

graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let outputURL = URL(fileURLWithPath: outputPath)
do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "WindowSwitcherIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG data."])
    }
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("Could not write app icon: \(error)\n", stderr)
    exit(1)
}

print("Generated app icon: \(outputURL.path)")
