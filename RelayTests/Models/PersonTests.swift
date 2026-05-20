//
//  PersonTests.swift
//  RelayTests
//
//  Covers the `Person` enum that supports `SleepSession.who`. Per Architecture
//  §1.1 + §1.3, `Person` is a String-backed enum (so SwiftData can store it as
//  a plain String, sidestepping enum migration friction).
//
//  RELAY-10: cases renamed to `.personA` / `.personB` so the same enum can
//  represent any two-parent household. Legacy raw-value decoding lives in
//  `PersonDefensiveDecodingTests`.
//

import XCTest
@testable import Relay

final class PersonTests: XCTestCase {

    func test_rawValues_areStableStrings() {
        XCTAssertEqual(Person.personA.rawValue, "personA")
        XCTAssertEqual(Person.personB.rawValue, "personB")
    }

    func test_initFromRawValue_roundTripsAllCases() {
        for person in Person.allCases {
            XCTAssertEqual(Person(rawValue: person.rawValue), person)
        }
    }

    func test_id_equalsRawValue_forIdentifiableConformance() {
        XCTAssertEqual(Person.personA.id, "personA")
        XCTAssertEqual(Person.personB.id, "personB")
    }

    func test_allCases_containsExactlyTwoPeople_forV1() {
        // Still two people — the rename did not relax the "two parents per
        // household" project-shape constraint.
        XCTAssertEqual(Person.allCases.count, 2)
        XCTAssertTrue(Person.allCases.contains(.personA))
        XCTAssertTrue(Person.allCases.contains(.personB))
    }
}
