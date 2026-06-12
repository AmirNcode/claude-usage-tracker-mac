# Claude Usage Tracker — Design

**Date:** 2026-06-12
**Status:** Approved (requirements confirmed with user via Q&A; user pre-approved autonomous implementation)

## Purpose

A minimal native macOS menu bar app that shows Claude (Pro/Max subscription) usage
limits as consumed by Claude Code: the current 5-hour session window and the 7-day
weekly window. Pure functionality, no fancy UI.

## Requirements (confirmed)

1. Menu bar title shows `<session>% / <weekly>%` — percent **used** (e.g. `30% / 60%`
   = 30% of the 5-hour session used, 60% of the weekly limit used).
2. Clicking the menu bar item opens a menu with exactly:
   - Line 1: session usage and local reset time, e.g. `30% - 17:00`
   - Line 2: weekly usage and local reset day+time, e.g. `60% - Mon 06:00`
   - Line 3: `Settings` (submenu: Launch at Login ✓, Notifications ✓, Refresh Now, Quit)
3. Notifications:
   - When the session window resets: "Session usage reset to 0%".
   - When the weekly window resets: "Weekly usage reset to 0%".
   - Warning the first time usage crosses **90%** in a window (once per window).
4. Stack: native Swift + AppKit, zero third-party dependencies. Builds with the
   Swift CLI toolchain (no Xcode required).
5. Installed to `/Applications`, launch-at-login enabled (toggleable).

## Data source

Claude Code stores OAuth credentials in the macOS Keychain item
`Claude Code-credentials` (JSON with `claudeAiOauth.accessToken`). The app:

1. Reads the token by shelling out to `/usr/bin/security find-generic-password
   -s "Claude Code-credentials" -w` (same access path as the CLI — verified to work
   without a permission prompt on this machine).
2. Calls `GET https://api.anthropic.com/api/oauth/usage` with headers
   `Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20`.
3. Response (verified live):

```json
{
  "five_hour": {"utilization": 90.0, "resets_at": "2026-06-12T19:30:00.405471+00:00"},
  "seven_day": {"utilization": 69.0, "resets_at": "2026-06-15T10:00:00.405493+00:00"}
}
```

`utilization` is percent used; `resets_at` is ISO-8601. Either window may be `null`
(no active window) — display `0%` with no reset time in that case.

**Read-only credentials policy:** the app never refreshes or writes OAuth tokens
(token refresh rotates the refresh token and could log the user out of Claude Code).
On HTTP 401 it re-reads the Keychain once (Claude Code refreshes the token whenever
it is used); if still unauthorized, the app shows an error state in the menu
(`–% / –%` title, first line "Token expired — use Claude Code") until a later poll
succeeds.

## Architecture

SwiftPM executable package; the release binary is wrapped into
`ClaudeUsageTracker.app` by `scripts/build-app.sh` (Info.plist with `LSUIElement=true`
so there is no Dock icon; ad-hoc codesigned).

Units (pure logic kept separate from shell for testability):

- **UsageModel** — `UsageSnapshot` struct + JSON parsing from the API response.
- **UsageFormatter** — pure functions producing the menu bar title (`"30% / 60%"`,
  rounded to integers) and menu lines (`"30% - 17:00"`, `"60% - Mon 06:00"`).
  Times are local timezone, fixed 24-hour `HH:mm`, weekday `EEE` in en_US_POSIX
  (matches the user's examples).
- **NotificationDecider** — pure decision logic: given the previous tracked state
  (per-window `resets_at`, `warnedAt90` flag) and a new snapshot, returns actions:
  schedule/replace/cancel reset notification, fire 90% warning, reset the warned
  flag when a new window starts.
- **UsageClient** — Keychain read + HTTP call (async, URLSession).
- **NotificationManager** — applies decider actions via `UNUserNotificationCenter`.
  Reset notifications are *scheduled* (`UNCalendarNotificationTrigger` at
  `resets_at`, stable identifiers `session-reset` / `weekly-reset`) so they fire
  on time even between polls; rescheduled whenever `resets_at` changes.
- **AppDelegate / StatusBarController** — NSStatusItem, menu, Settings submenu,
  60-second poll timer, immediate refresh on wake-from-sleep
  (`NSWorkspace.didWakeNotification`).

### Settings (persisted)

- *Launch at Login*: `SMAppService.mainApp` register/unregister; checkmark reflects
  current status. Registered on first launch by default (user chose auto-start).
- *Notifications*: `UserDefaults` bool, default on. When off: cancel pending
  scheduled notifications and skip warnings.
- *Refresh Now*: manual poll.
- *Quit*.

### CLI verification mode

`ClaudeUsageTracker --status` runs the fetch + formatting pipeline headlessly and
prints the title and menu lines, then exits. Used for automated verification
(no GUI/notification APIs touched, so it also works as a bare binary).

## Error handling

| Condition | Behavior |
|---|---|
| Keychain item missing | Title `–% / –%`, line 1 "Claude Code not logged in" |
| HTTP 401 after keychain re-read | Title `–% / –%`, line 1 "Token expired — use Claude Code" |
| Network error / non-200 | Keep last known data, append nothing; if no data yet, `–% / –%` |
| `five_hour`/`seven_day` null | That window shows `0%` and no reset time; cancel its scheduled reset notification |

## Testing

Pure logic (parsing, formatting, decider) covered by tests run via `swift test`
(Swift Testing) — or, if the CLT toolchain can't run the test harness, a fallback
assertion-based test executable run via `make test`. App shell verified by running
the built bundle and the `--status` CLI against the live API.

## Out of scope (future)

Threshold customization UI, multiple accounts, Opus-specific weekly limits,
historical usage graphs, signed/notarized distribution.
