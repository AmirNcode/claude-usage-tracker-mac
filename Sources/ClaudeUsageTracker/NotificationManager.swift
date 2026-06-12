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
                AppLog.log("Notification authorization error: \(error)")
            } else {
                AppLog.log("Notification authorization granted: \(granted)")
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
        guard available, !actions.isEmpty else { return }

        // Unsigned/ad-hoc builds are refused UN authorization (UNErrorDomain
        // Code=1, no prompt shown), so notifications fall back to AppleScript.
        // If the app is ever properly signed and authorized, the scheduled UN
        // path takes over automatically.
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let viaUN = settings.authorizationStatus == .authorized
            for action in actions {
                self?.perform(action, viaUN: viaUN)
            }
        }
    }

    private func perform(_ action: NotificationAction, viaUN: Bool) {
        let center = UNUserNotificationCenter.current()
        switch action {
        case .scheduleReset(let kind, let date):
            guard viaUN else { return }
            let content = UNMutableNotificationContent()
            content.title = resetTitle(kind)
            content.body = resetBody(kind)
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(
                identifier: "\(kind.rawValue)-reset", content: content, trigger: trigger
            )) { error in
                if let error {
                    AppLog.log("Scheduling \(kind.rawValue) reset notification failed: \(error)")
                }
            }
        case .cancelReset(let kind):
            guard viaUN else { return }
            center.removePendingNotificationRequests(withIdentifiers: ["\(kind.rawValue)-reset"])
        case .notifyReset(let kind):
            // In UN mode the notification scheduled at resets_at already fired.
            guard !viaUN else { return }
            postViaAppleScript(title: resetTitle(kind), body: resetBody(kind))
        case .warn90(let kind, let utilization, let resetsAt):
            let title = kind == .session
                ? "Session usage at \(Int(utilization.rounded()))%"
                : "Weekly usage at \(Int(utilization.rounded()))%"
            var body = ""
            if let resetsAt {
                let line = kind == .session
                    ? UsageFormatter.sessionLine(UsageSnapshot(
                        session: UsageWindow(utilization: utilization, resetsAt: resetsAt), weekly: nil))
                    : UsageFormatter.weeklyLine(UsageSnapshot(
                        session: nil, weekly: UsageWindow(utilization: utilization, resetsAt: resetsAt)))
                body = "Resets at \(line.components(separatedBy: " - ").last ?? "")"
            }
            if viaUN {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                center.add(UNNotificationRequest(
                    identifier: "\(kind.rawValue)-warn90", content: content, trigger: nil
                )) { error in
                    if let error {
                        AppLog.log("Delivering \(kind.rawValue) 90% warning failed: \(error)")
                    }
                }
            } else {
                postViaAppleScript(title: title, body: body)
            }
        }
    }

    private func resetTitle(_ kind: UsageWindowKind) -> String {
        kind == .session ? "Session usage reset to 0%" : "Weekly usage reset to 0%"
    }

    private func resetBody(_ kind: UsageWindowKind) -> String {
        kind == .session
            ? "A fresh 5-hour session window is available."
            : "A fresh weekly limit window is available."
    }

    private func postViaAppleScript(title: String, body: String) {
        func escaped(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(escaped(body))\" with title \"\(escaped(title))\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            AppLog.log("Posted notification via osascript (exit \(process.terminationStatus)): \(title)")
        } catch {
            AppLog.log("osascript notification failed: \(error)")
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
