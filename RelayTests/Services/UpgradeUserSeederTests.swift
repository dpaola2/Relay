//
//  UpgradeUserSeederTests.swift
//  RelayTests
//
//  RELAY-10 — Seeds Dave/Bethany names + marks onboarding completed on
//  upgrade installs (where existing SwiftData rows are already present and
//  names haven't been set yet). Fresh installs must NOT trigger the seed —
//  they should land on the onboarding screen so the new household configures
//  themselves.
//

import XCTest
@testable import Relay

final class UpgradeUserSeederTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var settings: PersonNameSettings!
    private var completion: OnboardingCompletionFlag!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "UpgradeUserSeederTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        settings = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        completion = OnboardingCompletionFlag(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        settings = nil
        completion = nil
        try super.tearDownWithError()
    }

    // MARK: - Upgrade install: existing data + empty names ⇒ seed

    func test_seed_setsDaveBethany_whenExistingDataAndEmptyNames() {
        let didSeed = UpgradeUserSeeder.seedIfNeeded(
            hasExistingSessions: true,
            settings: settings,
            completion: completion
        )

        XCTAssertTrue(didSeed)
        XCTAssertEqual(settings.nameA, "Dave")
        XCTAssertEqual(settings.nameB, "Bethany")
        XCTAssertTrue(completion.isCompleted)
    }

    // MARK: - Fresh install: no existing data ⇒ skip

    func test_seed_skips_onFreshInstall() {
        let didSeed = UpgradeUserSeeder.seedIfNeeded(
            hasExistingSessions: false,
            settings: settings,
            completion: completion
        )

        XCTAssertFalse(didSeed)
        XCTAssertEqual(settings.nameA, "")
        XCTAssertEqual(settings.nameB, "")
        XCTAssertFalse(completion.isCompleted, "Onboarding must show on fresh install")
    }

    // MARK: - Already-configured: names present ⇒ skip

    func test_seed_skips_whenNameAAlreadySet() {
        settings.nameA = "Casey"
        let didSeed = UpgradeUserSeeder.seedIfNeeded(
            hasExistingSessions: true,
            settings: settings,
            completion: completion
        )

        XCTAssertFalse(didSeed, "Names already configured ⇒ seeder must not overwrite")
        XCTAssertEqual(settings.nameA, "Casey", "User's chosen name preserved")
    }

    func test_seed_skips_whenNameBAlreadySet() {
        settings.nameB = "Avery"
        let didSeed = UpgradeUserSeeder.seedIfNeeded(
            hasExistingSessions: true,
            settings: settings,
            completion: completion
        )

        XCTAssertFalse(didSeed)
        XCTAssertEqual(settings.nameB, "Avery")
    }

    // MARK: - Idempotency: re-running on the same launch is safe

    func test_seed_isIdempotent_secondCallNoOps() {
        _ = UpgradeUserSeeder.seedIfNeeded(
            hasExistingSessions: true,
            settings: settings,
            completion: completion
        )
        let secondCall = UpgradeUserSeeder.seedIfNeeded(
            hasExistingSessions: true,
            settings: settings,
            completion: completion
        )
        XCTAssertFalse(secondCall, "Second call sees names already set ⇒ short-circuits")
    }
}
