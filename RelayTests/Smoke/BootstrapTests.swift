//
//  BootstrapTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M1: Test-Target Bootstrap & Smoke Test)
//
//  Covers gameplan acceptance criteria:
//    - DAT-bootstrap-5: A smoke test file exists with at least one test
//      that calls XCTAssertEqual(1 + 1, 2).
//    - DAT-bootstrap-6: Running the canonical test command goes green.
//
//  This file is intentionally minimal — it exists so that the very first
//  green run of the test target proves the actor-isolation footgun from
//  ADR-002 has been avoided (see also DAT-bootstrap-2 / -3 / -4 which are
//  verified by the pbxproj diff, not by code).
//

import XCTest

final class BootstrapTests: XCTestCase {

    /// DAT-bootstrap-5: minimum-viable smoke test. If this is red, the test
    /// target was never wired up (M1 incomplete). If this is green, M2+ can
    /// proceed with TDD.
    func test_smoke_arithmetic() {
        XCTAssertEqual(1 + 1, 2)
    }

    /// Belt-and-suspenders: confirms that XCTest is actually loading the
    /// test target's symbols (this would fail if the bundle was empty).
    func test_smoke_canInstantiateBundleClass() {
        let bundle = Bundle(for: BootstrapTests.self)
        XCTAssertNotNil(bundle.bundleIdentifier, "Test bundle should have an identifier")
    }
}
