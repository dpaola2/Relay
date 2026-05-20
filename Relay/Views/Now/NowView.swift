//
//  NowView.swift
//  Relay
//
//  Top-level Now-tab screen (Arch §3.4 / gameplan M3). Composes the active
//  session banner with the three primary action buttons. Builds its own
//  `NowViewModel` from the SwiftData `ModelContext` on first appear, and
//  refreshes the active-sessions view after each intent.
//
//  Per UX-002, each button tap fires a light haptic before invoking the
//  view-model intent (so the half-asleep operator gets immediate physical
//  confirmation the tap registered even if the visual state takes a moment).
//

import SwiftUI
import SwiftData

struct NowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.widgetRefresher) private var widgetRefresher
    @Environment(\.personNameSettings) private var nameSettings

    @State private var viewModel: NowViewModel?
    @State private var haptics: Haptics = Self.makeHaptics()

    var body: some View {
        VStack(spacing: 24) {
            ActiveSessionsBanner(sessions: viewModel?.activeSessions ?? [])
            NowButtonsView(
                nameA: nameSettings.displayName(for: .personA),
                nameB: nameSettings.displayName(for: .personB),
                onTapPersonA: { perform { try $0.tapPersonA() } },
                onTapPersonB: { perform { try $0.tapPersonB() } },
                onTapOnDuty: { perform { try $0.tapOnDuty() } }
            )
            Spacer()
        }
        .padding(20)
        .task {
            if viewModel == nil {
                let store = SwiftDataSleepSessionStore(context: modelContext, widgetRefresher: widgetRefresher)
                viewModel = NowViewModel(store: store, clock: SystemClock())
            }
            viewModel?.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepSessionsDidChange)) { _ in
            viewModel?.refresh()
        }
    }

    private func perform(_ intent: (NowViewModel) throws -> Void) {
        guard let viewModel else { return }
        haptics.light()
        do {
            try intent(viewModel)
            viewModel.refresh()
        } catch {
            // v1 swallows intent errors — the only failure surface is
            // `endedAt < startedAt` validation, which the Now intents cannot
            // trigger. Edit-screen errors (M4) get their own UI surface.
        }
    }

    private static func makeHaptics() -> Haptics {
        #if canImport(UIKit)
        return Haptics(player: UIKitLightImpactPlayer())
        #else
        return Haptics(player: NoopHapticPlayer())
        #endif
    }
}

#if !canImport(UIKit)
private final class NoopHapticPlayer: HapticFeedbackPlaying, @unchecked Sendable {
    func impactOccurred() {}
}
#endif
