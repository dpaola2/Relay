//
//  SleepDebtFormatterTests.swift
//  RelayTests
//
//  RELAY-9 — Sleep-debt widget (v1.5 plumbing, shipping as v1.4.1).
//
//  Behaviour-only tests for the pure formatter that turns a signed
//  TimeInterval balance into the widget's display string.
//

import XCTest
@testable import Relay

final class SleepDebtFormatterTests: XCTestCase {

    private let hour: TimeInterval = 3_600

    // MARK: - Negative balance ⇒ "−Xh Ym"

    func test_format_negativeBalance_rendersWithLeadingMinusSign() {
        // −3h 12m
        let result = SleepDebtFormatter.format(balance: -(3 * hour + 12 * 60))
        XCTAssertEqual(result, "−3h 12m")
    }

    func test_format_negativeBalance_rendersZeroHoursWhenOnlyMinutesOfDeficit() {
        let result = SleepDebtFormatter.format(balance: -(45 * 60))
        XCTAssertEqual(result, "−0h 45m")
    }

    // MARK: - Zero balance ⇒ "0"

    func test_format_zeroBalance_rendersAsBareZero() {
        // Per pitch: zero-deficit reads "0" — not "+0h 0m", not "−0h 0m".
        XCTAssertEqual(SleepDebtFormatter.format(balance: 0), "0")
    }

    func test_format_subSecondBalance_rendersAsBareZero() {
        // Tiny rounding noise either side of zero collapses to "0".
        XCTAssertEqual(SleepDebtFormatter.format(balance: 0.4), "0")
        XCTAssertEqual(SleepDebtFormatter.format(balance: -0.4), "0")
    }

    // MARK: - Positive balance ⇒ "+Xh Ym"

    func test_format_positiveBalance_rendersWithLeadingPlusSign() {
        let result = SleepDebtFormatter.format(balance: 30 * 60)
        XCTAssertEqual(result, "+0h 30m")
    }

    func test_format_positiveBalance_includesHoursAndMinutes() {
        let result = SleepDebtFormatter.format(balance: 2 * hour + 5 * 60)
        XCTAssertEqual(result, "+2h 5m")
    }

    // MARK: - No-data placeholder

    func test_noDataPlaceholder_isEmDash() {
        // Fresh install / store empty — widget renders an em-dash, not a number.
        XCTAssertEqual(SleepDebtFormatter.noDataPlaceholder, "—")
    }

    // MARK: - Rounding contract

    func test_format_roundsSecondsTowardZero_perMinute() {
        // 59s of deficit rounds down to 0m, so total reads "0".
        XCTAssertEqual(SleepDebtFormatter.format(balance: -59), "0")
        // 61s reads as 1m.
        XCTAssertEqual(SleepDebtFormatter.format(balance: -61), "−0h 1m")
    }
}
