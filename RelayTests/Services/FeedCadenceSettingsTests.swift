//
//  FeedCadenceSettingsTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M4: FeedCadenceSettings +
//  ForecastFirstRunFlag UserDefaults wrappers)
//
//  Covers gameplan acceptance criteria:
//    - FED-001: FeedCadenceSettings.hours: Double defaults to 2.0.
//    - FED-002: writes are clamped to [1.0, 4.0] and snapped to 0.5-hour steps.
//    - FED-003: anchorAt is set to the current quarter-hour the first time
//      hours is written OR the first time anchorAt is read with no value
//      persisted — whichever is earlier.
//    - Two UserDefaults keys: `relay.forecast.feedCadenceHours` (Double) and
//      `relay.forecast.feedCadenceAnchorAt` (Date).
//    - FeedCadenceSettings is `nonisolated final class`, `Sendable`, accepts
//      an injected UserDefaults for test isolation.
//    - PHL-005, PHL-006: ForecastFirstRunFlag.dismissed: Bool is one bit; once
//      true, stays true forever (no API to un-dismiss).
//    - Key: `relay.forecast.firstRunCardDismissed`.
//
//  Expected to FAIL until Stage 5 lands:
//    (a) `Relay/Services/FeedCadenceSettings.swift`
//    (b) `Relay/Services/ForecastFirstRunFlag.swift`
//

import XCTest
@testable import Relay

final class FeedCadenceSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "relay.tests.feedcadence"

    override func setUp() {
        super.setUp()
        // Fresh per-test UserDefaults so we don't pollute `.standard`.
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - FED-001: default value

    func test_hours_defaultsTo2_whenNothingPersisted() {
        let sut = FeedCadenceSettings(defaults: defaults)
        XCTAssertEqual(sut.hours, 2.0, accuracy: 0.001)
    }

    // MARK: - FED-002: clamp to [1.0, 4.0]

    func test_hours_clampsTo4_whenWrittenAbove() {
        let sut = FeedCadenceSettings(defaults: defaults)
        sut.hours = 6.0
        XCTAssertEqual(sut.hours, 4.0, accuracy: 0.001)
    }

    func test_hours_clampsTo1_whenWrittenBelow() {
        let sut = FeedCadenceSettings(defaults: defaults)
        sut.hours = 0.25
        XCTAssertEqual(sut.hours, 1.0, accuracy: 0.001)
    }

    func test_hours_acceptsBoundaryValues_1and4() {
        let sut = FeedCadenceSettings(defaults: defaults)
        sut.hours = 1.0
        XCTAssertEqual(sut.hours, 1.0, accuracy: 0.001)
        sut.hours = 4.0
        XCTAssertEqual(sut.hours, 4.0, accuracy: 0.001)
    }

    // MARK: - FED-002: snap to 0.5-hour steps

    func test_hours_snapsToNearestHalfHourStep() {
        let sut = FeedCadenceSettings(defaults: defaults)

        sut.hours = 2.1
        XCTAssertEqual(sut.hours, 2.0, accuracy: 0.001, "2.1 → 2.0")

        sut.hours = 2.3
        XCTAssertEqual(sut.hours, 2.5, accuracy: 0.001, "2.3 → 2.5")

        sut.hours = 2.74
        XCTAssertEqual(sut.hours, 2.5, accuracy: 0.001, "2.74 → 2.5")

        sut.hours = 2.76
        XCTAssertEqual(sut.hours, 3.0, accuracy: 0.001, "2.76 → 3.0")
    }

    func test_hours_persistsAcrossInstances() {
        let writer = FeedCadenceSettings(defaults: defaults)
        writer.hours = 3.0

        let reader = FeedCadenceSettings(defaults: defaults)
        XCTAssertEqual(reader.hours, 3.0, accuracy: 0.001)
    }

    func test_hours_usesDocumentedUserDefaultsKey() {
        let sut = FeedCadenceSettings(defaults: defaults)
        sut.hours = 2.5

        let raw = defaults.double(forKey: "relay.forecast.feedCadenceHours")
        XCTAssertEqual(raw, 2.5, accuracy: 0.001, "Key MUST be 'relay.forecast.feedCadenceHours'")
    }

    // MARK: - FED-003: anchor rounded to quarter-hour

    func test_anchorAt_isRoundedToQuarterHour_whenFirstRead() {
        let sut = FeedCadenceSettings(defaults: defaults)
        let anchor = sut.anchorAt

        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: anchor)
        XCTAssertTrue(
            [0, 15, 30, 45].contains(minute),
            "Anchor minute should be a quarter-hour boundary (got \(minute))"
        )

        let second = calendar.component(.second, from: anchor)
        XCTAssertEqual(second, 0, "Anchor seconds should be zero")
    }

    func test_anchorAt_isStable_acrossReads() {
        let sut = FeedCadenceSettings(defaults: defaults)
        let first = sut.anchorAt
        let second = sut.anchorAt
        XCTAssertEqual(first, second, "Anchor must persist across reads")
    }

    func test_anchorAt_persistsAcrossInstances() {
        let writer = FeedCadenceSettings(defaults: defaults)
        let firstAnchor = writer.anchorAt

        let reader = FeedCadenceSettings(defaults: defaults)
        XCTAssertEqual(reader.anchorAt, firstAnchor)
    }

    func test_anchorAt_usesDocumentedUserDefaultsKey() {
        let sut = FeedCadenceSettings(defaults: defaults)
        _ = sut.anchorAt

        let raw = defaults.object(forKey: "relay.forecast.feedCadenceAnchorAt") as? Date
        XCTAssertNotNil(raw, "Key MUST be 'relay.forecast.feedCadenceAnchorAt'")
    }

    func test_writingHours_alsoEstablishesAnchor_ifNotYetSet() {
        let sut = FeedCadenceSettings(defaults: defaults)
        // Anchor not yet read or written.
        XCTAssertNil(defaults.object(forKey: "relay.forecast.feedCadenceAnchorAt"))

        sut.hours = 3.0

        XCTAssertNotNil(
            defaults.object(forKey: "relay.forecast.feedCadenceAnchorAt"),
            "Writing hours for the first time should also establish the anchor (FED-003)"
        )
    }
}

