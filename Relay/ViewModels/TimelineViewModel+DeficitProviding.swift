//
//  TimelineViewModel+DeficitProviding.swift
//  Relay
//
//  Architecture §6.5 — `TimelineViewModel` is the lone view-model the Forecast
//  feature already keeps live on the Timeline tab (RELAY-4 caches the last 7
//  days of sessions in `sessions`). Conforming it to `DeficitProviding` lets
//  `ForecastViewModel` reuse the same in-memory aggregate instead of standing
//  up a parallel `TotalsViewModel` instance on the Timeline tab.
//
//  Semantics mirror `TotalsViewModel.sleepDebt(...)`: clip each cached
//  `SleepSession` to the trailing 24h window ending at `asOf`, sum the
//  overlaps per person, and return `max(0, target − actual)` in seconds.
//

import Foundation

extension TimelineViewModel: DeficitProviding {
    /// 24-hour sleep deficit (target − actual) in seconds, clamped to >= 0.
    /// Reads `sessions` (cached by `refresh()`); a stale cache simply yields a
    /// slightly stale deficit — `ForecastViewModel` refreshes us on every plan
    /// rebuild via `.sleepSessionsDidChange`.
    func deficit24h(
        for person: Person,
        targetHoursPer24h: Double,
        asOf: Date
    ) -> TimeInterval {
        let window: TimeInterval = 24 * 3_600
        let windowStart = asOf.addingTimeInterval(-window)
        var actual: TimeInterval = 0
        for session in sessions where session.who == person {
            actual += overlap(of: session, with: windowStart...asOf)
        }
        let target = targetHoursPer24h * 3_600
        return max(0, target - actual)
    }

    /// Length of the intersection of `session`'s [startedAt, effectiveEnd]
    /// interval with `window`. Open sessions clip at `window.upperBound`
    /// (the supplied `asOf`), matching `TotalsViewModel.overlap(...)`.
    private func overlap(
        of session: SleepSession,
        with window: ClosedRange<Date>
    ) -> TimeInterval {
        let effectiveEnd = session.endedAt ?? window.upperBound
        let safeEnd = max(effectiveEnd, session.startedAt)
        let lower = max(session.startedAt, window.lowerBound)
        let upper = min(safeEnd, window.upperBound)
        guard lower < upper else { return 0 }
        return upper.timeIntervalSince(lower)
    }
}
