//
//  AppShellView.swift
//  Relay
//
//  Root navigation shell — a four-tab TabView. Now is the default tab so the
//  app opens directly on the logging screen (PRD NAV-002 / NAV-003). All four
//  tabs now mount their real screens (NAV-001).
//
//  Debug menu (gameplan §M5 / QA-seed-2): a floating "Seed sample data" /
//  "Wipe all data" overlay is mounted when the binary is built with the Debug
//  configuration. Hidden in Release.
//

import SwiftUI
import SwiftData

struct AppShellView: View {
    var body: some View {
        TabView {
            Tab("Now", systemImage: "moon.fill") {
                NowView()
            }
            Tab("Timeline", systemImage: "chart.bar.fill") {
                TimelineView()
            }
            Tab("Totals", systemImage: "sum") {
                TotalsView()
            }
            Tab("Edit", systemImage: "pencil") {
                EditView()
            }
        }
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            QADebugMenu()
                .padding(.top, 8)
                .padding(.trailing, 12)
        }
        #endif
    }
}

#if DEBUG
/// Debug-only `Menu` for QA fixtures (gameplan QA-seed-2 / QA-seed-7).
///
/// "Seed sample data" runs `QASeed().seed(store:clock:)` against the live
/// `SwiftDataSleepSessionStore` (no confirmation — re-running is the
/// idempotency contract). "Wipe all data" is destructive and is the ONE
/// place an action confirmation is permitted (PRD UX bans confirmations on
/// logging actions; QA-seed-7 explicitly allows it here).
private struct QADebugMenu: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showWipeConfirmation = false

    var body: some View {
        Menu {
            Button("Seed sample data", systemImage: "tray.and.arrow.down") {
                runSeed()
            }
            Button("Wipe all data", systemImage: "trash", role: .destructive) {
                showWipeConfirmation = true
            }
        } label: {
            Image(systemName: "hammer.fill")
                .font(.title3)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .confirmationDialog(
            "Delete all sleep sessions?",
            isPresented: $showWipeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Wipe all data", role: .destructive) {
                runWipe()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every logged session. Debug-only.")
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

    private func runWipe() {
        let store = SwiftDataSleepSessionStore(context: modelContext)
        do {
            try QASeed().wipe(store: store)
            print("[QASeed] Wiped all sessions.")
        } catch {
            print("[QASeed] Wipe failed: \(error)")
        }
    }
}
#endif
