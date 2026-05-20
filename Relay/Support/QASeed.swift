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
    ///
    /// Pattern: typical week-1 newborn parents. Sleep is fragmented into 2–4h
    /// stretches, with handoffs around feeds. Per-parent 24h totals land in
    /// the 4–6h range — well under the 8h target the app uses as a baseline.
    /// Sessions are spread across three full nights + daytime catnaps so the
    /// Timeline and Totals tabs look populated but not improbable.
    private func scenarioPlans(now: Date) -> [ScenarioPlan] {
        let hour: TimeInterval = 3_600
        let day: TimeInterval = 24 * hour

        return [
            // ================================================================
            // Night 3 (~ -72h … -56h): three nights ago
            // ================================================================
            ScenarioPlan(
                scenario: "night-3/personA-early",
                who: .personA,
                startedAt: now.addingTimeInterval(-65 * hour),
                endedAt: now.addingTimeInterval(-62 * hour),
                note: nil
            ),
            ScenarioPlan(
                scenario: "night-3/personB-long-stretch",
                who: .personB,
                startedAt: now.addingTimeInterval(-62 * hour),
                endedAt: now.addingTimeInterval(-58 * hour),
                note: "First long stretch since Jo came home."
            ),

            // ================================================================
            // Day 3 (~ -52h): brief afternoon catnap
            // ================================================================
            ScenarioPlan(
                scenario: "day-3/personB-couch-nap",
                who: .personB,
                startedAt: now.addingTimeInterval(-52 * hour),
                endedAt: now.addingTimeInterval(-52 * hour + 30 * 60),
                note: nil
            ),

            // ================================================================
            // Night 2 (~ -48h … -32h): typical fragmented night
            // ================================================================
            ScenarioPlan(
                scenario: "night-2/personA-early",
                who: .personA,
                startedAt: now.addingTimeInterval(-45 * hour),
                endedAt: now.addingTimeInterval(-42 * hour - 30 * 60),
                note: nil
            ),
            ScenarioPlan(
                scenario: "night-2/personB-middle",
                who: .personB,
                startedAt: now.addingTimeInterval(-42 * hour),
                endedAt: now.addingTimeInterval(-39 * hour - 30 * 60),
                note: nil
            ),
            ScenarioPlan(
                scenario: "night-2/personA-dawn",
                who: .personA,
                startedAt: now.addingTimeInterval(-38 * hour),
                endedAt: now.addingTimeInterval(-35 * hour),
                note: "Back down after the 4am bottle."
            ),

            // ================================================================
            // Day 2 (~ -27h): one parent banks an afternoon block
            // ================================================================
            ScenarioPlan(
                scenario: "day-2/personB-afternoon-catchup",
                who: .personB,
                startedAt: now.addingTimeInterval(-27 * hour),
                endedAt: now.addingTimeInterval(-25 * hour),
                note: nil
            ),

            // ================================================================
            // Night 1 (~ -22h … -8h): last night
            //   Includes the <5min interrupted-catnap scenario (DURATION
            //   rendering test — exercises the "Xs" / sub-minute formatting).
            // ================================================================
            ScenarioPlan(
                scenario: "night-1/personA-evening",
                who: .personA,
                startedAt: now.addingTimeInterval(-22 * hour),
                endedAt: now.addingTimeInterval(-19 * hour),
                note: nil
            ),
            ScenarioPlan(
                scenario: "night-1/personB-middle",
                who: .personB,
                startedAt: now.addingTimeInterval(-19 * hour),
                endedAt: now.addingTimeInterval(-16 * hour - 30 * 60),
                note: nil
            ),
            ScenarioPlan(
                scenario: "night-1/personA-short-interrupted",
                who: .personA,
                startedAt: now.addingTimeInterval(-16 * hour),
                endedAt: now.addingTimeInterval(-16 * hour + 3 * 60),  // 3 minutes
                note: "Cat-nap — Jo woke up before I was down."
            ),
            ScenarioPlan(
                scenario: "night-1/personB-dawn",
                who: .personB,
                startedAt: now.addingTimeInterval(-15 * hour),
                endedAt: now.addingTimeInterval(-13 * hour),
                note: nil
            ),

            // ================================================================
            // Today (~ -10h … -9h): recovery nap after the dawn handoff
            // ================================================================
            ScenarioPlan(
                scenario: "today/personA-morning-recovery",
                who: .personA,
                startedAt: now.addingTimeInterval(-10 * hour),
                endedAt: now.addingTimeInterval(-9 * hour),
                note: nil
            ),

            // ================================================================
            // 7-day boundary (~ -6 days): inside the Edit window
            // ================================================================
            ScenarioPlan(
                scenario: "window/inside-7d-personB-6-days-old",
                who: .personB,
                startedAt: now.addingTimeInterval(-6 * day - hour),
                endedAt: now.addingTimeInterval(-6 * day + 2 * hour),  // 3h block
                note: nil
            ),

            // ================================================================
            // 7-day boundary (~ -8 days): OUTSIDE the Edit window.
            //   Doubles as the LONG-session test (>10h duration rendering) —
            //   narratively, the one night a grandparent took over so both
            //   parents got an unbroken sleep in the first week. This is the
            //   one realistic place an 11h block fits in newborn-period data.
            // ================================================================
            ScenarioPlan(
                scenario: "window/outside-7d-personA-8-days-old-long",
                who: .personA,
                startedAt: now.addingTimeInterval(-8 * day - 2 * hour),
                endedAt: now.addingTimeInterval(-8 * day + 9 * hour),  // 11h block
                note: "Mom stayed over — first full night since the hospital."
            ),

            // ================================================================
            // Concurrent open pair (ADR-001): both currently asleep.
            //   Realistic: both parents collapsed after the morning feed
            //   handoff. Open sessions exercise the active-session banner
            //   and the live duration ticker on the Now tab.
            // ================================================================
            ScenarioPlan(
                scenario: "concurrent-open/personA-open-now",
                who: .personA,
                startedAt: now.addingTimeInterval(-45 * 60),
                endedAt: nil,
                note: nil
            ),
            ScenarioPlan(
                scenario: "concurrent-open/personB-open-now",
                who: .personB,
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
    ///
    /// Durations match realistic newborn-parent patterns: 2–4h fragmented
    /// stretches, with one rare 6h block (narrated in the `note`) showing
    /// that the formatter handles the upper-realistic edge.
    private func backfillCoveragePlans(now: Date) -> [ScenarioPlan] {
        let hour: TimeInterval = 3_600
        let day: TimeInterval = 24 * hour

        return [
            // --- VAL-002 reach: two rows OLDER than 7d (must NOT show in Edit) ---
            ScenarioPlan(
                scenario: "backfill/outside-7d-personA-9-days-old",
                who: .personA,
                startedAt: now.addingTimeInterval(-9 * day),
                endedAt: now.addingTimeInterval(-9 * day + 3 * hour + 30 * 60),
                note: nil
            ),
            ScenarioPlan(
                scenario: "backfill/outside-7d-personB-10-days-old",
                who: .personB,
                startedAt: now.addingTimeInterval(-10 * day),
                endedAt: now.addingTimeInterval(-10 * day + 3 * hour),
                note: nil
            ),

            // --- Totals reach: ≥2 within-7d per person, realistic durations ---
            ScenarioPlan(
                scenario: "backfill/within-7d-personA-6-days-old",
                who: .personA,
                startedAt: now.addingTimeInterval(-6 * day),
                endedAt: now.addingTimeInterval(-6 * day + 3 * hour),
                note: nil
            ),
            ScenarioPlan(
                scenario: "backfill/within-7d-personB-6-days-old",
                who: .personB,
                startedAt: now.addingTimeInterval(-6 * day + 3 * hour),
                endedAt: now.addingTimeInterval(-6 * day + 6 * hour + 30 * 60),
                note: nil
            ),
            ScenarioPlan(
                scenario: "backfill/within-7d-personA-3-days-old-rare-long",
                who: .personA,
                startedAt: now.addingTimeInterval(-3 * day),
                endedAt: now.addingTimeInterval(-3 * day + 6 * hour),
                note: "Jo slept 6 straight — the only time so far."
            ),
            ScenarioPlan(
                scenario: "backfill/within-7d-personB-3-days-old",
                who: .personB,
                startedAt: now.addingTimeInterval(-3 * day + 30 * 60),
                endedAt: now.addingTimeInterval(-3 * day + 3 * hour),
                note: nil
            ),

            // --- 24h-to-7d band: a Bethany row JUST outside the sticky window
            //     (between 24h and 48h) so the within-24h selector still picks
            //     the Dave anchor below. ---
            ScenarioPlan(
                scenario: "backfill/within-7d-personB-36-hours-old",
                who: .personB,
                startedAt: now.addingTimeInterval(-36 * hour),
                endedAt: now.addingTimeInterval(-33 * hour),
                note: nil
            ),

            // --- DEF-001 sticky anchor: latest-startedAt within 24h is Dave ---
            ScenarioPlan(
                scenario: "backfill/within-24h-personA-sticky-anchor",
                who: .personA,
                startedAt: now.addingTimeInterval(-3 * hour),
                endedAt: now.addingTimeInterval(-1 * hour),
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
            .map { "\($0.whoRaw) since \($0.startedAt)" }
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
