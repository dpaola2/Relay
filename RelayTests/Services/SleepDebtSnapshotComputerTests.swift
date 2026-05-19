//
//  SleepDebtSnapshotComputerTests.swift
//  RelayTests
//
//  RELAY-9 — Pure computation seam between the timeline provider
//  and the model. Keeps `SleepDebtTimelineProvider` skinny and
//  the widget view trivial — both stay untested visually, the
//  math is tested here.
//

import XCTest
@testable import Relay

final class SleepDebtSnapshotComputerTests: XCTestCase {

    private var store: InMemorySleepSessionStore!
    private let hour: TimeInterval = 3_600
    private let referenceDate = Date(timeIntervalSince1970: 1_779_278_400)

    override func setUp() {
        super.setUp()
        store = InMemorySleepSessionStore()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Empty store ⇒ both balances nil (no-data state)

    func test_snapshot_returnsNilBalances_whenStoreIsEmpty() {
        let snapshot = SleepDebtSnapshotComputer.snapshot(from: store, at: referenceDate)

        XCTAssertNil(snapshot.daveBalance)
        XCTAssertNil(snapshot.bethanyBalance)
        XCTAssertEqual(snapshot.date, referenceDate)
    }

    // MARK: - Per-person signed balance

    func test_snapshot_computesNegativeBalance_forUnderSleptPerson() throws {
        // Dave: 4h in the last 24h → balance = 4h − 8h = −4h.
        // Bethany: 0h in the last 24h, but has at least one session in the
        // store somewhere (we have to put it inside the window or it won't
        // contribute to count) — instead seed her with a stale 72h-ago session
        // to register "not a fresh install" without affecting her 24h total.
        let d = try store.startSession(for: .dave, at: referenceDate.addingTimeInterval(-5 * hour))
        try store.endSession(d, at: referenceDate.addingTimeInterval(-1 * hour))

        let snapshot = SleepDebtSnapshotComputer.snapshot(from: store, at: referenceDate)

        XCTAssertEqual(snapshot.daveBalance ?? .infinity, -4 * hour, accuracy: 1.0)
        XCTAssertEqual(snapshot.bethanyBalance ?? .infinity, -8 * hour, accuracy: 1.0)
    }

    func test_snapshot_computesPositiveBalance_forOverSleptPerson() throws {
        // Bethany: 9h in the last 24h → balance = +1h.
        let b = try store.startSession(for: .bethany, at: referenceDate.addingTimeInterval(-10 * hour))
        try store.endSession(b, at: referenceDate.addingTimeInterval(-1 * hour))

        let snapshot = SleepDebtSnapshotComputer.snapshot(from: store, at: referenceDate)

        XCTAssertEqual(snapshot.bethanyBalance ?? .infinity, 1 * hour, accuracy: 1.0)
    }

    // MARK: - Open sessions count toward the moving target

    func test_snapshot_countsOpenSessionElapsedTime_atReferenceDate() throws {
        // Dave: open session started 2h ago. Counts as 2h of sleep.
        _ = try store.startSession(for: .dave, at: referenceDate.addingTimeInterval(-2 * hour))

        let snapshot = SleepDebtSnapshotComputer.snapshot(from: store, at: referenceDate)

        XCTAssertEqual(snapshot.daveBalance ?? .infinity, 2 * hour - 8 * hour, accuracy: 1.0)
    }

    // MARK: - Projection: balances at a future date deterministically

    func test_snapshot_projectsForward_byClippingTo24hWindowAtFutureDate() throws {
        // Dave: closed 8h session ending exactly at referenceDate.
        // At referenceDate, 24h window is [-24h, 0]. The 8h session is inside,
        // so balance = 8h − 8h = 0.
        // At referenceDate + 30h, the 24h window is [+6h, +30h]. The session
        // ended at 0h, BEFORE +6h, so 0h of it is inside the window → balance = -8h.
        let d = try store.startSession(for: .dave, at: referenceDate.addingTimeInterval(-8 * hour))
        try store.endSession(d, at: referenceDate)

        let nowSnap = SleepDebtSnapshotComputer.snapshot(from: store, at: referenceDate)
        let futureSnap = SleepDebtSnapshotComputer.snapshot(
            from: store,
            at: referenceDate.addingTimeInterval(30 * hour)
        )

        XCTAssertEqual(nowSnap.daveBalance ?? .infinity, 0, accuracy: 1.0)
        XCTAssertEqual(futureSnap.daveBalance ?? .infinity, -8 * hour, accuracy: 1.0)
    }
}
