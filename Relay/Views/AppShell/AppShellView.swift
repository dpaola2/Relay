//
//  AppShellView.swift
//  Relay
//
//  Root navigation shell. Five tabs in Release: Now, Timeline, Totals,
//  Edit, Settings. The Settings tab homes the Names section (always
//  visible) and — DEBUG-only — the QA seed/wipe actions.
//
//  RELAY-9 — tab selection is bound so the widget can deep-link the user
//  to Totals via `relay://totals` (delivered to `.onOpenURL`).
//
//  RELAY-10 — first-run onboarding is presented as `.fullScreenCover` when
//  `OnboardingCompletionFlag.isCompleted` is false. The flag flips the
//  moment the user taps Done on the Names screen, dismissing the cover
//  permanently.
//

import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case now, timeline, totals, edit, settings
}

struct AppShellView: View {
    let onboardingCompletion: OnboardingCompletionFlag

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
            Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                SettingsView()
            }
        }
        .onOpenURL { url in
            switch DeepLink(url: url) {
            case .totals: selection = .totals
            case .none: break
            }
        }
        .fullScreenCover(isPresented: .constant(!onboardingCompletion.isCompleted)) {
            OnboardingView(completion: onboardingCompletion)
        }
    }
}
