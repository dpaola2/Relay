//
//  SettingsView.swift
//  Relay
//
//  The Settings tab — currently homes the QA seed/wipe actions that previously
//  floated over the app shell. DEBUG-only: in Release builds the tab is hidden
//  by `AppShellView`, so this file is too.
//

#if DEBUG

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.widgetRefresher) private var widgetRefresher
    @State private var showWipeConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Sample data") {
                    Button {
                        runSeed()
                    } label: {
                        Label("Seed sample data", systemImage: "tray.and.arrow.down")
                    }
                    Button {
                        runSeedBackfillCoverage()
                    } label: {
                        Label("Seed backfill coverage", systemImage: "clock.arrow.circlepath")
                    }
                    Button(role: .destructive) {
                        showWipeConfirmation = true
                    } label: {
                        Label("Wipe all data", systemImage: "trash")
                            .foregroundStyle(Color.relayDeepTerracotta)
                    }
                }
            }
            .navigationTitle("Settings")
            .tint(Color.relayTerracotta)
            .confirmationDialog(
                "Delete all sleep sessions?",
                isPresented: $showWipeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Wipe all data", role: .destructive) { runWipe() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes every logged session. Debug-only.")
            }
        }
    }

    private func runSeed() {
        let store = SwiftDataSleepSessionStore(context: modelContext, widgetRefresher: widgetRefresher)
        do {
            try QASeed().seed(store: store, clock: SystemClock())
        } catch {
            print("[QASeed] Seed failed: \(error)")
        }
    }

    private func runSeedBackfillCoverage() {
        let store = SwiftDataSleepSessionStore(context: modelContext, widgetRefresher: widgetRefresher)
        do {
            try QASeed().seedBackfillCoverage(store: store, clock: SystemClock())
        } catch {
            print("[QASeed] Backfill seed failed: \(error)")
        }
    }

    private func runWipe() {
        let store = SwiftDataSleepSessionStore(context: modelContext, widgetRefresher: widgetRefresher)
        do {
            try QASeed().wipe(store: store)
            print("[QASeed] Wiped all sessions.")
        } catch {
            print("[QASeed] Wipe failed: \(error)")
        }
    }
}

#endif
