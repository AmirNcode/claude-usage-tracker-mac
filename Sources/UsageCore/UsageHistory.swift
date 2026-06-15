import Foundation

/// A point-in-time usage reading, persisted to build the stats timeline.
public struct UsageSample: Codable, Equatable {
    public let date: Date
    public let session: Double?
    public let weekly: Double?

    public init(date: Date, session: Double?, weekly: Double?) {
        self.date = date
        self.session = session
        self.weekly = weekly
    }
}

/// A timeline row: a sample plus the change since the previous sample.
public struct TimelineEntry: Equatable {
    public let date: Date
    public let session: Double?
    public let weekly: Double?
    public let sessionDelta: Double?
    public let weeklyDelta: Double?
}

public enum UsageHistory {
    /// Append a sample and drop anything older than `maxAge` before `now`.
    public static func appending(
        _ sample: UsageSample, to samples: [UsageSample],
        maxAge: TimeInterval, now: Date = Date()
    ) -> [UsageSample] {
        let cutoff = now.addingTimeInterval(-maxAge)
        return (samples + [sample]).filter { $0.date >= cutoff }
    }

    /// True when a reading is identical to the last stored one, so the timeline
    /// records only actual usage changes (idle polls don't add clutter).
    public static func isDuplicate(_ sample: UsageSample, of last: UsageSample?) -> Bool {
        guard let last else { return false }
        return last.session == sample.session && last.weekly == sample.weekly
    }

    /// Chronological entries with deltas versus the previous sample. The delta is
    /// nil for the first entry or when either side's percentage is missing.
    public static func timeline(_ samples: [UsageSample]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        entries.reserveCapacity(samples.count)
        var previous: UsageSample?
        for s in samples {
            entries.append(TimelineEntry(
                date: s.date,
                session: s.session,
                weekly: s.weekly,
                sessionDelta: delta(s.session, previous?.session),
                weeklyDelta: delta(s.weekly, previous?.weekly)
            ))
            previous = s
        }
        return entries
    }

    private static func delta(_ current: Double?, _ previous: Double?) -> Double? {
        guard let current, let previous else { return nil }
        return current - previous
    }
}
