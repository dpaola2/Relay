//
//  EditViewModelTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M4: Timeline + Totals + Edit)
//
//  Covers gameplan acceptance criteria:
//    - EDT-001 (ADR-003 / PRD Q7): the Edit screen lists sessions overlapping
//      the last 7 days, NOT 72h.
//    - EDT-002: each row exposes who, start, end (or open), duration.
//    - EDT-003 / EDT-004: row edits persist and are reflected on next read.
//    - EDT-005 (`Should`): a session can be deleted.
//    - EDT-006 (`Should`): a session's `who` can be reassigned.
//    - PRD §8 edge case: setting endedAt < startedAt is rejected inline.
//    - PRD §8 edge case: overlapping sessions are allowed (no validation).
//
//  Will FAIL until Stage 5 lands `Relay/ViewModels/EditViewModel.swift`.
//

import XCTest
@testable import Relay

final class EditViewModelTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private var clock: FakeClock!
    private var sut: EditViewModel!

    private let now = Date(timeIntervalSince1970: 1_779_278_400)
    private let day: TimeInterval = 24 * 3_600
    private let hour: TimeInterval = 3_600

    override func setUp() {
        super.setUp()
        store = InMemorySleepSessionStore()
        clock = FakeClock(now)
        sut = EditViewModel(store: store, clock: clock)
    }

    override func tearDown() {
        sut = nil
        clock = nil
        store = nil
        super.tearDown()
    }

    // MARK: - EDT-001 (ADR-003): 7-day window, not 72h

    func test_listedSessions_includes6DayOldSession_whichIs_OutsideTimelineWindow() throws {
        // 6 days old — inside Edit's 7-day window but outside Timeline's 72h.
        let s = try store.startSession(for: .personA, at: now.addingTimeInterval(-6 * day))
        try store.endSession(s, at: now.addingTimeInterval(-6 * day + 3 * hour))

        sut.refresh()

        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.id, s.id)
    }

    func test_listedSessions_excludesSessionOlderThan7Days() throws {
        // 8 days old, ended 7.5 days ago — outside the 7-day window.
        let s = try store.startSession(for: .personB, at: now.addingTimeInterval(-8 * day))
        try store.endSession(s, at: now.addingTimeInterval(-7.5 * day))

        sut.refresh()
        XCTAssertTrue(sut.sessions.isEmpty, "Session entirely outside 7-day window must be excluded")
    }

    /// Arch §3.6 / ADR-003 consequence — a long session that started 8 days
    /// ago but ended 6 days ago overlaps the 7-day window and MUST be listed.
    func test_listedSessions_includesOverlappingSession_startingBeforeWindow() throws {
        let s = try store.startSession(for: .personA, at: now.addingTimeInterval(-8 * day))
        try store.endSession(s, at: now.addingTimeInterval(-6 * day))

        sut.refresh()
        XCTAssertEqual(sut.sessions.count, 1, "Overlapping session must be listed per ADR-003")
    }

    /// Boundary exactness — a session whose `endedAt` is exactly at cutoff is
    /// included (predicate uses `>=`).
    func test_listedSessions_includesSessionEndingExactlyAtCutoff() throws {
        let cutoff = now.addingTimeInterval(-7 * day)
        let s = try store.startSession(for: .personA, at: cutoff.addingTimeInterval(-hour))
        try store.endSession(s, at: cutoff)

        sut.refresh()
        XCTAssertEqual(sut.sessions.count, 1, "endedAt == cutoff is inclusive (>=)")
    }

    // MARK: - EDT-002: row info surface

    func test_row_exposesWhoStartEndDuration_forClosedSession() throws {
        let started = now.addingTimeInterval(-2 * hour)
        let ended = now.addingTimeInterval(-1 * hour)
        let s = try store.startSession(for: .personB, at: started)
        try store.endSession(s, at: ended)

        sut.refresh()
        let row = sut.sessions.first!

        XCTAssertEqual(row.who, .personB)
        XCTAssertEqual(row.startedAt, started)
        XCTAssertEqual(row.endedAt, ended)
        XCTAssertEqual(row.duration(asOf: now), hour, accuracy: 1.0)
        XCTAssertFalse(row.isOpen)
    }

    func test_row_marksOngoingSession_byNilEndedAt() throws {
        _ = try store.startSession(for: .personA, at: now.addingTimeInterval(-30 * 60))

        sut.refresh()
        let row = sut.sessions.first!

        XCTAssertNil(row.endedAt)
        XCTAssertTrue(row.isOpen)
    }

    // MARK: - EDT-003 + EDT-004: edits persist

    func test_save_persistsNewStartAndEndTimes() throws {
        let original = try store.startSession(for: .personA, at: now.addingTimeInterval(-3 * hour))
        try store.endSession(original, at: now.addingTimeInterval(-2 * hour))

        let newStart = now.addingTimeInterval(-90 * 60)
        let newEnd = now.addingTimeInterval(-30 * 60)
        try sut.save(session: original, startedAt: newStart, endedAt: newEnd, who: nil)

        sut.refresh()
        let updated = sut.sessions.first(where: { $0.id == original.id })
        XCTAssertEqual(updated?.startedAt, newStart)
        XCTAssertEqual(updated?.endedAt, newEnd)
    }

    /// PRD §8 + Arch §1.3 — endedAt < startedAt is rejected.
    func test_save_throws_whenEndBeforeStart() throws {
        let s = try store.startSession(for: .personA, at: now.addingTimeInterval(-2 * hour))
        try store.endSession(s, at: now.addingTimeInterval(-1 * hour))

        XCTAssertThrowsError(
            try sut.save(
                session: s,
                startedAt: now.addingTimeInterval(-30 * 60),
                endedAt: now.addingTimeInterval(-60 * 60),
                who: nil
            ),
            "endedAt before startedAt must be rejected inline (PRD §8)"
        )
    }

    // MARK: - EDT-005 (Should): delete

    func test_delete_removesSessionFromList() throws {
        let s = try store.startSession(for: .personA, at: now.addingTimeInterval(-2 * hour))
        try store.endSession(s, at: now.addingTimeInterval(-1 * hour))

        sut.refresh()
        XCTAssertEqual(sut.sessions.count, 1)

        try sut.delete(s)
        sut.refresh()
        XCTAssertTrue(sut.sessions.isEmpty)
    }

    // MARK: - EDT-006 (Should): who reassignment

    func test_save_canReassignWho() throws {
        let s = try store.startSession(for: .personA, at: now.addingTimeInterval(-2 * hour))
        try store.endSession(s, at: now.addingTimeInterval(-1 * hour))

        try sut.save(session: s, startedAt: nil, endedAt: nil, who: .personB)

        sut.refresh()
        let updated = sut.sessions.first(where: { $0.id == s.id })
        XCTAssertEqual(updated?.who, .personB)
    }

    // MARK: - PRD §8 edge case: overlapping sessions are allowed

    func test_save_allowsEditsThatOverlapExistingSession() throws {
        let s1 = try store.startSession(for: .personA, at: now.addingTimeInterval(-2 * hour))
        try store.endSession(s1, at: now.addingTimeInterval(-1 * hour))
        let s2 = try store.startSession(for: .personB, at: now.addingTimeInterval(-90 * 60))
        try store.endSession(s2, at: now.addingTimeInterval(-30 * 60))

        // Edit s1 to overlap s2 — should NOT throw (PRD §8: no overlap validation in v1).
        XCTAssertNoThrow(
            try sut.save(
                session: s1,
                startedAt: now.addingTimeInterval(-90 * 60),
                endedAt: now.addingTimeInterval(-15 * 60),
                who: nil
            )
        )
    }
}
