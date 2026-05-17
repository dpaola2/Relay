//
//  ForecastEngineTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M2: ForecastEngine + DeficitProviding)
//
//  Covers gameplan acceptance criteria:
//    - ENG-001: ForecastEngine is a `nonisolated struct` with a single
//      `propose(_:)` method.
//    - ENG-002: Inputs struct carries planDay, now, calendar, deficits,
//      targetHoursPer24h, planningWindow, existingShifts.
//    - ENG-003: deficit math is `max(0, target − actual)`; larger-deficit
//      person gets the proposed larger block first.
//    - ENG-004: Planning window divided into two contiguous blocks sized in
//      proportion to relative deficit.
//    - ENG-005: any single block is capped at 5 hours (= 10 half-hour cells);
//      remainder dropped, not redistributed.
//    - ENG-006: engine MUST NOT propose in the afternoon/evening (now → start
//      of planning window).
//    - ENG-007: default planning window is 22:00 planDay → 06:00 planDay+1.
//    - ENG-008: both deficits zero → `[]` (empty proposal surfaces empty state).
//    - ENG-009: engine MUST NOT consult any "who did more" history.
//    - ENG-011: half-hour cells aligned with an existing `manuallyOverridden`
//      ProposedShift are NOT in the returned array; caller preserves those.
//    - EDG-001: zero deficits + empty existingShifts → `[]`.
//    - EDG-002: one-lane sessions → empty-lane parent gets larger block.
//    - EDG-008: DST transition inside planning window — window boundaries
//      computed via components-overlay, NOT `Calendar.date(bySettingHour:of:)`.
//    - DeficitProviding protocol contract.
//
//  Expected to FAIL until Stage 5 lands:
//    (a) `Relay/Services/ForecastEngine.swift`
//    (b) `Relay/Services/DeficitProviding.swift`
//

import XCTest
@testable import Relay

final class ForecastEngineTests: XCTestCase {

    private var calendar: Calendar!

    /// 2026-05-16 (Saturday) midnight UTC — the start-of-day for "tonight."
    private let planDay = Date(timeIntervalSince1970: 1_779_235_200)
    private let hour: TimeInterval = 3_600
    private let half: TimeInterval = 1_800
    private let target: Double = 8.0 // hours

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Standard 22:00 planDay → 06:00 planDay+1 window (ENG-007).
    private var defaultWindow: ForecastEngine.PlanningWindow {
        ForecastEngine.PlanningWindow(startHour: 22, endHour: 6)
    }

    /// "Now" at 4pm planDay — well before the planning window starts.
    private var afternoonNow: Date {
        planDay.addingTimeInterval(16 * hour)
    }

    private func makeInputs(
        deficits: [Person: TimeInterval] = [.dave: 0, .bethany: 0],
        existingShifts: [ProposedShift] = [],
        now: Date? = nil,
        window: ForecastEngine.PlanningWindow? = nil
    ) -> ForecastEngine.Inputs {
        ForecastEngine.Inputs(
            planDay: planDay,
            now: now ?? afternoonNow,
            calendar: calendar,
            deficits: deficits,
            targetHoursPer24h: target,
            planningWindow: window ?? defaultWindow,
            existingShifts: existingShifts
        )
    }

    private func makeShift(
        startedAt: Date,
        who: Person,
        overridden: Bool
    ) -> ProposedShift {
        ProposedShift(
            planDay: planDay,
            who: who,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(half),
            manuallyOverridden: overridden
        )
    }

    // MARK: - ENG-008 / EDG-001: empty inputs → empty proposal

    func test_propose_returnsEmpty_whenBothDeficitsAreZero_andNoExistingShifts() {
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(
            deficits: [.dave: 0, .bethany: 0],
            existingShifts: []
        ))

