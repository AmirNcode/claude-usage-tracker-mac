import Foundation

public enum UsageClientError: Error, CustomStringConvertible {
    case keychainItemNotFound
    case malformedCredentials
    case unauthorized
    case httpError(Int)
    case badResponse

    public var description: String {
        switch self {
        case .keychainItemNotFound: return "Claude Code credentials not found in Keychain"
        case .malformedCredentials: return "Could not read access token from Keychain item"
        case .unauthorized: return "Token expired — use Claude Code to refresh it"
        case .httpError(let code): return "Usage API returned HTTP \(code)"
        case .badResponse: return "Unexpected response from usage API"
        }
    }
}

/// Fetches usage from Anthropic's OAuth usage endpoint using the token Claude Code
/// keeps in the macOS Keychain. Strictly read-only on credentials: never refreshes
/// or writes tokens (token refresh rotates the refresh token and could log the
/// user out of Claude Code). On 401 it re-reads the Keychain once, since Claude
/// Code rotates the token whenever it runs.
public final class UsageClient {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"

    public init() {}

    public func fetchUsage() async throws -> UsageSnapshot {
        let token = try readAccessToken()
        do {
            return try await fetch(with: token)
        } catch UsageClientError.unauthorized {
            let fresh = try readAccessToken()
            guard fresh != token else { throw UsageClientError.unauthorized }
            return try await fetch(with: fresh)
        }
    }

    private func fetch(with token: String) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.badResponse
        }
        switch http.statusCode {
        case 200:
            return try UsageSnapshot.parse(from: data)
        case 401, 403:
            throw UsageClientError.unauthorized
        default:
            throw UsageClientError.httpError(http.statusCode)
        }
    }

    /// Reads the OAuth access token via /usr/bin/security — the same access path
    /// as the CLI, which avoids a per-app Keychain ACL prompt.
    private func readAccessToken() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", Self.keychainService, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            throw UsageClientError.keychainItemNotFound
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UsageClientError.keychainItemNotFound
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = json["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else {
            throw UsageClientError.malformedCredentials
        }
        return token
    }
}
