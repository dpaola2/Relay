//
//  LaneHeaderTests.swift
//  RelayTests
//
//  RELAY-8 / RELAY-10 — the always-visible color legend on the Day view. The
//  legend reads display names from `PersonNameSettings` via an injected
//  closure rather than calling into the enum directly; that's how the same
//  legend renders different households' names. Tests hit the pure-data seam
//  (`LaneHeader.entries(color:name:)`) so we verify shape without rendering
//  SwiftUI.
//

import XCTest
import SwiftUI
@testable import Relay

final class LaneHeaderTests: XCTestCase {

    private func paletteColor(for person: Person) -> Color {
        switch person {
        case .personA: return .relayTerracotta
        case .personB: return .relaySoftPeach
        }
    }

    private func name(for person: Person) -> String {
        switch person {
        case .personA: return "Casey"
        case .personB: return "Avery"
        }
    }

    func test_entries_returnsBothLanes_inLeftToRightOrder() {
        let entries = LaneHeader.entries(color: paletteColor(for:), name: name(for:))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].person, .personA, "Left lane must be personA")
        XCTAssertEqual(entries[1].person, .personB, "Right lane must be personB")
    }

    func test_entries_carryDisplayNamesFromClosure() {
        let entries = LaneHeader.entries(color: paletteColor(for:), name: name(for:))
        XCTAssertEqual(entries[0].label, "Casey")
        XCTAssertEqual(entries[1].label, "Avery")
    }

    func test_entries_useColorClosure() {
        // The legend's color must come from the supplied closure (which in
        // production is the TimelineViewModel's `color(for:)`), so the legend
        // is guaranteed to match the lanes.
        let entries = LaneHeader.entries(color: paletteColor(for:), name: name(for:))
        XCTAssertEqual(entries[0].color, .relayTerracotta)
        XCTAssertEqual(entries[1].color, .relaySoftPeach)
    }

    func test_entries_accessibilityLabels_includeNameAndColor() {
        let entries = LaneHeader.entries(color: paletteColor(for:), name: name(for:))
        XCTAssertEqual(entries[0].accessibilityLabel, "Casey's lane, terracotta")
        XCTAssertEqual(entries[1].accessibilityLabel, "Avery's lane, peach")
    }
}
