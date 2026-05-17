//
//  LaunchTimePruneTests.swift
//  RelayTests
//
//  RELAY-5 (M10 / EDG-010) — pure unit tests for the launch-time prune helper.
//  Drives the helper through `InMemoryProposedShiftStore` so we don't need to
//  spin up a real app launch.
//

import XCTest
@testable import Relay

final class LaunchTimePruneTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    // MARK: - cutoff math

    func test_cutoff_isStartOfDaySixDaysBeforeNow() {
        // 2026-05-17 14:00 in NY → cutoff is 2026-05-11 00:00 (today − 6 days).
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 14))!
        let cutoff = LaunchTimePrune.cutoff(now: now, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 0))!
        XCTAssertEqual(cutoff, expected)
    }

    func test_cutoff_isMidnightAnchored() {
        // Any time of day produces the same cutoff.
        let morning = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 1))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 23))!
        XCTAssertEqual(
            LaunchTimePrune.cutoff(now: morning, calendar: calendar),
            LaunchTimePrune.cutoff(now: evening, calendar: calendar)
        )
    }

    // MARK: - run(store:)

    func test_run_invokesPruneExactlyOnce() throws {
        let store = InMemoryProposedShiftStore()
        XCTAssertEqual(store.pruneCallCount, 0)

        LaunchTimePrune.run(store: store, now: .now, calendar: calendar)

        XCTAssertEqual(store.pruneCallCount, 1, "Launch-time prune is a single, one-shot call.")
    }

    func test_run_keepsRowsWithinRetentionWindow() throws {
        let store = InMemoryProposedShiftStore()
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 17, hour: 14))!

        // Insert one row per day from today back to today-8.
        let startOfToday = calendar.startOfDay(for: now)
        for daysBack in 0...8 {
            let planDay = calendar.date(byAdding: .day, value: -daysBack, to: startOfToday)!
            _ = try store.upsert(
                planDay: planDay,
                startedAt: planDay.addingTimeInterval(22 * 3_600),
                who: .dave,
                manuallyOverridden: false
            )
        }
        XCTAssertEqual(store.allRowsForTesting.count, 9)

        LaunchTimePrune.run(store: store, now: now, calendar: calendar)

        // Retention is 7 days inclusive of today (today + 6 previous days).
        // Strict `<` cutoff of today-6 prunes anything older than today-6.
        let remaining = store.allRowsForTesting.map { $0.planDay }.sorted()
        XCTAssertEqual(remaining.count, 7, "7 calendar days are retained (today + 6 prior).")
        let oldest = calendar.date(byAdding: .day, value: -6, to: startOfToday)!
        XCTAssertEqual(remaining.first, oldest, "Oldest retained row is exactly today − 6 days.")
        XCTAssertEqual(remaining.last, startOfToday, "Newest retained row is today.")
    }
}
