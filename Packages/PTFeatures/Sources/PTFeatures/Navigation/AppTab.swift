import SwiftUI

/// The 6 main tabs of the app.
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case papers
    case bookshelf
    case notes
    case statistics
    case ai
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .papers: return "Papers"
        case .bookshelf: return "Bookshelf"
        case .notes: return "Notes"
        case .statistics: return "Statistics"
        case .ai: return "AI"
        case .settings: return "Settings"
        }
    }

    public var icon: String {
        switch self {
        case .papers: return "doc.text.magnifyingglass"
        case .bookshelf: return "books.vertical"
        case .notes: return "note.text"
        case .statistics: return "chart.bar"
        case .ai: return "sparkles"
        case .settings: return "gearshape"
        }
    }

    /// Default tab order.
    public static let defaultOrder: [AppTab] = [.papers, .bookshelf, .notes, .statistics, .ai, .settings]

    // MARK: - Home Navigation Configuration (UserDefaults-backed)

    private static let enabledKey = "home_nav_enabled_tabs"
    private static let orderKey = "home_nav_tab_order"
    private static let versionKey = "home_nav_configuration_version"

    /// A monotonic version token bumped whenever the configuration changes.
    /// Use this as an `.id()` on tab containers so SwiftUI rebuilds them on change.
    public static var configurationVersion: Int {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        return defaults.integer(forKey: versionKey)
    }

    /// Notification posted when the home navigation configuration changes.
    public static let configurationDidChangeNotification = Notification.Name("AppTab.configurationDidChange")

    /// Whether this tab is currently enabled in the home navigation.
    /// Settings is always enabled regardless of user preference.
    public var enabled: Bool {
        if self == .settings { return true }
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        guard let raw = defaults.stringArray(forKey: AppTab.enabledKey) else {
            return true // default: all enabled
        }
        return raw.contains(rawValue)
    }

    /// Currently configured ordered list of enabled tabs.
    public static func currentOrder() -> [AppTab] {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        let order: [AppTab]
        if let rawOrder = defaults.stringArray(forKey: orderKey) {
            order = rawOrder.compactMap { AppTab(rawValue: $0) }
        } else {
            order = defaultOrder
        }
        let enabledSet: Set<AppTab>
        if let rawEnabled = defaults.stringArray(forKey: enabledKey) {
            var set = Set(rawEnabled.compactMap { AppTab(rawValue: $0) })
            set.insert(.settings)
            enabledSet = set
        } else {
            enabledSet = Set(AppTab.allCases)
        }
        return order.filter { enabledSet.contains($0) }
    }

    /// Persist enabled set and order to UserDefaults.
    public static func saveConfiguration(order: [AppTab], enabled: Set<AppTab>) {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        defaults.set(order.map { $0.rawValue }, forKey: orderKey)
        var enabled = enabled
        enabled.insert(.settings)
        defaults.set(enabled.map { $0.rawValue }, forKey: enabledKey)
        let version = defaults.integer(forKey: versionKey) + 1
        defaults.set(version, forKey: versionKey)
        NotificationCenter.default.post(name: configurationDidChangeNotification, object: nil)
    }

    /// Clear the stored configuration (resets to defaults).
    public static func resetConfiguration() {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        defaults.removeObject(forKey: enabledKey)
        defaults.removeObject(forKey: orderKey)
        let version = defaults.integer(forKey: versionKey) + 1
        defaults.set(version, forKey: versionKey)
        NotificationCenter.default.post(name: configurationDidChangeNotification, object: nil)
    }
}