        XCTAssertTrue(
            cells.isEmpty,
            "Both at target → empty proposal (ENG-008, EDG-001, OQ-5)"
        )
    }

    func test_propose_returnsEmpty_whenDeficitsDictionaryIsEmpty() {
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [:]))
        XCTAssertTrue(cells.isEmpty)
    }

    // MARK: - ENG-003 / ENG-004: deficit math + proportional split

    func test_propose_assignsLargerBlockToHigherDeficitPerson() {
        // Bethany has 3h more deficit than Dave. She gets the larger block.
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 2 * hour,
            .bethany: 5 * hour,
        ]))

        let bethanyCount = cells.filter { $0.who == .bethany }.count
        let daveCount = cells.filter { $0.who == .dave }.count

        XCTAssertGreaterThan(
            bethanyCount,
            daveCount,
            "Higher-deficit person gets the larger block (ENG-003)"
        )
    }

    func test_propose_assignsLargerBlockToDave_whenDavesDeficitIsHigher() {
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 5 * hour,
            .bethany: 1 * hour,
        ]))

        let daveCount = cells.filter { $0.who == .dave }.count
        let bethanyCount = cells.filter { $0.who == .bethany }.count

        XCTAssertGreaterThan(daveCount, bethanyCount)
    }

    func test_propose_dividesWindowIntoTwoContiguousBlocks() {
        // 8-hour window (22:00 → 06:00) = 16 half-hour cells. With both
        // deficits non-zero, all 16 should be assigned, contiguous, one
        // person then the other.
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 2 * hour,
            .bethany: 5 * hour,
        ]))

        // Cells sorted by startedAt.
        let sorted = cells.sorted { $0.startedAt < $1.startedAt }

        // Cells are contiguous: each cell starts 30min after the previous.
        for i in 1..<sorted.count {
            let gap = sorted[i].startedAt.timeIntervalSince(sorted[i - 1].startedAt)
            XCTAssertEqual(
                gap,
                half,
                accuracy: 0.001,
                "Cells must be contiguous (ENG-004) — gap at index \(i)"
            )
        }

        // Exactly two `who` groups, in order: one block then the other.
        let whoRun = sorted.map { $0.who }
        let transitions = zip(whoRun, whoRun.dropFirst()).filter { $0 != $1 }.count
        XCTAssertEqual(
            transitions,
            1,
            "Two contiguous blocks means exactly one who→who transition"
        )
    }

    func test_propose_splitsProportionallyToRelativeDeficit() {
        // Bethany 6h, Dave 2h => ratio 3:1 → Bethany gets 3/4 of 16 cells = 12,
        // Dave gets 4. (Engine rounds toward larger-deficit person.)
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 2 * hour,
            .bethany: 6 * hour,
        ]))

        let bethanyCount = cells.filter { $0.who == .bethany }.count
        let daveCount = cells.filter { $0.who == .dave }.count
        let total = bethanyCount + daveCount

        XCTAssertGreaterThan(bethanyCount, daveCount)
        // Bethany's share should be roughly 3x Dave's. Allow ±1 cell for rounding.
        XCTAssertEqual(
            Double(bethanyCount) / Double(total),
            0.75,
            accuracy: 0.10,
            "Bethany should get ~75% of cells when deficit ratio is 3:1"
        )
    }

    // MARK: - ENG-005: 5-hour cap

    func test_propose_capsSingleBlockAtFiveHours() {
        // Bethany has all the deficit; Dave has zero. Without a cap, Bethany
        // would get the entire 8-hour window (16 cells). The cap drops her
        // block at 10 cells (5 hours); the remainder is NOT redistributed.
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 0,
            .bethany: 8 * hour,
        ]))

        let bethanyCount = cells.filter { $0.who == .bethany }.count
        XCTAssertLessThanOrEqual(
            bethanyCount,
            10,
            "Single block capped at 5 hours = 10 cells (ENG-005)"
        )
    }

    func test_propose_doesNotRedistributeOverflowAcrossPeople() {
        // Dave at zero deficit, Bethany at huge deficit → cap drops Bethany's
        // overflow rather than reassigning the extra cells to Dave.
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 0,
            .bethany: 8 * hour,
        ]))

        let daveCount = cells.filter { $0.who == .dave }.count
        XCTAssertEqual(
            daveCount,
            0,
            "When Dave has zero deficit, no overflow from cap goes to him (ENG-005)"
        )
    }

    // MARK: - ENG-006: no proposals before the planning window

    func test_propose_doesNotEmitCellsBeforePlanningWindowStart() {
        // Window starts 22:00. Now is 16:00. Engine must not propose 16:00..22:00.
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 4 * hour,
            .bethany: 4 * hour,
        ]))

        let windowStart = planDay.addingTimeInterval(22 * hour)
        for cell in cells {
            XCTAssertGreaterThanOrEqual(
                cell.startedAt,
                windowStart,
                "ENG-006: no cells before planning-window start (22:00)"
            )
        }
    }

    // MARK: - ENG-007: default window is 22:00 planDay → 06:00 planDay+1

    func test_propose_planningWindowDefaultsTo22PMto6AM() {
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 4 * hour,
            .bethany: 4 * hour,
        ]))

        let sorted = cells.sorted { $0.startedAt < $1.startedAt }
        guard let first = sorted.first, let last = sorted.last else {
            return XCTFail("Expected at least one cell when both deficits non-zero")
        }

        let windowStart = planDay.addingTimeInterval(22 * hour)
        let windowEnd = planDay.addingTimeInterval((24 + 6) * hour)

        XCTAssertEqual(first.startedAt, windowStart, "First cell starts at 22:00")
        XCTAssertEqual(
            last.endedAt,
            windowEnd,
            "Last cell ends at 06:00 planDay+1 (= 30h after planDay start)"
        )
    }

    // MARK: - ENG-009: NO turn-taking / history / quota math

    func test_propose_ignoresExistingShiftsForBalanceMath_onlyConsultsCurrentDeficits() {
        // Existing rows from yesterday's plan favor Bethany. The engine MUST
        // NOT treat them as "Bethany did more last night, so Dave gets more
        // tonight." Only current deficits matter.
        let yesterdayPlanDay = calendar.date(byAdding: .day, value: -1, to: planDay)!
        let yesterdayShift = ProposedShift(
            planDay: yesterdayPlanDay,
            who: .bethany,
            startedAt: yesterdayPlanDay.addingTimeInterval(22 * hour),
            endedAt: yesterdayPlanDay.addingTimeInterval(22 * hour + half)
        )

        let engine = ForecastEngine()
        // Deficits: Dave 1h, Bethany 5h → Bethany wins.
        let cells = engine.propose(makeInputs(
            deficits: [.dave: 1 * hour, .bethany: 5 * hour],
            existingShifts: [yesterdayShift]
        ))

        let bethanyCount = cells.filter { $0.who == .bethany }.count
        let daveCount = cells.filter { $0.who == .dave }.count
        XCTAssertGreaterThan(
            bethanyCount,
            daveCount,
            "Engine uses ONLY current deficits, not history (ENG-009)"
        )
    }

    // MARK: - ENG-011: overridden cells are skipped, NOT replaced

    func test_propose_excludesCellsAlignedWithManuallyOverriddenShifts() {
        // Two overridden cells at 22:00 and 22:30 (both Dave). Engine output
        // must NOT include cells with those startedAt values — the caller
        // preserves the overrides untouched.
        let windowStart = planDay.addingTimeInterval(22 * hour)
        let overrideA = makeShift(startedAt: windowStart, who: .dave, overridden: true)
        let overrideB = makeShift(
            startedAt: windowStart.addingTimeInterval(half),
            who: .dave,
            overridden: true
        )

        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(
            deficits: [.dave: 2 * hour, .bethany: 6 * hour],
            existingShifts: [overrideA, overrideB]
        ))

        let conflictingStarts = cells.map(\.startedAt).filter {
            $0 == windowStart || $0 == windowStart.addingTimeInterval(half)
        }
        XCTAssertTrue(
            conflictingStarts.isEmpty,
            "Engine output must not include cells whose start aligns with a manuallyOverridden row (ENG-011)"
        )
    }

    func test_propose_doesNotSkipNonOverriddenExistingShifts() {
        // A non-overridden existing shift is engine-controlled and MAY be
        // replaced on re-run. The engine's output covers that cell normally.
        let windowStart = planDay.addingTimeInterval(22 * hour)
        let nonOverride = makeShift(startedAt: windowStart, who: .dave, overridden: false)

        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(
            deficits: [.dave: 2 * hour, .bethany: 6 * hour],
            existingShifts: [nonOverride]
        ))

        let hasFirstCell = cells.contains { $0.startedAt == windowStart }
        XCTAssertTrue(
            hasFirstCell,
            "Non-overridden existing shifts do not block engine re-emission (ENG-011)"
        )
    }

    // MARK: - EDG-002: one-lane data → empty-lane parent gets the larger block

    func test_propose_givesLargerBlockToEmptyLaneParent() {
        // Bethany is fully depleted (deficit == target). Dave is at zero
        // deficit (he slept 8h). Bethany should get the larger block.
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 0,
            .bethany: target * 3_600,
        ]))

        let bethanyCount = cells.filter { $0.who == .bethany }.count
        let daveCount = cells.filter { $0.who == .dave }.count
        XCTAssertGreaterThan(
            bethanyCount,
            daveCount,
            "EDG-002: empty-lane parent (fully depleted) gets the larger block"
        )
    }

    // MARK: - Half-hour cell invariant

    func test_propose_eachCellIsExactly30Minutes() {
        let engine = ForecastEngine()
        let cells = engine.propose(makeInputs(deficits: [
            .dave: 3 * hour,
            .bethany: 5 * hour,
        ]))

        for cell in cells {
            XCTAssertEqual(
                cell.endedAt.timeIntervalSince(cell.startedAt),
                half,
                accuracy: 0.001,
                "Every cell is exactly 30 minutes (ADR-001)"
            )
        }
    }

    // MARK: - EDG-008: DST transition inside the planning window

    /// PIN: this test catches the `Calendar.date(bySettingHour:of:)` footgun.
    /// US spring-forward 2026 is Sunday 2026-03-08 at 02:00 local time. The
    /// planning window 22:00 Sat → 06:00 Sun straddles the transition. If the
    /// engine uses `bySettingHour` with `.forward` semantics, anchoring "06:00
    /// Sunday" silently rolls to the next day. Tests use America/New_York to
    /// observe DST behavior; window MUST be computed via the components-
    /// overlay pattern (`Calendar.date(from: components)`).
    func test_propose_windowBoundariesAreCorrect_aroundUSSpringForwardDST() {
        var dstCalendar = Calendar(identifier: .gregorian)
        dstCalendar.timeZone = TimeZone(identifier: "America/New_York")!

        // 2026-03-07 (Saturday) local midnight in America/New_York.
        // EST is UTC-5; midnight EST = 05:00 UTC.
        // 2026-03-07 05:00:00 UTC.
        let dstPlanDay = Date(timeIntervalSince1970: 1_772_866_800)

        let dstAfternoon = dstPlanDay.addingTimeInterval(16 * hour)

        let inputs = ForecastEngine.Inputs(
            planDay: dstPlanDay,
            now: dstAfternoon,
            calendar: dstCalendar,
            deficits: [.dave: 3 * hour, .bethany: 5 * hour],
            targetHoursPer24h: target,
            planningWindow: ForecastEngine.PlanningWindow(startHour: 22, endHour: 6),
            existingShifts: []
        )

        let engine = ForecastEngine()
        let cells = engine.propose(inputs)

        let sorted = cells.sorted { $0.startedAt < $1.startedAt }
        guard let first = sorted.first, let last = sorted.last else {
            return XCTFail("Expected cells across DST window")
        }

        // First cell must be 22:00 LOCAL on planDay — not rolled forward.
        let firstComps = dstCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: first.startedAt
        )
        XCTAssertEqual(firstComps.year, 2026)
        XCTAssertEqual(firstComps.month, 3)
        XCTAssertEqual(firstComps.day, 7, "First cell on planDay (Saturday March 7)")
        XCTAssertEqual(firstComps.hour, 22)
        XCTAssertEqual(firstComps.minute, 0)

        // Last cell endedAt must be 06:00 LOCAL on planDay+1 (Sunday) —
        // even though DST spring-forward erases the 02:00→03:00 hour locally.
        let lastComps = dstCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: last.endedAt
        )
        XCTAssertEqual(lastComps.year, 2026)
        XCTAssertEqual(lastComps.month, 3)
        XCTAssertEqual(
            lastComps.day,
            8,
            "Last cell ends on Sunday March 8 — NOT rolled forward to Monday"
        )
        XCTAssertEqual(lastComps.hour, 6)
        XCTAssertEqual(lastComps.minute, 0)
    }

    // MARK: - ENG-001: ForecastEngine.propose returns Equatable cells

    func test_proposedHalfHour_isEquatable() {
        let started = planDay.addingTimeInterval(22 * hour)
        let a = ForecastEngine.ProposedHalfHour(
            startedAt: started,
            endedAt: started.addingTimeInterval(half),
            who: .dave
        )
        let b = ForecastEngine.ProposedHalfHour(
            startedAt: started,
            endedAt: started.addingTimeInterval(half),
            who: .dave
        )
        let c = ForecastEngine.ProposedHalfHour(
            startedAt: started,
            endedAt: started.addingTimeInterval(half),
            who: .bethany
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

// MARK: - DeficitProviding protocol contract

/// Verifies the `DeficitProviding` protocol exists with the documented surface
/// and is `Sendable`. A trivial test conformer proves the signature compiles.
final class DeficitProvidingProtocolTests: XCTestCase {

    /// Test conformer — purely a compile-time / contract check.
    private struct StubDeficitProvider: DeficitProviding {
        let value: TimeInterval
        func deficit24h(
            for person: Person,
            targetHoursPer24h: Double,
            asOf: Date
        ) -> TimeInterval {
            value
        }
    }

    func test_deficitProviding_protocolHasDocumentedSignature() {
        let provider: any DeficitProviding = StubDeficitProvider(value: 5 * 3_600)
        let d = provider.deficit24h(
            for: .dave,
            targetHoursPer24h: 8.0,
            asOf: Date(timeIntervalSince1970: 1_780_000_000)
        )
        XCTAssertEqual(d, 5 * 3_600, accuracy: 0.001)
    }
}
