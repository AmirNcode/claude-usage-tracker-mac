import Foundation

/// One rate-limit window (5-hour session or 7-day weekly) as reported by the API.
public struct UsageWindow: Equatable {
    /// Percent used, 0–100 (may exceed 100 briefly).
    public let utilization: Double
    /// When this window resets; nil when the API reports no reset time.
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// Parsed result of GET https://api.anthropic.com/api/oauth/usage.
public struct UsageSnapshot: Equatable {
    /// `five_hour` window; nil when no session window is active.
    public let session: UsageWindow?
    /// `seven_day` window; nil when not reported.
    public let weekly: UsageWindow?

    public init(session: UsageWindow?, weekly: UsageWindow?) {
        self.session = session
        self.weekly = weekly
    }

    public static func parse(from data: Data) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(APIResponse.self, from: data)
        return UsageSnapshot(
            session: response.fiveHour.map { $0.asWindow() },
            weekly: response.sevenDay.map { $0.asWindow() }
        )
    }
}

private struct APIResponse: Decodable {
    let fiveHour: APIWindow?
    let sevenDay: APIWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct APIWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    func asWindow() -> UsageWindow {
        UsageWindow(utilization: utilization ?? 0, resetsAt: resetsAt.flatMap(parseISO8601))
    }
}

// The API emits fractional seconds ("2026-06-12T19:30:00.405471+00:00") but
// tolerate plain ISO-8601 too.
private func parseISO8601(_ string: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
}
