import AppKit
import UsageCore

/// Where the current access token comes from.
enum AccountSource: Equatable {
    case oauth        // user logged in through this app
    case claudeCode   // borrowed from Claude Code's Keychain item
    case none
}

enum AuthError: Error, CustomStringConvertible {
    case notLoggedIn
    case loginFailed(String)

    var description: String {
        switch self {
        case .notLoggedIn: return "Not connected to a Claude account"
        case .loginFailed(let why): return "Login failed: \(why)"
        }
    }
}

/// Manages the Claude account connection: this app's own OAuth token (with refresh)
/// and a read-only fallback to Claude Code's existing Keychain token.
final class AuthManager {
    static let ownService = "ClaudeUsageTracker-credentials"
    static let claudeCodeService = "Claude Code-credentials"

    // Set transiently between starting and completing an interactive login.
    private var pendingPKCE: PKCE?
    private var pendingState: String?

    /// Synchronous best-effort source detection for UI display.
    var source: AccountSource {
        if Keychain.read(service: Self.ownService).flatMap(OAuthToken.fromKeychainData) != nil {
            return .oauth
        }
        if Keychain.read(service: Self.claudeCodeService).flatMap(OAuthToken.fromKeychainData) != nil {
            return .claudeCode
        }
        return .none
    }

    var isLoggedInViaOAuth: Bool { source == .oauth }

    /// Returns a usable access token, refreshing this app's OAuth token if needed.
    /// `forceRefresh` is used after a 401 to recover from an expired token.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        if let data = Keychain.read(service: Self.ownService),
           let token = OAuthToken.fromKeychainData(data) {
            if forceRefresh || token.needsRefresh() {
                if let refreshed = try? await refresh(token: token) {
                    return refreshed.accessToken
                }
                // Refresh failed; fall through to whatever we have / Claude Code.
            }
            if !token.accessToken.isEmpty { return token.accessToken }
        }
        if let data = Keychain.read(service: Self.claudeCodeService),
           let token = OAuthToken.fromKeychainData(data) {
            return token.accessToken
        }
        throw AuthError.notLoggedIn
    }

    // MARK: - Interactive OAuth login

    /// Opens the Claude authorization page in the browser and returns the PKCE
    /// state. The user copies the displayed code and pastes it into the app, which
    /// then calls `completeLogin`.
    func beginLogin() {
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        pendingPKCE = pkce
        pendingState = state
        NSWorkspace.shared.open(OAuthConfig.authorizeURL(pkce: pkce, state: state))
    }

    func completeLogin(pastedCode raw: String) async throws {
        guard let pkce = pendingPKCE else {
            throw AuthError.loginFailed("No login in progress — click Log in first.")
        }
        guard let parsed = OAuthConfig.parsePastedCode(raw) else {
            throw AuthError.loginFailed("Empty code.")
        }
        let request = OAuthConfig.tokenExchangeRequest(
            code: parsed.code, verifier: pkce.verifier, state: parsed.state ?? pendingState
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AuthError.loginFailed("token endpoint returned HTTP \(code)")
        }
        let token = try OAuthToken.parse(from: data)
        Keychain.write(service: Self.ownService, account: "claude", data: token.keychainData())
        pendingPKCE = nil
        pendingState = nil
    }

    func logout() {
        Keychain.delete(service: Self.ownService)
    }

    // MARK: - Refresh

    private func refresh(token: OAuthToken) async throws -> OAuthToken {
        guard !token.refreshToken.isEmpty else { throw AuthError.loginFailed("no refresh token") }
        let (data, response) = try await URLSession.shared.data(
            for: OAuthConfig.refreshRequest(refreshToken: token.refreshToken)
        )
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.loginFailed("refresh failed")
        }
        var refreshed = try OAuthToken.parse(from: data)
        // Some providers omit a new refresh token; keep the existing one.
        if refreshed.refreshToken.isEmpty {
            refreshed = OAuthToken(accessToken: refreshed.accessToken,
                                   refreshToken: token.refreshToken,
                                   expiresAt: refreshed.expiresAt)
        }
        Keychain.write(service: Self.ownService, account: "claude", data: refreshed.keychainData())
        return refreshed
    }
}
