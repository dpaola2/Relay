//
//  SwiftDataSleepSessionStoreTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M2: Domain Model & Persistence)
//
//  Covers gameplan acceptance criteria:
//    - DAT-002: persistence is local SwiftData.
//    - DAT-store-1: `SleepSessionStore` protocol exposes the documented surface.
//    - DAT-store-2: `SwiftDataSleepSessionStore` conforms to the protocol and is
//      `nonisolated final class` backed by an injected `ModelContext`.
//    - PRD §8 edge case: `update` with `endedAt < startedAt` is rejected.
//
//  Uses an in-memory `ModelContainer` so the test target doesn't pollute a real
//  store. Tests will FAIL until Stage 5 lands the model + store types.
//

import XCTest
import SwiftData
@testable import Relay

final class SwiftDataSleepSessionStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var sut: SwiftDataSleepSessionStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([SleepSession.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        sut = SwiftDataSleepSessionStore(context: ModelContext(container))
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    // MARK: - DAT-store-1: reads + writes round-trip

    func test_startSession_createsOpenSession_andReturnsIt() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let s = try sut.startSession(for: .dave, at: now)

        XCTAssertEqual(s.who, .dave)
        XCTAssertEqual(s.startedAt, now)
        XCTAssertNil(s.endedAt)
        XCTAssertTrue(s.isOpen)

        let openForDave = try sut.openSession(for: .dave)
        XCTAssertEqual(openForDave?.id, s.id)
    }

    func test_endSession_closesAtGivenTime() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let s = try sut.startSession(for: .dave, at: start)
        let end = start.addingTimeInterval(3_600)

        try sut.endSession(s, at: end)

        let fetched = try sut.openSession(for: .dave)
        XCTAssertNil(fetched, "Session should no longer appear as open after endSession")

        let allInRange = try sut.sessions(in: start...end)
        XCTAssertEqual(allInRange.count, 1)
        XCTAssertEqual(allInRange.first?.endedAt, end)
    }

    func test_allOpenSessions_returnsBothPeople_whenBothAreSleeping() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        _ = try sut.startSession(for: .dave, at: now)
        _ = try sut.startSession(for: .bethany, at: now.addingTimeInterval(60))

        let open = try sut.allOpenSessions()
        XCTAssertEqual(open.count, 2)
        XCTAssertTrue(open.contains { $0.who == .dave })
        XCTAssertTrue(open.contains { $0.who == .bethany })
    }

    func test_sessions_inRange_includesOverlappingSessions() throws {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let oneHour: TimeInterval = 3_600

        // Session that ends just before the window — should be excluded.
        let before = try sut.startSession(for: .dave, at: base - 3 * oneHour)
        try sut.endSession(before, at: base - 2 * oneHour)

        // Session straddling the start of the window — should be included.
        let straddle = try sut.startSession(for: .bethany, at: base - oneHour)
        try sut.endSession(straddle, at: base + oneHour)

        // Open session inside the window — should be included.
        _ = try sut.startSession(for: .dave, at: base + 2 * oneHour)

        let range: ClosedRange<Date> = base...(base + 4 * oneHour)
        let results = try sut.sessions(in: range)
        XCTAssertEqual(results.count, 2, "Overlapping + interior sessions only")
        XCTAssertFalse(results.contains { $0.id == before.id })
    }

    // MARK: - DAT-store-1 update double-optional semantics

    func test_update_setsFields_whenNonNilProvided() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let s = try sut.startSession(for: .dave, at: start)
        let newStart = start.addingTimeInterval(60)
        let newEnd = start.addingTimeInterval(3_600)

        try sut.update(s, startedAt: newStart, endedAt: .some(newEnd), who: .bethany, note: .some("revised"))

        XCTAssertEqual(s.startedAt, newStart)
        XCTAssertEqual(s.endedAt, newEnd)
        XCTAssertEqual(s.who, .bethany)
        XCTAssertEqual(s.note, "revised")
    }

    /// Double-optional contract: outer `nil` means "don't touch."
    func test_update_doesNotTouchEndedAt_whenOuterIsNil() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let s = try sut.startSession(for: .dave, at: start)
        try sut.endSession(s, at: start.addingTimeInterval(3_600))
        let originalEnd = s.endedAt

        try sut.update(s, startedAt: nil, endedAt: nil, who: nil, note: nil)

        XCTAssertEqual(s.endedAt, originalEnd, "Outer-nil endedAt means 'don't touch'")
    }

    /// Double-optional contract: outer `.some(nil)` means "set to nil" — reopens
    /// a previously-closed session.
    func test_update_setsEndedAtToNil_whenOuterIsSomeNil() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let s = try sut.startSession(for: .dave, at: start)
        try sut.endSession(s, at: start.addingTimeInterval(3_600))

        try sut.update(s, startedAt: nil, endedAt: .some(nil), who: nil, note: nil)

        XCTAssertNil(s.endedAt, "Outer-some-inner-nil endedAt means 'reopen the session'")
        XCTAssertTrue(s.isOpen)
    }

    /// PRD §8 edge case + Arch §1.3 invariant.
    func test_update_throws_whenEndedAtPrecedesStartedAt() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let s = try sut.startSession(for: .dave, at: start)
        let badEnd = start.addingTimeInterval(-60)

        XCTAssertThrowsError(
            try sut.update(s, startedAt: nil, endedAt: .some(badEnd), who: nil, note: nil),
            "endedAt before startedAt must be rejected"
        )
    }

    // MARK: - DAT-store-1: delete

    func test_delete_removesSession() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let s = try sut.startSession(for: .dave, at: now)
        XCTAssertNotNil(try sut.openSession(for: .dave))

        try sut.delete(s)

        XCTAssertNil(try sut.openSession(for: .dave))
    }

    // MARK: - DAT-store-2: per-person open invariant (relaxed per ADR-001)

    func test_openSession_forPerson_returnsOnlyThatPersonsOpenSession() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        _ = try sut.startSession(for: .dave, at: now)
        _ = try sut.startSession(for: .bethany, at: now.addingTimeInterval(60))

        XCTAssertEqual(try sut.openSession(for: .dave)?.who, .dave)
        XCTAssertEqual(try sut.openSession(for: .bethany)?.who, .bethany)
    }

    // MARK: - RELAY-9: widget refresh fires after every write
    //
    // The widget kind that gets reloaded is irrelevant at this layer.
    // The store's contract: any successful commit calls
    // `WidgetRefreshing.refresh()` exactly once.

    func test_startSession_callsWidgetRefresher() throws {
        let spy = SpyWidgetRefresher()
        let store = SwiftDataSleepSessionStore(
            context: ModelContext(container),
            widgetRefresher: spy
        )

        _ = try store.startSession(for: .dave, at: Date(timeIntervalSince1970: 1_780_000_000))

        XCTAssertEqual(spy.refreshCount, 1)
    }

    func test_endSession_callsWidgetRefresher() throws {
        let spy = SpyWidgetRefresher()
        let store = SwiftDataSleepSessionStore(
            context: ModelContext(container),
            widgetRefresher: spy
        )
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let session = try store.startSession(for: .dave, at: start)
        XCTAssertEqual(spy.refreshCount, 1)

        try store.endSession(session, at: start.addingTimeInterval(3_600))

        XCTAssertEqual(spy.refreshCount, 2)
    }

    func test_update_callsWidgetRefresher() throws {
        let spy = SpyWidgetRefresher()
        let store = SwiftDataSleepSessionStore(
            context: ModelContext(container),
            widgetRefresher: spy
        )
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let session = try store.startSession(for: .dave, at: start)

        try store.update(
            session,
            startedAt: nil,
            endedAt: .some(start.addingTimeInterval(3_600)),
            who: nil,
            note: .some("note")
        )

        XCTAssertEqual(spy.refreshCount, 2, "Start + update both refresh")
    }

    func test_delete_callsWidgetRefresher() throws {
        let spy = SpyWidgetRefresher()
        let store = SwiftDataSleepSessionStore(
            context: ModelContext(container),
            widgetRefresher: spy
        )
        let session = try store.startSession(for: .dave, at: Date(timeIntervalSince1970: 1_780_000_000))

        try store.delete(session)

        XCTAssertEqual(spy.refreshCount, 2)
    }

    func test_init_defaultsToNoopRefresher_andStillCommits() throws {
        // The widget refresher has a default value so existing callers don't
        // need to thread it through. Smoke test: the default constructor still
        // works and writes still commit.
        let store = SwiftDataSleepSessionStore(context: ModelContext(container))
        let session = try store.startSession(for: .dave, at: Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertNotNil(session.id)
    }
}
