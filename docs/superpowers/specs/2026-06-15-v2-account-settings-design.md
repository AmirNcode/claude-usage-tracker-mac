# Claude Usage Tracker v2 — Account, Settings, Packaging

**Date:** 2026-06-15
**Status:** Implemented (requirements confirmed with user; user pre-authorized autonomous build)

Builds on the [v1 design](2026-06-12-claude-usage-tracker-design.md). This phase
adds standalone account login, a settings window, color customization, an app
icon, DMG distribution — and **removes notifications entirely**.

## Decisions (confirmed with user)

1. **Account connection:** browser OAuth login **with Claude Code token as fallback**.
   The app prefers its own logged-in token (auto-refreshed); if absent it reads
   Claude Code's Keychain token read-only. OAuth is unofficial (reuses Claude
   Code's public client + Anthropic's endpoints) and may break — the fallback
   guarantees the app keeps working.
2. **Notifications: removed.** The earlier reset/90% notifications are gone. The
   menu bar color thresholds replace them as the at-a-glance warning. (User found
   the AppleScript notifications clunky and—due to a bug—spammy; and built-in
   notifications need a signed build.)
3. **Distribution:** DMG (drag-to-Applications) + GitHub Release workflow. Ad-hoc
   signed by default; Developer ID signing/notarization optional via secrets.
4. **App icon:** a circular usage-gauge in Claude coral on graphite, generated from
   code (`scripts/gen-icon.swift`).
5. **Menu bar:** keep the `58% / 6%` numbers, now colored per window.

## Bugs fixed from v1

- **Frozen menu bar / silent failures.** v1 polled every 60 s indefinitely and tripped
  the usage endpoint's rate limit (HTTP 429); the error path silently kept stale
  data. Fixes: default 5-minute interval (configurable 1–15), exponential backoff
  capped at 30 min that honors `Retry-After`, an ephemeral cache-free `URLSession`
  (defensive — the endpoint already sends `no-store`), and visible connection /
  last-refreshed / last-error status in the menu and Settings.
- **Notification spam.** `resets_at` carries sub-second jitter that changes every
  request, so v1's "window changed" check fired every poll, re-triggering the 90%
  warning. Removed with notifications; reset-time comparisons are no longer used.

## Architecture

### UsageCore (pure, unit-tested)

- `UsageModel` — API parsing (unchanged).
- `UsageFormatter` — menu bar / menu line strings (unchanged).
- `UsageLevel` — `normal | warning(≥90) | critical(≥100)` from utilization + a
  thresholds-enabled flag. UI maps this to color.
- `OAuth` — `PKCE` (S256, CryptoKit), `OAuthConfig` (authorize URL, token-exchange
  and refresh request builders, pasted-code parsing), `OAuthToken` (parse,
  expiry/`needsRefresh`, Keychain JSON round-trip, reads Claude Code's
  `claudeAiOauth` shape).
- `UsageClient` — networking only; takes an access token; cache-free; maps 401/403→
  `unauthorized`, 429→`rateLimited(retryAfter:)`.

### App shell

- `Keychain` — wraps `/usr/bin/security` (robust across ad-hoc rebuilds; `-A`).
- `AuthManager` — token source resolution (own item `ClaudeUsageTracker-credentials`
  → Claude Code item, read-only), OAuth login (`beginLogin` opens browser,
  `completeLogin(pastedCode:)` exchanges), refresh, logout, `source` for display.
- `Preferences` — `ObservableObject` over UserDefaults (thresholds, per-window
  color hex, refresh minutes, launch at login).
- `AppState` — `ObservableObject` shared with Settings (snapshot, lastRefreshed,
  lastError, source).
- `AppColors` — `UsageLevel` + custom hex → `NSColor` (threshold wins; else custom;
  else `labelColor`).
- `AppDelegate` — status item with a colored attributed title, restructured menu,
  variable-interval poller with backoff, 401→force-refresh retry, wake refresh,
  launch-at-login via `SMAppService`, hosts the Settings window.
- `SettingsView` (SwiftUI, `NSHostingController`) — Account / Appearance / General /
  About tabs.

### Packaging

- `scripts/gen-icon.swift` + `build-icon.sh` → `Resources/AppIcon.icns`.
- `scripts/build-app.sh` → `.app` (icon + Info.plist with `LSUIElement`,
  `CODESIGN_IDENTITY`-aware signing).
- `scripts/make-dmg.sh` → `.dmg` with Applications symlink.
- `.github/workflows/release.yml` → tests + DMG on `v*` tags, attached to the release.

## Verification

- `make test` — 64 assertion checks (parsing, formatting, levels, PKCE/OAuth, token).
- `make status` — live data via Claude Code fallback.
- Installed bundle runs, polls without error, renders the colored `58% / 6%` title
  (captured in `docs/images/menubar.png`); DMG mounts with the expected layout.
- OAuth login is implemented but **not** verifiable end-to-end here (needs an
  interactive browser approval); the PKCE/URL/exchange/refresh request construction
  is unit-tested, and the Claude Code fallback is verified working.

## Out of scope (future)

Notarized distribution by default, notifications (revisit once signed), Opus-specific
weekly limits, historical graphs, multiple accounts.
