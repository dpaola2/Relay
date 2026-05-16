//
//  QASeed.swift
//  Relay
//
//  Debug-only seed mechanism that populates the SwiftData store with realistic
//  test data covering every QA scenario from gameplan §M5 / QA-seed-3:
//
//    • Happy path     — 2 Dave + 2 Bethany closed sessions in the last 72h
//    • Concurrent     — one open Dave + one open Bethany (per ADR-001)
//    • Open session   — guaranteed by the concurrent pair above
//    • 7-day boundary — a ~6-day-old session (inside Edit window) and a
//                       ~8-day-old session (outside Edit window) per ADR-003
//    • Short          — a <5-minute session for duration rendering
//    • Long           — a >10-hour session for duration rendering
//    • Note           — at least one session has a populated `note` field
//
//  Wrapped in `#if DEBUG` so neither the helper nor its call sites compile
//  into Release builds (gameplan QA-seed-2). The `AppShellView` toolbar that
//  invokes this is also `#if DEBUG`-gated.
//
//  Idempotency (QA-seed-4): `seed()` calls `wipe()` first, so running it
//  twice yields the same row count. `wipe()` is the implementation primitive
//  for both the idempotency contract and the "Wipe all data" debug action
//  (QA-seed-7).
//

#if DEBUG
import Foundation

/// Debug seeder for the `SleepSessionStore`. Pure helper — no UI, no state.
/// Construct once and call `seed(store:clock:)` or `wipe(store:)`.
struct QASeed {

    init() {}

    // MARK: - Public API

    /// Wipe-then-seed the store with the full QA fixture set. Idempotent:
    /// calling this twice produces the same row count and the same scenarios.
    /// Prints a one-shot summary to the Xcode console (QA-seed-5).
    func seed(store: SleepSessionStore, clock: any Clock) throws {
        try wipe(store: store)

        let now = clock.now
        var scenarios: [String] = []
        var created: [SleepSession] = []

        for plan in scenarioPlans(now: now) {
            let session = try store.startSession(for: plan.who, at: plan.startedAt)
            try store.update(
                session,
                startedAt: nil,
                endedAt: plan.endedAt.map { .some($0) },
                who: nil,
                note: plan.note.map { .some($0) }
            )
            scenarios.append(plan.scenario)
            created.append(session)
        }

        printSummary(created: created, scenarios: scenarios, now: now)
    }

    /// Delete every `SleepSession` from the store. Powers both the "Wipe all
    /// data" debug action (QA-seed-7) and `seed()`'s idempotency contract.
    func wipe(store: SleepSessionStore) throws {
        let everything = try store.sessions(in: Date.distantPast...Date.distantFuture)
        for session in everything {
            try store.delete(session)
        }
    }

    // MARK: - Scenario plan

    /// One row's worth of seed plan. Pure data — no SwiftData coupling.
    private struct ScenarioPlan {
        let scenario: String
        let who: Person
        let startedAt: Date
        let endedAt: Date?
        let note: String?
    }

    /// The canonical scenario set. Anchored to `now` so the seed works for any
    /// `clock.now` — production (SystemClock) or tests (FakeClock).
    private func scenarioPlans(now: Date) -> [ScenarioPlan] {
        let hour: TimeInterval = 3_600
        let day: TimeInterval = 24 * hour

        return [
            // --- Happy path: 2 Dave + 2 Bethany closed sessions in last 72h ---
            ScenarioPlan(
                scenario: "happy-path/dave-night-3",
                who: .dave,
                startedAt: now.addingTimeInterval(-66 * hour),
                endedAt: now.addingTimeInterval(-60 * hour),
                note: nil
            ),
            ScenarioPlan(
                scenario: "happy-path/bethany-night-3",
                who: .bethany,
                startedAt: now.addingTimeInterval(-60 * hour),
                endedAt: now.addingTimeInterval(-56 * hour),
                note: "First long stretch since Jo arrived."
            ),
            ScenarioPlan(
                scenario: "happy-path/dave-long-night-2",
                who: .dave,
                startedAt: now.addingTimeInterval(-42 * hour),
                endedAt: now.addingTimeInterval(-30 * hour - 30 * 60),
                note: nil
            ),
            ScenarioPlan(
                scenario: "happy-path/bethany-night-1",
                who: .bethany,
                startedAt: now.addingTimeInterval(-18 * hour),
                endedAt: now.addingTimeInterval(-13 * hour),
                note: nil
            ),

            // --- Short session (<5 min) for duration rendering ---
            ScenarioPlan(
                scenario: "duration/short-nap-dave",
                who: .dave,
                startedAt: now.addingTimeInterval(-24 * hour),
                endedAt: now.addingTimeInterval(-24 * hour + 3 * 60),
                note: "Cat-nap interrupted by Jo."
            ),

            // --- 7-day window boundary: ~6 days old (inside Edit window) ---
            ScenarioPlan(
                scenario: "window/inside-7d-bethany-6-days-old",
                who: .bethany,
                startedAt: now.addingTimeInterval(-6 * day - 2 * hour),
                endedAt: now.addingTimeInterval(-6 * day + 4 * hour),
                note: nil
            ),

            // --- 7-day window boundary: ~8 days old (outside Edit window) ---
            ScenarioPlan(
                scenario: "window/outside-7d-dave-8-days-old",
                who: .dave,
                startedAt: now.addingTimeInterval(-8 * day - 1 * hour),
                endedAt: now.addingTimeInterval(-8 * day + 5 * hour),
                note: nil
            ),

            // --- Concurrent open pair (ADR-001): both currently open ---
            ScenarioPlan(
                scenario: "concurrent-open/dave-open-now",
                who: .dave,
                startedAt: now.addingTimeInterval(-45 * 60),
                endedAt: nil,
                note: nil
            ),
            ScenarioPlan(
                scenario: "concurrent-open/bethany-open-now",
                who: .bethany,
                startedAt: now.addingTimeInterval(-20 * 60),
                endedAt: nil,
                note: nil
            ),
        ]
    }

    // MARK: - Console summary

    private func printSummary(
        created: [SleepSession],
        scenarios: [String],
        now: Date
    ) {
        let openSessions = created.filter { $0.isOpen }
        let openDescriptions = openSessions
            .map { "\($0.who.displayName) since \($0.startedAt)" }
            .joined(separator: ", ")

        print("[QASeed] Seeded \(created.count) sessions at clock.now=\(now).")
        print("[QASeed] Scenarios: \(scenarios.joined(separator: ", ")).")
        if openSessions.isEmpty {
            print("[QASeed] Open sessions: none.")
        } else {
            print("[QASeed] Open sessions: \(openDescriptions).")
        }
    }
}
#endif
