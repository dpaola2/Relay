//
//  FeedCadenceSettingsSheet.swift
//  Relay
//
//  RELAY-5 (M8 / FED-006) — user-facing settings sheet presented from the
//  gear toolbar icon on the Timeline tab. Hosts a single `Stepper` bound to
//  `FeedCadenceSettings.hours` (range 1.0...4.0, step 0.5).
//
//  Co-located with the DEBUG `SettingsView.swift` under `Relay/Views/Settings/`
//  but a separate file with NO `#if DEBUG` guard — this surface ships in
//  Release builds (architecture §6.10 + gameplan §M8).
//
//  `FeedCadenceSettings` is a `nonisolated final class` whose `hours` getter
//  reads from `UserDefaults`. The sheet mirrors the value into `@State` so
//  SwiftUI's `Stepper` has an `Int`-stable binding, and writes back on each
//  change.
//

import SwiftUI

struct FeedCadenceSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let settings: FeedCadenceSettings
    @State private var hours: Double = FeedCadenceSettings.defaultHours

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(
                        value: $hours,
                        in: FeedCadenceSettings.minHours...FeedCadenceSettings.maxHours,
                        step: FeedCadenceSettings.stepHours
                    ) {
                        LabeledContent("Every") {
                            Text(formatted(hours))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Feed cadence")
                } footer: {
                    Text("Feed markers project forward and backward from the anchor at this cadence. Render-only — Relay doesn't log feeds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Feed cadence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.relayTerracotta)
        .onAppear { hours = settings.hours }
        .onChange(of: hours) { _, newValue in
            settings.hours = newValue
        }
    }

    private func formatted(_ value: Double) -> String {
        let whole = floor(value)
        let half = value - whole >= 0.25
        let hourWord = (value == 1.0) ? "hour" : "hours"
        return half
            ? "\(Int(whole)).5 \(hourWord)"
            : "\(Int(whole)).0 \(hourWord)"
    }
}
