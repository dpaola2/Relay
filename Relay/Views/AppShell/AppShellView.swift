//
//  AppShellView.swift
//  Relay
//
//  Root navigation shell. Four tabs in Release; in Debug a fifth "Settings"
//  tab is appended where the QA seed/wipe actions live (RELAY-4 follow-up:
//  the previous floating debug overlay collided with the Day-view chevrons,
//  so the tooling moved into its own tab).
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
                DayTimelineView()
            }
            Tab("Totals", systemImage: "sum") {
                TotalsView()
            }
            Tab("Edit", systemImage: "pencil") {
                EditView()
            }
            #if DEBUG
            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
            #endif
        }
    }
}
