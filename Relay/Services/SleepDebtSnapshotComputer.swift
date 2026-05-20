//
//  SleepDebtSnapshotComputer.swift
//  Relay
//
//  RELAY-9 — Pure computation between the widget's `TimelineProvider`
//  and the model. Given a store + reference date, returns the two
//  balances the widget displays. Lives in the main app target with
//  shared file membership in `RelayWidgetExtension` (see the target
//  membership in Xcode — the file-system synchronized group includes
//  it automatically if added to `Relay/` AND the widget reads from
//  here via a shared SwiftData container — see `RELAY-9` plan).
//
//  No widget here: this file imports only Foundation so it stays
//  testable with the existing `InMemorySleepSessionStore`.
//

import Foundation

struct SleepDebtSnapshot: Sendable, Equatable {
    /// Reference date the balances were computed for.
    let date: Date

    /// Signed `actual − target` in seconds. Nil ⇒ store is empty
    /// (fresh install before backfill) — render the em-dash placeholder.
    let personABalance: TimeInterval?
    let personBBalance: TimeInterval?
}

enum SleepDebtSnapshotComputer {

    /// Default sleep target — matches `SleepDebtBadge`'s default.
    static let defaultTargetHoursPer24h: Double = 8.0
    static let defaultWindow: TimeInterval = 24 * 3_600
    /// Widest scan window — matches `TotalsViewModel`'s 72h horizon.
    static let scanWindow: TimeInterval = 72 * 3_600

    /// Convenience overload that reads sessions from a store, then defers
    /// to `snapshot(sessions:at:...)`. Used by the app target (where the
    /// `SleepSessionStore` protocol is in scope) and tests.
    static func snapshot(
        from store: any SleepSessionStore,
        at now: Date,
        targetHoursPer24h: Double = defaultTargetHoursPer24h,
        window: TimeInterval = defaultWindow
    ) -> SleepDebtSnapshot {
        let scanLower = now.addingTimeInterval(-scanWindow)
        let sessions = (try? store.sessions(in: scanLower...now)) ?? []
        return snapshot(
            sessions: sessions,
            at: now,
            targetHoursPer24h: targetHoursPer24h,
            window: window
        )
    }

    /// Primary entry point — works on an in-memory snapshot of sessions.
    /// Lets the widget extension call this without depending on the
    /// `SleepSessionStore` protocol.
    static func snapshot(
        sessions: [SleepSession],
        at now: Date,
        targetHoursPer24h: Double = defaultTargetHoursPer24h,
        window: TimeInterval = defaultWindow
    ) -> SleepDebtSnapshot {
        guard !sessions.isEmpty else {
            return SleepDebtSnapshot(date: now, personABalance: nil, personBBalance: nil)
        }
        return SleepDebtSnapshot(
            date: now,
            personABalance: balance(for: .personA, sessions: sessions, now: now,
                                 targetHoursPer24h: targetHoursPer24h, window: window),
            personBBalance: balance(for: .personB, sessions: sessions, now: now,
                                    targetHoursPer24h: targetHoursPer24h, window: window)
        )
    }

    // MARK: - Per-person signed balance

    private static func balance(
        for person: Person,
        sessions: [SleepSession],
        now: Date,
        targetHoursPer24h: Double,
        window: TimeInterval
    ) -> TimeInterval {
        let scaledTarget = (targetHoursPer24h * 3_600) * (window / (24 * 3_600))
        let windowStart = now.addingTimeInterval(-window)
        var actual: TimeInterval = 0
        for session in sessions where session.who == person {
            actual += overlap(session: session, with: windowStart...now)
        }
        return actual - scaledTarget
    }

    private static func overlap(
        session: SleepSession,
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
