import SwiftUI
import UsageCore

/// Connection / refresh status, shared between the menu bar and the settings window.
final class AppState: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var lastRefreshed: Date?
    @Published var lastError: String?
    @Published var isRefreshing = false
    @Published var source: AccountSource = .none

    var connectionDescription: String {
        switch source {
        case .oauth: return "Connected (logged in)"
        case .claudeCode: return "Connected via Claude Code"
        case .none: return "Not connected"
        }
    }

    var lastRefreshedDescription: String {
        guard let lastRefreshed else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: lastRefreshed)
    }
}
