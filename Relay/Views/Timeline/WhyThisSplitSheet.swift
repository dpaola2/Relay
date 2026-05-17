//
//  WhyThisSplitSheet.swift
//  Relay
//
//  RELAY-5 (M8) — the philosophy modal presented from the `ⓘ` toolbar icon
//  on the Timeline tab. Three parts:
//
//    1. Live deficit line — "X has Yh Zm more deficit than you over the last
//       48h." Computed at sheet-open from `DeficitProviding.deficit48h(...)`.
//    2. FIXED Care Principle paragraph (PHL-002): sleep is recovery; the more
//       depleted parent gets the longer block.
//    3. FIXED follow-up (PHL-002): this isn't about whose turn it is.
//
//  Two actions (PHL-003): `[Adjust]` dismisses and asks the host to scroll to
//  the first proposed block; `[Got it]` dismisses.
//
//  Copy is exposed as `static let` properties so tests can assert against
//  plain strings (the test-against-behavior-not-snapshots rule from
//  CLAUDE.md §"Engineering Methodology" item 2).
//
//  PHL-007 — copy MUST NOT contain "wellness", "balance", "self-care", or
//  "mindful". Asserted by `WhyThisSplitSheetTests`.
//

import SwiftUI

struct WhyThisSplitSheet: View {

    // MARK: - Copy (exposed for tests)

    /// Sheet title. Short enough to fit a navigation bar.
    static let titleCopy = "Why this split"

    /// FIXED body copy — the two Care Principle paragraphs (PHL-002). The
    /// live deficit line is rendered separately and is NOT part of this string
    /// (it changes per-sheet-open; this string is the philosophical anchor).
    /// Total ≤120 words per the word-count test.
    static let bodyCopy = """
    Sleep is recovery, especially in the fourth trimester. The more depleted parent gets the longer block tonight.

    This isn't about whose turn it is — Relay doesn't track turns. It's about who needs the rest right now.
    """

    /// Primary action — dismisses the sheet and scrolls the underlying
    /// timeline to the first proposed block.
    static let adjustActionLabel = "Adjust"

    /// Secondary action — dismisses the sheet.
    static let gotItActionLabel = "Got it"

    // MARK: - Dependencies

    let deficitLine: String
    let onAdjust: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !deficitLine.isEmpty {
                        Text(deficitLine)
                            .font(.headline)
                            .foregroundStyle(Color.relayCream)
                    }
                    Text(Self.bodyCopy)
                        .font(.body)
                        .foregroundStyle(Color.relayCream)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(Color.relayInk.ignoresSafeArea())
            .navigationTitle(Self.titleCopy)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Self.gotItActionLabel) { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Self.adjustActionLabel) { onAdjust() }
                }
            }
        }
        .tint(Color.relayTerracotta)
    }
}

// MARK: - Deficit line composition

extension WhyThisSplitSheet {
    /// Composes the live deficit line shown above the fixed paragraphs.
    /// Returns "" when both deficits are within one minute of each other —
    /// the sheet then shows only the fixed Care Principle text. Pure helper
    /// so unit tests can drive it directly.
    static func deficitLine(daveDeficit48h: TimeInterval, bethanyDeficit48h: TimeInterval) -> String {
        let diff = abs(daveDeficit48h - bethanyDeficit48h)
        guard diff >= 60 else { return "" }
        let leader: Person = daveDeficit48h > bethanyDeficit48h ? .dave : .bethany
        let total = Int(diff)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        return "\(leader.displayName) has \(hours)h \(minutes)m more deficit than you over the last 48h."
    }
}
