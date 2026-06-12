import Foundation
import UserNotifications
import UsageCore

/// Applies NotificationDecider actions via UNUserNotificationCenter and persists
/// per-window tracking state across launches. Reset notifications are scheduled
/// locally for the exact resets_at time, so they fire on time even between polls.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private let defaults = UserDefaults.standard

    /// UNUserNotificationCenter aborts in processes without a bundle (e.g. a bare
    /// `swift run` binary), so notification work is skipped there.
    private let available = Bundle.main.bundleIdentifier != nil

    override init() {
        super.init()
        if available {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("Notification authorization error: \(error.localizedDescription)")
            } else {
                NSLog("Notification authorization granted: \(granted)")
            }
        }
    }

    func process(snapshot: UsageSnapshot, notificationsEnabled: Bool) {
        apply(window: snapshot.session, kind: .session, enabled: notificationsEnabled)
        apply(window: snapshot.weekly, kind: .weekly, enabled: notificationsEnabled)
    }

    private func apply(window: UsageWindow?, kind: UsageWindowKind, enabled: Bool) {
        let (actions, newState) = NotificationDecider.decide(
            previous: loadState(kind),
            window: window,
            kind: kind,
            notificationsEnabled: enabled
        )
        saveState(newState, kind)
        guard available else { return }

        let center = UNUserNotificationCenter.current()
        for action in actions {
            switch action {
            case .scheduleReset(let kind, let date):
                let content = UNMutableNotificationContent()
                content.title = kind == .session
                    ? "Session usage reset to 0%"
                    : "Weekly usage reset to 0%"
                content.body = kind == .session
                    ? "A fresh 5-hour session window is available."
                    : "A fresh weekly limit window is available."
                content.sound = .default
                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: date
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                center.add(UNNotificationRequest(
                    identifier: "\(kind.rawValue)-reset", content: content, trigger: trigger
                ))
            case .cancelReset(let kind):
                center.removePendingNotificationRequests(withIdentifiers: ["\(kind.rawValue)-reset"])
            case .warn90(let kind, let utilization, let resetsAt):
                let content = UNMutableNotificationContent()
                content.title = kind == .session
                    ? "Session usage at \(Int(utilization.rounded()))%"
                    : "Weekly usage at \(Int(utilization.rounded()))%"
                if let resetsAt {
                    let line = kind == .session
                        ? UsageFormatter.sessionLine(UsageSnapshot(
                            session: UsageWindow(utilization: utilization, resetsAt: resetsAt), weekly: nil))
                        : UsageFormatter.weeklyLine(UsageSnapshot(
                            session: nil, weekly: UsageWindow(utilization: utilization, resetsAt: resetsAt)))
                    content.body = "Resets at \(line.components(separatedBy: " - ").last ?? "")"
                }
                content.sound = .default
                center.add(UNNotificationRequest(
                    identifier: "\(kind.rawValue)-warn90", content: content, trigger: nil
                ))
            }
        }
    }

    // MARK: - Tracking state persistence

    private func stateKey(_ kind: UsageWindowKind) -> String { "tracking.\(kind.rawValue)" }

    private func loadState(_ kind: UsageWindowKind) -> WindowTrackingState {
        guard
            let data = defaults.data(forKey: stateKey(kind)),
            let state = try? JSONDecoder().decode(WindowTrackingState.self, from: data)
        else {
            return WindowTrackingState()
        }
        return state
    }

    private func saveState(_ state: WindowTrackingState, _ kind: UsageWindowKind) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey(kind))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while the app is "active" (menu bar apps count as such).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