// MARK: - ForecastFirstRunFlag

final class ForecastFirstRunFlagTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "relay.tests.firstrun"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - PHL-005: defaults to NOT dismissed

    func test_dismissed_defaultsToFalse_whenNothingPersisted() {
        let sut = ForecastFirstRunFlag(defaults: defaults)
        XCTAssertFalse(sut.dismissed)
    }

    // MARK: - PHL-006: once dismissed, stays dismissed

    func test_dismissed_flipsToTrue_andPersists() {
        let writer = ForecastFirstRunFlag(defaults: defaults)
        writer.dismissed = true

        let reader = ForecastFirstRunFlag(defaults: defaults)
        XCTAssertTrue(reader.dismissed)
    }

    func test_dismissed_isPermanent_noPathToReset() {
        // Per PHL-006: "once dismissed, MUST never reappear." No API to
        // un-dismiss. Writing `false` after `true` must be a no-op OR throw —
        // either way, dismissed remains true.
        let sut = ForecastFirstRunFlag(defaults: defaults)
        sut.dismissed = true
        sut.dismissed = false // Attempting to un-dismiss.

        XCTAssertTrue(
            sut.dismissed,
            "PHL-006: dismissed=true is permanent; setting false is a no-op"
        )
    }

    func test_dismissed_usesDocumentedUserDefaultsKey() {
        let sut = ForecastFirstRunFlag(defaults: defaults)
        sut.dismissed = true

        let raw = defaults.bool(forKey: "relay.forecast.firstRunCardDismissed")
        XCTAssertTrue(raw, "Key MUST be 'relay.forecast.firstRunCardDismissed'")
    }
}
