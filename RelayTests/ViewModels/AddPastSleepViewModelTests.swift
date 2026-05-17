//
//  AddPastSleepViewModelTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (RELAY-2 / Milestone M1: AddPastSleepViewModel)
//
//  Covers gameplan acceptance criteria for the headless view model that
//  powers the "Add Past Sleep" sheet:
//
//    - DEF-001 — sticky `Who` default derived from `store.sessions(in: last 24h)`,
//                newest-first, with `.dave` cold-start (ADR-002).
//    - DEF-002 / DEF-003 — `startedAt` defaults to yesterday 11pm; `endedAt`
//                          defaults to today 7am in the injected `Calendar`.
//    - DEF-004 — defaults are computed at VM-init (sheet-open), not at app launch.
//    - VAL-001 — `endBeforeStart` when `startedAt >= endedAt`; Save disabled.
//    - VAL-002 — `startOutsideSevenDayWindow` when `startedAt < clock.now - 7d`.
//    - VAL-003 — `endInFuture` when `endedAt > clock.now`.
//    - VAL priority — `endBeforeStart` > `endInFuture` > `startOutsideSevenDayWindow`.
//    - VAL-004 — `validationMessage` returns `ValidationError.helperCopy` when
//                invalid; `nil` when valid.
//    - VAL-005 — validation surfaces only via `isSaveEnabled` + `validationMessage`.
//    - STO-001 — `save()` calls `startSession(for:at:)` then
//                `update(_:startedAt:endedAt:who:note:)` with the right args.
//    - STO-001 (note empty) / STO-001 (note non-empty) — note `.isEmpty` writes
//                `nil`; otherwise `.some(note)`.
//    - STO-002 — persisted row is byte-identical to a Now-captured session
//                (no provenance flag, just `who` + `startedAt` + `endedAt` + `note`).
//    - STO-005 — `save()` does NOT consult open sessions for the same person.
//    - STO (validation guard) — `save()` is a no-op when `validationError != nil`.
//    - PRD §8 edge cases — exact-equality (`start == end`) rejected; empty note
//                          rules; first-ever launch (no prior taps) is cold-start.
//
//  Will FAIL until Stage 5 lands `Relay/ViewModels/AddPastSleepViewModel.swift`.
//
//  Mocks (`InMemorySleepSessionStore`, `FakeClock`) declare `@unchecked Sendable`
//  per CLAUDE.md §6 — the `RelayTests` target does NOT inherit
//  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so this test class stays
//  unannotated and runs off the main actor.
//

import XCTest
@testable import Relay

