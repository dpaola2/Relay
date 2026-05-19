//
//  DeepLinkTests.swift
//  RelayTests
//
//  RELAY-9 — Widget tap → app deep-link parsing.
//

import XCTest
@testable import Relay

final class DeepLinkTests: XCTestCase {

    func test_relayTotalsURL_parsesToTotals() {
        XCTAssertEqual(DeepLink(url: URL(string: "relay://totals")!), .totals)
    }

    func test_unknownHostUnderRelayScheme_returnsNil() {
        XCTAssertNil(DeepLink(url: URL(string: "relay://nope")!))
    }

    func test_wrongScheme_returnsNil() {
        XCTAssertNil(DeepLink(url: URL(string: "http://totals")!))
    }

    func test_emptyURL_returnsNil() {
        // file://path has no host of "totals" so should not parse.
        XCTAssertNil(DeepLink(url: URL(string: "file:///totals")!))
    }
}
