//
//  AppShellView.swift
//  Relay
//
//  Root navigation shell — a four-tab TabView. Now is the default tab so the
//  app opens directly on the logging screen (PRD NAV-002 / NAV-003). Tab
//  bodies are M2 placeholders; feature views replace them in M3 (Now) and
//  M4 (Timeline, Totals, Edit).
//

import SwiftUI

struct AppShellView: View {
    var body: some View {
        TabView {
            Tab("Now", systemImage: "moon.fill") {
                NowView()
            }
            Tab("Timeline", systemImage: "chart.bar.fill") {
                PlaceholderTab(title: "Timeline")
            }
            Tab("Totals", systemImage: "sum") {
                PlaceholderTab(title: "Totals")
            }
            Tab("Edit", systemImage: "pencil") {
                PlaceholderTab(title: "Edit")
            }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.largeTitle)
            .foregroundStyle(.secondary)
    }
}
