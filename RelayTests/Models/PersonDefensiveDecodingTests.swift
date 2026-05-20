//
//  PersonDefensiveDecodingTests.swift
//  RelayTests
//
//  RELAY-10 — The widget runs in a separate process and can decode a
//  SleepSession row that hasn't been touched by PersonEnumMigrator yet.
//  `Person.init(rawValue:)` must accept the legacy `"dave"` / `"bethany"`
//  raw strings AND the new `"personA"` / `"personB"` strings so neither
//  process ever stumbles on transient state. The fallback is documented
//  as v1.6-only — remove in v1.7.
//

import XCTest
@testable import Relay

final class PersonDefensiveDecodingTests: XCTestCase {

    func test_initFromRawValue_acceptsLegacyDave_returningPersonA() {
        XCTAssertEqual(Person(rawValue: "dave"), .personA)
    }

    func test_initFromRawValue_acceptsLegacyBethany_returningPersonB() {
        XCTAssertEqual(Person(rawValue: "bethany"), .personB)
    }

    func test_initFromRawValue_acceptsCanonicalPersonA() {
        XCTAssertEqual(Person(rawValue: "personA"), .personA)
    }

    func test_initFromRawValue_acceptsCanonicalPersonB() {
        XCTAssertEqual(Person(rawValue: "personB"), .personB)
    }

    func test_initFromRawValue_returnsNil_forGarbage() {
        XCTAssertNil(Person(rawValue: "claude"))
        XCTAssertNil(Person(rawValue: ""))
        XCTAssertNil(Person(rawValue: "DAVE"))
    }
}
