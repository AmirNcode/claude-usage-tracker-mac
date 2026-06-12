import Foundation
import UsageCore

func runUsageFormatterTests() {
    let berlin = TimeZone(identifier: "Europe/Berlin")! // UTC+2 in June (DST)
    // 2026-06-12T19:30:00Z (Friday) and 2026-06-15T10:00:00Z (Monday)
    let sessionReset = Date(timeIntervalSince1970: 1781292600)
    let weeklyReset = Date(timeIntervalSince1970: 1781517600)

    test("menu bar title shows rounded percentages") {
        let s = UsageSnapshot(
            session: UsageWindow(utilization: 29.6, resetsAt: sessionReset),
            weekly: UsageWindow(utilization: 60.4, resetsAt: weeklyReset)
        )
        expectEqual(UsageFormatter.menuBarTitle(s), "30% / 60%")
    }

    test("menu bar title with no data shows placeholders") {
        expectEqual(UsageFormatter.menuBarTitle(nil), "–% / –%")
    }

    test("nil windows render as zero percent") {
        let s = UsageSnapshot(session: nil, weekly: nil)
        expectEqual(UsageFormatter.menuBarTitle(s), "0% / 0%")
        expectEqual(UsageFormatter.sessionLine(s, timeZone: berlin), "0%")
        expectEqual(UsageFormatter.weeklyLine(s, timeZone: berlin), "0%")
    }

    test("session line shows local reset time") {
        let s = UsageSnapshot(
            session: UsageWindow(utilization: 90.0, resetsAt: sessionReset),
            weekly: nil
        )
        expectEqual(UsageFormatter.sessionLine(s, timeZone: berlin), "90% - 21:30")
    }

    test("weekly line shows local reset day and time") {
        let s = UsageSnapshot(
            session: nil,
            weekly: UsageWindow(utilization: 69.0, resetsAt: weeklyReset)
        )
        expectEqual(UsageFormatter.weeklyLine(s, timeZone: berlin), "69% - Mon 12:00")
    }

    test("window without reset date omits time") {
        let s = UsageSnapshot(
            session: UsageWindow(utilization: 12.0, resetsAt: nil),
            weekly: nil
        )
        expectEqual(UsageFormatter.sessionLine(s, timeZone: berlin), "12%")
    }
}
