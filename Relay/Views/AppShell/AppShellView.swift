//
//  AppShellView.swift
//  Relay
//
//  Root navigation shell — a four-tab TabView. Now is the default tab so the
//  app opens directly on the logging screen (PRD NAV-002 / NAV-003). All four
//  tabs now mount their real screens (NAV-001).
//

import SwiftUI

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
    }
}
