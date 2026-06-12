# Claude Usage Tracker (macOS menu bar)

A tiny native macOS menu bar app that shows your Claude subscription usage limits,
as consumed by Claude Code / claude.ai:

```
43% / 73%        ← menu bar: [5-hour session used] / [weekly limit used]
```

Clicking it shows:

```
43% - 20:30      ← session usage, resets at 20:30 (local time)
73% - Mon 05:59  ← weekly usage, resets Monday 05:59 (local time)
Settings ▸         Launch at Login ✓ / Notifications ✓ / Refresh Now / Quit
```

## Notifications

- **Reset alerts** — fires the moment the 5-hour session window or the weekly
  window resets ("Session usage reset to 0%"), so you can use your limits
  efficiently. Scheduled locally at the exact reset time, not dependent on polling.
- **90% warning** — fires once per window the first time usage crosses 90%.

## How it works

Claude Code stores an OAuth token in the macOS Keychain (item
`Claude Code-credentials`). The app reads that token (read-only — it never
refreshes or modifies your credentials) and polls Anthropic's usage endpoint
(`GET https://api.anthropic.com/api/oauth/usage`) every 60 seconds, plus
immediately on wake from sleep.

Requirements: macOS 14+, Claude Code logged in with a Pro/Max subscription
account. No dependencies; no Xcode needed to build (Command Line Tools suffice).

## Build & install

```sh
make test      # run unit tests
make app       # build build/ClaudeUsageTracker.app
make install   # build, copy to /Applications, launch
make status    # print current usage in the terminal (no GUI)
```

On first launch the app:

- asks for **notification permission** — click *Allow* to get reset/90% alerts;
- registers itself as a **login item** (toggle in Settings ▸ Launch at Login);
- if macOS ever shows a **Keychain prompt** for it, click *Always Allow*.

## Error states

| Menu bar | First menu line | Meaning |
|---|---|---|
| `–% / –%` | `Claude Code not logged in` | No credentials in the Keychain |
| `–% / –%` | `Token expired — use Claude Code` | Stored token expired; run any Claude Code command to refresh it |
| `–% / –%` | `Offline — retrying every minute` | Network/API error before first successful fetch |
| stale values | — | Errors after a successful fetch keep the last known data |

## Project layout

```
Sources/UsageCore/            pure logic: parsing, formatting, notification decisions, API client
Sources/ClaudeUsageTracker/   app shell: menu bar UI, settings, UNUserNotificationCenter
Tests/UsageCoreTests/         assertion-based test runner (CLT toolchain has no XCTest)
Resources/Info.plist          bundle metadata (LSUIElement menu bar app)
scripts/build-app.sh          builds and ad-hoc signs the .app
docs/superpowers/specs/       design spec
```
