# Limit projection + GroundLoop branding — design

## Why
Kirill wants to see, at a glance, whether his current usage pace will run a quota
out before it resets (as PokeTokenBar shows "At current rate, limit hit at 10:06"),
and wants the app to present itself only as "GroundLoop", never "LLM Usage".

## Goals
- Per quota bar: an orange warning line `⚠ At current rate, limit hit at HH:MM`
  shown only when the projected hit time is before the window resets.
- Per quota bar: a grey pace tick at `elapsed / window length`, so fill past the
  tick = ahead of an even pace.
- Replace every user-visible "LLM Usage" with "GroundLoop".

## Non-goals
- No notifications (existing LowQuotaNotifier stays as is).
- No recent-burst / history-based rate; no reset clock time changes.

## Approaches considered
- **Window average** (picked): rate = usedPercent / time since window start.
  Stable, works immediately, matches PokeTokenBar within minutes.
- Recent burst from 5-min history snapshots: reactive but noisy, needs warm-up.
- Blend: most accurate, hardest to reason about.

## Design
- Library (`Sources/GroundLoop/Models/UsageData.swift`): pure helpers on
  `UsageMetric`, taking `now: Date`:
  - `windowStart = resetsAt − durationMs` (nil if either missing).
  - `paceFraction(now:)` → elapsed / duration, clamped 0…1.
  - `projectedLimitDate(now:)` → `now + (100 − used) / (used / elapsed)`;
    nil when used is 0 or ≥ 100, when elapsed < max(10 min, 2% of window)
    (avoid wild projections right after a reset), or when the result is not
    before `resetsAt`.
- UI (`MetricRowView`): grey 2-pt tick over the bar at `paceFraction`; orange
  caption with `exclamationmark.triangle.fill` under the bar when
  `projectedLimitDate` is non-nil. Time as `HH:mm`, prefixed with weekday when
  not today (e.g. "Sun 16:59"). Refreshes with the existing 60 s TimelineView.
- Branding: `Info.plist` CFBundleName/CFBundleDisplayName, `HeaderView` title,
  `StatusBarController` accessibility labels, README line → "GroundLoop".
- Tests: unit tests for the helpers (normal projection, hit-after-reset → nil,
  too-early guard, 0% / 100%, missing period).

## Left to the builder
Exact tick styling and spacing.
