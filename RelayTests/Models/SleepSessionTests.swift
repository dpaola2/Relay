//
//  SleepSessionTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M2: Domain Model & Persistence)
//
//  Covers gameplan acceptance criteria:
//    - DAT-001: SleepSession shape (id, whoRaw, startedAt, endedAt?, note?,
//      createdAt, updatedAt) + computed `who: Person`, `isOpen: Bool`,
//      `duration(asOf:)`.
//    - DAT-005-relaxed: per-person open invariant is enforced at the view-model
//      and store layer, not in the model. The model itself only carries
//      `endedAt: Date?` semantics.
//    - PRD §8 edge case: `who` falls back to `.dave` if `whoRaw` is corrupt.
//
//  All tests are expected to FAIL until M2 lands `Relay/Models/SleepSession.swift`
//  and `Relay/Models/Person.swift`. Compile errors here ARE the M2 implementation
//  checklist.
//

import XCTest
@testable import Relay

final class SleepSessionTests: XCTestCase {

    // MARK: - DAT-001: shape + initialization

    func test_init_setsAllFields_whenAllProvided() {
        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_780_000_000)
        let ended = started.addingTimeInterval(3_600)

        let s = SleepSession(
            id: id,
            who: .bethany,
            startedAt: started,
            endedAt: ended,
            note: "with Jo",
            createdAt: started,
            updatedAt: ended
        )

        XCTAssertEqual(s.id, id)
        XCTAssertEqual(s.who, .bethany)
        XCTAssertEqual(s.startedAt, started)
        XCTAssertEqual(s.endedAt, ended)
        XCTAssertEqual(s.note, "with Jo")
        XCTAssertEqual(s.createdAt, started)
        XCTAssertEqual(s.updatedAt, ended)
    }

    func test_init_defaultsEndedAtToNil_forOpenSession() {
        let s = SleepSession(who: .dave, startedAt: .now)
        XCTAssertNil(s.endedAt)
        XCTAssertNil(s.note)
    }

    func test_init_persistsWhoAsRawString() {
        let dave = SleepSession(who: .dave, startedAt: .now)
        let beth = SleepSession(who: .bethany, startedAt: .now)
        XCTAssertEqual(dave.whoRaw, "dave")
        XCTAssertEqual(beth.whoRaw, "bethany")
    }

    // MARK: - DAT-001: `who` bridge round-trip

    func test_whoGetter_returnsCorrespondingPersonForRawValue() {
        let s = SleepSession(who: .dave, startedAt: .now)
        XCTAssertEqual(s.who, .dave)

        s.whoRaw = "bethany"
        XCTAssertEqual(s.who, .bethany)
    }

    func test_whoSetter_writesRawValueBack() {
        let s = SleepSession(who: .dave, startedAt: .now)
        s.who = .bethany
        XCTAssertEqual(s.whoRaw, "bethany")

        s.who = .dave
        XCTAssertEqual(s.whoRaw, "dave")
    }

    /// PRD §8 + Architecture §1.3 — defensive fallback when storage is corrupt.
    func test_whoGetter_fallsBackToDave_whenRawValueIsCorrupt() {
        let s = SleepSession(who: .bethany, startedAt: .now)
        s.whoRaw = "garbage_corrupt_value"
        XCTAssertEqual(s.who, .dave, "Corrupt whoRaw should fall back to .dave per Arch §1.3")
    }

    // MARK: - DAT-001: `isOpen` derivation

    func test_isOpen_isTrue_whenEndedAtIsNil() {
        let s = SleepSession(who: .dave, startedAt: .now, endedAt: nil)
        XCTAssertTrue(s.isOpen)
    }

    func test_isOpen_isFalse_whenEndedAtIsSet() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let s = SleepSession(who: .dave, startedAt: start, endedAt: start.addingTimeInterval(60))
        XCTAssertFalse(s.isOpen)
    }

    // MARK: - DAT-001: `duration(asOf:)` math

    func test_duration_returnsEndedMinusStarted_forClosedSession() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let end = start.addingTimeInterval(3_600) // 1h
        let s = SleepSession(who: .dave, startedAt: start, endedAt: end)

        XCTAssertEqual(s.duration(asOf: .now), 3_600, accuracy: 0.001)
    }

    /// TOT-003 / TIM-005 — open sessions count their elapsed-so-far portion via
    /// `duration(asOf:)`. The reference date stands in for "now."
    func test_duration_usesReferenceDate_forOpenSession() {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let s = SleepSession(who: .dave, startedAt: start, endedAt: nil)
        let refNow = start.addingTimeInterval(1_800) // 30m later

        XCTAssertEqual(s.duration(asOf: refNow), 1_800, accuracy: 0.001)
    }

    func test_duration_returnsZero_whenReferenceDateIsBeforeStart() {
        // Defensive: a clock-rewind shouldn't produce a negative duration.
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let s = SleepSession(who: .dave, startedAt: start, endedAt: nil)
        let refBefore = start.addingTimeInterval(-100)

        XCTAssertEqual(s.duration(asOf: refBefore), 0, accuracy: 0.001)
    }

    // MARK: - PRD §8 edge case: DST-spanning duration is correct from Date math

    func test_duration_spanningDST_isCorrect_fromDateMath() {
        // Two `Date` instants 8 hours apart in absolute time, regardless of
        // wall-clock DST jumps. PRD §8: "Date math is sufficient."
        let start = Date(timeIntervalSince1970: 1_710_046_800) // arbitrary instant
        let end = start.addingTimeInterval(8 * 3_600)
        let s = SleepSession(who: .dave, startedAt: start, endedAt: end)

        XCTAssertEqual(s.duration(asOf: .now), 8 * 3_600, accuracy: 0.001)
    }
}
