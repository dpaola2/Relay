//
//  AppShellView.swift
//  Relay
//
//  Root navigation shell. Four tabs in Release; in Debug a fifth "Settings"
//  tab is appended where the QA seed/wipe actions live (RELAY-4 follow-up:
//  the previous floating debug overlay collided with the Day-view chevrons,
//  so the tooling moved into its own tab).
//
//  RELAY-9 — tab selection is bound so the widget can deep-link the user
//  to Totals via `relay://totals` (delivered to `.onOpenURL`).
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case now, timeline, totals, edit
    #if DEBUG
    case settings
    #endif
}

struct AppShellView: View {
    @State private var selection: AppTab = .now

    var body: some View {
        TabView(selection: $selection) {
            Tab("Now", systemImage: "moon.fill", value: AppTab.now) {
                NowView()
            }
            Tab("Timeline", systemImage: "chart.bar.fill", value: AppTab.timeline) {
                DayTimelineView()
            }
            Tab("Totals", systemImage: "sum", value: AppTab.totals) {
                TotalsView()
            }
            Tab("Edit", systemImage: "pencil", value: AppTab.edit) {
                EditView()
            }
            #if DEBUG
            Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                SettingsView()
            }
            #endif
        }
        .onOpenURL { url in
            switch DeepLink(url: url) {
            case .totals: selection = .totals
            case .none: break
            }
        }
    }
}
