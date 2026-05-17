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

    init() {
        let schema = Schema([
            SleepSession.self,
            ProposedShift.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            self.sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        // RELAY-5 (M10 / EDG-010) — prune ProposedShift rows older than the
        // 7-day retention window (ADR-003). Pure on-launch hygiene; errors are
        // swallowed inside the helper so a transient SwiftData failure cannot
        // block app launch.
        LaunchTimePrune.run(store: SwiftDataProposedShiftStore(context: sharedModelContainer.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .preferredColorScheme(.dark)
                .tint(.relayTerracotta)
                .foregroundStyle(Color.relayCream, Color.relaySoftCream)
                .background(Color.relayInk.ignoresSafeArea())
        }
        .modelContainer(sharedModelContainer)
    }
}
