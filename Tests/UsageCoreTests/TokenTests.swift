import Foundation
import UsageCore

func runTokenTests() {
    let now = Date(timeIntervalSince1970: 1_000_000)

    test("parses token response with expires_in") {
        let json = """
        {"access_token":"at","refresh_token":"rt","expires_in":3600}
        """
        let token = try OAuthToken.parse(from: Data(json.utf8), now: now)
        expectEqual(token.accessToken, "at")
        expectEqual(token.refreshToken, "rt")
        expectEqual(token.expiresAt.timeIntervalSince1970, now.timeIntervalSince1970 + 3600)
    }

    test("token expiring within the skew window needs refresh") {
        let token = OAuthToken(accessToken: "a", refreshToken: "r",
                               expiresAt: now.addingTimeInterval(60))
        expect(token.needsRefresh(now: now), "should refresh when <5min remain")
    }

    test("token with ample life does not need refresh") {
        let token = OAuthToken(accessToken: "a", refreshToken: "r",
                               expiresAt: now.addingTimeInterval(3600))
        expect(!token.needsRefresh(now: now), "should not refresh with 1h remaining")
    }

    test("round-trips through keychain JSON encoding") {
        let token = OAuthToken(accessToken: "a", refreshToken: "r", expiresAt: now)
        let data = token.keychainData()
        let restored = OAuthToken.fromKeychainData(data)
        expectEqual(restored?.accessToken, "a")
        expectEqual(restored?.refreshToken, "r")
        expectEqual(restored.map { Int($0.expiresAt.timeIntervalSince1970) },
                    Int(now.timeIntervalSince1970))
    }

    test("reads Claude Code's claudeAiOauth keychain format") {
        let json = """
        {"claudeAiOauth":{"accessToken":"cc","refreshToken":"ccr","expiresAt":1000000000000}}
        """
        let token = OAuthToken.fromKeychainData(Data(json.utf8))
        expectEqual(token?.accessToken, "cc")
        expectEqual(token?.refreshToken, "ccr")
        expectEqual(token.map { Int($0.expiresAt.timeIntervalSince1970) }, 1000000000)
    }
}
