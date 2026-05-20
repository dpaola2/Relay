//
//  PersonEnumMigrator.swift
//  Relay
//
//  RELAY-10 — One-shot migration from the v1.5 raw values (`"dave"` /
//  `"bethany"`) to the v1.6 canonical raw values (`"personA"` /
//  `"personB"`).
//
//  Lifecycle (must run in `RelayApp.init()` AFTER `SwiftDataStoreMigrator`
//  and BEFORE the production `ModelContainer` is constructed):
//
//      _ = try? PersonEnumMigrator.migrateIfNeeded(
//          at: AppGroupContainer.storeURL!,
//          defaults: .relayAppGroup
//      )
//
//  Safety contract:
//  - Idempotent. A UserDefaults sentinel (`relay.personEnum.migrated.v1_6`)
//    latches on first run; later launches see the flag and skip.
//  - Other fields are preserved bit-identical. We only mutate `whoRaw`.
//  - Synchronous. The widget extension can wake at any time; we don't want
//    the widget reading a half-migrated store.
//  - Returns `true` only if rows were actually rewritten on THIS call.
//    The signal feeds `UpgradeUserSeeder` so we can distinguish "fresh
//    install" from "upgrade install with existing data."
//

import Foundation
import SwiftData

enum PersonEnumMigrator {

    /// UserDefaults key. Stable string so we can read the same flag from the
    /// widget side if we ever need it. (Today only the app touches this.)
    static let sentinelKey = "relay.personEnum.migrated.v1_6"

    /// Run the migration if it hasn't already been recorded. Returns `true`
    /// when at least one row was rewritten on this invocation; `false` when
    /// the sentinel was already set OR the store was empty (no work to do).
    @discardableResult
    static func migrateIfNeeded(
        at storeURL: URL,
        defaults: UserDefaults
    ) throws -> Bool {
        if defaults.bool(forKey: sentinelKey) { return false }

        let didRewrite = try rewriteLegacyRows(at: storeURL)
        defaults.set(true, forKey: sentinelKey)
        return didRewrite
    }

    // MARK: - Private

    private static let legacyToCanonical: [String: String] = [
        "dave": "personA",
        "bethany": "personB"
    ]

    /// Open the container at `storeURL`, fetch every `SleepSession`, and
    /// rewrite legacy `whoRaw` values. Returns `true` if at least one row
    /// was changed.
    private static func rewriteLegacyRows(at storeURL: URL) throws -> Bool {
        let schema = Schema([SleepSession.self])
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<SleepSession>())

        var changed = false
        for row in rows {
            if let canonical = legacyToCanonical[row.whoRaw], row.whoRaw != canonical {
                row.whoRaw = canonical
                changed = true
            }
        }
        if changed {
            try context.save()
        }
        return changed
    }
}
