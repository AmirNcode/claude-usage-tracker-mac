import Foundation
import UsageCore

func runNotificationDeciderTests() {
    let now = Date(timeIntervalSince1970: 1781280000) // 2026-06-12T16:00:00Z
    let reset1 = Date(timeIntervalSince1970: 1781292600) // 19:30Z, in the future
    let reset2 = Date(timeIntervalSince1970: 1781310600) // next window

    func decide(
        previous: WindowTrackingState = WindowTrackingState(),
        window: UsageWindow?,
        enabled: Bool = true
    ) -> (actions: [NotificationAction], newState: WindowTrackingState) {
        NotificationDecider.decide(
            previous: previous, window: window, kind: .session,
            notificationsEnabled: enabled, now: now
        )
    }

    test("first poll schedules reset notification") {
        let result = decide(window: UsageWindow(utilization: 30, resetsAt: reset1))
        expectEqual(result.actions, [.scheduleReset(window: .session, at: reset1)])
        expectEqual(result.newState.resetsAt, reset1)
        expectEqual(result.newState.warnedAt90, false)
    }

    // Scheduling is idempotent (same identifier replaces itself) so a notification
    // attempted before the user granted permission is retried on every poll.
    test("unchanged reset date reschedules idempotently") {
        let prev = WindowTrackingState(resetsAt: reset1, warnedAt90: false)
        let result = decide(previous: prev, window: UsageWindow(utilization: 45, resetsAt: reset1))
        expectEqual(result.actions, [.scheduleReset(window: .session, at: reset1)])
        expectEqual(result.newState, prev)
    }

    test("crossing 90 fires warning once") {
        let prev = WindowTrackingState(resetsAt: reset1, warnedAt90: false)
        let first = decide(previous: prev, window: UsageWindow(utilization: 92, resetsAt: reset1))
        expectEqual(first.actions, [
            .scheduleReset(window: .session, at: reset1),
            .warn90(window: .session, utilization: 92, resetsAt: reset1),
        ])
        expectEqual(first.newState.warnedAt90, true)

        let second = decide(previous: first.newState, window: UsageWindow(utilization: 95, resetsAt: reset1))
        expectEqual(second.actions, [.scheduleReset(window: .session, at: reset1)])
    }

    test("exactly 90 counts as warning") {
        let prev = WindowTrackingState(resetsAt: reset1, warnedAt90: false)
        let result = decide(previous: prev, window: UsageWindow(utilization: 90, resetsAt: reset1))
        expectEqual(result.actions, [
            .scheduleReset(window: .session, at: reset1),
            .warn90(window: .session, utilization: 90, resetsAt: reset1),
        ])
    }

    test("new window resets warning flag and reschedules") {
        let prev = WindowTrackingState(resetsAt: reset1, warnedAt90: true)
        let result = decide(previous: prev, window: UsageWindow(utilization: 10, resetsAt: reset2))
        expectEqual(result.actions, [.scheduleReset(window: .session, at: reset2)])
        expectEqual(result.newState.warnedAt90, false)
        expectEqual(result.newState.resetsAt, reset2)
    }

    test("new window already over 90 warns again") {
        let prev = WindowTrackingState(resetsAt: reset1, warnedAt90: true)
        let result = decide(previous: prev, window: UsageWindow(utilization: 91, resetsAt: reset2))
        expectEqual(result.actions, [
            .scheduleReset(window: .session, at: reset2),
            .warn90(window: .session, utilization: 91, resetsAt: reset2),
        ])
        expectEqual(result.newState.warnedAt90, true)
    }

    test("window disappearing cancels reset notification") {
        let prev = WindowTrackingState(resetsAt: reset1, warnedAt90: true)
        let result = decide(previous: prev, window: nil)
        expectEqual(result.actions, [.cancelReset(window: .session)])
        expectEqual(result.newState, WindowTrackingState())
    }

    test("past reset date is not scheduled") {
        let past = Date(timeIntervalSince1970: 1781270000) // before `now`
        let result = decide(window: UsageWindow(utilization: 30, resetsAt: past))
        expectEqual(result.actions, [.cancelReset(window: .session)])
        expectEqual(result.newState.resetsAt, past)
    }

    test("disabled notifications only cancel") {
        let result = decide(window: UsageWindow(utilization: 95, resetsAt: reset1), enabled: false)
        expectEqual(result.actions, [.cancelReset(window: .session)])
        // State still tracks the window so re-enabling works cleanly.
        expectEqual(result.newState.resetsAt, reset1)
    }
}
