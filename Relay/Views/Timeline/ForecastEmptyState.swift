//
//  ForecastEmptyState.swift
//  Relay
//
//  RELAY-5 (M8 / PHL-004) — what renders inside the lane area when
//  `ForecastViewModel.renderableBlocks(...)` returns `[]`. Title is the fixed
//  Care Principle 1 line ("Sleep is recovery."); body explains why no
//  proposal is shown; primary action links to the RELAY-2 Backfill sheet so
//  the user can populate historical data and get a real proposal next time.
//
//  Copy is exposed as `static let` properties so tests can assert against
//  plain strings (the test-against-behavior-not-snapshots rule from CLAUDE.md
//  §"Engineering Methodology" item 2). PHL-007 banned-words guard applies.
//

import SwiftUI

struct ForecastEmptyState: View {

    // MARK: - Copy (exposed for tests)

    /// Fixed Care Principle 1 line (PHL-004).
    static let titleCopy = "Sleep is recovery."

    /// Fixed empty-state body (PHL-004).
    static let bodyCopy = "Relay proposes tonight's split when it knows how depleted each of you is. Right now it doesn't know anything yet."

    /// Primary action label — links to the RELAY-2 Backfill sheet.
    static let primaryActionLabel = "Add the last two days"

    /// Secondary explanatory line under the primary action.
    static let secondaryLineCopy = "Or just start logging tonight — the proposal will get smarter every time you tap."

    // MARK: - Dependencies

    let onAddPast: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.titleCopy)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.relayCream)

            Text(Self.bodyCopy)
                .font(.body)
                .foregroundStyle(Color.relayCream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onAddPast) {
                Text(Self.primaryActionLabel)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.relayTerracotta)
                    .foregroundStyle(Color.relayInk)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.primaryActionLabel)
            .accessibilityHint("Opens the backfill sheet to enter the last two days of sleep.")

            Text(Self.secondaryLineCopy)
                .font(.footnote)
                .foregroundStyle(Color.relaySoftCream.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
