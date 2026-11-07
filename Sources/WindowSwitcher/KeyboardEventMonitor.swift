import AppKit
import ApplicationServices
import CoreGraphics

struct ShortcutConfiguration {
    var keyCode: Int64
    var requiredModifiers: CGEventFlags

    init(settings: AppSettings) {
        keyCode = settings.shortcutKey.keyCode
        requiredModifiers = settings.requiredModifierMask
    }
}

final class KeyboardEventMonitor {
    var onBegin: ((Bool) -> Void)?
    var onStep: ((Bool) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    var shortcut = ShortcutConfiguration(settings: AppSettings())

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false
    private var isSwitching = false

    func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        if eventTap != nil { return true }

        let eventMask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue) |
            (CGEventMask(1) << CGEventType.keyUp.rawValue) |
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = keyboardTapCallback
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isRunning = false
            return false
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            isRunning = false
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        isSwitching = false
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isSwitching {
                isSwitching = false
                onCancel?()
            }
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let reverse = flags.contains(.maskShift)

        switch type {
        case .keyDown:
            if keyCode == shortcut.keyCode && modifiersMatch(flags) {
                if isSwitching {
                    onStep?(reverse)
                } else {
                    isSwitching = true
                    onBegin?(reverse)
                }
                return nil
            }

            if isSwitching {
                switch keyCode {
                case 53: // Escape
                    isSwitching = false
                    onCancel?()
                    return nil
                case 123, 126: // Left / Up
                    onStep?(true)
                    return nil
                case 124, 125: // Right / Down
                    onStep?(false)
                    return nil
                default:
                    break
                }
            }

        case .keyUp:
            if keyCode == shortcut.keyCode && isSwitching { return nil }

        case .flagsChanged:
            if isSwitching && !modifiersMatch(flags) {
                isSwitching = false
                onCommit?()
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func modifiersMatch(_ flags: CGEventFlags) -> Bool {
        let relevant: CGEventFlags = [.maskAlternate, .maskCommand, .maskControl]
        return flags.intersection(relevant) == shortcut.requiredModifiers
    }
}

private func keyboardTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyboardEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(type: type, event: event)
}
