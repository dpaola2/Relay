//
//  EmptyStateAndEdgeTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M6: Empty States, Edge Cases & Polish)
//
//  Covers gameplan acceptance criteria that aren't naturally homed in a single
//  view-model test file:
//    - EMPTY-now: idle state (no active sessions) renders cleanly.
//    - EMPTY-timeline: empty 72h band is not an error (also covered in
//      TimelineViewModelTests; this is a deliberate cross-check at the M6 layer).
//    - EMPTY-totals: zero data => `0h 0m`.
//    - EMPTY-edit: zero sessions in 7-day window => empty-state shape.
//    - Relaunch-after-72h: Timeline only shows last 72h; Edit still shows older
//      sessions inside its 7-day window.
//
//  Will FAIL until Stage 5 lands the four view models.
//

import XCTest
@testable import Relay

final class EmptyStateAndEdgeTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private var clock: FakeClock!

    private let now = Date(timeIntervalSince1970: 1_779_278_400)
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 24 * 3_600

    override func setUp() {
        super.setUp()
        store = InMemorySleepSessionStore()
        clock = FakeClock(now)
    }

    override func tearDown() {
        clock = nil
        store = nil
        super.tearDown()
    }

    // MARK: - EMPTY-now

    func test_nowViewModel_idleState_hasNoActiveSessions() {
        let sut = NowViewModel(store: store, clock: clock)
        sut.refresh()

        XCTAssertTrue(sut.activeSessions.isEmpty, "Idle Now-screen state: no active sessions")
    }

    // MARK: - EMPTY-timeline (also asserted in TimelineDayViewModelTests)

    func test_timelineViewModel_emptyDay_returnsEmptySlices() {
        let sut = TimelineViewModel(store: store, clock: clock)
        sut.refresh()

        let slices = sut.slices(for: sut.today)
        XCTAssertTrue(slices.personA.isEmpty)
        XCTAssertTrue(slices.personB.isEmpty)
    }

    // MARK: - EMPTY-totals

    func test_totalsViewModel_zeroSessions_returnsZero_notNil() {
        let sut = TotalsViewModel(store: store, clock: clock)
        sut.refresh()

        for window: TimeInterval in [24 * hour, 48 * hour, 72 * hour] {
            XCTAssertEqual(sut.total(for: .personA, over: window), 0)
            XCTAssertEqual(sut.total(for: .personB, over: window), 0)
        }
    }

    // MARK: - EMPTY-edit

    func test_editViewModel_zeroSessions_inLast7Days_returnsEmptyList() {
        let sut = EditViewModel(store: store, clock: clock)
        sut.refresh()

        XCTAssertTrue(sut.sessions.isEmpty, "Empty 7-day window: empty list (not error)")
    }

    // MARK: - 5-day-old session: Day view shows it on its day; Edit still shows it

    func test_fiveDayOldSession_appearsOnItsDay_andOnEdit() throws {
        // RELAY-4: Day view exposes the trailing 7-day window (matches ADR-003).
        // A 5-day-old session must therefore be visible on the day it occurred.
        let s = try store.startSession(for: .personA, at: now.addingTimeInterval(-5 * day))
        try store.endSession(s, at: now.addingTimeInterval(-5 * day + hour))

        let timeline = TimelineViewModel(store: store, clock: clock)
        timeline.refresh()
        let fiveDaysAgo = Calendar.current.startOfDay(for: now.addingTimeInterval(-5 * day))
        let slices = timeline.slices(for: fiveDaysAgo)
        XCTAssertEqual(slices.personA.count, 1, "5-day-old session appears on its calendar day")

        let edit = EditViewModel(store: store, clock: clock)
        edit.refresh()
        XCTAssertEqual(edit.sessions.count, 1, "Same session also appears on Edit (7-day window)")
    }
}
