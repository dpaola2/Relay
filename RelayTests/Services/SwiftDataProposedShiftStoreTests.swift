//
//  SwiftDataProposedShiftStoreTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M3: ProposedShiftStore protocol +
//  SwiftData concrete + InMemory mock)
//
//  Covers gameplan acceptance criteria:
//    - `ProposedShiftStore` protocol exists with the documented surface:
//      `shifts(forPlanDay:)`, `upsert(planDay:startedAt:who:manuallyOverridden:)`,
//      `cycle(planDay:startedAt:currentEngineProposal:)`, `delete(_:)`,
//      `prune(olderThan:)`.
//    - `SwiftDataProposedShiftStore` concrete: `@unchecked Sendable`, treats
//      `ModelContext` as single-threaded.
//    - `Notification.Name.proposedShiftsDidChange` posted after every write.
//    - `upsert(...)` is idempotent on `(planDay, startedAt)` — calling twice
//      with the same args creates one row.
//    - `cycle(...)`: Dave → Bethany → unassigned → engine-proposal (ADJ-001 +
//      ADJ-003). Returning to engine-proposed assignment clears
//      `manuallyOverridden`.
//    - `prune(olderThan:)` deletes rows with `planDay < cutoffPlanDay`.
//    - Defensive `whoRaw` fallback round-trip.
//
//  Tests will FAIL until Stage 5 lands:
//    (a) `Relay/Services/ProposedShiftStore.swift` (protocol +
//        `.proposedShiftsDidChange` declaration)
//    (b) `Relay/Services/SwiftDataProposedShiftStore.swift` (concrete)
//    (c) `Relay/Services/ProposedShiftStore+Environment.swift` (env key)
//

import XCTest
import SwiftData
@testable import Relay

final class SwiftDataProposedShiftStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var sut: SwiftDataProposedShiftStore!

    private let planDay = Date(timeIntervalSince1970: 1_780_000_000)
    private let half: TimeInterval = 1_800
    private let hour: TimeInterval = 3_600

    override func setUpWithError() throws {
        try super.setUpWithError()
        let schema = Schema([SleepSession.self, ProposedShift.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        sut = SwiftDataProposedShiftStore(context: ModelContext(container))
    }

    override func tearDown() {
        sut = nil
        container = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var firstCellStart: Date {
        planDay.addingTimeInterval(22 * hour) // 22:00 planDay
    }

    // MARK: - upsert: insert path

    func test_upsert_insertsNewRow_whenNoneExists() throws {
        let shift = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )

        XCTAssertEqual(shift.planDay, planDay)
        XCTAssertEqual(shift.who, .dave)
        XCTAssertEqual(shift.startedAt, firstCellStart)
        XCTAssertEqual(
            shift.endedAt.timeIntervalSince(shift.startedAt),
            half,
            accuracy: 0.001,
            "Store-created row must satisfy the 30-min invariant"
        )
        XCTAssertFalse(shift.manuallyOverridden)

        let all = try sut.shifts(forPlanDay: planDay)
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - upsert: idempotent on composite (planDay, startedAt)

    func test_upsert_isIdempotent_onCompositeKey() throws {
        _ = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )
        _ = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )

        let all = try sut.shifts(forPlanDay: planDay)
        XCTAssertEqual(
            all.count,
            1,
            "Repeat upsert on (planDay, startedAt) updates in place — no duplicates"
        )
    }

    func test_upsert_updatesFields_onSecondCall() throws {
        _ = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )
        _ = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .bethany,
            manuallyOverridden: true
        )

        let all = try sut.shifts(forPlanDay: planDay)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.who, .bethany)
        XCTAssertTrue(all.first?.manuallyOverridden ?? false)
    }

    // MARK: - shifts(forPlanDay:) — scoping

    func test_shifts_forPlanDay_returnsOnlyThatDaysRows() throws {
        _ = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )
        let otherDay = planDay.addingTimeInterval(24 * hour)
        _ = try sut.upsert(
            planDay: otherDay,
            startedAt: otherDay.addingTimeInterval(22 * hour),
            who: .bethany,
            manuallyOverridden: false
        )

        let today = try sut.shifts(forPlanDay: planDay)
        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today.first?.who, .dave)
    }

    func test_shifts_forPlanDay_returnsRowsSortedByStartedAt() throws {
        let s2 = firstCellStart.addingTimeInterval(half)
        let s3 = firstCellStart.addingTimeInterval(2 * half)
        _ = try sut.upsert(planDay: planDay, startedAt: s3, who: .dave, manuallyOverridden: false)
        _ = try sut.upsert(planDay: planDay, startedAt: firstCellStart, who: .dave, manuallyOverridden: false)
        _ = try sut.upsert(planDay: planDay, startedAt: s2, who: .dave, manuallyOverridden: false)

        let all = try sut.shifts(forPlanDay: planDay)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].startedAt, firstCellStart)
        XCTAssertEqual(all[1].startedAt, s2)
        XCTAssertEqual(all[2].startedAt, s3)
    }

    // MARK: - delete

    func test_delete_removesRow() throws {
        let shift = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )

        try sut.delete(shift)

        let all = try sut.shifts(forPlanDay: planDay)
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - prune(olderThan:)

    func test_prune_removesRowsWithPlanDayBeforeCutoff() throws {
        let oldDay = planDay.addingTimeInterval(-10 * 24 * hour)
        let recentDay = planDay.addingTimeInterval(-2 * 24 * hour)
        _ = try sut.upsert(
            planDay: oldDay,
            startedAt: oldDay.addingTimeInterval(22 * hour),
            who: .dave,
            manuallyOverridden: false
        )
        _ = try sut.upsert(
            planDay: recentDay,
            startedAt: recentDay.addingTimeInterval(22 * hour),
            who: .bethany,
            manuallyOverridden: false
        )

        let cutoff = planDay.addingTimeInterval(-6 * 24 * hour)
        try sut.prune(olderThan: cutoff)

        let oldRows = try sut.shifts(forPlanDay: oldDay)
        let recentRows = try sut.shifts(forPlanDay: recentDay)
        XCTAssertTrue(oldRows.isEmpty, "Rows with planDay < cutoff are pruned")
        XCTAssertEqual(recentRows.count, 1, "Rows with planDay >= cutoff remain")
    }

    // MARK: - cycle: Dave → Bethany → unassigned → engine-proposal

    func test_cycle_unassignedCell_assignsToCurrentEngineProposal() throws {
        // Cell starts unassigned (no row). Engine proposes Dave. First tap
        // cycles unassigned → engine-proposal (Dave). Override should be
        // cleared because the new state equals the engine proposal.
        let result = try sut.cycle(
            planDay: planDay,
            startedAt: firstCellStart,
            currentEngineProposal: .dave
        )

        XCTAssertEqual(result?.who, .dave)
        XCTAssertEqual(
            result?.manuallyOverridden,
            false,
            "Returning to engine-proposed assignment clears override (ADJ-003)"
        )
    }

    func test_cycle_daveCell_advancesToBethany_andSetsOverride() throws {
        _ = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )

        let result = try sut.cycle(
            planDay: planDay,
            startedAt: firstCellStart,
            currentEngineProposal: .dave
        )

        XCTAssertEqual(result?.who, .bethany)
        XCTAssertTrue(
            result?.manuallyOverridden ?? false,
            "User-driven advance from engine state sets override (ADJ-002)"
        )
    }

    func test_cycle_bethanyCell_advancesToUnassigned_returnsNil() throws {
        _ = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .bethany,
            manuallyOverridden: true
        )

        let result = try sut.cycle(
            planDay: planDay,
            startedAt: firstCellStart,
            currentEngineProposal: .dave
        )

        XCTAssertNil(result, "Bethany → unassigned cycles to nil")
        let all = try sut.shifts(forPlanDay: planDay)
        XCTAssertTrue(
            all.isEmpty,
            "Unassigned state deletes the underlying row"
        )
    }

    func test_cycle_clearsOverride_whenReturnedToEngineAssignment() throws {
        // Full 4-step rotation: start at engine state (Dave, override=false).
        // Tap → Bethany override. Tap → unassigned. Tap → Dave (back to engine
        // assignment) → override cleared.
        _ = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )

        _ = try sut.cycle(planDay: planDay, startedAt: firstCellStart, currentEngineProposal: .dave) // → Bethany
        _ = try sut.cycle(planDay: planDay, startedAt: firstCellStart, currentEngineProposal: .dave) // → unassigned
        let final = try sut.cycle(planDay: planDay, startedAt: firstCellStart, currentEngineProposal: .dave) // → Dave

        XCTAssertEqual(final?.who, .dave)
        XCTAssertEqual(
            final?.manuallyOverridden,
            false,
            "ADJ-003: re-cycling to engine state clears the override flag"
        )
    }

    // MARK: - Notification: posts on every write

    func test_upsert_postsProposedShiftsDidChangeNotification() throws {
        let expectation = self.expectation(forNotification: .proposedShiftsDidChange, object: nil)

        _ = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )

        wait(for: [expectation], timeout: 1.0)
    }

    func test_delete_postsProposedShiftsDidChangeNotification() throws {
        let shift = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .dave,
            manuallyOverridden: false
        )

        let expectation = self.expectation(forNotification: .proposedShiftsDidChange, object: nil)

        try sut.delete(shift)

        wait(for: [expectation], timeout: 1.0)
    }

    func test_prune_postsProposedShiftsDidChangeNotification() throws {
        let expectation = self.expectation(forNotification: .proposedShiftsDidChange, object: nil)

        try sut.prune(olderThan: planDay)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Defensive whoRaw fallback round-trips through SwiftData

    func test_corruptWhoRaw_roundTripsAsDave() throws {
        let shift = try sut.upsert(
            planDay: planDay,
            startedAt: firstCellStart,
            who: .bethany,
            manuallyOverridden: false
        )

        // Simulate storage corruption by mutating the persisted raw value.
        shift.whoRaw = "garbage_corrupt_value"

        let all = try sut.shifts(forPlanDay: planDay)
        XCTAssertEqual(
            all.first?.who,
            .dave,
            "Corrupt whoRaw must defensively read back as .dave"
        )
    }
}
