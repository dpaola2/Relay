//
//  PersonEnumMigratorTests.swift
//  RelayTests
//
//  RELAY-10 — One-shot rewrite of legacy `whoRaw` strings on the existing
//  SwiftData store. `"dave"` → `"personA"`, `"bethany"` → `"personB"`.
//  Idempotent via a UserDefaults sentinel so subsequent launches skip the work.
//

import XCTest
import SwiftData
@testable import Relay

final class PersonEnumMigratorTests: XCTestCase {

    private var tempRoot: URL!
    private var storeURL: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = fm.temporaryDirectory.appendingPathComponent(
            "person-enum-migrator-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        storeURL = tempRoot.appendingPathComponent("test.store")

        suiteName = "PersonEnumMigratorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempRoot)
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        storeURL = nil
        tempRoot = nil
        try super.tearDownWithError()
    }

    // MARK: - Happy path: legacy rows rewrite to canonical raw values

    func test_migrate_rewritesLegacyDave_toPersonA() throws {
        try seed(legacyRaw: "dave")

        let didWork = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)

        XCTAssertTrue(didWork, "Migrator did rewrite a row, so it returns true on this launch")
        let rows = try fetchAllRaw()
        XCTAssertEqual(rows, ["personA"])
    }

    func test_migrate_rewritesLegacyBethany_toPersonB() throws {
        try seed(legacyRaw: "bethany")

        _ = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)

        XCTAssertEqual(try fetchAllRaw(), ["personB"])
    }

    func test_migrate_leavesCanonicalRowsAlone() throws {
        try seed(legacyRaw: "personA")
        try seed(legacyRaw: "personB")

        _ = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)

        XCTAssertEqual(try fetchAllRaw().sorted(), ["personA", "personB"])
    }

    func test_migrate_mixedLegacyAndCanonical_rewritesOnlyLegacy() throws {
        try seed(legacyRaw: "dave")
        try seed(legacyRaw: "personB")
        try seed(legacyRaw: "bethany")

        _ = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)

        XCTAssertEqual(try fetchAllRaw().sorted(), ["personA", "personB", "personB"])
    }

    // MARK: - Idempotency: sentinel guards subsequent runs

    func test_migrate_setsSentinelFlag_afterRunning() throws {
        try seed(legacyRaw: "dave")
        _ = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: PersonEnumMigrator.sentinelKey))
    }

    func test_migrate_isNoOp_whenSentinelAlreadySet() throws {
        defaults.set(true, forKey: PersonEnumMigrator.sentinelKey)
        try seed(legacyRaw: "dave")

        let didWork = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)

        XCTAssertFalse(didWork, "Sentinel already set ⇒ migrator skips, returns false")
        XCTAssertEqual(try fetchAllRaw(), ["dave"], "Skipped run must NOT rewrite — the defensive decoder handles reads")
    }

    func test_migrate_isIdempotent_acrossTwoRuns() throws {
        try seed(legacyRaw: "dave")
        _ = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)
        _ = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)
        XCTAssertEqual(try fetchAllRaw(), ["personA"])
    }

    // MARK: - Empty store: still sets sentinel so future launches skip

    func test_migrate_emptyStore_setsSentinel_andReturnsFalse() throws {
        let didWork = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)
        XCTAssertFalse(didWork, "No rows to rewrite ⇒ no work done")
        XCTAssertTrue(defaults.bool(forKey: PersonEnumMigrator.sentinelKey),
                      "Sentinel still latches so subsequent launches skip the scan")
    }

    // MARK: - Other fields preserved

    func test_migrate_preservesAllOtherFields() throws {
        let startedAt = Date(timeIntervalSince1970: 1_780_000_000)
        let endedAt = startedAt.addingTimeInterval(3_600)
        let id = UUID()
        try seedFull(id: id, legacyRaw: "dave", startedAt: startedAt, endedAt: endedAt, note: "carry-through")

        _ = try PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: defaults)

        let container = try ModelContainer(for: SleepSession.self, configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<SleepSession>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, id)
        XCTAssertEqual(rows.first?.whoRaw, "personA")
        XCTAssertEqual(rows.first?.startedAt, startedAt)
        XCTAssertEqual(rows.first?.endedAt, endedAt)
        XCTAssertEqual(rows.first?.note, "carry-through")
    }

    // MARK: - Helpers

    /// Insert a single SleepSession with a directly-set `whoRaw`. We bypass
    /// `Person.init?(rawValue:)` so we can simulate persisted legacy values.
    private func seed(legacyRaw: String) throws {
        let container = try ModelContainer(for: SleepSession.self, configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)
        let session = SleepSession(who: .personA, startedAt: .now)
        session.whoRaw = legacyRaw
        context.insert(session)
        try context.save()
    }

    private func seedFull(
        id: UUID,
        legacyRaw: String,
        startedAt: Date,
        endedAt: Date?,
        note: String?
    ) throws {
        let container = try ModelContainer(for: SleepSession.self, configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)
        let session = SleepSession(
            id: id,
            who: .personA,
            startedAt: startedAt,
            endedAt: endedAt,
            note: note
        )
        session.whoRaw = legacyRaw
        context.insert(session)
        try context.save()
    }

    private func fetchAllRaw() throws -> [String] {
        let container = try ModelContainer(for: SleepSession.self, configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<SleepSession>()).map(\.whoRaw)
    }
}
