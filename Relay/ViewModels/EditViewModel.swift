//
//  EditViewModel.swift
//  Relay
//
//  The Edit-screen view model — a 7-day window over `SleepSession` (per
//  ADR-003 / PRD Q7). The Timeline window is 72h; this window is wider so
//  the correction surface reaches back further than the visualization.
//
//  Predicate matches Arch §3.6 exactly — sessions are listed if their start
//  OR their effective end overlaps `[now - 7d, now]`. That means a session
//  that started 8 days ago but ended 6 days ago is INCLUDED, and a session
//  whose `endedAt` is exactly at the cutoff is INCLUDED (`>=`).
//
//  Per ADR-002 / CLAUDE.md §"Engineering Methodology" item 6 this is
//  `@Observable nonisolated final class`.
//

import Foundation
import Observation

@Observable
nonisolated final class EditViewModel {
    private let store: any SleepSessionStore
    private let clock: any Clock

    /// Sessions inside the 7-day window, sorted newest-first. Driven by
    /// `refresh()`. The view binds rows directly to `SleepSession` so the
    /// `who` / `startedAt` / `endedAt` / `duration(asOf:)` / `isOpen` surface
    /// from EDT-002 is exposed via the model itself.
    var sessions: [SleepSession] = []

    init(store: any SleepSessionStore, clock: any Clock = SystemClock()) {
        self.store = store
        self.clock = clock
    }

    // MARK: - Window

    var windowEnd: Date { clock.now }
    var windowStart: Date { windowEnd.addingTimeInterval(-7 * 24 * 3_600) }

    // MARK: - Refresh

    /// Re-read sessions whose start OR end overlaps the 7-day window (ADR-003).
    func refresh() {
        let cutoff = windowStart
        let upper = windowEnd
        // Fetch a generous range, then filter for the OR-predicate per Arch §3.6.
        let widerRange = cutoff.addingTimeInterval(-365 * 24 * 3_600)...upper
        let all = (try? store.sessions(in: widerRange)) ?? []
        sessions = all.filter { row in
            // Include if startedAt is inside the window …
            if row.startedAt >= cutoff && row.startedAt <= upper { return true }
            // … or if endedAt is inside the window (`>=` cutoff is inclusive)
            //   — for open sessions, `endedAt ?? .distantPast` keeps them
            //   considered via the startedAt branch above.
            let effectiveEnd = row.endedAt ?? .distantPast
            return effectiveEnd >= cutoff && effectiveEnd <= upper
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - Writes

    /// Persist edits to a session. Any non-nil argument applies; `nil` means
    /// "don't touch." `endedAt < startedAt` throws `SleepSessionStoreError`.
    /// Reassigning `who` (EDT-006) goes through the same path.
    func save(
        session: SleepSession,
        startedAt: Date?,
        endedAt: Date?,
        who: Person?
    ) throws {
        try store.update(
            session,
            startedAt: startedAt,
            endedAt: endedAt.map { .some($0) },
            who: who,
            note: nil
        )
    }

    /// Remove a session from the store (EDT-005).
    func delete(_ session: SleepSession) throws {
        try store.delete(session)
    }
}
