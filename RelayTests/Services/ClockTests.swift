//
//  ClockTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M2: Domain Model & Persistence)
//
//  Covers gameplan acceptance criteria:
//    - DAT-clock-1: A `Clock` protocol + `SystemClock` concrete impl exist
//      at `Relay/Services/Clock.swift` for time injection in view models.
//
//  Will FAIL until Stage 5 lands `Relay/Services/Clock.swift`.
//

import XCTest
@testable import Relay

final class ClockTests: XCTestCase {

    func test_systemClock_returnsCurrentTime_withinTolerance() {
        let sut = SystemClock()
        let before = Date()
        let observed = sut.now
        let after = Date()

        // `now` should fall in [before, after] — i.e., wall-clock honest.
        XCTAssertGreaterThanOrEqual(observed, before)
        XCTAssertLessThanOrEqual(observed, after)
    }

    /// Establishes that view-model layer can substitute a fake by depending on
    /// `any Clock`, not on `SystemClock` directly.
    func test_systemClock_conformsToClockProtocol() {
        let sut: any Clock = SystemClock()
        XCTAssertNotNil(sut.now)
    }
}
