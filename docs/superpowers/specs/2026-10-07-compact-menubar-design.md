# Compact vertical menu bar item

**Date:** 2026-10-07

## Problem

The menu bar item rendered `68%  /  62%` on one line (~110 pt wide), taking too much
horizontal space in a crowded menu bar.

## Design

The status item is now a fixed-width (~56 pt) custom view (`StatusBarView`) inside the
`NSStatusItem` button:

```
 ┌──────┐  68%   ← 5-hour session
 │ ring │  62%   ← 7-day weekly
 └──────┘
```

- **Left: progress icon (16 pt).**
  - *Outer ring* (2 pt stroke) = 5-hour session utilization, drawn clockwise from 12 o'clock.
  - *Inner pie* = weekly utilization, a filled wedge from 12 o'clock.
  - Each has a 25%-alpha track of the same color so the empty part is still visible.
- **Right: two stacked percentages**, 9 pt semibold monospaced-digit, right-aligned in a
  column sized for `100%` so the item never changes width as numbers move.
- No data yet: `–%` / `–%` and empty tracks.

### Colors

| Level | Session (ring + top %) | Weekly (pie + bottom %) |
|---|---|---|
| < 80% | ring: label color; text: custom color or label color | same |
| ≥ 80% (`warning`) | **orange** | **yellow** |
| ≥ 100% (`critical`) | **red** | **red** |

- `UsageLevel.warningThreshold` moved from 90 → **80** (applies to text and icon).
- Rings are always monochrome below the threshold (the custom colors only affect the text).
- When "Highlight high usage" is off, everything stays at its normal color.

## Implementation notes

- `StatusBarView` draws inside `effectiveAppearance.performAsCurrentDrawingAppearance`, so
  `labelColor` follows the menu bar's light/dark tint, and redraws on
  `viewDidChangeEffectiveAppearance`.
- It returns `nil` from `hitTest` so clicks fall through to the status button and open the menu.
- `AppColors.color(level:warning:customHex:)` takes the per-window warning color;
  `AppColors.ringColor` is the same without a custom color.
- The old single-line text survives as the button tooltip (`UsageFormatter.menuBarTitle`) and in
  `--status` CLI output.
- `docs/images/menubar.png` is an offscreen render of `StatusBarView` (68% / 62%, dark bar).
