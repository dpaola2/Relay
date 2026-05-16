//
//  PersonTests.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M2: Domain Model & Persistence)
//
//  Covers the `Person` enum that supports `SleepSession.who`. Per Architecture
//  §1.1 + §1.3, `Person` is a String-backed enum (so SwiftData can store it as
//  a plain String, sidestepping enum migration friction).
//
//  Expected to FAIL until Stage 5 lands `Relay/Models/Person.swift`.
//

import XCTest
@testable import Relay

final class PersonTests: XCTestCase {

    func test_rawValues_areStableStrings() {
        XCTAssertEqual(Person.dave.rawValue, "dave")
        XCTAssertEqual(Person.bethany.rawValue, "bethany")
    }

    func test_initFromRawValue_roundTripsAllCases() {
        for person in Person.allCases {
            XCTAssertEqual(Person(rawValue: person.rawValue), person)
        }
    }

    func test_initFromRawValue_returnsNil_forUnknownValue() {
        XCTAssertNil(Person(rawValue: "claude"))
        XCTAssertNil(Person(rawValue: ""))
    }

    func test_displayName_isHumanReadable() {
        XCTAssertEqual(Person.dave.displayName, "Dave")
        XCTAssertEqual(Person.bethany.displayName, "Bethany")
    }

    func test_id_equalsRawValue_forIdentifiableConformance() {
        XCTAssertEqual(Person.dave.id, "dave")
        XCTAssertEqual(Person.bethany.id, "bethany")
    }

    func test_allCases_containsExactlyTwoPeople_forV1() {
        // V1 is single-couple. Adding a third person is out of scope and would
        // require revisiting the data model.
        XCTAssertEqual(Person.allCases.count, 2)
        XCTAssertTrue(Person.allCases.contains(.dave))
        XCTAssertTrue(Person.allCases.contains(.bethany))
    }
}
