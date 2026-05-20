//
//  QASeedTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M5: QA Test Data)
//
//  Covers gameplan acceptance criteria:
//    - QA-seed-1: A seedable helper exists at `Relay/Support/QASeed.swift`
//      with a `seed(store:clock:)` entry point.
//    - QA-seed-3: Seed creates a multi-scenario fixture set (happy path,
//      concurrent open, 7-day boundary, short/long, note populated).
//    - QA-seed-4: Idempotency — `seed()` twice does NOT duplicate rows.
//    - QA-seed-7: `wipe()` deletes all sessions.
//
//  The seeder is wrapped in `#if DEBUG` per QA-seed-2; this test file ALSO
//  wraps in `#if DEBUG` so the symbol is reachable from tests when the test
//  target is built with the Debug configuration (which is the only one we
//  ever run tests in).
//
//  Will FAIL until Stage 5 lands `Relay/Support/QASeed.swift`.
//

#if DEBUG
import XCTest
@testable import Relay

final class QASeedTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private var clock: FakeClock!
    private var seeder: QASeed!

    private let now = Date(timeIntervalSince1970: 1_779_278_400)
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

    // MARK: - QA-seed-3: scenario coverage

    func test_seed_createsHappyPath_2DaveAnd2BethanySessions() throws {
        try seeder.seed(store: store, clock: clock)

        let allSessions = try store.sessions(in: now.addingTimeInterval(-10 * day)...now.addingTimeInterval(day))
        let daveClosed = allSessions.filter { $0.who == .personA && !$0.isOpen }
        let bethanyClosed = allSessions.filter { $0.who == .personB && !$0.isOpen }

        XCTAssertGreaterThanOrEqual(daveClosed.count, 2, "Happy path: ≥2 closed Dave sessions in 72h")
        XCTAssertGreaterThanOrEqual(bethanyClosed.count, 2, "Happy path: ≥2 closed Bethany sessions in 72h")
    }

    func test_seed_createsAtLeastOneOpenSession_forActiveBannerExercise() throws {
        try seeder.seed(store: store, clock: clock)

        let openSessions = try store.allOpenSessions()
        XCTAssertGreaterThanOrEqual(openSessions.count, 1, "Need at least one open session for banner QA")
    }

    func test_seed_createsSessionInsideAndOutside7DayWindow() throws {
        try seeder.seed(store: store, clock: clock)

        let allSessions = store.allRowsForTesting

        let inside6Days = allSessions.contains { s in
            s.startedAt > now.addingTimeInterval(-7 * day)
                && s.startedAt < now.addingTimeInterval(-5 * day)
        }
        let outside8Days = allSessions.contains { s in
            s.startedAt < now.addingTimeInterval(-7 * day)
        }

        XCTAssertTrue(inside6Days, "Need a ~6-day-old session to exercise Edit's 7-day window")
        XCTAssertTrue(outside8Days, "Need an ~8-day-old session to exercise OUTSIDE the 7-day window")
    }

    func test_seed_createsShortAndLongSession_forDurationRendering() throws {
        try seeder.seed(store: store, clock: clock)

        let allClosed = store.allRowsForTesting.filter { !$0.isOpen }
        let hasShort = allClosed.contains { $0.duration(asOf: now) < 5 * 60 }
        let hasLong = allClosed.contains { $0.duration(asOf: now) > 10 * 3_600 }

        XCTAssertTrue(hasShort, "Need a <5min session for duration formatting")
        XCTAssertTrue(hasLong, "Need a >10h session for duration formatting")
    }

    func test_seed_createsSessionWithNote_forNoteFieldExercise() throws {
        try seeder.seed(store: store, clock: clock)

        let hasNote = store.allRowsForTesting.contains { ($0.note ?? "").isEmpty == false }
        XCTAssertTrue(hasNote, "Need at least one session with a populated `note`")
    }

    // MARK: - QA-seed-4: idempotency

    func test_seed_calledTwice_doesNotDuplicateRows() throws {
        try seeder.seed(store: store, clock: clock)
        let countAfterFirst = store.allRowsForTesting.count

        try seeder.seed(store: store, clock: clock)
        let countAfterSecond = store.allRowsForTesting.count

        XCTAssertEqual(
            countAfterFirst,
            countAfterSecond,
            "Idempotency: second seed must not duplicate"
        )
    }

    // MARK: - QA-seed-7: wipe deletes all sessions

    func test_wipe_deletesAllSessions() throws {
        try seeder.seed(store: store, clock: clock)
        XCTAssertFalse(store.allRowsForTesting.isEmpty)

        try seeder.wipe(store: store)

        XCTAssertTrue(store.allRowsForTesting.isEmpty)
    }
}
#endif
