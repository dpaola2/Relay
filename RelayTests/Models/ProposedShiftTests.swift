//
//  ProposedShiftTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M1: ProposedShift @Model + Schema +
//  Smoke Test)
//
//  Covers gameplan acceptance criteria:
//    - MDL-001: ProposedShift @Model exists with documented fields + computed
//      `who: Person` with defensive `.dave` fallback (mirrors SleepSession).
//    - MDL-003: Person enum is reused as-is (verified indirectly).
//    - Class invariant: any constructed ProposedShift satisfies
//      `endedAt.timeIntervalSince(startedAt) == 1800` (30 min).
//    - Defensive `who` fallback: a ProposedShift constructed with a corrupt
//      whoRaw value reads back as `.dave`.
//
//  Expected to FAIL until Stage 5 lands `Relay/Models/ProposedShift.swift`.
//  Compile errors here ARE the M1 implementation checklist.
//

import XCTest
@testable import Relay

final class ProposedShiftTests: XCTestCase {

    private let planDay = Date(timeIntervalSince1970: 1_780_000_000)
    private let half: TimeInterval = 1_800 // 30 min

    // MARK: - MDL-001: shape + initialization

    func test_init_setsAllFields_whenAllProvided() {
        let id = UUID()
        let started = planDay.addingTimeInterval(22 * 3_600) // 10pm
        let ended = started.addingTimeInterval(half)
        let created = started.addingTimeInterval(-1)
        let updated = started

        let shift = ProposedShift(
            id: id,
            planDay: planDay,
            who: .bethany,
            startedAt: started,
            endedAt: ended,
            manuallyOverridden: true,
            createdAt: created,
            updatedAt: updated
        )

        XCTAssertEqual(shift.id, id)
        XCTAssertEqual(shift.planDay, planDay)
        XCTAssertEqual(shift.who, .bethany)
        XCTAssertEqual(shift.startedAt, started)
        XCTAssertEqual(shift.endedAt, ended)
        XCTAssertEqual(shift.manuallyOverridden, true)
        XCTAssertEqual(shift.createdAt, created)
        XCTAssertEqual(shift.updatedAt, updated)
    }

    func test_init_defaultsOverrideToFalse() {
        let started = planDay.addingTimeInterval(22 * 3_600)
        let shift = ProposedShift(
            planDay: planDay,
            who: .dave,
            startedAt: started,
            endedAt: started.addingTimeInterval(half)
        )

        XCTAssertFalse(
            shift.manuallyOverridden,
            "Engine-proposed rows should default to manuallyOverridden = false"
        )
    }

    func test_init_persistsWhoAsRawString() {
        let started = planDay.addingTimeInterval(22 * 3_600)
        let dave = ProposedShift(
            planDay: planDay,
            who: .dave,
            startedAt: started,
            endedAt: started.addingTimeInterval(half)
        )
        let beth = ProposedShift(
            planDay: planDay,
            who: .bethany,
            startedAt: started,
            endedAt: started.addingTimeInterval(half)
        )

        XCTAssertEqual(dave.whoRaw, "dave")
        XCTAssertEqual(beth.whoRaw, "bethany")
    }

    // MARK: - MDL-001: `who` bridge round-trip (mirrors SleepSession)

    func test_whoGetter_returnsCorrespondingPersonForRawValue() {
        let started = planDay.addingTimeInterval(22 * 3_600)
        let shift = ProposedShift(
            planDay: planDay,
            who: .dave,
            startedAt: started,
            endedAt: started.addingTimeInterval(half)
        )
        XCTAssertEqual(shift.who, .dave)

        shift.whoRaw = "bethany"
        XCTAssertEqual(shift.who, .bethany)
    }

    func test_whoSetter_writesRawValueBack() {
        let started = planDay.addingTimeInterval(22 * 3_600)
        let shift = ProposedShift(
            planDay: planDay,
            who: .dave,
            startedAt: started,
            endedAt: started.addingTimeInterval(half)
        )
        shift.who = .bethany
        XCTAssertEqual(shift.whoRaw, "bethany")

        shift.who = .dave
        XCTAssertEqual(shift.whoRaw, "dave")
    }

    /// PRD §8 + Discovery Q6 — defensive fallback to `.dave` for corrupt
    /// storage. Mirrors `SleepSession.who` semantics exactly.
    func test_whoGetter_fallsBackToDave_whenRawValueIsCorrupt() {
        let started = planDay.addingTimeInterval(22 * 3_600)
        let shift = ProposedShift(
            planDay: planDay,
            who: .bethany,
            startedAt: started,
            endedAt: started.addingTimeInterval(half)
        )

        shift.whoRaw = "garbage_corrupt_value"

        XCTAssertEqual(
            shift.who,
            .dave,
            "Corrupt whoRaw should fall back to .dave per Discovery Q6"
        )
    }

    // MARK: - Class invariant: endedAt - startedAt == 30 min (1800s)

    func test_classInvariant_endedAtIsExactly30MinutesAfterStartedAt() {
        let started = planDay.addingTimeInterval(22 * 3_600)
        let shift = ProposedShift(
            planDay: planDay,
            who: .dave,
            startedAt: started,
            endedAt: started.addingTimeInterval(half)
        )

        XCTAssertEqual(
            shift.endedAt.timeIntervalSince(shift.startedAt),
            1_800,
            accuracy: 0.001,
            "Class invariant per ADR-001: every cell is exactly 30 minutes"
        )
    }

    // MARK: - Multiple instances per planDay are independent

    func test_distinctInstances_holdIndependentValues() {
        let started1 = planDay.addingTimeInterval(22 * 3_600)
        let started2 = started1.addingTimeInterval(half)

        let s1 = ProposedShift(
            planDay: planDay,
            who: .dave,
            startedAt: started1,
            endedAt: started1.addingTimeInterval(half)
        )
        let s2 = ProposedShift(
            planDay: planDay,
            who: .bethany,
            startedAt: started2,
            endedAt: started2.addingTimeInterval(half)
        )

        XCTAssertNotEqual(s1.id, s2.id)
        XCTAssertEqual(s1.who, .dave)
        XCTAssertEqual(s2.who, .bethany)
        XCTAssertEqual(s2.startedAt.timeIntervalSince(s1.startedAt), half)
    }
}
