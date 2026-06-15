import Foundation
import UsageCore

func runOAuthPKCETests() {
    test("PKCE verifier is URL-safe and adequately long") {
        let pkce = PKCE.generate()
        expect(pkce.verifier.count >= 43 && pkce.verifier.count <= 128,
               "verifier length \(pkce.verifier.count) out of RFC range")
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        expect(pkce.verifier.unicodeScalars.allSatisfy { allowed.contains($0) },
               "verifier has non-unreserved characters: \(pkce.verifier)")
    }

    test("PKCE challenge is base64url SHA-256 with no padding") {
        // Known RFC 7636 Appendix B test vector.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        expectEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        expect(!pkce.challenge.contains("="), "challenge must not be padded")
        expect(!pkce.challenge.contains("+") && !pkce.challenge.contains("/"),
               "challenge must be base64url")
    }

    test("authorize URL contains required PKCE params") {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = OAuthConfig.authorizeURL(pkce: pkce, state: "xyz")
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: comps.queryItems!.map { ($0.name, $0.value ?? "") })
        expectEqual(items["response_type"], "code")
        expectEqual(items["client_id"], OAuthConfig.clientID)
        expectEqual(items["code_challenge"], pkce.challenge)
        expectEqual(items["code_challenge_method"], "S256")
        expectEqual(items["state"], "xyz")
        expect(items["redirect_uri"] != nil, "redirect_uri missing")
        expect(items["scope"] != nil, "scope missing")
        expect(comps.host == "claude.ai", "unexpected authorize host \(comps.host ?? "nil")")
    }

    test("authorization code with appended state is split") {
        let parsed = OAuthConfig.parsePastedCode("THECODE#THESTATE")
        expectEqual(parsed?.code, "THECODE")
        expectEqual(parsed?.state, "THESTATE")
    }

    test("authorization code without state still parses") {
        let parsed = OAuthConfig.parsePastedCode("  JUSTCODE  ")
        expectEqual(parsed?.code, "JUSTCODE")
        expect(parsed?.state == nil, "state should be nil")
    }

    test("token exchange request is well-formed JSON POST") {
        let pkce = PKCE(verifier: "verifier123")
        let req = OAuthConfig.tokenExchangeRequest(code: "abc", verifier: pkce.verifier, state: "st")
        expectEqual(req.httpMethod, "POST")
        expectEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
        expectEqual(body["grant_type"] as? String, "authorization_code")
        expectEqual(body["code"] as? String, "abc")
        expectEqual(body["code_verifier"] as? String, "verifier123")
        expectEqual(body["client_id"] as? String, OAuthConfig.clientID)
    }

    test("refresh request uses refresh_token grant") {
        let req = OAuthConfig.refreshRequest(refreshToken: "r123")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as! [String: Any]
        expectEqual(body["grant_type"] as? String, "refresh_token")
        expectEqual(body["refresh_token"] as? String, "r123")
        expectEqual(body["client_id"] as? String, OAuthConfig.clientID)
    }
}
