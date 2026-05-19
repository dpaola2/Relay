//
//  RelayApp.swift
//  Relay
//
//  Created by Dave Paola on 5/16/26.
//

import SwiftUI
import SwiftData

@main
struct RelayApp: App {
    let sharedModelContainer: ModelContainer
    private let widgetRefresher: any WidgetRefreshing = WidgetCenterRefresher()

    init() {
        // RELAY-9: one-shot migration of the SwiftData store from the
        // legacy app-sandbox location to the App Group container so
        // RelayWidgetExtension can read it. Idempotent on every cold
        // launch; never overwrites existing App Group data.
        if let legacy = AppGroupContainer.legacyStoreURL,
           let target = AppGroupContainer.storeURL {
            try? SwiftDataStoreMigrator.migrateIfNeeded(from: legacy, to: target)
        }

        let schema = Schema([SleepSession.self])
        let configuration: ModelConfiguration
        if let storeURL = AppGroupContainer.storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            // Fall back to the default location in the (unlikely) case the
            // App Group entitlement isn't resolvable. The widget won't see
            // data until the entitlement is fixed, but the app keeps working.
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        do {
            self.sharedModelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .preferredColorScheme(.dark)
                .tint(.relayTerracotta)
                .foregroundStyle(Color.relayCream, Color.relaySoftCream)
                .background(Color.relayInk.ignoresSafeArea())
                .environment(\.widgetRefresher, widgetRefresher)
        }
        .modelContainer(sharedModelContainer)
    }
}
