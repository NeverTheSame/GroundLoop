# Limit Projection + GroundLoop Branding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a pace tick and an "At current rate, limit hit at HH:MM" warning on each quota bar, and rename every user-visible "LLM Usage" to "GroundLoop".

**Architecture:** Pure, `now`-injected helpers on `UsageMetric` in the GroundLoop library compute window start, pace fraction and projected limit date from `period.resetsAt` + `period.durationMs`. `MetricRowView` renders them inside its existing 60 s `TimelineView`.

**Tech Stack:** Swift 5.9+/SwiftPM, SwiftUI (macOS 14), swift-testing (`import Testing`).

**Spec:** `docs/superpowers/specs/2026-11-19-limit-projection-design.md`

## Global Constraints

- Rate = window average: `usedPercent / elapsed`, elapsed = `now − (resetsAt − durationMs)`.
- No projection when used is 0 or ≥ 100, when elapsed < max(10 min, 2% of window), or when projected ≥ `resetsAt`.
- Warning copy: `At current rate, limit hit at HH:mm`; prefix weekday (`EEE HH:mm`, e.g. "Sun 16:59") when not today. Orange, `exclamationmark.triangle.fill`.
- No notifications. No history-based rate.
- Working tree has unrelated uncommitted user changes: do NOT commit; leave changes unstaged for the user.

## Review Focus

1. Metric with `resetsAt` already in the past (stale fetch) → no tick beyond bar, no warning (pace clamps to 1, projection nil).
2. Metric whose `durationMs` is nil (e.g. some GLM/Copilot paths) → no tick, no warning, no crash.
3. Clock skew: `resetsAt − duration` in the future (elapsed < 0) → pace 0, projection nil.
4. Weekly window projected to a different day → weekday prefix shown.
5. Pace tick must not overflow the bar width at pace = 1.

---

### Task 1: Pace helpers on UsageMetric

**Files:**
- Modify: `Sources/GroundLoop/Models/UsageData.swift` (extension after `UsageMetric`)
- Test: `Tests/GroundLoopTests/UsagePaceTests.swift` (new, swift-testing)

**Interfaces:**
- Produces:
  - `extension UsageMetric { public func windowStart() -> Date? }`
  - `public func paceFraction(now: Date = Date()) -> Double?` — clamped 0…1, nil without resetsAt/durationMs
  - `public func projectedLimitDate(now: Date = Date()) -> Date?`

- [ ] **Step 1: Write failing tests** (helper `metric(used:, elapsed:, duration:)` building a `.percent` metric with `resetsAt = now − elapsed + duration`):
  - `projectsHitBeforeReset`: 5h window, 39 min elapsed, 18% → projected ≈ now + 2.96h (±60 s); paceFraction ≈ 0.13.
  - `nilWhenHitAfterReset`: 5h window, 4h elapsed, 50% → nil.
  - `nilTooEarly`: 5h window, 5 min elapsed, 10% → nil; 7-day window, 2h elapsed (< 2% = 3.36h), 5% → nil.
  - `nilAtZeroAndFull`: 0% → nil; 100% → nil.
  - `nilWithoutPeriodData`: period nil → all three nil; durationMs nil → all nil.
  - `paceClamps`: resetsAt in past → paceFraction == 1, projection nil; window start in future → paceFraction == 0, projection nil.
- [ ] **Step 2:** `swift test --filter UsagePaceTests` → FAIL (no member).
- [ ] **Step 3:** Implement the three functions per Global Constraints.
- [ ] **Step 4:** `swift test --filter UsagePaceTests` → PASS; `swift test` whole suite PASS.

### Task 2: MetricRowView pace tick + warning

**Files:**
- Modify: `Sources/groundloop-menubar/Views/MetricRowView.swift`

**Interfaces:**
- Consumes: `paceFraction(now:)`, `projectedLimitDate(now:)` from Task 1.

- [ ] **Step 1:** Wrap bar + caption area in the existing `TimelineView(.periodic(from: .now, by: 60))` so both use `context.date`.
- [ ] **Step 2:** Overlay a 2-pt wide, 10-pt tall `Color.secondary` capsule at `x = min(width * pace, width - 2)` when pace non-nil.
- [ ] **Step 3:** Under the bar, when projection non-nil, `Label` with `exclamationmark.triangle.fill` + copy per Global Constraints, `.font(.caption2)`, `.foregroundColor(.orange)`. Formatter: `HH:mm` if `Calendar.current.isDateInToday`, else `EEE HH:mm`.
- [ ] **Step 4:** `swift build` → succeeds with no new warnings.

### Task 3: Branding

**Files:**
- Modify: `Sources/groundloop-menubar/Resources/Info.plist:9,11`, `Sources/groundloop-menubar/Views/HeaderView.swift:9`, `Sources/groundloop-menubar/StatusBarController.swift:23,87`, `README.md:29`

- [ ] **Step 1:** Replace "LLM Usage" with "GroundLoop" in the plist and Swift files; README line → "Monitor your AI coding quotas from the macOS menu bar with GroundLoop."-style wording that drops the phrase.
- [ ] **Step 2:** `grep -rn "LLM Usage" Sources README.md` → no output; `swift build` succeeds.
