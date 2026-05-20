//
//  PhilosophyScreen.swift
//  Relay
//
//  RELAY-10 — Onboarding screen 2. The only in-app surface of Care
//  Principle 1 ("Sleep is recovery"). Banned-word-clean per RELAY-5
//  PHL-007: no "wellness," "balance," "self-care," "mindful," "journey."
//
//  Wrapped in `ScrollView` so accessibility text sizes don't clip — the
//  screen is intentionally not redesigned for AccessibilityXXXL; scrolling
//  is the defensive fallback.
//

import SwiftUI

struct PhilosophyScreen: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Sleep is recovery.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.relayTerracotta)
                        .padding(.top, 80)

                    Text("Relay tracks who slept, not who's \u{201C}winning.\u{201D}")
                        .font(.title3)
                        .foregroundStyle(Color.relayCream)

                    Text("No turn-taking math, no coaching, no notifications.")
                        .font(.title3)
                        .foregroundStyle(Color.relayCream)

                    Text("Just the night, both parents, one screen.")
                        .font(.title3)
                        .foregroundStyle(Color.relaySoftCream)
                        .padding(.top, 12)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            OnboardingPrimaryButton(title: "Next", action: onNext)
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
