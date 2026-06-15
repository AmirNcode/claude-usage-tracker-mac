import SwiftUI
import Combine

/// User settings, backed by UserDefaults and observable by the SwiftUI settings
/// window. AppDelegate subscribes to re-render the menu bar when these change.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    private func set<T>(_ value: T, _ key: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
    }

    /// Color thresholds: orange at >=90%, red at >=100%.
    @Published var thresholdsEnabled: Bool {
        didSet { defaults.set(thresholdsEnabled, forKey: "thresholdsEnabled") }
    }

    /// Custom menu bar colors (hex like "#RRGGBB"); empty = automatic (label color).
    @Published var sessionColorHex: String {
        didSet { defaults.set(sessionColorHex, forKey: "sessionColorHex") }
    }
    @Published var weeklyColorHex: String {
        didSet { defaults.set(weeklyColorHex, forKey: "weeklyColorHex") }
    }

    /// Refresh interval in minutes.
    @Published var refreshMinutes: Int {
        didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes") }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin") }
    }

    private init() {
        thresholdsEnabled = defaults.object(forKey: "thresholdsEnabled") as? Bool ?? true
        sessionColorHex = defaults.string(forKey: "sessionColorHex") ?? ""
        weeklyColorHex = defaults.string(forKey: "weeklyColorHex") ?? ""
        refreshMinutes = max(1, defaults.object(forKey: "refreshMinutes") as? Int ?? 5)
        launchAtLogin = defaults.object(forKey: "launchAtLogin") as? Bool ?? true
    }

    var refreshInterval: TimeInterval { TimeInterval(refreshMinutes * 60) }
}
