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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            self.sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
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
        }
        .modelContainer(sharedModelContainer)
    }
}
