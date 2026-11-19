import Foundation
import Testing
@testable import GroundLoop

private let hour: TimeInterval = 3600

private func metric(
    used: Double,
    elapsed: TimeInterval,
    duration: TimeInterval,
    now: Date
) -> UsageMetric {
    UsageMetric(
        label: "Session",
        usedPercent: used,
        format: .percent,
        period: UsagePeriod(
            label: "window",
            resetsAt: now.addingTimeInterval(duration - elapsed),
            durationMs: Int(duration * 1000)
        )
    )
}

@Test func projectsHitBeforeReset() {
    let now = Date()
    let m = metric(used: 18, elapsed: 39 * 60, duration: 5 * hour, now: now)
    let projected = try! #require(m.projectedLimitDate(now: now))
    // 18% in 39 min -> 82% more takes 39 * 82/18 min ≈ 2.96 h
    let expected = now.addingTimeInterval(39 * 60 * 82 / 18)
    #expect(abs(projected.timeIntervalSince(expected)) < 60)
    #expect(abs(m.paceFraction(now: now)! - 0.13) < 0.001)
}

@Test func nilWhenHitAfterReset() {
    let now = Date()
    let m = metric(used: 50, elapsed: 4 * hour, duration: 5 * hour, now: now)
    #expect(m.projectedLimitDate(now: now) == nil)
}

@Test func nilTooEarlyInWindow() {
    let now = Date()
    let session = metric(used: 10, elapsed: 5 * 60, duration: 5 * hour, now: now)
    #expect(session.projectedLimitDate(now: now) == nil)
    let weekly = metric(used: 5, elapsed: 2 * hour, duration: 7 * 24 * hour, now: now)
    #expect(weekly.projectedLimitDate(now: now) == nil)
}

@Test func nilAtZeroAndFull() {
    let now = Date()
    #expect(metric(used: 0, elapsed: hour, duration: 5 * hour, now: now).projectedLimitDate(now: now) == nil)
    #expect(metric(used: 100, elapsed: hour, duration: 5 * hour, now: now).projectedLimitDate(now: now) == nil)
}

@Test func nilWithoutPeriodData() {
    let now = Date()
    let noPeriod = UsageMetric(label: "x", usedPercent: 50, format: .percent)
    #expect(noPeriod.windowStart() == nil)
    #expect(noPeriod.paceFraction(now: now) == nil)
    #expect(noPeriod.projectedLimitDate(now: now) == nil)

    let noDuration = UsageMetric(
        label: "x", usedPercent: 50, format: .percent,
        period: UsagePeriod(label: "w", resetsAt: now.addingTimeInterval(hour))
    )
    #expect(noDuration.windowStart() == nil)
    #expect(noDuration.paceFraction(now: now) == nil)
    #expect(noDuration.projectedLimitDate(now: now) == nil)
}

@Test func paceClampsOutsideWindow() {
    let now = Date()
    // Reset already passed (stale data)
    let stale = metric(used: 40, elapsed: 6 * hour, duration: 5 * hour, now: now)
    #expect(stale.paceFraction(now: now) == 1)
    #expect(stale.projectedLimitDate(now: now) == nil)
    // Window start in the future (clock skew)
    let future = metric(used: 40, elapsed: -hour, duration: 5 * hour, now: now)
    #expect(future.paceFraction(now: now) == 0)
    #expect(future.projectedLimitDate(now: now) == nil)
}
