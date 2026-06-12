import Foundation
import UsageCore

func runUsageModelTests() {
    test("parses live-shaped response") {
        let json = """
        {"five_hour":{"utilization":90.0,"resets_at":"2026-06-12T19:30:00.405471+00:00"},
         "seven_day":{"utilization":69.0,"resets_at":"2026-06-15T10:00:00.405493+00:00"},
         "seven_day_opus":null,
         "extra_usage":{"is_enabled":false}}
        """
        let snapshot = try UsageSnapshot.parse(from: Data(json.utf8))
        expectEqual(snapshot.session?.utilization, 90.0)
        expectEqual(snapshot.weekly?.utilization, 69.0)

        let expected = Date(timeIntervalSince1970: 1781292600.405471)
        if let actual = snapshot.session?.resetsAt {
            expect(abs(actual.timeIntervalSince(expected)) < 0.01, "session resetsAt off: \(actual)")
        } else {
            expect(false, "session resetsAt missing")
        }
    }

    test("parses dates without fractional seconds") {
        let json = """
        {"five_hour":{"utilization":5.0,"resets_at":"2026-06-12T19:30:00+00:00"},"seven_day":null}
        """
        let snapshot = try UsageSnapshot.parse(from: Data(json.utf8))
        let expected = Date(timeIntervalSince1970: 1781292600)
        if let actual = snapshot.session?.resetsAt {
            expect(abs(actual.timeIntervalSince(expected)) < 0.01, "resetsAt off: \(actual)")
        } else {
            expect(false, "session resetsAt missing")
        }
    }

    test("parses null windows") {
        let json = #"{"five_hour":null,"seven_day":null}"#
        let snapshot = try UsageSnapshot.parse(from: Data(json.utf8))
        expect(snapshot.session == nil, "session should be nil")
        expect(snapshot.weekly == nil, "weekly should be nil")
    }

    test("parses window with null resets_at") {
        let json = #"{"five_hour":{"utilization":0.0,"resets_at":null},"seven_day":null}"#
        let snapshot = try UsageSnapshot.parse(from: Data(json.utf8))
        expectEqual(snapshot.session?.utilization, 0.0)
        expect(snapshot.session?.resetsAt == nil, "resetsAt should be nil")
    }

    test("throws on garbage") {
        expectThrows {
            _ = try UsageSnapshot.parse(from: Data("not json".utf8))
        }
    }
}
