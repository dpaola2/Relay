//
//  LaneHeaderTests.swift
//  RelayTests
//
//  RELAY-8 (Part 3) — the always-visible color legend on the Day view. Tests
//  hit the pure-data seam (`LaneHeader.entries(color:)`) rather than rendering
//  SwiftUI: we verify the legend exposes one entry per lane, in left-to-right
//  order (Dave then Bethany), each carrying the person's display name + the
//  palette color sourced from the same function the lanes use.
//

import XCTest
import SwiftUI
@testable import Relay

final class LaneHeaderTests: XCTestCase {

    private func paletteColor(for person: Person) -> Color {
        switch person {
        case .dave: return .relayTerracotta
        case .bethany: return .relaySoftPeach
        }
    }

    func test_entries_returnsBothLanes_inLeftToRightOrder() {
        let entries = LaneHeader.entries(color: paletteColor(for:))
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].person, .dave, "Left lane must be Dave")
        XCTAssertEqual(entries[1].person, .bethany, "Right lane must be Bethany")
    }

    func test_entries_carryDisplayNames() {
        let entries = LaneHeader.entries(color: paletteColor(for:))
        XCTAssertEqual(entries[0].label, "Dave")
        XCTAssertEqual(entries[1].label, "Bethany")
    }

    func test_entries_useColorClosure() {
        // The legend's color must come from the supplied closure (which in
        // production is the TimelineViewModel's `color(for:)`), so the legend
        // is guaranteed to match the lanes.
        let entries = LaneHeader.entries(color: paletteColor(for:))
        XCTAssertEqual(entries[0].color, .relayTerracotta)
        XCTAssertEqual(entries[1].color, .relaySoftPeach)
    }

    func test_entries_accessibilityLabels_describeLaneAndColor() {
        let entries = LaneHeader.entries(color: paletteColor(for:))
        XCTAssertEqual(entries[0].accessibilityLabel, "Dave's lane, terracotta")
        XCTAssertEqual(entries[1].accessibilityLabel, "Bethany's lane, peach")
    }
}
