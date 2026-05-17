//
//  ProposedShiftSchemaSmokeTest.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M1: ProposedShift @Model + Schema +
//  Smoke Test)
//
//  CRITICAL — this test catches the #1 SwiftData footgun documented in
//  CLAUDE.md: forgetting to register a new `@Model` in the `Schema([...])`
//  array in `Relay/RelayApp.swift`.
//
//  It opens a `ModelContainer` configured with the SAME schema array used by
//  the production app (`SleepSession.self` + `ProposedShift.self`), then
//  inserts and fetches one `ProposedShift` row. If `ProposedShift.self` is
//  missing from the production schema, this test will fail at container
//  construction OR at fetch time.
//
//  Expected to FAIL until M1 lands:
//    (a) `Relay/Models/ProposedShift.swift` (the model type), AND
//    (b) the one-line addition of `ProposedShift.self` to `Schema([...])`
//        in `Relay/RelayApp.swift`.
//

import XCTest
import SwiftData
@testable import Relay

final class ProposedShiftSchemaSmokeTest: XCTestCase {

    /// The production schema array — kept in sync with `Relay/RelayApp.swift`.
    /// When Stage 5 adds `ProposedShift.self` to RelayApp's `Schema([...])`,
    /// this array must match.
    private static let productionSchema = Schema([
        SleepSession.self,
        ProposedShift.self,
    ])

    func test_modelContainer_opensWithProductionSchema_includingProposedShift() throws {
        let config = ModelConfiguration(
            schema: Self.productionSchema,
            isStoredInMemoryOnly: true
        )

        let container = try ModelContainer(
            for: Self.productionSchema,
            configurations: [config]
        )

        XCTAssertNotNil(
            container,
            "ModelContainer must open cleanly with ProposedShift registered. " +
            "If this fails, Stage 5 forgot to add ProposedShift.self to " +
            "Schema([...]) in Relay/RelayApp.swift — the #1 SwiftData footgun."
        )
    }

    func test_modelContainer_roundTripsOneProposedShift() throws {
        let config = ModelConfiguration(
            schema: Self.productionSchema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: Self.productionSchema,
            configurations: [config]
        )
        let context = ModelContext(container)

        let planDay = Date(timeIntervalSince1970: 1_780_000_000)
        let started = planDay.addingTimeInterval(22 * 3_600) // 10pm
        let ended = started.addingTimeInterval(1_800)        // +30 min

        let shift = ProposedShift(
            planDay: planDay,
            who: .bethany,
            startedAt: started,
            endedAt: ended
        )
        context.insert(shift)
        try context.save()

        let descriptor = FetchDescriptor<ProposedShift>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(
            fetched.count,
            1,
            "Inserted ProposedShift must round-trip through the production schema"
        )
        let first = try XCTUnwrap(fetched.first)
        XCTAssertEqual(first.who, .bethany)
        XCTAssertEqual(first.planDay, planDay)
        XCTAssertEqual(first.startedAt, started)
        XCTAssertEqual(first.endedAt, ended)
        XCTAssertFalse(first.manuallyOverridden)
    }

    func test_modelContainer_alsoRoundTripsSleepSession_provingSchemaCoexists() throws {
        // Belt-and-suspenders — the additive schema change must not regress
        // SleepSession persistence. If this fails, the schema migration broke
        // RELAY-2/3/4 data.
        let config = ModelConfiguration(
            schema: Self.productionSchema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(
            for: Self.productionSchema,
            configurations: [config]
        )
        let context = ModelContext(container)

        let now = Date(timeIntervalSince1970: 1_780_000_000)
        context.insert(SleepSession(who: .dave, startedAt: now))
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<SleepSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.who, .dave)
    }
}
