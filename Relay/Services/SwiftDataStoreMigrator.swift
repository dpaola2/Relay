//
//  SwiftDataStoreMigrator.swift
//  Relay
//
//  RELAY-9 — One-shot copy of the SwiftData store from the legacy
//  app-sandbox URL to the App Group container so the widget extension
//  can read it.
//
//  Safety contract:
//  - Never overwrite an existing target. If the App Group store is
//    already present, do nothing. This is what makes the call
//    idempotent on every cold launch.
//  - Never delete the legacy store. A failed migration must leave
//    the user in a recoverable state.
//  - Journal files (WAL/SHM) are optional — SQLite only emits them
//    on unclean shutdown — so missing journal files are not an error.
//

import Foundation

enum SwiftDataStoreMigrator {

    /// Copy `default.store` + `-wal` + `-shm` from `legacyURL` to
    /// `targetURL` if and only if `targetURL` does not yet exist.
    /// No-op on fresh install (legacy absent) and on subsequent
    /// cold launches (target present).
    static func migrateIfNeeded(
        from legacyURL: URL,
        to targetURL: URL,
        fileManager: FileManager = .default
    ) throws {
        guard !fileManager.fileExists(atPath: targetURL.path) else { return }
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        try copyIfPresent(at: legacyURL, to: targetURL, fileManager: fileManager)
        try copyIfPresent(at: legacyURL.sqliteWAL, to: targetURL.sqliteWAL, fileManager: fileManager)
        try copyIfPresent(at: legacyURL.sqliteSHM, to: targetURL.sqliteSHM, fileManager: fileManager)
    }

    private static func copyIfPresent(
        at source: URL,
        to destination: URL,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.copyItem(at: source, to: destination)
    }
}

private extension URL {
    var sqliteWAL: URL { deletingLastPathComponent().appendingPathComponent(lastPathComponent + "-wal") }
    var sqliteSHM: URL { deletingLastPathComponent().appendingPathComponent(lastPathComponent + "-shm") }
}
