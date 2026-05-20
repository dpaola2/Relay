//
//  WelcomeScreen.swift
//  Relay
//
//  RELAY-10 — Onboarding screen 1. Big, calm, low-information.
//

import SwiftUI

struct WelcomeScreen: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Text("Welcome to")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.relaySoftCream)
                Text("Relay")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.relayTerracotta)
            }

            Text("Sleep tracking for the newborn period.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.relayCream)

            Spacer()

            OnboardingPrimaryButton(title: "Next", action: onNext)
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Shared primary button styling for onboarding screens. Matches the look
/// of `NowPrimaryButton` so the user's first taps feel like the rest of
/// the app.
struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(isEnabled ? Color.relayInk : Color.relayInk.opacity(0.45))
                .background(
                    (isEnabled ? Color.relayTerracotta : Color.relayTerracotta.opacity(0.4)),
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
    }
}
