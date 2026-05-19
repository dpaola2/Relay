//
//  SleepDebtFormatter.swift
//  Relay
//
//  Pure formatter for the sleep-debt widget (RELAY-9). Lives in the main
//  app target so it can be reused by the widget extension (added in a
//  follow-up commit) and exercised by RelayTests without pulling in WidgetKit.
//
//  Contract per RELAY-9 pitch:
//      negative balance → "−Xh Ym"   (deficit; user needs more sleep)
//      zero balance     → "0"        (target met — not "+0h 0m", not "−0h 0m")
//      positive balance → "+Xh Ym"   (surplus)
//      no data          → "—"        (em-dash; e.g., fresh install)
//
//  Rounding is per-minute toward zero (whole minutes only, no seconds).
//

import Foundation

enum SleepDebtFormatter {

    /// What the widget renders when the store has nothing to compute from
    /// (empty store, missing person, etc.). Kept distinct from the numeric
    /// path so call sites are explicit.
    static let noDataPlaceholder = "—"

    /// Format a signed balance (`actual − target`) as the widget string.
    static func format(balance seconds: TimeInterval) -> String {
        let absMinutes = Int(abs(seconds) / 60)
        if absMinutes == 0 { return "0" }
        let hours = absMinutes / 60
        let minutes = absMinutes % 60
        let prefix = seconds < 0 ? "\u{2212}" : "+"
        return "\(prefix)\(hours)h \(minutes)m"
    }
}
