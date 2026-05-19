//
//  SwiftDataStoreMigratorTests.swift
//  RelayTests
//
//  RELAY-9 — Critical: there is live data on Dave's device. The
//  migrator copies the SwiftData store (default.store + WAL/SHM
//  journal files) from the app-sandbox location to the App Group
//  container URL exactly once, idempotently, and never overwrites
//  an existing target.
//
//  Tests use a temp directory as a stand-in for both URLs.
//

import XCTest
@testable import Relay

final class SwiftDataStoreMigratorTests: XCTestCase {

    private var tempRoot: URL!
    private var legacyURL: URL!
    private var targetURL: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = fm.temporaryDirectory.appendingPathComponent(
            "migrator-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try fm.createDirectory(at: tempRoot.appendingPathComponent("legacy"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tempRoot.appendingPathComponent("group"), withIntermediateDirectories: true)
        legacyURL = tempRoot.appendingPathComponent("legacy/default.store")
        targetURL = tempRoot.appendingPathComponent("group/default.store")
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tempRoot)
        tempRoot = nil
        legacyURL = nil
        targetURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Happy path: legacy present, target absent ⇒ copy

    func test_migrate_copiesAllThreeStoreFiles_whenTargetAbsent() throws {
        try writeStub(at: legacyURL, contents: "main")
        try writeStub(at: legacyURL.appendingWAL, contents: "wal")
        try writeStub(at: legacyURL.appendingSHM, contents: "shm")

        try SwiftDataStoreMigrator.migrateIfNeeded(from: legacyURL, to: targetURL)

        XCTAssertEqual(try String(contentsOf: targetURL), "main")
        XCTAssertEqual(try String(contentsOf: targetURL.appendingWAL), "wal")
        XCTAssertEqual(try String(contentsOf: targetURL.appendingSHM), "shm")
    }

    func test_migrate_leavesLegacyInPlace_afterCopy() throws {
        // Defensive: we do NOT delete the legacy store. If the App Group
        // copy goes wrong, the user can still roll back. Cleanup is a
        // separate decision for a later version.
        try writeStub(at: legacyURL, contents: "main")

        try SwiftDataStoreMigrator.migrateIfNeeded(from: legacyURL, to: targetURL)

        XCTAssertTrue(fm.fileExists(atPath: legacyURL.path))
    }

    // MARK: - Idempotency: target exists ⇒ never overwrite

    func test_migrate_isNoOp_whenTargetAlreadyExists() throws {
        try writeStub(at: legacyURL, contents: "LEGACY DATA")
        try writeStub(at: targetURL, contents: "EXISTING TARGET — must not be touched")

        try SwiftDataStoreMigrator.migrateIfNeeded(from: legacyURL, to: targetURL)

        XCTAssertEqual(
            try String(contentsOf: targetURL),
            "EXISTING TARGET — must not be touched",
            "Idempotent: never clobber existing App Group data"
        )
    }

    // MARK: - Source absent ⇒ no-op

    func test_migrate_isNoOp_whenLegacyAbsent() throws {
        // Fresh install, no legacy store. Migrator must succeed silently.
        XCTAssertNoThrow(try SwiftDataStoreMigrator.migrateIfNeeded(from: legacyURL, to: targetURL))
        XCTAssertFalse(fm.fileExists(atPath: targetURL.path))
    }

    // MARK: - Journal files: optional

    func test_migrate_succeeds_whenWALandSHMabsent() throws {
        // SwiftData's journal files only exist if the DB was unclean-shutdown.
        // A clean-shutdown store has only `default.store` — the migrator must
        // not require the journal files.
        try writeStub(at: legacyURL, contents: "main only")

        try SwiftDataStoreMigrator.migrateIfNeeded(from: legacyURL, to: targetURL)

        XCTAssertEqual(try String(contentsOf: targetURL), "main only")
        XCTAssertFalse(fm.fileExists(atPath: targetURL.appendingWAL.path))
        XCTAssertFalse(fm.fileExists(atPath: targetURL.appendingSHM.path))
    }

    func test_migrate_copiesAvailableJournalFiles_evenIfPartial() throws {
        // WAL but no SHM: still copy WAL, skip SHM without erroring.
        try writeStub(at: legacyURL, contents: "main")
        try writeStub(at: legacyURL.appendingWAL, contents: "wal only")

        try SwiftDataStoreMigrator.migrateIfNeeded(from: legacyURL, to: targetURL)

        XCTAssertEqual(try String(contentsOf: targetURL.appendingWAL), "wal only")
        XCTAssertFalse(fm.fileExists(atPath: targetURL.appendingSHM.path))
    }

    // MARK: - Helpers

    private func writeStub(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}

private extension URL {
    /// SwiftData's SQLite write-ahead log sidecar.
    var appendingWAL: URL { deletingLastPathComponent().appendingPathComponent(lastPathComponent + "-wal") }
    /// SwiftData's SQLite shared-memory sidecar.
    var appendingSHM: URL { deletingLastPathComponent().appendingPathComponent(lastPathComponent + "-shm") }
}
