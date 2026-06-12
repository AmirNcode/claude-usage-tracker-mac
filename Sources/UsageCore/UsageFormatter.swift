import Foundation

/// Pure formatting of usage data into the exact strings shown in the UI.
/// Fixed 24-hour times and en_US_POSIX weekday names ("Mon 06:00") to match
/// the agreed display format regardless of system locale.
public enum UsageFormatter {
    /// Menu bar title, e.g. "30% / 60%". Placeholders when no data: "–% / –%".
    public static func menuBarTitle(_ snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "–% / –%" }
        return "\(percent(snapshot.session)) / \(percent(snapshot.weekly))"
    }

    /// First menu line, e.g. "30% - 17:00" (local time). "30%" if no reset time.
    public static func sessionLine(_ snapshot: UsageSnapshot, timeZone: TimeZone = .current) -> String {
        line(for: snapshot.session, dateFormat: "HH:mm", timeZone: timeZone)
    }

    /// Second menu line, e.g. "60% - Mon 06:00" (local time). "60%" if no reset time.
    public static func weeklyLine(_ snapshot: UsageSnapshot, timeZone: TimeZone = .current) -> String {
        line(for: snapshot.weekly, dateFormat: "EEE HH:mm", timeZone: timeZone)
    }

    private static func percent(_ window: UsageWindow?) -> String {
        "\(Int((window?.utilization ?? 0).rounded()))%"
    }

    private static func line(for window: UsageWindow?, dateFormat: String, timeZone: TimeZone) -> String {
        let pct = percent(window)
        guard let resetsAt = window?.resetsAt else { return pct }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return "\(pct) - \(formatter.string(from: resetsAt))"
    }
}
