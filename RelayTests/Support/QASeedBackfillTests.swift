//
//  QASeedBackfillTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (RELAY-2 / Milestone M3: QA Test Data for Backfill)
//
//  Covers gameplan acceptance criteria for the new `backfillCoverage` QA seed
//  scenario that exercises the v1.1 Backfill UX surface area:
//
//    - QA-backfill-1 — A `backfillCoverage` entry point exists on `QASeed`
//      that seeds the store with realistic recent sessions.
//    - QA-backfill-2 — Seed creates at least two sessions older than 7 days
//      (to confirm VAL-002 reach — they should NOT appear in the Edit list).
//    - QA-backfill-3 — Seed creates at least one within-24h session for
//      `.personA` (the DEF-001 sticky-Who anchor).
//    - QA-backfill-4 — Seed creates at least two within-7d sessions per person
//      so Totals has meaningful 24/48/72h numbers immediately.
//    - QA-backfill-5 — Idempotency: invoking the scenario twice produces the
//      same final store state (Relay's seed contract per QASeed).
//    - QA-backfill-6 — After seeding, `AddPastSleepViewModel.resolveDefaultWho`
//      (the underlying DEF-001 derivation) returns `.personA` — confirms the
//      sticky path is exercised by the seed.
//
//  Wrapped in `#if DEBUG` matching `QASeedTests.swift` and `QASeed.swift` —
//  the seeder is Debug-only.
//
//  Will FAIL until Stage 5 extends `Relay/Support/QASeed.swift` with the
//  `backfillCoverage` scenario (and corresponding `seedBackfillCoverage(...)`
//  or equivalent entry point).
//

#if DEBUG
import XCTest
@testable import Relay