final class AddPastSleepViewModelTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private var clock: FakeClock!

    // A deterministic anchor: 2026-05-16 at 14:00 UTC. We choose a UTC calendar
    // throughout so "yesterday 11pm → today 7am" tests don't drift on the CI
    // machine's local TZ.
    private let now = Date(timeIntervalSince1970: 1_778_940_000)

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private let hour: TimeInterval = 3_600
    private let day: TimeInterval = 24 * 3_600

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

    // MARK: - Helper

    private func makeSUT(
        store overrideStore: InMemorySleepSessionStore? = nil,
        clock overrideClock: FakeClock? = nil
    ) -> AddPastSleepViewModel {
        AddPastSleepViewModel(
            store: overrideStore ?? store,
            clock: overrideClock ?? clock,
            calendar: utcCalendar
        )
    }

    // ========================================================================
    // MARK: - DEF-002 / DEF-003 / DEF-004: time defaults at sheet-open
    // ========================================================================

    /// DEF-002: `startedAt` defaults to yesterday 11pm in the injected calendar.
    func test_init_startedAtDefaultsToYesterday11pm_inInjectedCalendar() {
        let sut = makeSUT()

        let components = utcCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: sut.startedAt
        )
        // `now` is 2026-05-16 14:00 UTC, so "yesterday 11pm" is 2026-05-15 23:00.
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 23)
        XCTAssertEqual(components.minute, 0)
    }

    /// DEF-003: `endedAt` defaults to today 7am in the injected calendar.
    func test_init_endedAtDefaultsToToday7am_inInjectedCalendar() {
        let sut = makeSUT()

        let components = utcCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: sut.endedAt
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 16)
        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 0)
    }

    /// DEF-004: defaults are computed at VM-init time, not captured at app launch.
    /// Advancing the clock between two constructions produces different defaults.
    func test_init_defaultsAreComputedAtInit_notAtAppLaunch() {
        let earlySUT = makeSUT()

        // Advance the clock by one day; construct again.
        clock.advance(by: day)
        let laterSUT = makeSUT()

        XCTAssertNotEqual(
            earlySUT.startedAt,
            laterSUT.startedAt,
            "DEF-004: a FakeClock advance between two inits must move the default"
        )
        XCTAssertNotEqual(earlySUT.endedAt, laterSUT.endedAt)
    }

    /// Defaults span exactly 8 hours (23:00 → 07:00) — sanity check on the
    /// "common case is 2-tap entry" claim in the pitch.
    func test_init_defaultDurationIsEightHours() {
        let sut = makeSUT()
        let expected: TimeInterval = 8 * hour
        XCTAssertEqual(sut.endedAt.timeIntervalSince(sut.startedAt), expected, accuracy: 1.0)
    }

    // ========================================================================
    // MARK: - DEF-001: sticky `Who` default (ADR-002)
    // ========================================================================

    /// DEF-001 cold-start: when the store has no sessions in the last 24h,
    /// `who` defaults to `.dave`.
    func test_init_who_defaultsToDave_whenStoreEmpty() {
        let sut = makeSUT()
        XCTAssertEqual(sut.who, .dave)
    }

    /// DEF-001 sticky: when the most-recent session within 24h belongs to
    /// Bethany, `who` defaults to Bethany.
    func test_init_who_isSticky_toBethany_whenBethanyHasRecentSession() throws {
        // Bethany started a session 1h ago — the only recent activity.
        _ = try store.startSession(for: .bethany, at: now.addingTimeInterval(-1 * hour))

        let sut = makeSUT()
        XCTAssertEqual(sut.who, .bethany, "DEF-001 sticky: should follow the most recent within-24h `who`")
    }

    /// DEF-001 sticky: when both people have sessions in the last 24h,
    /// `who` follows the one with the latest `startedAt` (newest-first).
    func test_init_who_isSticky_toLatestStartedSession_acrossPeople() throws {
        _ = try store.startSession(for: .dave, at: now.addingTimeInterval(-12 * hour))
        _ = try store.startSession(for: .bethany, at: now.addingTimeInterval(-3 * hour))

        let sut = makeSUT()
        XCTAssertEqual(sut.who, .bethany, "DEF-001: newest startedAt wins")
    }

    /// DEF-001 boundary: sessions older than 24h do NOT influence the default.
    func test_init_who_ignoresSessions_olderThan24Hours() throws {
        // 25h ago — outside the 24h sticky window.
        _ = try store.startSession(for: .bethany, at: now.addingTimeInterval(-25 * hour))

        let sut = makeSUT()
        XCTAssertEqual(sut.who, .dave, "Sessions older than 24h are not sticky anchors")
    }

    /// DEF-001 resilience: if `store.sessions(in:)` throws, `who` falls back
    /// to `.dave` without crashing the VM init.
    func test_init_who_fallsBackToDave_whenStoreSessionsThrows() {
        let throwingStore = ThrowingSleepSessionStore()
        let sut = AddPastSleepViewModel(
            store: throwingStore,
            clock: clock,
            calendar: utcCalendar
        )
        XCTAssertEqual(sut.who, .dave, "Throwing store must not crash; falls back to .dave")
    }

    // ========================================================================
    // MARK: - VAL-001: endBeforeStart
    // ========================================================================

    func test_validation_endBeforeStart_whenStartIsAfterEnd() {
        let sut = makeSUT()
        // Defaults are 11pm yesterday → 7am today. Swap them.
        let originalStart = sut.startedAt
        let originalEnd = sut.endedAt
        sut.startedAt = originalEnd        // 7am
        sut.endedAt = originalStart        // yesterday 11pm — now BEFORE start

        XCTAssertEqual(sut.validationError, .endBeforeStart)
        XCTAssertFalse(sut.isSaveEnabled)
    }

    /// PRD §8: `Fell asleep` exactly equal to `Woke up` is also rejected
    /// (Save disabled — duration must be > 0).
    func test_validation_endBeforeStart_whenStartEqualsEnd() {
        let sut = makeSUT()
        sut.startedAt = now.addingTimeInterval(-3 * hour)
        sut.endedAt = now.addingTimeInterval(-3 * hour)

        XCTAssertEqual(sut.validationError, .endBeforeStart, "start == end is treated as endBeforeStart")
        XCTAssertFalse(sut.isSaveEnabled)
    }

    // ========================================================================
    // MARK: - VAL-002: startOutsideSevenDayWindow
    // ========================================================================

    func test_validation_startOutsideSevenDayWindow_whenStartIs8DaysAgo() {
        let sut = makeSUT()
        sut.startedAt = now.addingTimeInterval(-8 * day)
        sut.endedAt = now.addingTimeInterval(-8 * day + hour)

        XCTAssertEqual(sut.validationError, .startOutsideSevenDayWindow)
        XCTAssertFalse(sut.isSaveEnabled)
    }

    /// Boundary: `startedAt` exactly at the 7-day cutoff is INCLUDED (>=).
    func test_validation_startedAtExactly7DaysAgo_isAllowed() {
        let sut = makeSUT()
        sut.startedAt = now.addingTimeInterval(-7 * day)
        sut.endedAt = now.addingTimeInterval(-7 * day + hour)

        XCTAssertNil(sut.validationError, "startedAt == now - 7d is inside the window (>=)")
        XCTAssertTrue(sut.isSaveEnabled)
    }

    // ========================================================================
    // MARK: - VAL-003: endInFuture
    // ========================================================================

    func test_validation_endInFuture_whenEndIsLaterThanClockNow() {
        let sut = makeSUT()
        sut.startedAt = now.addingTimeInterval(-hour)
        sut.endedAt = now.addingTimeInterval(hour)

        XCTAssertEqual(sut.validationError, .endInFuture)
        XCTAssertFalse(sut.isSaveEnabled)
    }

    /// Boundary: `endedAt == clock.now` exactly is allowed (`>`, not `>=`).
    func test_validation_endedAtExactlyAtClockNow_isAllowed() {
        let sut = makeSUT()
        sut.startedAt = now.addingTimeInterval(-hour)
        sut.endedAt = now

        XCTAssertNil(sut.validationError, "endedAt == clock.now is allowed (strict future check)")
        XCTAssertTrue(sut.isSaveEnabled)
    }

    // ========================================================================
    // MARK: - Validation priority (endBeforeStart > endInFuture > windowOutside)
    // ========================================================================

    /// When `start >= end` AND `end > now`, `endBeforeStart` wins.
    func test_validation_priority_endBeforeStartWinsOverEndInFuture() {
        let sut = makeSUT()
        // start = now + 2h, end = now + 1h → start > end AND end > now.
        sut.startedAt = now.addingTimeInterval(2 * hour)
        sut.endedAt = now.addingTimeInterval(hour)

        XCTAssertEqual(sut.validationError, .endBeforeStart,
                       "endBeforeStart has highest priority")
    }

    /// When `end > now` AND `start < now - 7d`, `endInFuture` wins.
    func test_validation_priority_endInFutureWinsOverStartOutsideWindow() {
        let sut = makeSUT()
        sut.startedAt = now.addingTimeInterval(-8 * day)
        sut.endedAt = now.addingTimeInterval(hour)

        XCTAssertEqual(sut.validationError, .endInFuture,
                       "endInFuture has priority over startOutsideSevenDayWindow")
    }

    // ========================================================================
    // MARK: - VAL-004: validationMessage mirrors ValidationError.helperCopy
    // ========================================================================

    func test_validationMessage_returnsHelperCopy_whenInvalid() {
        let sut = makeSUT()
        sut.startedAt = now
        sut.endedAt = now.addingTimeInterval(-hour) // end before start

        guard let message = sut.validationMessage else {
            return XCTFail("Expected non-nil validationMessage when invalid")
        }
        XCTAssertEqual(
            message,
            AddPastSleepViewModel.ValidationError.endBeforeStart.helperCopy,
            "validationMessage must mirror ValidationError.helperCopy exactly"
        )
    }

    func test_validationMessage_returnsNil_whenValid() {
        let sut = makeSUT()
        // Defaults are within window, end after start, end before now (yesterday 11p → today 7a,
        // and `now` is 14:00 — so 7am is in the past). Valid.
        XCTAssertNil(sut.validationError)
        XCTAssertNil(sut.validationMessage)
    }

    /// VAL-004: each `ValidationError` case provides distinct helper copy.
    func test_validationError_helperCopy_isDistinct_perCase() {
        let copies: Set<String> = [
            AddPastSleepViewModel.ValidationError.endBeforeStart.helperCopy,
            AddPastSleepViewModel.ValidationError.endInFuture.helperCopy,
            AddPastSleepViewModel.ValidationError.startOutsideSevenDayWindow.helperCopy
        ]
        XCTAssertEqual(copies.count, 3, "Each ValidationError case must have a distinct helperCopy")
    }

    /// VAL-004: helper copy is non-empty for every case (testing surface, not
    /// exact wording — Stage 5 may tune copy per PRD Q5).
    func test_validationError_helperCopy_isNonEmpty_perCase() {
        XCTAssertFalse(AddPastSleepViewModel.ValidationError.endBeforeStart.helperCopy.isEmpty)
        XCTAssertFalse(AddPastSleepViewModel.ValidationError.endInFuture.helperCopy.isEmpty)
        XCTAssertFalse(AddPastSleepViewModel.ValidationError.startOutsideSevenDayWindow.helperCopy.isEmpty)
    }

    // ========================================================================
    // MARK: - VAL-005: isSaveEnabled is the only validation affordance
    // ========================================================================

    func test_isSaveEnabled_mirrorsValidationErrorIsNil() {
        let sut = makeSUT()
        XCTAssertTrue(sut.isSaveEnabled, "Defaults are valid → save enabled")
        XCTAssertNil(sut.validationError)

        // Break validity.
        sut.endedAt = sut.startedAt.addingTimeInterval(-hour)
        XCTAssertFalse(sut.isSaveEnabled, "End before start → save disabled")
        XCTAssertNotNil(sut.validationError)
    }

    // ========================================================================
    // MARK: - `duration` (UI-005)
    // ========================================================================

    func test_duration_returnsEndMinusStart() {
        let sut = makeSUT()
        let expected = sut.endedAt.timeIntervalSince(sut.startedAt)
        XCTAssertEqual(sut.duration, expected, accuracy: 1.0)
    }

    /// `duration` can be negative when start > end — the UI layer decides
    /// how to render that case (per gameplan M4); the VM does not clamp.
    func test_duration_canBeNegative_whenStartIsAfterEnd() {
        let sut = makeSUT()
        sut.startedAt = now
        sut.endedAt = now.addingTimeInterval(-hour)
        XCTAssertEqual(sut.duration, -hour, accuracy: 1.0)
    }

    // ========================================================================
    // MARK: - STO-001 / STO-002: save() uses the two-call write path
    // ========================================================================

    func test_save_callsStartSession_thenUpdate() throws {
        let sut = makeSUT()
        // Defaults: yesterday 11pm → today 7am, both within window and in the past.

        XCTAssertEqual(store.startCallCount, 0)
        XCTAssertEqual(store.updateCallCount, 0)

        try sut.save()

        XCTAssertEqual(store.startCallCount, 1, "STO-001: save() must call startSession once")
        XCTAssertEqual(store.updateCallCount, 1, "STO-001: save() must call update once (to set endedAt)")
    }

    /// STO-001 / STO-002: the persisted row has exactly `who`, `startedAt`,
    /// `endedAt`, and `note` matching the view model state — schema-identical
    /// to a Now-captured session.
    func test_save_persistsRowWithExactState() throws {
        let sut = makeSUT()
        sut.who = .bethany
        let start = now.addingTimeInterval(-5 * hour)
        let end = now.addingTimeInterval(-2 * hour)
        sut.startedAt = start
        sut.endedAt = end
        sut.note = "Long stretch."

        try sut.save()

        let rows = store.allRowsForTesting
        XCTAssertEqual(rows.count, 1, "Exactly one row created")
        let row = rows[0]
        XCTAssertEqual(row.who, .bethany)
        XCTAssertEqual(row.startedAt, start)
        XCTAssertEqual(row.endedAt, end)
        XCTAssertEqual(row.note, "Long stretch.")
    }

    // ========================================================================
    // MARK: - STO-001 (note empty / non-empty)
    // ========================================================================

    /// Empty note → store sees `nil` (no `.some("")`).
    func test_save_writesNilNote_whenNoteIsEmpty() throws {
        let sut = makeSUT()
        sut.note = ""

        try sut.save()

        let row = store.allRowsForTesting.first
        XCTAssertNil(row?.note, "Empty note must persist as nil, not \"\"")
    }

    func test_save_writesProvidedNote_whenNoteHasContent() throws {
        let sut = makeSUT()
        sut.note = "Jo's 1am wake"

        try sut.save()

        let row = store.allRowsForTesting.first
        XCTAssertEqual(row?.note, "Jo's 1am wake")
    }

    // ========================================================================
    // MARK: - STO-005: save() doesn't consult open sessions
    // ========================================================================

    /// Per ADR-001 + gameplan STO-005, backfill must NOT short-circuit when
    /// a same-person open session exists. The closed row is created
    /// independently.
    func test_save_doesNotShortCircuit_whenSamePersonHasOpenSession() throws {
        // Dave has an in-progress live session.
        _ = try store.startSession(for: .dave, at: now.addingTimeInterval(-30 * 60))
        let openCountBefore = try store.allOpenSessions().count
        XCTAssertEqual(openCountBefore, 1)

        let sut = makeSUT()
        sut.who = .dave
        // Backfill a closed session overlapping the open one.
        sut.startedAt = now.addingTimeInterval(-3 * hour)
        sut.endedAt = now.addingTimeInterval(-hour)

        try sut.save()

        // The open session is untouched; a NEW closed row exists.
        let allRows = store.allRowsForTesting
        XCTAssertEqual(allRows.count, 2, "STO-005: backfilled row is independent of the open session")
        XCTAssertEqual(try store.allOpenSessions().count, 1, "Pre-existing open session must remain open")
    }

    // ========================================================================
    // MARK: - STO (validation guard): save() is a no-op when invalid
    // ========================================================================

    /// Defensive belt-and-suspenders — even if the UI somehow calls `save()`
    /// while disabled, the VM should not write anything.
    func test_save_isNoOp_whenValidationErrorIsSet() throws {
        let sut = makeSUT()
        sut.startedAt = now
        sut.endedAt = now.addingTimeInterval(-hour) // invalid: end before start
        XCTAssertNotNil(sut.validationError)

        try sut.save()

        XCTAssertEqual(store.startCallCount, 0, "save() must not call startSession when invalid")
        XCTAssertEqual(store.updateCallCount, 0, "save() must not call update when invalid")
        XCTAssertTrue(store.allRowsForTesting.isEmpty, "No row should be created")
    }

    // ========================================================================
    // MARK: - PRD §8 edge case: defaults remain stable across reopen
    // ========================================================================

    /// PRD §8: "User saves, immediately re-opens sheet" — defaults are
    /// re-computed from `clock.now`, NOT sticky to the last-saved values.
    func test_init_defaults_recomputedOnReopen_notStickyToLastSave() throws {
        let firstSheet = makeSUT()
        // User edits to specific times and saves.
        firstSheet.startedAt = now.addingTimeInterval(-10 * hour)
        firstSheet.endedAt = now.addingTimeInterval(-2 * hour)
        try firstSheet.save()

        // Reopen the sheet at the same clock.now.
        let secondSheet = makeSUT()
        // Defaults are still yesterday 11pm → today 7am, NOT the last-saved values.
        let secondStartComponents = utcCalendar.dateComponents([.hour, .minute], from: secondSheet.startedAt)
        let secondEndComponents = utcCalendar.dateComponents([.hour, .minute], from: secondSheet.endedAt)
        XCTAssertEqual(secondStartComponents.hour, 23, "Reopen still defaults to yesterday 11pm")
        XCTAssertEqual(secondStartComponents.minute, 0)
        XCTAssertEqual(secondEndComponents.hour, 7, "Reopen still defaults to today 7am")
        XCTAssertEqual(secondEndComponents.minute, 0)
    }
}

// MARK: - Test-only doubles

/// Store that throws on every read so we can prove DEF-001 resilience —
/// `who` must default to `.dave` rather than crashing the VM init.
private final class ThrowingSleepSessionStore: SleepSessionStore, @unchecked Sendable {
    struct BoomError: Error {}

    func sessions(in range: ClosedRange<Date>) throws -> [SleepSession] {
        throw BoomError()
    }

    func openSession(for who: Person) throws -> SleepSession? {
        throw BoomError()
    }

    func allOpenSessions() throws -> [SleepSession] {
        throw BoomError()
    }

    func startSession(for who: Person, at startedAt: Date) throws -> SleepSession {
        throw BoomError()
    }

    func endSession(_ session: SleepSession, at endedAt: Date) throws {
        throw BoomError()
    }

    func update(
        _ session: SleepSession,
        startedAt: Date?,
        endedAt: Date??,
        who: Person?,
        note: String??
    ) throws {
        throw BoomError()
    }

    func delete(_ session: SleepSession) throws {
        throw BoomError()
    }
}
