//
//  ForecastFirstRunFlag.swift
//  Relay
//
//  Single-bit `UserDefaults` wrapper for the first-run philosophy card on the
//  Forecast view. Tiny wrapper so the view model can inject a fake in tests.
//
//  Per PRD PHL-006 ("once dismissed, MUST never reappear"): the flag is a
//  one-way bit. Writing `false` after `true` is a deliberate no-op — there is
//  no path to un-dismiss in v1.3 (no debug "reset" affordance; M9 QA seed does
//  not touch this key).
//
//  See architecture proposal §6.8.
//

import Foundation

nonisolated final class ForecastFirstRunFlag: Sendable {
    private let defaults: UserDefaults
    private let key = "relay.forecast.firstRunCardDismissed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `true` once the user has dismissed the first-run card. Setting `true`
    /// persists; setting `false` after `true` is a no-op (PHL-006 — the flag
    /// is permanent once raised).
    var dismissed: Bool {
        get { defaults.bool(forKey: key) }
        set {
            guard newValue else { return }
            defaults.set(true, forKey: key)
        }
    }
}
