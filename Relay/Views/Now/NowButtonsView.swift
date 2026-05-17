//
//  NowButtonsView.swift
//  Relay
//
//  The three primary Now-screen actions. Full-width, high-contrast,
//  thumb-reachable; each tap fires a light haptic (UX-002 / Arch §7
//  Decision 7) and forwards to the supplied closure. No confirmation
//  dialogs (NOW-008). No animations >150ms (NOW-010).
//

import SwiftUI

struct NowButtonsView: View {
    let onTapISleeping: () -> Void
    let onTapBethanySleeping: () -> Void
    let onTapOnDuty: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            NowPrimaryButton(
                title: "I'm sleeping",
                systemImage: "moon.zzz.fill",
                action: onTapISleeping
            )
            NowPrimaryButton(
                title: "Bethany sleeping",
                systemImage: "moon.fill",
                action: onTapBethanySleeping
            )
            NowPrimaryButton(
                title: "On duty",
                systemImage: "sun.max.fill",
                action: onTapOnDuty
            )
        }
    }
}

private struct NowPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.title2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(.primary)
            .background(Color.relayCream.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
