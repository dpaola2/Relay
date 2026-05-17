//
//  TimelineDayViewModelTests.swift
//  RelayTests
//
//  RELAY-4 — vertical Day view. Tests cover the day-slicing API the new
//  `DayTimelineView` reads:
//    - `slices(for:)` clips overlapping sessions to a local-calendar day
//    - day-spanning sessions appear in both days, same `sessionID`
//    - open sessions clip to `min(clock.now, dayEnd)`
//    - per-person lanes are grouped + sorted chronologically
//    - `today` and `earliestSelectableDay` clamp navigation
//    - `nowAnchor(in:)` returns `clock.now` only when displayed day is today
//

import XCTest
@testable import Relay

final class TimelineDayViewModelTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private var clock: FakeClock!
    private var calendar: Calendar!

    /// Anchor inside a local calendar day. Using GMT calendar keeps the day
    /// math deterministic regardless of the runner's locale.
    private let now = Date(timeIntervalSince1970: 1_779_278_400) // 2026-05-16 12:00:00 UTC
    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 24 * 3_600

    override func setUp() {
        super.setUp()
        store = InMemorySleepSessionStore()
        clock = FakeClock(now)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        calendar = nil
        clock = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeVM() -> TimelineViewModel {
        TimelineViewModel(store: store, clock: clock, calendar: calendar)
    }

    private var todayStart: Date {
        calendar.dateInterval(of: .day, for: now)!.start
    }

    // MARK: - color(for:) — stable per-person identity (carried over from v1)

    func test_color_isDistinct_perPerson() {
        let sut = makeVM()
        XCTAssertNotEqual(sut.color(for: .dave), sut.color(for: .bethany))
    }

    func test_color_isStable_acrossInvocations() {
        let sut = makeVM()
        XCTAssertEqual(sut.color(for: .dave), sut.color(for: .dave))
        XCTAssertEqual(sut.color(for: .bethany), sut.color(for: .bethany))
    }

    // MARK: - today / earliestSelectableDay

    func test_today_returnsStartOfClockDay() {
        let sut = makeVM()
        XCTAssertEqual(sut.today, todayStart)
    }

    func test_earliestSelectableDay_isSixDaysBeforeToday() {
        let sut = makeVM()
        let expected = calendar.date(byAdding: .day, value: -6, to: todayStart)!
        XCTAssertEqual(sut.earliestSelectableDay, expected)
    }

    // MARK: - slices(for:) — basic grouping

    func test_slices_groupsSessionsByPerson() throws {
        let dStart = todayStart.addingTimeInterval(2 * hour)   // 02:00
        let dEnd = todayStart.addingTimeInterval(5 * hour)     // 05:00
        let bStart = todayStart.addingTimeInterval(3 * hour)   // 03:00
        let bEnd = todayStart.addingTimeInterval(7 * hour)     // 07:00

        let d = try store.startSession(for: .dave, at: dStart)
        try store.endSession(d, at: dEnd)
        let b = try store.startSession(for: .bethany, at: bStart)
        try store.endSession(b, at: bEnd)

        let sut = makeVM()
        sut.refresh()
        let slices = sut.slices(for: todayStart)

        XCTAssertEqual(slices.dave.count, 1)
        XCTAssertEqual(slices.bethany.count, 1)
        XCTAssertEqual(slices.dave.first?.who, .dave)
        XCTAssertEqual(slices.bethany.first?.who, .bethany)
    }

    func test_slices_sortsEachLaneChronologically() throws {
        let a = try store.startSession(for: .dave, at: todayStart.addingTimeInterval(5 * hour))
        try store.endSession(a, at: todayStart.addingTimeInterval(6 * hour))
        let b = try store.startSession(for: .dave, at: todayStart.addingTimeInterval(1 * hour))
        try store.endSession(b, at: todayStart.addingTimeInterval(2 * hour))

        let sut = makeVM()
        sut.refresh()
        let slices = sut.slices(for: todayStart)

        XCTAssertEqual(slices.dave.count, 2)
        XCTAssertLessThan(
            slices.dave[0].visibleStart,
            slices.dave[1].visibleStart,
            "Lane slices must be sorted chronologically"
        )
    }

    func test_slices_excludesSessionsOutsideDay() throws {
        // Whole-day window: a session entirely the day before must not appear.
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let s = try store.startSession(for: .dave, at: yesterdayStart.addingTimeInterval(2 * hour))
        try store.endSession(s, at: yesterdayStart.addingTimeInterval(4 * hour))

        let sut = makeVM()
        sut.refresh()
        let slices = sut.slices(for: todayStart)

        XCTAssertTrue(slices.dave.isEmpty)
        XCTAssertTrue(slices.bethany.isEmpty)
    }

    // MARK: - Day-spanning sessions — render in BOTH days, clipped

    func test_slices_clipSpanningSessionAtDayStart() throws {
        // Session: 22:00 yesterday → 03:00 today. From today's perspective the
        // visible portion is [todayStart, todayStart+3h).
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let start = yesterdayStart.addingTimeInterval(22 * hour)
        let end = todayStart.addingTimeInterval(3 * hour)
        let s = try store.startSession(for: .dave, at: start)
        try store.endSession(s, at: end)

        let sut = makeVM()
        sut.refresh()
        let slices = sut.slices(for: todayStart)

        XCTAssertEqual(slices.dave.count, 1)
        let slice = slices.dave[0]
        XCTAssertEqual(slice.visibleStart, todayStart, "Spanning session clips to day start")
        XCTAssertEqual(slice.visibleEnd, end)
        XCTAssertEqual(slice.sessionID, s.id, "Slice still points at the underlying session")
    }

    func test_slices_clipSpanningSessionAtDayEnd() throws {
        // Same session viewed from yesterday: visible portion is [22:00, dayEnd).
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let yesterdayEnd = todayStart
        let start = yesterdayStart.addingTimeInterval(22 * hour)
        let end = todayStart.addingTimeInterval(3 * hour)
        let s = try store.startSession(for: .dave, at: start)
        try store.endSession(s, at: end)

        let sut = makeVM()
        sut.refresh()
        let slices = sut.slices(for: yesterdayStart)

        XCTAssertEqual(slices.dave.count, 1)
        let slice = slices.dave[0]
        XCTAssertEqual(slice.visibleStart, start)
        XCTAssertEqual(slice.visibleEnd, yesterdayEnd, "Spanning session clips to day end")
        XCTAssertEqual(slice.sessionID, s.id)
    }

    func test_slices_sameSessionAppearsInBothDaysWithSameSessionID() throws {
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let start = yesterdayStart.addingTimeInterval(22 * hour)
        let end = todayStart.addingTimeInterval(3 * hour)
        let s = try store.startSession(for: .bethany, at: start)
        try store.endSession(s, at: end)

        let sut = makeVM()
        sut.refresh()
        let yesterday = sut.slices(for: yesterdayStart)
        let today = sut.slices(for: todayStart)

        XCTAssertEqual(yesterday.bethany.first?.sessionID, s.id)
        XCTAssertEqual(today.bethany.first?.sessionID, s.id)
        XCTAssertNotEqual(
            yesterday.bethany.first?.id,
            today.bethany.first?.id,
            "Slice IDs must differ per-day so SwiftUI ForEach treats them as distinct rows"
        )
    }

    // MARK: - Open sessions

    func test_openSession_today_clipsToClockNow() throws {
        // Open session started 90 minutes before now. Displayed on today, the
        // slice should end at clock.now.
        let start = now.addingTimeInterval(-90 * 60)
        _ = try store.startSession(for: .dave, at: start)

        let sut = makeVM()
        sut.refresh()
        let slices = sut.slices(for: todayStart)

        XCTAssertEqual(slices.dave.count, 1)
        let slice = slices.dave[0]
        XCTAssertTrue(slice.isOpen)
        XCTAssertEqual(slice.visibleStart, start)
        XCTAssertEqual(slice.visibleEnd, clock.now)
    }

    func test_openSession_pastDay_clipsToDayEnd() throws {
        // Open session that started two days ago, viewed from that day.
        // It must clip to that day's end, NOT bleed forward to clock.now.
        let twoDaysAgoStart = calendar.date(byAdding: .day, value: -2, to: todayStart)!
        let twoDaysAgoEnd = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let start = twoDaysAgoStart.addingTimeInterval(23 * hour)
        _ = try store.startSession(for: .bethany, at: start)

        let sut = makeVM()
        sut.refresh()
        let slices = sut.slices(for: twoDaysAgoStart)

        XCTAssertEqual(slices.bethany.count, 1)
        XCTAssertEqual(slices.bethany.first?.visibleEnd, twoDaysAgoEnd)
    }

    // MARK: - nowAnchor(in:)

    func test_nowAnchor_returnsClockNow_forToday() {
        let sut = makeVM()
        XCTAssertEqual(sut.nowAnchor(in: todayStart), clock.now)
    }

    func test_nowAnchor_returnsNil_forPastDay() {
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let sut = makeVM()
        XCTAssertNil(sut.nowAnchor(in: yesterdayStart))
    }

    // MARK: - DaySlice duration label is full session duration

    func test_slice_fullDuration_isUnderlyingSessionDuration() throws {
        // 5h session spanning midnight — both day slices report the FULL 5h
        // duration so the user can read "5h" on either side of midnight.
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let start = yesterdayStart.addingTimeInterval(22 * hour) // 22:00 yesterday
        let end = todayStart.addingTimeInterval(3 * hour)        // 03:00 today (5h total)
        let s = try store.startSession(for: .dave, at: start)
        try store.endSession(s, at: end)

        let sut = makeVM()
        sut.refresh()
        let yesterday = sut.slices(for: yesterdayStart)
        let today = sut.slices(for: todayStart)

        XCTAssertEqual(yesterday.dave.first?.fullDuration, 5 * hour)
        XCTAssertEqual(today.dave.first?.fullDuration, 5 * hour)
    }
}
