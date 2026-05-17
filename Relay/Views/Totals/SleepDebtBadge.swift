//
//  SleepDebtBadge.swift
//  Relay
//
//  Per-person "sleep debt" indicator — target hours minus actual, floored at
//  zero (gameplan M6 / TOT-004, conditional per Q11 resolution 2026-05-16).
//  Default target is 8 hours per 24h (Arch §7 Decision 8 / approval note).
//
//  The math lives on `TotalsViewModel.sleepDebt(for:targetHoursPer24h:window:)`;
//  this view is the visual surface that consumes it. Shown inside
//  `PersonTotalsCard` so a more-deprived parent is visually obvious at a glance.
//

import SwiftUI

struct SleepDebtBadge: View {
    let person: Person
    let viewModel: TotalsViewModel

    /// Default target — 8 hours per 24-hour window. Overrideable for testing
    /// or future per-person configuration.
    var targetHoursPer24h: Double = 8.0

    private let window: TimeInterval = 24 * 3_600

    var body: some View {
        let debt = viewModel.sleepDebt(
            for: person,
            targetHoursPer24h: targetHoursPer24h,
            window: window
        )
        HStack(spacing: 8) {
            Image(systemName: debt > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .foregroundStyle(debt > 0 ? Color.relayDeepTerracotta : Color.relayCream)
            Text(label(for: debt))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityLabel(Text(accessibilityLabel(for: debt)))
    }

    private func label(for debt: TimeInterval) -> String {
        if debt <= 0 { return "Target met (\(Int(targetHoursPer24h))h / 24h)" }
        return "Debt: \(formatHoursMinutes(debt))"
    }

    private func accessibilityLabel(for debt: TimeInterval) -> String {
        if debt <= 0 { return "\(person.displayName) sleep target met." }
        return "\(person.displayName) sleep debt \(formatHoursMinutes(debt))."
    }

    private func formatHoursMinutes(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }
}
