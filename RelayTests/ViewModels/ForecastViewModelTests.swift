//
//  ForecastViewModelTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M5: ForecastViewModel + same-who run
//  collapse + notification-driven refresh)
//
//  Covers gameplan acceptance criteria:
//    - ForecastViewModel is `@Observable nonisolated final class`.
//    - Constructor takes (engine, store, deficitProvider, clock, calendar,
//      firstRunFlag).
//    - `refresh(forPlanDay:)`: fetches existing shifts, gathers deficits,
//      calls engine.propose(...), writes non-overridden engine output via
//      upsert(...), deletes rows the engine no longer proposes that aren't
//      overridden, preserves manuallyOverridden rows untouched.
//    - ENG-011: override preservation — override rows are byte-identical
//      after refresh.
//    - `renderableBlocks(forPlanDay:)`: collapses consecutive same-`who`
//      half-hour rows into one rectangle per run.
//    - Subscribes to `.sleepSessionsDidChange` and `.proposedShiftsDidChange`;
//      calls `refresh(...)` on receive.
//    - Idempotent: repeated refresh with same state doesn't double-write.
//    - ENG-010: view can call `refresh(forPlanDay:)` from `.onAppear`.
//    - EDG-002: planDay with sessions in only one lane produces proposal
//      favoring empty-lane parent.
//
//  Expected to FAIL until Stage 5 lands:
//    (a) `Relay/ViewModels/ForecastViewModel.swift`
//    (b) `TimelineViewModel` extension conforming to `DeficitProviding`
//        (or a dedicated adapter).
//

import XCTest
@testable import Relay

final class ForecastViewModelTests: XCTestCase {

    private var engine: ForecastEngine!
    private var store: InMemoryProposedShiftStore!
    private var deficits: StubDeficitProvider!
    private var clock: FakeClock!
    private var calendar: Calendar!
    private var firstRunFlag: ForecastFirstRunFlag!
    private var sut: ForecastViewModel!

    // 2026-05-16 (Saturday) midnight UTC.
    private let planDay = Date(timeIntervalSince1970: 1_779_235_200)
    private let hour: TimeInterval = 3_600
    private let half: TimeInterval = 1_800

    private var afternoonNow: Date {
        planDay.addingTimeInterval(16 * hour)
    }

    override func setUp() {
        super.setUp()
        engine = ForecastEngine()
        store = InMemoryProposedShiftStore()
        deficits = StubDeficitProvider()
        clock = FakeClock(afternoonNow)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Per-test UserDefaults so the first-run flag is isolated.
        let suite = "relay.tests.fvm.\(UUID().uuidString)"
        firstRunFlag = ForecastFirstRunFlag(defaults: UserDefaults(suiteName: suite)!)
        sut = ForecastViewModel(
            engine: engine,
            store: store,
            deficitProvider: deficits,
            clock: clock,
            calendar: calendar,
            firstRunFlag: firstRunFlag
        )
    }

