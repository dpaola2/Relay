//
//  NowViewModelTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M3: Now Screen — Logging State Machine + UI)
//
//  Covers gameplan acceptance criteria:
//    - NOW-004 / NOW-005 — happy-path "tap sleeping" creates an open session.
//    - NOW-004-noop (ADR-001 / PRD Q5) — re-tap same person is a no-op.
//    - NOW-005-concurrent (ADR-001 / PRD Q6) — tapping other parent allows both
//      sessions open simultaneously.
//    - NOW-006 — "On duty" closes ALL open sessions; no-op when none open.
//    - NOW-007 — view model exposes active session(s) for the banner.
//    - Edge case (PRD §8) — open session persists across app kill (verified by
//      M2 store tests; here we verify the view-model refresh-on-appear path).
//
//  All tests use an `InMemorySleepSessionStore` (Mocks/) and a `FakeClock` for
//  determinism. Tests will FAIL until Stage 5 lands `NowViewModel`.
//

import XCTest
@testable import Relay

final class NowViewModelTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private var clock: FakeClock!
    private var sut: NowViewModel!

    private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    override func setUp() {
        super.setUp()
        store = InMemorySleepSessionStore()
        clock = FakeClock(t0)
        sut = NowViewModel(store: store, clock: clock)
    }

    override func tearDown() {
        sut = nil
        clock = nil
        store = nil
        super.tearDown()
    }

    // MARK: - NOW-004: tap "I'm sleeping" (Dave) with no open session

    func test_tapISleeping_withNoneOpen_createsOpenDaveSession() throws {
        try sut.tapISleeping()

        let openForDave = try store.openSession(for: .dave)
        XCTAssertNotNil(openForDave)
        XCTAssertEqual(openForDave?.who, .dave)
        XCTAssertEqual(openForDave?.startedAt, t0)
        XCTAssertNil(openForDave?.endedAt)
    }

    // MARK: - NOW-004-noop (ADR-001 / PRD Q5): re-tap same person is idempotent

    func test_tapISleeping_withDaveAlreadyOpen_isNoOp() throws {
        try sut.tapISleeping()
        let openBefore = try store.openSession(for: .dave)
        let startBefore = openBefore?.startedAt
        XCTAssertEqual(store.startCallCount, 1)

        clock.advance(by: 120)
        try sut.tapISleeping() // second tap — should do nothing

        XCTAssertEqual(store.startCallCount, 1, "Second tapISleeping should NOT create a new session (ADR-001 Q5)")

        let openAfter = try store.openSession(for: .dave)
        XCTAssertEqual(openAfter?.id, openBefore?.id, "Same session, not replaced")
        XCTAssertEqual(openAfter?.startedAt, startBefore, "startedAt is unchanged (no truncation)")
    }

    // MARK: - NOW-005: tap "Bethany sleeping" with no open session

    func test_tapBethanySleeping_withNoneOpen_createsOpenBethanySession() throws {
        try sut.tapBethanySleeping()

        let openForBethany = try store.openSession(for: .bethany)
        XCTAssertNotNil(openForBethany)
        XCTAssertEqual(openForBethany?.who, .bethany)
        XCTAssertEqual(openForBethany?.startedAt, t0)
    }

    // MARK: - NOW-005-concurrent (ADR-001 / PRD Q6): per-person concurrency

    func test_tapBethanySleeping_whileDaveIsOpen_keepsBothOpen() throws {
        try sut.tapISleeping()
        clock.advance(by: 60)
        try sut.tapBethanySleeping()

        let allOpen = try store.allOpenSessions()
        XCTAssertEqual(allOpen.count, 2, "Per-person concurrency (ADR-001): both can be open")
        XCTAssertTrue(allOpen.contains { $0.who == .dave })
        XCTAssertTrue(allOpen.contains { $0.who == .bethany })

        // Dave's session must NOT have been silently truncated.
        let dave = allOpen.first { $0.who == .dave }
        XCTAssertNil(dave?.endedAt, "Dave's session stays open when Bethany taps")
    }

    func test_tapBethanySleeping_withBethanyAlreadyOpen_isNoOp() throws {
        try sut.tapBethanySleeping()
        XCTAssertEqual(store.startCallCount, 1)

        clock.advance(by: 30)
        try sut.tapBethanySleeping()

        XCTAssertEqual(store.startCallCount, 1, "Idempotency guard applies to Bethany too (ADR-001 Q5 generalized)")
    }

    // MARK: - NOW-006: "On duty" closes all open sessions

    func test_tapOnDuty_withNoOpenSessions_isNoOp() throws {
        XCTAssertNoThrow(try sut.tapOnDuty())

        let open = try store.allOpenSessions()
        XCTAssertTrue(open.isEmpty)
        XCTAssertEqual(store.endCallCount, 0, "No session means no endSession call")
    }

    func test_tapOnDuty_withOneOpenSession_closesIt() throws {
        try sut.tapISleeping()
        clock.advance(by: 3_600) // 1h
        try sut.tapOnDuty()

        XCTAssertTrue(try store.allOpenSessions().isEmpty)

        let allInWindow = try store.sessions(in: t0...clock.now)
        XCTAssertEqual(allInWindow.count, 1)
        XCTAssertEqual(allInWindow.first?.endedAt, clock.now)
    }

    func test_tapOnDuty_withBothOpenSessions_closesBothAtSameClockNow() throws {
        try sut.tapISleeping()
        clock.advance(by: 30)
        try sut.tapBethanySleeping()
        clock.advance(by: 1_800)
        let endMoment = clock.now

        try sut.tapOnDuty()

        let openAfter = try store.allOpenSessions()
        XCTAssertTrue(openAfter.isEmpty)

        let all = try store.sessions(in: t0...endMoment)
        XCTAssertEqual(all.count, 2)
        for s in all {
            XCTAssertEqual(s.endedAt, endMoment, "Both sessions close at the same `clock.now`")
        }
    }

    // MARK: - NOW-007: active sessions exposed for banner

    func test_activeSessions_reflectsCurrentlyOpenSessions_afterRefresh() throws {
        try sut.tapISleeping()
        sut.refresh()
        XCTAssertEqual(sut.activeSessions.count, 1)
        XCTAssertEqual(sut.activeSessions.first?.who, .dave)

        clock.advance(by: 60)
        try sut.tapBethanySleeping()
        sut.refresh()
        XCTAssertEqual(sut.activeSessions.count, 2)

        try sut.tapOnDuty()
        sut.refresh()
        XCTAssertEqual(sut.activeSessions.count, 0)
    }

    // MARK: - Edge case (PRD §8): persistence across app kill

    /// Simulates relaunch by constructing a fresh `NowViewModel` over a store
    /// that already contains an open session. Active session must surface on
    /// the first refresh.
    func test_initialRefresh_seesOpenSession_fromPreviousLaunch() throws {
        // Seed an open Dave session as if a prior launch wrote it.
        _ = try store.startSession(for: .dave, at: t0)

        let freshClock = FakeClock(t0.addingTimeInterval(1_200))
        let freshVM = NowViewModel(store: store, clock: freshClock)
        freshVM.refresh()

        XCTAssertEqual(freshVM.activeSessions.count, 1)
        XCTAssertEqual(freshVM.activeSessions.first?.who, .dave)
    }
}
