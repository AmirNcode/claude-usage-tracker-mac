import Foundation

public enum UsageWindowKind: String, Codable {
    case session
    case weekly
}

/// What the app remembers about a window between polls.
public struct WindowTrackingState: Equatable, Codable {
    public var resetsAt: Date?
    public var warnedAt90: Bool

    public init(resetsAt: Date? = nil, warnedAt90: Bool = false) {
        self.resetsAt = resetsAt
        self.warnedAt90 = warnedAt90
    }
}

public enum NotificationAction: Equatable {
    /// Schedule (or replace) the local notification that fires when the window resets.
    case scheduleReset(window: UsageWindowKind, at: Date)
    /// Cancel any pending reset notification for the window.
    case cancelReset(window: UsageWindowKind)
    /// Fire an immediate "usage at/over 90%" warning.
    case warn90(window: UsageWindowKind, utilization: Double, resetsAt: Date?)
    /// The tracked window's reset time has passed and the window rolled: announce
    /// "usage reset to 0%" now. Used for poll-driven delivery when scheduled
    /// notifications are unavailable (unsigned builds get no UN authorization).
    case notifyReset(window: UsageWindowKind)
}

/// Pure decision logic for notifications; the caller applies the returned actions
/// via UNUserNotificationCenter and persists the returned state.
public enum NotificationDecider {
    public static func decide(
        previous: WindowTrackingState,
        window: UsageWindow?,
        kind: UsageWindowKind,
        notificationsEnabled: Bool,
        now: Date = Date()
    ) -> (actions: [NotificationAction], newState: WindowTrackingState) {
        // The window we were tracking ended (its reset time passed and the API
        // no longer reports it) — the usage counter has reset to 0%.
        let resetHappened = previous.resetsAt.map { tracked in
            now >= tracked && window?.resetsAt != tracked
        } ?? false

        guard let window else {
            var actions: [NotificationAction] = []
            if notificationsEnabled, resetHappened {
                actions.append(.notifyReset(window: kind))
            }
            actions.append(.cancelReset(window: kind))
            return (actions, WindowTrackingState())
        }

        var state = previous
        state.resetsAt = window.resetsAt
        let windowChanged = window.resetsAt != previous.resetsAt
        if windowChanged {
            state.warnedAt90 = false
        }

        guard notificationsEnabled else {
            return ([.cancelReset(window: kind)], state)
        }

        var actions: [NotificationAction] = []
        if resetHappened {
            actions.append(.notifyReset(window: kind))
        }
        // Always (re)schedule: replacing a pending request with the same identifier
        // is a no-op, and it self-heals when notification permission is granted
        // after the window was first seen.
        if let resetsAt = window.resetsAt, resetsAt > now {
            actions.append(.scheduleReset(window: kind, at: resetsAt))
        } else {
            actions.append(.cancelReset(window: kind))
        }
        if window.utilization >= 90, !state.warnedAt90 {
            actions.append(.warn90(window: kind, utilization: window.utilization, resetsAt: window.resetsAt))
            state.warnedAt90 = true
        }
        return (actions, state)
    }
}
