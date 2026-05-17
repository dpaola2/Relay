//
//  LaunchTimePrune.swift
//  Relay
//
//  RELAY-5 (M10 / EDG-010) — launch-time prune of stale `ProposedShift` rows.
//
//  Called once from `RelayApp.init()` after the `ModelContainer` is built. The
//  cutoff matches ADR-003's 7-day retention policy: anything with `planDay`
//  strictly older than `today - 6 days` is removed, which keeps today plus the
//  previous 6 days (7 calendar days total) — same window the Edit screen lists.
//
//  Implementation note: SwiftData prune via `store.prune(olderThan:)` uses
//  strict `<` semantics. Computing the cutoff as `startOfDay(today) - 6 days`
//  produces a midnight-anchored Date so a row created at any time on
//  `today - 7 days` (which has the same `planDay = startOfDay`) compares
//  `<` the cutoff and is pruned, while every row from `today - 6 days` onward
//  is preserved.
//
//  Extracted into a pure helper so the cutoff math is unit-testable without
//  driving `RelayApp` from a test (which would require a full app launch).
//

import Foundation

/// Pure helper that runs the M10 launch-time prune of stale `ProposedShift`
/// rows. Errors from the store are swallowed and logged at debug level so a
/// transient SwiftData failure cannot block app launch.
enum LaunchTimePrune {

    /// Number of calendar days of `ProposedShift` history to retain. Matches
    /// ADR-003's `SleepSession` Edit-screen window so the two domains stay
    /// aligned.
    static let retentionDays = 7

    /// Computes the strict-`<` cutoff for `store.prune(olderThan:)`. Anchored
    /// to `startOfDay(now)` so today's rows (and today-relative `planDay`
    /// values) are preserved.
    static func cutoff(now: Date, calendar: Calendar) -> Date {
        let startOfToday = calendar.startOfDay(for: now)
        let daysBack = -(retentionDays - 1)
        return calendar.date(byAdding: .day, value: daysBack, to: startOfToday) ?? startOfToday
    }

    /// Runs the prune. Safe to call once per app launch.
    static func run(store: any ProposedShiftStore, now: Date = .now, calendar: Calendar = .current) {
        let cutoffDate = cutoff(now: now, calendar: calendar)
        do {
            try store.prune(olderThan: cutoffDate)
        } catch {
            // Swallow — a failed prune is a non-fatal hygiene operation. The
            // next launch will retry, and the data set is small enough
            // (≤16 rows/day × 7 days = ≤112 rows) that an unpruned tail does
            // not affect correctness.
            #if DEBUG
            print("LaunchTimePrune: prune failed — \(error)")
            #endif
        }
    }
}
