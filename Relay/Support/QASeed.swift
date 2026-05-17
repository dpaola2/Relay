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
        try applyPlans(scenarioPlans(now: clock.now), to: store, now: clock.now)
    }

    /// Wipe-then-seed the store with the Backfill (RELAY-2 / M3) fixture set.
    /// Exercises the v1.1 Backfill UX surface: outside-7d rows (VAL-002),
    /// a within-24h Dave anchor (DEF-001 sticky), and per-person within-7d
    /// coverage for Totals. Same idempotency contract as `seed(store:clock:)`.
    func seedBackfillCoverage(store: SleepSessionStore, clock: any Clock) throws {
        try wipe(store: store)
        try applyPlans(backfillCoveragePlans(now: clock.now), to: store, now: clock.now)
    }

    // MARK: - Plan application

    /// Walk a plan list and write each row via the canonical two-call path
    /// (`startSession` + `update(endedAt:..., note:...)`). Prints a one-shot
    /// summary so the Xcode console shows what landed.
    private func applyPlans(
        _ plans: [ScenarioPlan],
        to store: SleepSessionStore,
        now: Date
    ) throws {
        var scenarios: [String] = []
        var created: [SleepSession] = []

        for plan in plans {
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

    /// Backfill (RELAY-2 / M3) plan set. Tighter and more focused than the
    /// canonical `seed` — covers exactly the surfaces the Backfill sheet
    /// touches: VAL-002 (outside-7d rows), DEF-001 sticky-Who anchor, and
    /// Totals reach (≥2 within-7d rows per person).
    private func backfillCoveragePlans(now: Date) -> [ScenarioPlan] {
        let hour: TimeInterval = 3_600
        let day: TimeInterval = 24 * hour

        return [
            // --- VAL-002 reach: two rows OLDER than 7d (must NOT show in Edit) ---
            ScenarioPlan(
                scenario: "backfill/outside-7d-dave-9-days-old",
                who: .dave,
                startedAt: now.addingTimeInterval(-9 * day),
                endedAt: now.addingTimeInterval(-9 * day + 6 * hour),
                note: nil
            ),
            ScenarioPlan(
                scenario: "backfill/outside-7d-bethany-10-days-old",
                who: .bethany,
                startedAt: now.addingTimeInterval(-10 * day),
                endedAt: now.addingTimeInterval(-10 * day + 5 * hour),
                note: nil
            ),

            // --- Totals reach: ≥2 within-7d per person ---
            ScenarioPlan(
                scenario: "backfill/within-7d-dave-6-days-old",
                who: .dave,
                startedAt: now.addingTimeInterval(-6 * day),
                endedAt: now.addingTimeInterval(-6 * day + 7 * hour),
                note: nil
            ),
            ScenarioPlan(
                scenario: "backfill/within-7d-bethany-6-days-old",
                who: .bethany,
                startedAt: now.addingTimeInterval(-6 * day + hour),
                endedAt: now.addingTimeInterval(-6 * day + 7 * hour),
                note: nil
            ),
            ScenarioPlan(
                scenario: "backfill/within-7d-dave-3-days-old",
                who: .dave,
                startedAt: now.addingTimeInterval(-3 * day),
                endedAt: now.addingTimeInterval(-3 * day + 7 * hour),
                note: "Long stretch — Jo slept through."
            ),
            ScenarioPlan(
                scenario: "backfill/within-7d-bethany-3-days-old",
                who: .bethany,
                startedAt: now.addingTimeInterval(-3 * day + 30 * 60),
                endedAt: now.addingTimeInterval(-3 * day + 5 * hour),
                note: nil
            ),

            // --- 24h-to-7d band: a Bethany row JUST outside the sticky window
            //     (between 24h and 48h) so the within-24h selector still picks
            //     the Dave anchor below. ---
            ScenarioPlan(
                scenario: "backfill/within-7d-bethany-36-hours-old",
                who: .bethany,
                startedAt: now.addingTimeInterval(-36 * hour),
                endedAt: now.addingTimeInterval(-28 * hour),
                note: nil
            ),

            // --- DEF-001 sticky anchor: latest-startedAt within 24h is Dave ---
            ScenarioPlan(
                scenario: "backfill/within-24h-dave-sticky-anchor",
                who: .dave,
                startedAt: now.addingTimeInterval(-3 * hour),
                endedAt: now.addingTimeInterval(-1 * hour),
                note: "Pre-dawn shift — sticky-Who anchor."
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
