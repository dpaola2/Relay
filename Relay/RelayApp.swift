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
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SleepSession.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }
}
