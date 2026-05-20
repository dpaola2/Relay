//
//  RelayApp.swift
//  Relay
//
//  Created by Dave Paola on 5/16/26.
//
//  RELAY-10 — Strict 6-step init order so the widget extension can wake at
//  any point and read a consistent store:
//
//    1. SwiftDataStoreMigrator   (RELAY-9: move bytes to App Group URL)
//    2. PersonEnumMigrator       (rewrite legacy whoRaw values)
//    3. ModelContainer           (constructed against the App Group URL)
//    4. PersonNameSettings       (App-Group UserDefaults)
//    5. OnboardingCompletionFlag (App-Group UserDefaults)
//    6. UpgradeUserSeeder        (Dave/Bethany seed iff upgrade install)
//

import SwiftUI
import SwiftData

@main
struct RelayApp: App {
    let sharedModelContainer: ModelContainer
    private let widgetRefresher: any WidgetRefreshing = WidgetCenterRefresher()
    private let personNameSettings: PersonNameSettings
    private let onboardingCompletion: OnboardingCompletionFlag

    init() {
        // Step 1 — Move bytes to the App Group container if they're still
        // in the legacy app-sandbox location. Idempotent.
        if let legacy = AppGroupContainer.legacyStoreURL,
           let target = AppGroupContainer.storeURL {
            try? SwiftDataStoreMigrator.migrateIfNeeded(from: legacy, to: target)
        }

        // Step 2 — Rewrite legacy whoRaw values. Synchronous so the widget
        // can never read a half-migrated store. Sentinel-guarded.
        let groupDefaults: UserDefaults = .relayAppGroup
        var didMigrateEnum = false
        if let storeURL = AppGroupContainer.storeURL {
            didMigrateEnum = (try? PersonEnumMigrator.migrateIfNeeded(at: storeURL, defaults: groupDefaults)) ?? false
        }
        _ = didMigrateEnum  // signal is no longer load-bearing — see Step 6.

        // Step 3 — Production ModelContainer against the (post-migration)
        // App Group URL. Fallback to default location only if the
        // entitlement is unresolvable (configuration bug).
        let schema = Schema([SleepSession.self])
        let configuration: ModelConfiguration
        if let storeURL = AppGroupContainer.storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        do {
            self.sharedModelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        // Step 4 — Name settings. Widget refresher injected so every name
        // change kicks the home-screen widget's timeline.
        let settings = PersonNameSettings(defaults: groupDefaults, widgetRefresher: widgetRefresher)
        self.personNameSettings = settings

        // Step 5 — Onboarding completion latch.
        let completion = OnboardingCompletionFlag(defaults: groupDefaults)
        self.onboardingCompletion = completion

        // Step 6 — Upgrade-user seed. If there are existing rows AND no
        // names yet, this is a v1.5 → v1.6 upgrade on my phone: seed
        // Dave/Bethany and mark onboarding complete so I don't see Welcome.
        // Fresh installs land on onboarding.
        let hasExistingSessions = Self.hasExistingSessions(in: sharedModelContainer)
        UpgradeUserSeeder.seedIfNeeded(
            hasExistingSessions: hasExistingSessions,
            settings: settings,
            completion: completion
        )
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(onboardingCompletion: onboardingCompletion)
                .preferredColorScheme(.dark)
                .tint(.relayTerracotta)
                .foregroundStyle(Color.relayCream, Color.relaySoftCream)
                .background(Color.relayInk.ignoresSafeArea())
                .environment(\.widgetRefresher, widgetRefresher)
                .environment(\.personNameSettings, personNameSettings)
        }
        .modelContainer(sharedModelContainer)
    }

    /// Read against the freshly-constructed container to decide whether
    /// this is an upgrade install. We use a temporary `ModelContext` so
    /// we don't touch any view-layer context that may not exist yet.
    private static func hasExistingSessions(in container: ModelContainer) -> Bool {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SleepSession>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }
}