    override func tearDown() {
        sut = nil
        firstRunFlag = nil
        calendar = nil
        clock = nil
        deficits = nil
        store = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - refresh: engine output is written via upsert

    func test_refresh_writesEngineOutputToStore() {
        deficits.deficitForDave = 2 * hour
        deficits.deficitForBethany = 5 * hour

        sut.refresh(forPlanDay: planDay)

        let rows = (try? store.shifts(forPlanDay: planDay)) ?? []
        XCTAssertFalse(
            rows.isEmpty,
            "Engine output (non-empty) must be persisted via upsert"
        )
    }

    func test_refresh_returnsEmpty_whenBothDeficitsZero() {
        deficits.deficitForDave = 0
        deficits.deficitForBethany = 0

        sut.refresh(forPlanDay: planDay)

        let rows = (try? store.shifts(forPlanDay: planDay)) ?? []
        XCTAssertTrue(
            rows.isEmpty,
            "Empty proposal → store has no rows for this planDay"
        )
    }

    // MARK: - ENG-011: override preservation

    func test_refresh_preservesManuallyOverriddenRows_byteIdentical() throws {
        // Seed two override rows (Bethany at 22:00 and 22:30, both forced).
        let windowStart = planDay.addingTimeInterval(22 * hour)
        let override1 = try store.upsert(
            planDay: planDay,
            startedAt: windowStart,
            who: .bethany,
            manuallyOverridden: true
        )
        let override2 = try store.upsert(
            planDay: planDay,
            startedAt: windowStart.addingTimeInterval(half),
            who: .bethany,
            manuallyOverridden: true
        )
        let id1 = override1.id
        let id2 = override2.id

        // Engine would otherwise propose Dave for these cells.
        deficits.deficitForDave = 5 * hour
        deficits.deficitForBethany = 1 * hour

        sut.refresh(forPlanDay: planDay)

        let rows = try store.shifts(forPlanDay: planDay)
        let row1 = rows.first { $0.startedAt == windowStart }
        let row2 = rows.first { $0.startedAt == windowStart.addingTimeInterval(half) }

        XCTAssertEqual(row1?.id, id1, "Override row 1 must keep its identity (same id)")
        XCTAssertEqual(row2?.id, id2, "Override row 2 must keep its identity (same id)")
        XCTAssertEqual(row1?.who, .bethany, "Override who is preserved")
        XCTAssertEqual(row2?.who, .bethany)
        XCTAssertTrue(row1?.manuallyOverridden ?? false)
        XCTAssertTrue(row2?.manuallyOverridden ?? false)
    }

    // MARK: - refresh: deletes non-overridden rows the engine no longer proposes

    func test_refresh_deletesStaleNonOverriddenRows() throws {
        // Seed a non-overridden row that the engine WILL NOT re-emit (it's a
        // cell at a planDay-relative slot the engine won't touch — Dave at
        // 22:00 when the engine wants Bethany everywhere). Then refresh and
        // confirm the stale row was deleted.
        let windowStart = planDay.addingTimeInterval(22 * hour)
        _ = try store.upsert(
            planDay: planDay,
            startedAt: windowStart,
            who: .dave,
            manuallyOverridden: false
        )

        // Engine: only Bethany has deficit → cap at 5h, Dave gets zero.
        deficits.deficitForDave = 0
        deficits.deficitForBethany = 8 * hour

        sut.refresh(forPlanDay: planDay)

        let rows = try store.shifts(forPlanDay: planDay)
        let cellAt22 = rows.first { $0.startedAt == windowStart }
        XCTAssertEqual(
            cellAt22?.who,
            .bethany,
            "Stale Dave row at 22:00 is replaced by engine's Bethany (or deleted then re-upserted)"
        )
    }

    // MARK: - same-who run collapse

    func test_renderableBlocks_collapsesAdjacentSameWhoCells() throws {
        // Three consecutive Dave cells at 22:00, 22:30, 23:00 → one rectangle
        // 22:00–23:30 (1.5h total). Followed by one Bethany cell at 23:30 →
        // a second rectangle 23:30–00:00.
        let windowStart = planDay.addingTimeInterval(22 * hour)
        _ = try store.upsert(planDay: planDay, startedAt: windowStart, who: .dave, manuallyOverridden: false)
        _ = try store.upsert(planDay: planDay, startedAt: windowStart.addingTimeInterval(half), who: .dave, manuallyOverridden: false)
        _ = try store.upsert(planDay: planDay, startedAt: windowStart.addingTimeInterval(2 * half), who: .dave, manuallyOverridden: false)
        _ = try store.upsert(planDay: planDay, startedAt: windowStart.addingTimeInterval(3 * half), who: .bethany, manuallyOverridden: false)

        let blocks = sut.renderableBlocks(forPlanDay: planDay)
        XCTAssertEqual(blocks.count, 2, "Three Dave cells collapse to one block; Bethany cell is a second block")

        let daveBlock = blocks.first { $0.who == .dave }
        let bethBlock = blocks.first { $0.who == .bethany }
        XCTAssertEqual(daveBlock?.startedAt, windowStart)
        XCTAssertEqual(daveBlock?.endedAt, windowStart.addingTimeInterval(3 * half))
        XCTAssertEqual(bethBlock?.startedAt, windowStart.addingTimeInterval(3 * half))
        XCTAssertEqual(bethBlock?.endedAt, windowStart.addingTimeInterval(4 * half))
    }

    func test_renderableBlocks_doesNotCollapseAcrossWhoBoundary() throws {
        let windowStart = planDay.addingTimeInterval(22 * hour)
        _ = try store.upsert(planDay: planDay, startedAt: windowStart, who: .dave, manuallyOverridden: false)
        _ = try store.upsert(planDay: planDay, startedAt: windowStart.addingTimeInterval(half), who: .bethany, manuallyOverridden: false)

        let blocks = sut.renderableBlocks(forPlanDay: planDay)
        XCTAssertEqual(blocks.count, 2, "Different who → no collapse")
    }

    func test_renderableBlocks_doesNotCollapseAcrossTimeGap() throws {
        // Two Dave cells separated by an unassigned gap: 22:00 (Dave), 23:00
        // (Dave). The 22:30 cell is missing → no collapse.
        let windowStart = planDay.addingTimeInterval(22 * hour)
        _ = try store.upsert(planDay: planDay, startedAt: windowStart, who: .dave, manuallyOverridden: false)
        _ = try store.upsert(planDay: planDay, startedAt: windowStart.addingTimeInterval(2 * half), who: .dave, manuallyOverridden: false)

        let blocks = sut.renderableBlocks(forPlanDay: planDay)
        XCTAssertEqual(blocks.count, 2, "Gap between same-who cells prevents collapse")
    }

    func test_renderableBlocks_returnsEmpty_whenNoShifts() {
        let blocks = sut.renderableBlocks(forPlanDay: planDay)
        XCTAssertTrue(blocks.isEmpty)
    }

    // MARK: - ENG-010: refresh-on-appear

    func test_refresh_canBeCalledFromViewOnAppear() {
        // Stand-in for `.onAppear` triggering refresh — verified by call
        // counting on the in-memory store.
        let priorShiftsCalls = store.shiftsCallCount

        sut.refresh(forPlanDay: planDay)

        XCTAssertGreaterThan(
            store.shiftsCallCount,
            priorShiftsCalls,
            "refresh(forPlanDay:) must read existing shifts via the store"
        )
    }

    // MARK: - idempotency

    func test_refresh_doesNotDoubleWrite_whenCalledTwiceWithSameState() {
        deficits.deficitForDave = 2 * hour
        deficits.deficitForBethany = 5 * hour

        sut.refresh(forPlanDay: planDay)
        let countAfterFirst = (try? store.shifts(forPlanDay: planDay))?.count ?? 0

        sut.refresh(forPlanDay: planDay)
        let countAfterSecond = (try? store.shifts(forPlanDay: planDay))?.count ?? 0

        XCTAssertEqual(
            countAfterFirst,
            countAfterSecond,
            "Repeat refresh with unchanged inputs must not multiply rows"
        )
    }

    // MARK: - Notification-driven refresh

    func test_refresh_triggers_onSleepSessionsDidChange() {
        deficits.deficitForDave = 2 * hour
        deficits.deficitForBethany = 5 * hour
        sut.beginObserving(planDay: planDay)
        defer { sut.endObserving() }

        let priorCalls = store.shiftsCallCount

        NotificationCenter.default.post(name: .sleepSessionsDidChange, object: nil)

        // Allow synchronous notification delivery.
        XCTAssertGreaterThan(
            store.shiftsCallCount,
            priorCalls,
            "Posting .sleepSessionsDidChange must drive a refresh"
        )
    }

    func test_refresh_triggers_onProposedShiftsDidChange() {
        deficits.deficitForDave = 2 * hour
        deficits.deficitForBethany = 5 * hour
        sut.beginObserving(planDay: planDay)
        defer { sut.endObserving() }

        let priorCalls = store.shiftsCallCount

        NotificationCenter.default.post(name: .proposedShiftsDidChange, object: nil)

        XCTAssertGreaterThan(
            store.shiftsCallCount,
            priorCalls,
            "Posting .proposedShiftsDidChange must drive a refresh"
        )
    }

    // MARK: - EDG-002 integration: one-lane data favors empty-lane parent

    func test_refresh_withOnlyBethanyDepleted_proposesLargerBlockForBethany() {
        deficits.deficitForDave = 0
        deficits.deficitForBethany = 8 * hour

        sut.refresh(forPlanDay: planDay)

        let rows = (try? store.shifts(forPlanDay: planDay)) ?? []
        let bethCount = rows.filter { $0.who == .bethany }.count
        let daveCount = rows.filter { $0.who == .dave }.count
        XCTAssertGreaterThan(
            bethCount,
            daveCount,
            "EDG-002: empty-lane parent (Bethany fully depleted) gets larger block"
        )
    }
}

// MARK: - Stub deficit provider

/// Test double for `DeficitProviding`. Per ADR-002, mocks across actor
/// boundaries use `@unchecked Sendable`. Struct is fine here since all state is
/// value-typed.
final class StubDeficitProvider: DeficitProviding, @unchecked Sendable {
    var deficitForDave: TimeInterval = 0
    var deficitForBethany: TimeInterval = 0

    func deficit24h(
        for person: Person,
        targetHoursPer24h: Double,
        asOf: Date
    ) -> TimeInterval {
        switch person {
        case .dave: return deficitForDave
        case .bethany: return deficitForBethany
        }
    }
}
