//
//  AppGroupContainer.swift
//  Relay
//
//  RELAY-9 — Centralized resolution of the App Group container so the
//  app target and the widget extension target stay in lockstep on the
//  identifier and the store filename.
//

import Foundation

enum AppGroupContainer {

    /// The single identifier shared by both targets.
    /// Must match the entitlement and the value typed in
    /// Xcode's Signing & Capabilities for both targets.
    static let identifier = "group.com.davepaola.relay"

    /// SwiftData's default filename when `ModelConfiguration` is
    /// constructed without an explicit URL. We match it so the
    /// migrator copies cleanly from legacy → group.
    static let storeFilename = "default.store"

    /// The App Group's shared container URL. Nil in environments
    /// without the entitlement (rare; mostly a unit-test concern).
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Full URL to the SwiftData store inside the App Group container.
    static var storeURL: URL? {
        url?.appendingPathComponent(storeFilename)
    }

    /// Legacy SwiftData store URL — the default location used before
    /// the App Group migration (i.e., `Library/Application Support/default.store`
    /// inside the app sandbox). Used as the migration source on first
    /// launch of v1.5.
    static var legacyStoreURL: URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent(storeFilename)
    }
}
