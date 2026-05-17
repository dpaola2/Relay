//
//  TotalsViewModel.swift
//  Relay
//
//  Per-person cumulative-sleep aggregation across configurable windows
//  (24h / 48h / 72h). Open sessions count their elapsed-so-far portion
//  (TOT-003). Sessions whose interval straddles the window are clipped to
//  the window for accurate totals.
//
//  Also exposes the M6 sleep-debt derivation (TOT-004, Nice, conditional);
//  the implementation lives here so the test suite can reach it from M4
//  without waiting on M6 view-layer work.
//
//  Per ADR-002 / CLAUDE.md §"Engineering Methodology" item 6 this is
//  `@Observable nonisolated final class`.
//

import Foundation
import Observation

@Observable
nonisolated final class TotalsViewModel {
    private let store: any SleepSessionStore
    private let clock: any Clock

    /// All sessions that overlap the widest window we care about (72h). Driven
    /// by `refresh()`. We over-fetch once and aggregate in memory so 24/48/72h
    /// totals share a single store read.
    private var recentSessions: [SleepSession] = []

    init(store: any SleepSessionStore, clock: any Clock = SystemClock()) {
        self.store = store
        self.clock = clock
    }

    // MARK: - Refresh

    /// Re-read the last 72h of sessions from the store. View calls this on
    /// appear.
    func refresh() {
        let now = clock.now
        let range = now.addingTimeInterval(-72 * 3_600)...now
        recentSessions = (try? store.sessions(in: range)) ?? []
    }

    // MARK: - Totals

    /// Cumulative sleep for `person` over `window` seconds before `clock.now`.
    /// Sessions are clipped to the window. Open sessions count up to `clock.now`.
    func total(for person: Person, over window: TimeInterval) -> TimeInterval {
        let now = clock.now
        let windowStart = now.addingTimeInterval(-window)
        var total: TimeInterval = 0
        for session in recentSessions where session.who == person {
            total += overlap(of: session, with: windowStart...now)
        }
        return max(0, total)
    }

    // MARK: - Sleep debt (M6 TOT-004, conditional)

    /// Target hours - actual sleep, floored at zero. Scales the target from
    /// the 24h baseline to the requested window so callers can pass arbitrary
    /// windows without changing the target semantics.
    func sleepDebt(
        for person: Person,
        targetHoursPer24h: Double,
        window: TimeInterval
    ) -> TimeInterval {
        let scaledTarget = (targetHoursPer24h * 3_600) * (window / (24 * 3_600))
        let actual = total(for: person, over: window)
        return max(0, scaledTarget - actual)
    }

    // MARK: - Private

    /// Length of the intersection of `session`'s [startedAt, effectiveEnd]
    /// interval with `window`. Open sessions use `clock.now` as their end.
    /// A reference end earlier than start yields zero (clock-rewind safety).
    private func overlap(
        of session: SleepSession,
        with window: ClosedRange<Date>
    ) -> TimeInterval {
        let effectiveEnd = session.endedAt ?? clock.now
        let safeEnd = max(effectiveEnd, session.startedAt)
        let lower = max(session.startedAt, window.lowerBound)
        let upper = min(safeEnd, window.upperBound)
        guard lower < upper else { return 0 }
        return upper.timeIntervalSince(lower)
    }
}
