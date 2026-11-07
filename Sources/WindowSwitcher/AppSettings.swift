import Foundation
import CoreGraphics

// MARK: - User-configurable appearance and behavior

enum SwitcherVisualStyle: String, Codable, CaseIterable, Identifiable {
    case thumbnails
    case icons
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thumbnails: return "Karten mit Vorschau"
        case .icons: return "App-Symbole"
        case .list: return "Kompakte Liste"
        }
    }
}

enum ShortcutKey: String, Codable, CaseIterable, Identifiable {
    case tab
    case space
    case a
    case s
    case d

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tab: return "Tab"
        case .space: return "Leertaste"
        case .a: return "A"
        case .s: return "S"
        case .d: return "D"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .tab: return 48
        case .space: return 49
        case .a: return 0
        case .s: return 1
        case .d: return 2
        }
    }
}

struct AppSettings: Codable, Equatable {
    var includeMinimizedWindows = true
    var includeHiddenApplications = true
    var includeWindowsOnOtherSpaces = true
    var excludedBundleIdentifiers: [String] = []

    var visualStyle: SwitcherVisualStyle = .thumbnails
    var columns = 3

    var shortcutKey: ShortcutKey = .tab
    var shortcutUsesOption = true
    var shortcutUsesCommand = false
    var shortcutUsesControl = false

    /// Enables hover selection and click-to-activate on switcher cards.
    /// Keyboard navigation remains available when this option is disabled.
    var mouseControlEnabled = true

    var appearance: String = "system"

    var requiredModifierMask: CGEventFlags {
        var result: CGEventFlags = []
        if shortcutUsesOption { result.insert(.maskAlternate) }
        if shortcutUsesCommand { result.insert(.maskCommand) }
        if shortcutUsesControl { result.insert(.maskControl) }
        return result
    }

    var hasValidShortcut: Bool {
        shortcutUsesOption || shortcutUsesCommand || shortcutUsesControl
    }

    // Keep compatibility with settings files written by versions before 0.3.8.
    // decodeIfPresent is important here: adding mouseControlEnabled must not
    // discard a user's existing preferences when the key is absent.
    private enum CodingKeys: String, CodingKey {
        case includeMinimizedWindows
        case includeHiddenApplications
        case includeWindowsOnOtherSpaces
        case excludedBundleIdentifiers
        case visualStyle
        case columns
        case shortcutKey
        case shortcutUsesOption
        case shortcutUsesCommand
        case shortcutUsesControl
        case mouseControlEnabled
        case appearance
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includeMinimizedWindows = try container.decodeIfPresent(Bool.self, forKey: .includeMinimizedWindows) ?? true
        includeHiddenApplications = try container.decodeIfPresent(Bool.self, forKey: .includeHiddenApplications) ?? true
        includeWindowsOnOtherSpaces = try container.decodeIfPresent(Bool.self, forKey: .includeWindowsOnOtherSpaces) ?? true
        excludedBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .excludedBundleIdentifiers) ?? []
        visualStyle = try container.decodeIfPresent(SwitcherVisualStyle.self, forKey: .visualStyle) ?? .thumbnails
        columns = try container.decodeIfPresent(Int.self, forKey: .columns) ?? 3
        shortcutKey = try container.decodeIfPresent(ShortcutKey.self, forKey: .shortcutKey) ?? .tab
        shortcutUsesOption = try container.decodeIfPresent(Bool.self, forKey: .shortcutUsesOption) ?? true
        shortcutUsesCommand = try container.decodeIfPresent(Bool.self, forKey: .shortcutUsesCommand) ?? false
        shortcutUsesControl = try container.decodeIfPresent(Bool.self, forKey: .shortcutUsesControl) ?? false
        mouseControlEnabled = try container.decodeIfPresent(Bool.self, forKey: .mouseControlEnabled) ?? true
        appearance = try container.decodeIfPresent(String.self, forKey: .appearance) ?? "system"
    }
}

final class AppSettingsStore {
    static let shared = AppSettingsStore()

    private let storageKey = "WindowSwitcher.settings.v3"
    private(set) var settings: AppSettings

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func save(_ newSettings: AppSettings) {
        settings = newSettings
        guard let data = try? JSONEncoder().encode(newSettings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
