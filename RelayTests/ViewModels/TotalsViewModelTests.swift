//
//  TotalsViewModelTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M4: Timeline + Totals + Edit; M6 edge cases)
//
//  Covers gameplan acceptance criteria:
//    - TOT-001: 24h / 48h / 72h cumulative sleep per person.
//    - TOT-002: numbers are large + minimal decoration (a view assertion, but
//      the view-model exposes the raw `TimeInterval` for the view to render).
//    - TOT-003 (`Should`): open sessions count their elapsed-so-far portion.
//    - TOT-empty (PRD §8): zero sessions => 0 (not nil, not error).
//    - M6 edge: DST-spanning session counts the absolute Date-math interval.
//    - M6 edge: clock-rewind doesn't crash (defensive zero).
//    - M6 TOT-004 (`Nice`, conditional): sleep-debt indicator math.
//
//  Will FAIL until Stage 5 lands `Relay/ViewModels/TotalsViewModel.swift`.
//

import XCTest
@testable import Relay

final class TotalsViewModelTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private var clock: FakeClock!
    private var sut: TotalsViewModel!

    private let now = Date(timeIntervalSince1970: 1_779_278_400)
    private let hour: TimeInterval = 3_600

    override func setUp() {
        super.setUp()
        store = InMemorySleepSessionStore()
        clock = FakeClock(now)
        sut = TotalsViewModel(store: store, clock: clock)
    }

    override func tearDown() {
        sut = nil
        clock = nil
        store = nil
        super.tearDown()
    }

    // MARK: - TOT-001: per-person cumulative over 24h / 48h / 72h

    func test_total24h_sumsClosedSessions_inLast24h_forGivenPerson() throws {
        // Dave: 4h ending 2h ago (entirely inside 24h)
        let d1 = try store.startSession(for: .dave, at: now.addingTimeInterval(-6 * hour))
        try store.endSession(d1, at: now.addingTimeInterval(-2 * hour))
        // Dave: 1h ending 23h ago (inside 24h)
        let d2 = try store.startSession(for: .dave, at: now.addingTimeInterval(-24 * hour))
        try store.endSession(d2, at: now.addingTimeInterval(-23 * hour))
        // Bethany: 2h ending 1h ago — must NOT count toward Dave's total.
        let b1 = try store.startSession(for: .bethany, at: now.addingTimeInterval(-3 * hour))
        try store.endSession(b1, at: now.addingTimeInterval(-1 * hour))

        sut.refresh()

        XCTAssertEqual(sut.total(for: .dave, over: 24 * hour), 5 * hour, accuracy: 1.0)
        XCTAssertEqual(sut.total(for: .bethany, over: 24 * hour), 2 * hour, accuracy: 1.0)
    }

    func test_total48h_aggregatesAcrossWiderWindow() throws {
        // Dave: 3h closed 30h ago (outside 24h, inside 48h)
        let d = try store.startSession(for: .dave, at: now.addingTimeInterval(-33 * hour))
        try store.endSession(d, at: now.addingTimeInterval(-30 * hour))

        sut.refresh()

        XCTAssertEqual(sut.total(for: .dave, over: 24 * hour), 0, accuracy: 1.0, "Outside 24h")
        XCTAssertEqual(sut.total(for: .dave, over: 48 * hour), 3 * hour, accuracy: 1.0)
    }

    func test_total72h_aggregatesEvenWider() throws {
        let d = try store.startSession(for: .dave, at: now.addingTimeInterval(-60 * hour))
        try store.endSession(d, at: now.addingTimeInterval(-58 * hour))

        sut.refresh()
        XCTAssertEqual(sut.total(for: .dave, over: 72 * hour), 2 * hour, accuracy: 1.0)
        XCTAssertEqual(sut.total(for: .dave, over: 48 * hour), 0, accuracy: 1.0)
    }

    // MARK: - TOT-003: open sessions count elapsed-so-far

    func test_total24h_includesOpenSessionDurationToNow() throws {
        // Open Dave session started 2h ago.
        _ = try store.startSession(for: .dave, at: now.addingTimeInterval(-2 * hour))

        sut.refresh()
        XCTAssertEqual(sut.total(for: .dave, over: 24 * hour), 2 * hour, accuracy: 1.0)
    }

    func test_total24h_clipsSessionToWindow_whenStartedBeforeWindow() throws {
        // Closed Dave session: started 26h ago, ended 22h ago (i.e., 4h total,
        // but only 2h is inside the 24h window).
        let d = try store.startSession(for: .dave, at: now.addingTimeInterval(-26 * hour))
        try store.endSession(d, at: now.addingTimeInterval(-22 * hour))

        sut.refresh()
        XCTAssertEqual(
            sut.total(for: .dave, over: 24 * hour),
            2 * hour,
            accuracy: 1.0,
            "Sessions are clipped to the window for correct cumulative math"
        )
    }

    // MARK: - TOT-empty: zero sessions returns 0h 0m, not error

    func test_totals_areZero_whenNoSessionsExist() {
        sut.refresh()
        XCTAssertEqual(sut.total(for: .dave, over: 24 * hour), 0, accuracy: 0.001)
        XCTAssertEqual(sut.total(for: .dave, over: 48 * hour), 0, accuracy: 0.001)
        XCTAssertEqual(sut.total(for: .dave, over: 72 * hour), 0, accuracy: 0.001)
        XCTAssertEqual(sut.total(for: .bethany, over: 24 * hour), 0, accuracy: 0.001)
    }

    // MARK: - M6 edge: DST-spanning session

    func test_total24h_handlesDSTSpanningSession_viaDateMath() throws {
        // 8 hours of absolute time, regardless of wall-clock DST jump.
        let dstStart = now.addingTimeInterval(-10 * hour)
        let dstEnd = dstStart.addingTimeInterval(8 * hour) // 2h ago
        let d = try store.startSession(for: .dave, at: dstStart)
        try store.endSession(d, at: dstEnd)

        sut.refresh()
        XCTAssertEqual(sut.total(for: .dave, over: 24 * hour), 8 * hour, accuracy: 1.0)
    }

    // MARK: - M6 edge: clock-rewind / negative duration safety

    func test_total_isNonNegative_evenIfClockRewindsMidSession() throws {
        let original = now
        // Open session started in the future relative to a rewound clock.
        _ = try store.startSession(for: .dave, at: original.addingTimeInterval(100))
        clock.currentDate = original // pretend clock rewound

        sut.refresh()
        XCTAssertGreaterThanOrEqual(
            sut.total(for: .dave, over: 24 * hour),
            0,
            "Defensive: clock-rewind must not produce negative cumulative"
        )
    }

    // MARK: - M6 TOT-004 (Nice, conditional): sleep-debt indicator

    func test_sleepDebt_isTargetMinusActual_forGivenWindow() throws {
        // Dave slept 4h in the last 24h.
        let d = try store.startSession(for: .dave, at: now.addingTimeInterval(-5 * hour))
        try store.endSession(d, at: now.addingTimeInterval(-1 * hour))

        sut.refresh()
        let debt = sut.sleepDebt(for: .dave, targetHoursPer24h: 8.0, window: 24 * hour)

        XCTAssertEqual(debt, 4 * hour, accuracy: 1.0, "8h target - 4h actual = 4h debt")
    }

    func test_sleepDebt_isZero_whenActualMeetsOrExceedsTarget() throws {
        let d = try store.startSession(for: .dave, at: now.addingTimeInterval(-9 * hour))
        try store.endSession(d, at: now.addingTimeInterval(-0.5 * hour))

        sut.refresh()
        let debt = sut.sleepDebt(for: .dave, targetHoursPer24h: 8.0, window: 24 * hour)

        XCTAssertEqual(debt, 0, accuracy: 1.0, "Meeting target means no debt (not negative)")
    }
}