final class QASeedBackfillTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private var clock: FakeClock!
    private var seeder: QASeed!

    private let now = Date(timeIntervalSince1970: 1_779_278_400)
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 24 * 3_600

    override func setUp() {
        super.setUp()
        store = InMemorySleepSessionStore()
        clock = FakeClock(now)
        seeder = QASeed()
    }

    override func tearDown() {
        seeder = nil
        clock = nil
        store = nil
        super.tearDown()
    }

    // ========================================================================
    // MARK: - QA-backfill-1 / QA-backfill-2: outside-7-day rows
    // ========================================================================

    /// QA-backfill-2: at least two sessions older than 7 days exist post-seed.
    /// These exercise VAL-002's reach in the Backfill sheet (they should NOT
    /// be addable through the sheet's 7-day window).
    func test_seedBackfillCoverage_createsAtLeastTwoSessionsOlderThan7Days() throws {
        try seeder.seedBackfillCoverage(store: store, clock: clock)

        let olderThan7Days = store.allRowsForTesting.filter { row in
            row.startedAt < now.addingTimeInterval(-7 * day)
        }
        XCTAssertGreaterThanOrEqual(
            olderThan7Days.count, 2,
            "QA-backfill-2: need ≥2 sessions older than 7 days"
        )
    }

    // ========================================================================
    // MARK: - QA-backfill-3: within-24h Dave anchor for sticky Who
    // ========================================================================

    /// QA-backfill-3: at least one within-24h session for Dave so the sticky
    /// Who derivation has a deterministic anchor.
    func test_seedBackfillCoverage_createsAtLeastOneWithin24hDaveSession() throws {
        try seeder.seedBackfillCoverage(store: store, clock: clock)

        let within24hDave = store.allRowsForTesting.filter { row in
            row.who == .personA && row.startedAt > now.addingTimeInterval(-24 * hour)
        }
        XCTAssertGreaterThanOrEqual(
            within24hDave.count, 1,
            "QA-backfill-3: need ≥1 within-24h Dave session as sticky-Who anchor"
        )
    }

    // ========================================================================
    // MARK: - QA-backfill-4: within-7-day Totals coverage per person
    // ========================================================================

    /// QA-backfill-4: at least two within-7-day sessions per person so Totals
    /// has meaningful 24/48/72h numbers post-seed.
    func test_seedBackfillCoverage_createsAtLeastTwoWithin7dSessionsPerPerson() throws {
        try seeder.seedBackfillCoverage(store: store, clock: clock)

        let cutoff = now.addingTimeInterval(-7 * day)
        let within7dDave = store.allRowsForTesting.filter {
            $0.who == .personA && $0.startedAt >= cutoff
        }
        let within7dBethany = store.allRowsForTesting.filter {
            $0.who == .personB && $0.startedAt >= cutoff
        }

        XCTAssertGreaterThanOrEqual(within7dDave.count, 2,
                                    "QA-backfill-4: need ≥2 within-7d Dave sessions for Totals coverage")
        XCTAssertGreaterThanOrEqual(within7dBethany.count, 2,
                                    "QA-backfill-4: need ≥2 within-7d Bethany sessions for Totals coverage")
    }

    // ========================================================================
    // MARK: - QA-backfill-5: idempotency
    // ========================================================================

    /// QA-backfill-5: invoking the scenario twice does not duplicate rows —
    /// same contract as the canonical `QASeed.seed()`.
    func test_seedBackfillCoverage_calledTwice_doesNotDuplicateRows() throws {
        try seeder.seedBackfillCoverage(store: store, clock: clock)
        let countAfterFirst = store.allRowsForTesting.count

        try seeder.seedBackfillCoverage(store: store, clock: clock)
        let countAfterSecond = store.allRowsForTesting.count

        XCTAssertEqual(
            countAfterFirst,
            countAfterSecond,
            "QA-backfill-5: second seed must not duplicate rows"
        )
    }

    /// QA-backfill-5: the post-state after two invocations is identical to
    /// the post-state after one — `who`/`startedAt`/`endedAt` triples match.
    func test_seedBackfillCoverage_idempotency_finalStateMatches() throws {
        try seeder.seedBackfillCoverage(store: store, clock: clock)
        let firstState = stateSignature(of: store.allRowsForTesting)

        try seeder.seedBackfillCoverage(store: store, clock: clock)
        let secondState = stateSignature(of: store.allRowsForTesting)

        XCTAssertEqual(firstState, secondState,
                       "QA-backfill-5: final store state must be identical across invocations")
    }

    // ========================================================================
    // MARK: - QA-backfill-6: sticky Who derivation lands on .personA
    // ========================================================================

    /// QA-backfill-6: after seeding, the DEF-001 derivation (used by
    /// `AddPastSleepViewModel` at sheet-open) resolves `Who` to `.personA`.
    /// We assert this by reading the latest-startedAt within-24h session
    /// directly — same selection rule `AddPastSleepViewModel` will use.
    func test_seedBackfillCoverage_stickyWhoDerivation_landsOnDave() throws {
        try seeder.seedBackfillCoverage(store: store, clock: clock)

        let dayAgo = now.addingTimeInterval(-24 * hour)
        let recent = try store.sessions(in: dayAgo...now)
        let latest = recent.max(by: { $0.startedAt < $1.startedAt })

        XCTAssertNotNil(latest, "Need ≥1 within-24h session for sticky-Who anchor")
        XCTAssertEqual(latest?.who, .personA, "QA-backfill-6: sticky-Who anchor must be Dave")
    }

    // MARK: - Helpers

    /// Order-independent state signature so idempotency comparisons aren't
    /// brittle to insertion order. `id` is excluded (UUIDs are new per row).
    private func stateSignature(of rows: [SleepSession]) -> [String] {
        rows
            .map { row in
                let endComponent = row.endedAt.map { "\($0.timeIntervalSince1970)" } ?? "nil"
                let noteComponent = row.note ?? "nil"
                return "\(row.who.rawValue)|\(row.startedAt.timeIntervalSince1970)|\(endComponent)|\(noteComponent)"
            }
            .sorted()
    }
}
#endif
