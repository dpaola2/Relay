//
//  SettingsView.swift
//  Relay
//
//  The Settings tab. Promoted to Release in RELAY-10 because production
//  users need a Names section to edit per-person display names. The Sample
//  Data section (QA Seed / Wipe) stays DEBUG-only so it never ships.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.widgetRefresher) private var widgetRefresher
    @Environment(\.personNameSettings) private var nameSettings

    var body: some View {
        NavigationStack {
            Form {
                NamesSection(settings: nameSettings)
                #if DEBUG
                SampleDataSection(modelContext: modelContext, widgetRefresher: widgetRefresher)
                #endif
            }
            .navigationTitle("Settings")
            .tint(Color.relayTerracotta)
        }
    }
}

// MARK: - Names

/// Editable per-person names. Reads/writes through `PersonNameSettings`,
/// which fires the widget refresh hook on every set; the home-screen
/// widget picks up the change on its next reload.
private struct NamesSection: View {
    @Bindable var settings: PersonNameSettings

    /// Cap names at 30 characters so the lane-header strip and widget rows
    /// stay legible. The picker rendering does its own truncation, but this
    /// keeps the underlying store from growing unbounded.
    private static let maxLength = 30

    var body: some View {
        Section("Names") {
            TextField("Person A", text: bindingFor(\.nameA))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            TextField("Person B", text: bindingFor(\.nameB))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
    }

    /// `@Bindable` already gives us `$settings.nameA`, but we wrap it so
    /// edits that exceed the length cap don't slip through. The setter
    /// truncates rather than rejecting, so a paste of a 50-char string
    /// trims to 30 without losing focus.
    private func bindingFor(_ keyPath: ReferenceWritableKeyPath<PersonNameSettings, String>) -> Binding<String> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                let trimmed = String(newValue.prefix(Self.maxLength))
                settings[keyPath: keyPath] = trimmed
            }
        )
    }
}

// MARK: - Sample data (DEBUG only)

#if DEBUG
private struct SampleDataSection: View {
    let modelContext: ModelContext
    let widgetRefresher: any WidgetRefreshing

    @State private var showWipeConfirmation = false

    var body: some View {
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
