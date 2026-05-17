//
//  SettingsView.swift
//  Relay
//
//  The Settings tab — currently homes the QA seed/wipe actions that previously
//  floated over the app shell. DEBUG-only: in Release builds the tab is hidden
//  by `AppShellView`, so this file is too.
//

// MUST NOT compile in Release. Every QA-seed action below — including the
// Forecast seed buttons added in M9 — lives inside the file-wide `#if DEBUG`
// guard. The grep-verifiable token "RELAY_DEBUG_ONLY_FORECAST_SEEDS" pins this
// invariant: a Release build's binary must not contain it. AppShellView also
// hides the Settings tab in Release, so even reachability is impossible.
#if DEBUG

import SwiftUI
import SwiftData

// RELAY_DEBUG_ONLY_FORECAST_SEEDS — see file header.

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
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

                Section("Forecast QA") {
                    Button {
                        runSeedForecastAutoProposal()
                    } label: {
                        Label("Seed: Forecast with auto-proposal", systemImage: "calendar.badge.clock")
                    }
                    Button {
                        runSeedForecastManualOverrides()
                    } label: {
                        Label("Seed: Forecast with manual overrides", systemImage: "hand.tap")
                    }
                    Button(role: .destructive) {
                        runSeedForecastEmptyState()
                    } label: {
                        Label("Seed: Forecast empty state", systemImage: "tray")
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
        let store = SwiftDataSleepSessionStore(context: modelContext)
        do {
            try QASeed().seed(store: store, clock: SystemClock())
        } catch {
            print("[QASeed] Seed failed: \(error)")
        }
    }

    private func runSeedBackfillCoverage() {
        let store = SwiftDataSleepSessionStore(context: modelContext)
        do {
            try QASeed().seedBackfillCoverage(store: store, clock: SystemClock())
        } catch {
            print("[QASeed] Backfill seed failed: \(error)")
        }
    }

    private func runWipe() {
        let store = SwiftDataSleepSessionStore(context: modelContext)
        do {
            try QASeed().wipe(store: store)
            print("[QASeed] Wiped all sessions.")
        } catch {
            print("[QASeed] Wipe failed: \(error)")
        }
    }

    // MARK: - Forecast QA seeds (M9)
    //
    // Three idempotent DEBUG-only seeds Dave uses to QA the Forecast feature
    // in the simulator. Each goes through the existing store APIs
    // (`SwiftDataSleepSessionStore`, `SwiftDataProposedShiftStore`,
    // `ForecastFirstRunFlag`) — never raw `ModelContext`. The wipe-then-write
    // shape mirrors `QASeed.seed(...)` so a second tap produces the same data,
    // not duplicates.
    //
    // These functions MUST NOT compile in Release. They live inside the
    // file-wide `#if DEBUG` guard; the AppShellView Settings tab is also
    // DEBUG-only so the call sites can't be reached in Release either.

    private func runSeedForecastAutoProposal() {
        let sessionStore = SwiftDataSleepSessionStore(context: modelContext)
        let proposedStore = SwiftDataProposedShiftStore(context: modelContext)
        let clock = SystemClock()
        do {
            try ForecastQASeed().seedAutoProposal(
                sessionStore: sessionStore,
                proposedStore: proposedStore,
                clock: clock
            )
        } catch {
            print("[ForecastQASeed] Auto-proposal seed failed: \(error)")
        }
    }

    private func runSeedForecastManualOverrides() {
        let sessionStore = SwiftDataSleepSessionStore(context: modelContext)
        let proposedStore = SwiftDataProposedShiftStore(context: modelContext)
        let clock = SystemClock()
        do {
            try ForecastQASeed().seedManualOverrides(
                sessionStore: sessionStore,
                proposedStore: proposedStore,
                clock: clock
            )
        } catch {
            print("[ForecastQASeed] Manual-overrides seed failed: \(error)")
        }
    }

    private func runSeedForecastEmptyState() {
        let sessionStore = SwiftDataSleepSessionStore(context: modelContext)
        let proposedStore = SwiftDataProposedShiftStore(context: modelContext)
        let clock = SystemClock()
        do {
            try ForecastQASeed().seedEmptyState(
                sessionStore: sessionStore,
                proposedStore: proposedStore,
                clock: clock
            )
        } catch {
            print("[ForecastQASeed] Empty-state seed failed: \(error)")
        }
    }
}

#endif
