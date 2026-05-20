//
//  NowButtonsView.swift
//  Relay
//
//  The three primary Now-screen actions. Full-width, high-contrast,
//  thumb-reachable; each tap fires a light haptic (UX-002 / Arch §7
//  Decision 7) and forwards to the supplied closure. No confirmation
//  dialogs (NOW-008). No animations >150ms (NOW-010).
//
//  RELAY-10 — button labels are name-aware. The first two read
//  "<nameA> sleeping" / "<nameB> sleeping" so neither parent is the
//  presumed operator. (The old "I'm sleeping" / "Bethany sleeping"
//  copy assumed Dave was holding the phone.)
//

import SwiftUI

struct NowButtonsView: View {
    let nameA: String
    let nameB: String
    let onTapPersonA: () -> Void
    let onTapPersonB: () -> Void
    let onTapOnDuty: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            NowPrimaryButton(
                title: "\(nameA) sleeping",
                systemImage: "moon.zzz.fill",
                action: onTapPersonA
            )
            NowPrimaryButton(
                title: "\(nameB) sleeping",
                systemImage: "moon.fill",
                action: onTapPersonB
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
