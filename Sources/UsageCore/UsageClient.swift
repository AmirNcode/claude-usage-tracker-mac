import Foundation

public enum UsageClientError: Error, CustomStringConvertible {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case httpError(Int)
    case badResponse

    public var description: String {
        switch self {
        case .unauthorized: return "Token expired or unauthorized"
        case .rateLimited: return "Rate limited by the usage API"
        case .httpError(let code): return "Usage API returned HTTP \(code)"
        case .badResponse: return "Unexpected response from usage API"
        }
    }
}

/// Networking-only client for Anthropic's OAuth usage endpoint. Token acquisition
/// (Keychain / OAuth refresh) is handled by the caller and passed in per request.
public final class UsageClient {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let session: URLSession

    public init() {
        // Ephemeral, cache-free session: the usage endpoint sends `no-store`, but
        // be defensive so "Refresh Now" always hits the network.
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    public func fetchUsage(accessToken: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.badResponse }
        switch http.statusCode {
        case 200:
            return try UsageSnapshot.parse(from: data)
        case 401, 403:
            throw UsageClientError.unauthorized
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw UsageClientError.rateLimited(retryAfter: retryAfter)
        default:
            throw UsageClientError.httpError(http.statusCode)
        }
    }
}
