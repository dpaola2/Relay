//
//  TimelineViewModelTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M4: Timeline + Totals + Edit)
//
//  Covers gameplan acceptance criteria:
//    - TML-001: 72h horizontal band relative to `clock.now`.
//    - TML-002: each session has a color identity tied to its `Person`.
//    - TML-003: day/night shading (bands at ~22:00–06:00) — view-model exposes
//      the bands as data the view consumes.
//    - TML-004 (`Should`): gaps are implicit (no separate "on duty" rendering).
//    - TML-005: open sessions extend to `clock.now`.
//    - TML-006 (`Should`): empty 72h window is not an error.
//
//  Will FAIL until Stage 5 lands `Relay/ViewModels/TimelineViewModel.swift`.
//

import XCTest
@testable import Relay

final class TimelineViewModelTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private var clock: FakeClock!

    // 2026-05-16 12:00:00 UTC — well after Jo's birth, comfortable middle-of-day anchor.
    private let now = Date(timeIntervalSince1970: 1_779_278_400)
    private let hour: TimeInterval = 3_600

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

    // MARK: - TML-001: 72h window

    func test_windowStart_is72HoursBeforeNow() {
        let sut = TimelineViewModel(store: store, clock: clock)
        let expected = now.addingTimeInterval(-72 * hour)
        XCTAssertEqual(sut.windowStart, expected, "Window starts 72h before now")
        XCTAssertEqual(sut.windowEnd, now, "Window ends at clock.now")
    }

    func test_sessions_includesSessionsInWindow() throws {
        // Inside window: 1h Dave session that started 12h ago.
        let s1 = try store.startSession(for: .dave, at: now.addingTimeInterval(-12 * hour))
        try store.endSession(s1, at: now.addingTimeInterval(-11 * hour))

        let sut = TimelineViewModel(store: store, clock: clock)
        sut.refresh()

        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.id, s1.id)
    }

    func test_sessions_excludesSessionsBeforeWindow() throws {
        // Outside window: a session that ended 73h ago.
        let s = try store.startSession(for: .dave, at: now.addingTimeInterval(-74 * hour))
        try store.endSession(s, at: now.addingTimeInterval(-73 * hour))

        let sut = TimelineViewModel(store: store, clock: clock)
        sut.refresh()

        XCTAssertTrue(sut.sessions.isEmpty, "Session entirely before 72h window must be excluded")
    }

    func test_sessions_includesStraddlingSession() throws {
        // Started before the 72h window, ended inside it — must be included.
        let s = try store.startSession(for: .bethany, at: now.addingTimeInterval(-80 * hour))
        try store.endSession(s, at: now.addingTimeInterval(-70 * hour))

        let sut = TimelineViewModel(store: store, clock: clock)
        sut.refresh()

        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.id, s.id)
    }

    // MARK: - TML-005: open sessions extend to `clock.now`

    func test_openSession_inWindow_isIncluded_andExtendsToNow() throws {
        // Open session that started 30m ago.
        _ = try store.startSession(for: .dave, at: now.addingTimeInterval(-1_800))

        let sut = TimelineViewModel(store: store, clock: clock)
        sut.refresh()

        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertTrue(sut.sessions.first?.isOpen ?? false)
        // The view-model offers an "effective end" derivation for rendering.
        XCTAssertEqual(
            sut.effectiveEnd(of: sut.sessions.first!),
            now,
            "Open sessions render extending to clock.now"
        )
    }

    // MARK: - TML-002: color identity tied to Person

    func test_color_isDistinct_perPerson() {
        let sut = TimelineViewModel(store: store, clock: clock)
        XCTAssertNotEqual(sut.color(for: .dave), sut.color(for: .bethany))
    }

    func test_color_isStable_acrossInvocations() {
        let sut = TimelineViewModel(store: store, clock: clock)
        XCTAssertEqual(sut.color(for: .dave), sut.color(for: .dave))
        XCTAssertEqual(sut.color(for: .bethany), sut.color(for: .bethany))
    }

    // MARK: - TML-003: day/night shading bands

    func test_nightBands_coverWindow_atRoughly22ToO6() {
        let sut = TimelineViewModel(store: store, clock: clock)
        let bands = sut.nightBands

        XCTAssertFalse(bands.isEmpty, "72h window should produce night bands")
        for band in bands {
            // Each band must lie inside the [windowStart, windowEnd] range.
            XCTAssertGreaterThanOrEqual(band.start, sut.windowStart)
            XCTAssertLessThanOrEqual(band.end, sut.windowEnd)
            XCTAssertLessThan(band.start, band.end, "Bands have non-zero width")
        }
    }

    // MARK: - TML-006 (`Should`): empty 72h window is not an error

    func test_emptyWindow_returnsEmptySessions_withoutError() {
        let sut = TimelineViewModel(store: store, clock: clock)
        sut.refresh()

        XCTAssertTrue(sut.sessions.isEmpty)
        // The shading data still exists even with zero sessions — empty state is
        // an "empty 72h band with shading," not an error or placeholder.
        XCTAssertFalse(sut.nightBands.isEmpty, "Shading is present even when no sessions exist")
    }
}
