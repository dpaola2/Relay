//
//  ForecastFirstRunCard.swift
//  Relay
//
//  RELAY-5 (M8 / PHL-005, PHL-006) — dismissable one-time inline card that
//  appears above the proposed-block area on the first appearance of a
//  non-empty proposal. Anchors Care Principle 7 ("the tool proposes; you
//  decide") and the deviation-is-fine frame (Principle 5) before the user
//  has a chance to feel like the proposal is a verdict.
//
//  PHL-006 — permanence. Once dismissed, the card MUST NOT reappear. The
//  one-way latch lives in `ForecastFirstRunFlag` (M4); this view consults
//  the flag via `shouldRender(flag:)`.
//
//  Copy is exposed as `static let` properties so tests can assert plain
//  strings. PHL-007 banned-words guard applies.
//

import SwiftUI

struct ForecastFirstRunCard: View {

    // MARK: - Copy (exposed for tests)

    /// Fixed title (PHL-005).
    static let titleCopy = "This is a starting place."

    /// Fixed body (PHL-005).
    static let bodyCopy = "Tap any block to adjust. The plan is yours — Relay just gives you a grounded place to start the conversation. Deviation is expected; nothing is being tracked."

    /// Single action — dismisses the card and raises the permanence flag.
    static let actionLabel = "Got it"

    // MARK: - Render decision

    /// Whether the card should render given the current flag state. Pure
    /// function so `ForecastFirstRunCardTests` can drive it directly without
    /// instantiating the view (PHL-006).
    static func shouldRender(flag: ForecastFirstRunFlag) -> Bool {
        !flag.dismissed
    }

    // MARK: - Dependencies

    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.titleCopy)
                .font(.headline)
                .foregroundStyle(Color.relayCream)

            Text(Self.bodyCopy)
                .font(.footnote)
                .foregroundStyle(Color.relayCream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(Self.actionLabel, action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.relayTerracotta)
                    .foregroundStyle(Color.relayInk)
                    .accessibilityLabel("Dismiss starting-place note")
            }
        }
        .padding(14)
        .background(Color.relayCream.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.relayCream.opacity(0.18), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
