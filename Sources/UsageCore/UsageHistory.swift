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

    /// Insert a sample in date order, replacing any sample already at that exact
    /// timestamp, then prune anything older than `maxAge`. Manual entry uses this
    /// to backfill a reading the app missed (e.g. a session reset it slept through).
    public static func inserting(
        _ sample: UsageSample, into samples: [UsageSample],
        maxAge: TimeInterval, now: Date = Date()
    ) -> [UsageSample] {
        var result = samples.filter { $0.date != sample.date }
        let index = result.firstIndex { $0.date > sample.date } ?? result.count
        result.insert(sample, at: index)
        let cutoff = now.addingTimeInterval(-maxAge)
        return result.filter { $0.date >= cutoff }
    }

    /// Samples inside the trailing `window` ending at `now`, padded at both ends
    /// so a flat stretch still draws a line: the last reading before the window
    /// is carried in at the window start, and the latest reading is carried
    /// forward to `now`. Samples are only recorded when a value changes, so an
    /// unchanged reading is the correct value for the gap between them.
    public static func windowed(
        _ samples: [UsageSample], window: TimeInterval, now: Date = Date()
    ) -> [UsageSample] {
        let start = now.addingTimeInterval(-window)
        var result = samples.filter { $0.date >= start && $0.date <= now }
        if let carryIn = samples.last(where: { $0.date < start }) {
            result.insert(UsageSample(date: start, session: carryIn.session, weekly: carryIn.weekly), at: 0)
        }
        if let last = result.last, last.date < now {
            result.append(UsageSample(date: now, session: last.session, weekly: last.weekly))
        }
        return result
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
