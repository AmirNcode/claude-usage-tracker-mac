# Claude Usage Tracker v3 — Usage Stats

**Date:** 2026-06-15
**Status:** Implemented (scope confirmed with user: chart + timeline with deltas)

Adds a Stats window reachable from the menu bar dropdown, to help users see how
their prompting moves usage over time.

## Goal & honest scope

Help users understand how usage changes over time so they can prompt more
efficiently. The usage API only exposes **aggregate** session/weekly percentages —
there is no per-message breakdown, and the app has no signal for when the user
sends a prompt. So we record a **history of percentage samples** and show how it
changes; we can show *when usage jumped and by how much*, not "this exact prompt
cost X%". (Per-message token counts exist in Claude Code transcripts but are a
different unit, Claude Code-only, and out of scope here.)

## Behavior

- On every successful poll, append a sample `(timestamp, session%, weekly%)` to a
  local history file; prune entries older than 14 days.
- Menu dropdown gains **Stats…** which opens a window with:
  1. A **line chart** (Swift Charts — verified to compile in the CLT-only
     toolchain) of session% and weekly% over time, y-axis 0–100.
  2. A **timeline list**, most recent first: `HH:mm:ss — Session 58% (+8%) ·
     Weekly 6% (+0%)`. The delta is versus the previous sample; a window reset
     shows as a large negative delta (meaningful: "usage reset").
- While the Stats window is open, polling speeds up to **60 s** (and refreshes
  immediately on open) so prompt-driven jumps are visible; it returns to the
  configured interval when closed. Short bursts only, to respect rate limits.
- Empty state when too few samples: "Collecting data…".

## Architecture

### UsageCore (pure, tested)

- `UsageSample: Codable` — `{ date, session: Double?, weekly: Double? }`.
- `TimelineEntry` — sample plus `sessionDelta`/`weeklyDelta` (nil when either side
  is missing or it's the first entry).
- `UsageHistory`:
  - `appending(_:to:maxAge:now:)` — append + prune by age.
  - `timeline(_:)` — chronological entries with deltas vs the previous sample.

### App shell

- `UsageHistoryStore: ObservableObject` — loads/saves
  `~/Library/Application Support/ClaudeUsageTracker/history.json`, appends via the
  pure function, `@Published samples` so the window updates live.
- `StatsView` (SwiftUI / `NSHostingController`) — chart + timeline list.
- `AppDelegate` — owns the store; appends on poll success; adds the menu item;
  hosts the window; shortens the poll interval while the window is visible.

## Out of scope

Per-prompt token attribution, CSV export, date-range filtering, multi-day
aggregation. Possible later.
