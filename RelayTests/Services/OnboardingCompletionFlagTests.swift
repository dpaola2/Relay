//
//  OnboardingCompletionFlagTests.swift
//  RelayTests
//
//  RELAY-10 — One-way latch persisted to App-Group UserDefaults. Once an
//  onboarding completes (manually via the Names screen, or implicitly via
//  the upgrade-user seed), the flag never flips back without an explicit
//  reset call. The reset surface exists for QA / wipe, not for production.
//

import XCTest
@testable import Relay

final class OnboardingCompletionFlagTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "OnboardingCompletionFlagTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func test_isCompleted_isFalse_byDefault() {
        let sut = OnboardingCompletionFlag(defaults: defaults)
        XCTAssertFalse(sut.isCompleted)
    }

    func test_markCompleted_setsFlagTrue() {
        let sut = OnboardingCompletionFlag(defaults: defaults)
        sut.markCompleted()
        XCTAssertTrue(sut.isCompleted)
    }

    func test_markCompleted_persists() {
        let first = OnboardingCompletionFlag(defaults: defaults)
        first.markCompleted()

        let fresh = OnboardingCompletionFlag(defaults: defaults)
        XCTAssertTrue(fresh.isCompleted)
    }

    func test_markCompletedTwice_isIdempotent() {
        let sut = OnboardingCompletionFlag(defaults: defaults)
        sut.markCompleted()
        sut.markCompleted()
        XCTAssertTrue(sut.isCompleted)
    }
}
