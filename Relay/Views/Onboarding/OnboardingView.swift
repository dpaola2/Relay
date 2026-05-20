//
//  OnboardingView.swift
//  Relay
//
//  RELAY-10 — Three-screen first-run flow: Welcome → Philosophy → Names.
//  Presented as a `.fullScreenCover` from the app root whenever
//  `OnboardingCompletionFlag.isCompleted == false`. Once the user taps
//  Done on the Names screen, the flag flips and the cover dismisses
//  permanently.
//
//  Container uses `TabView(.page)` for the dot indicator and natural
//  swipe-between-screens. The flow is short (~30 seconds total) and
//  unskippable on purpose — the philosophy screen is the only in-app
//  surface of Care Principle 1 and only fires here.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.personNameSettings) private var nameSettings
    let completion: OnboardingCompletionFlag

    @State private var selectedTab: Int = 0
    @State private var draftA: String = ""
    @State private var draftB: String = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            WelcomeScreen(onNext: { advance(to: 1) })
                .tag(0)
            PhilosophyScreen(onNext: { advance(to: 2) })
                .tag(1)
            NamesScreen(
                draftA: $draftA,
                draftB: $draftB,
                onDone: finish
            )
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color.relayInk.ignoresSafeArea())
        .foregroundStyle(Color.relayCream)
    }

    private func advance(to next: Int) {
        withAnimation(.easeOut(duration: 0.18)) {
            selectedTab = next
        }
    }

    private func finish() {
        nameSettings.nameA = String(draftA.prefix(30))
        nameSettings.nameB = String(draftB.prefix(30))
        completion.markCompleted()
    }
}
