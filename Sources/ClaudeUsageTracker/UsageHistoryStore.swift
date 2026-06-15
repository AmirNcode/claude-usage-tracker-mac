import Foundation
import Combine
import UsageCore

/// Persists usage samples to Application Support and exposes them to the Stats
/// window. History is pruned to the last 14 days.
final class UsageHistoryStore: ObservableObject {
    @Published private(set) var samples: [UsageSample] = []

    private let maxAge: TimeInterval = 14 * 24 * 3600
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeUsageTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("history.json")
        load()
    }

    func record(_ snapshot: UsageSnapshot, at date: Date = Date()) {
        let sample = UsageSample(date: date,
                                 session: snapshot.session?.utilization,
                                 weekly: snapshot.weekly?.utilization)
        // Record only actual changes so idle polls don't clutter the timeline.
        guard !UsageHistory.isDuplicate(sample, of: samples.last) else { return }
        samples = UsageHistory.appending(sample, to: samples, maxAge: maxAge, now: date)
        save()
    }

    var timeline: [TimelineEntry] { UsageHistory.timeline(samples) }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([UsageSample].self, from: data) else { return }
        samples = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
