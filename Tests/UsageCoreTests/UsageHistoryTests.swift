import Foundation
import UsageCore

func runUsageHistoryTests() {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ secs: Double) -> Date { t0.addingTimeInterval(secs) }

    test("appending adds a sample") {
        let s = UsageSample(date: t0, session: 10, weekly: 20)
        let result = UsageHistory.appending(s, to: [], maxAge: 3600, now: t0)
        expectEqual(result.count, 1)
        expectEqual(result.first?.session, 10)
    }

    test("appending prunes samples older than maxAge") {
        let old = UsageSample(date: at(0), session: 1, weekly: 1)
        let recent = UsageSample(date: at(3000), session: 2, weekly: 2)
        let fresh = UsageSample(date: at(7200), session: 3, weekly: 3)
        // maxAge 3600s, now = at(7200): keep samples with date >= at(3600).
        let result = UsageHistory.appending(fresh, to: [old, recent], maxAge: 3600, now: at(7200))
        expectEqual(result.count, 1)
        expectEqual(result.first?.session, 3)
    }

    test("timeline is empty for no samples") {
        expect(UsageHistory.timeline([]).isEmpty, "expected empty timeline")
    }

    test("first timeline entry has nil deltas") {
        let entries = UsageHistory.timeline([UsageSample(date: t0, session: 10, weekly: 20)])
        expectEqual(entries.count, 1)
        expect(entries[0].sessionDelta == nil, "first delta should be nil")
        expect(entries[0].weeklyDelta == nil, "first weekly delta should be nil")
    }

    test("deltas computed against previous sample") {
        let samples = [
            UsageSample(date: at(0), session: 10, weekly: 20),
            UsageSample(date: at(60), session: 18, weekly: 21),
        ]
        let entries = UsageHistory.timeline(samples)
        expectEqual(entries.count, 2)
        expectEqual(entries[1].sessionDelta, 8)
        expectEqual(entries[1].weeklyDelta, 1)
    }

    test("a window reset shows a negative delta") {
        let samples = [
            UsageSample(date: at(0), session: 92, weekly: 50),
            UsageSample(date: at(60), session: 3, weekly: 51),
        ]
        let entries = UsageHistory.timeline(samples)
        expectEqual(entries[1].sessionDelta, -89)
    }

    test("nil percentages produce nil deltas") {
        let samples = [
            UsageSample(date: at(0), session: nil, weekly: 20),
            UsageSample(date: at(60), session: 5, weekly: 25),
        ]
        let entries = UsageHistory.timeline(samples)
        expect(entries[1].sessionDelta == nil, "delta should be nil when previous is nil")
        expectEqual(entries[1].weeklyDelta, 5)
    }

    test("isDuplicate detects identical consecutive readings") {
        let a = UsageSample(date: at(0), session: 50, weekly: 20)
        let b = UsageSample(date: at(60), session: 50, weekly: 20)
        let c = UsageSample(date: at(120), session: 51, weekly: 20)
        expect(UsageHistory.isDuplicate(b, of: a), "same %s should be duplicate")
        expect(!UsageHistory.isDuplicate(c, of: a), "changed session should not be duplicate")
        expect(!UsageHistory.isDuplicate(a, of: nil), "first sample is never a duplicate")
    }

    test("samples round-trip through JSON") {
        let samples = [
            UsageSample(date: t0, session: 10, weekly: 20),
            UsageSample(date: at(60), session: nil, weekly: 21),
        ]
        let data = try JSONEncoder().encode(samples)
        let restored = try JSONDecoder().decode([UsageSample].self, from: data)
        expectEqual(restored.count, 2)
        expect(restored[1].session == nil, "nil session should survive round-trip")
        expectEqual(restored[1].weekly, 21)
    }

    test("windowed keeps only samples inside the window") {
        let samples = [
            UsageSample(date: at(0), session: 1, weekly: 1),
            UsageSample(date: at(7000), session: 2, weekly: 2),
            UsageSample(date: at(7200), session: 3, weekly: 3),
        ]
        // window 3600s ending at at(7200): keeps at(7000) and at(7200), carries in at(0).
        let result = UsageHistory.windowed(samples, window: 3600, now: at(7200))
        expectEqual(result.count, 3)
        expectEqual(result[0].date, at(3600))
        expectEqual(result[0].session, 1)
        expectEqual(result[2].session, 3)
    }

    test("windowed carries the last value forward to now") {
        let samples = [UsageSample(date: at(0), session: 40, weekly: 60)]
        let result = UsageHistory.windowed(samples, window: 3600, now: at(1800))
        expectEqual(result.count, 2)
        expectEqual(result[1].date, at(1800))
        expectEqual(result[1].session, 40)
        expectEqual(result[1].weekly, 60)
    }

    test("windowed spans the window when every sample predates it") {
        let samples = [UsageSample(date: at(0), session: 40, weekly: 60)]
        let result = UsageHistory.windowed(samples, window: 3600, now: at(10_000))
        expectEqual(result.count, 2)
        expectEqual(result[0].date, at(6400))
        expectEqual(result[1].date, at(10_000))
        expectEqual(result[0].session, 40)
    }

    test("windowed returns nothing for no samples") {
        expect(UsageHistory.windowed([], window: 3600, now: t0).isEmpty, "expected no points")
    }
}
