import Foundation
import CryptoKit

/// Proof Key for Code Exchange (RFC 7636) pair.
public struct PKCE {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.challenge = Data(digest).base64URLEncodedString()
    }

    /// Generates a cryptographically random verifier (96 bytes -> 128 base64url chars).
    public static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 96)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return PKCE(verifier: Data(bytes).base64URLEncodedString())
    }
}

/// OAuth endpoints and parameters for Claude.
///
/// IMPORTANT: This reuses the Claude Code public client and Anthropic's OAuth
/// endpoints. There is no official third-party usage API; this is unofficial and
/// may break or violate Anthropic's terms. The app falls back to Claude Code's
/// existing Keychain token when this login is not used.
public enum OAuthConfig {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeEndpoint = URL(string: "https://claude.ai/oauth/authorize")!
    public static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    public static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    public static let scope = "org:create_api_key user:profile user:inference"

    public static func authorizeURL(pkce: PKCE, state: String) -> URL {
        var comps = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return comps.url!
    }

    /// The authorize page presents `code#state`; accept either form.
    public static func parsePastedCode(_ raw: String) -> (code: String, state: String?)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        return (parts[0], parts.count > 1 ? parts[1] : nil)
    }

    public static func tokenExchangeRequest(code: String, verifier: String, state: String?) -> URLRequest {
        var body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]
        if let state { body["state"] = state }
        return jsonPOST(to: tokenEndpoint, body: body)
    }

    public static func refreshRequest(refreshToken: String) -> URLRequest {
        jsonPOST(to: tokenEndpoint, body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])
    }

    private static func jsonPOST(to url: URL, body: [String: Any]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }
}

/// An OAuth token pair with its absolute expiry.
public struct OAuthToken: Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Refresh a little early to avoid races near expiry.
    public static let refreshSkew: TimeInterval = 5 * 60

    public func needsRefresh(now: Date = Date()) -> Bool {
        now.addingTimeInterval(Self.refreshSkew) >= expiresAt
    }

    public static func parse(from data: Data, now: Date = Date()) throws -> OAuthToken {
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return OAuthToken(
            accessToken: r.access_token,
            refreshToken: r.refresh_token ?? "",
            expiresAt: now.addingTimeInterval(r.expires_in ?? 3600)
        )
    }

    /// Our own Keychain payload (mirrors Claude Code's nested shape so the format
    /// is recognizable and forward-compatible).
    public func keychainData() -> Data {
        let payload: [String: Any] = ["claudeAiOauth": [
            "accessToken": accessToken,
            "refreshToken": refreshToken,
            "expiresAt": Int(expiresAt.timeIntervalSince1970 * 1000),
        ]]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    /// Reads either our payload or Claude Code's `claudeAiOauth` Keychain item.
    public static func fromKeychainData(_ data: Data) -> OAuthToken? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? json
        guard let access = oauth["accessToken"] as? String, !access.isEmpty else { return nil }
        let refresh = oauth["refreshToken"] as? String ?? ""
        let expiresMs = (oauth["expiresAt"] as? Double) ?? 0
        return OAuthToken(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: expiresMs / 1000)
        )
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
