//
//  DeficitProviding.swift
//  Relay
//
//  Tiny protocol the ForecastEngine consumes for per-person 24h deficit math.
//  Kept narrow per CLAUDE.md §4 Interface Segregation so tests can supply a
//  trivial fake without standing up `TotalsViewModel`. `TotalsViewModel`
//  conforms to it via an adapter (M5).
//
//  Engine semantics (Architecture §6.5):
//  - Returns seconds remaining to target (i.e. `max(0, target − actual_24h)`).
//  - Clamped to >= 0. Never negative.
//

import Foundation

protocol DeficitProviding: Sendable {
    /// Returns the 24-hour deficit (target − actual) in seconds, clamped to >= 0.
    func deficit24h(
        for person: Person,
        targetHoursPer24h: Double,
        asOf: Date
    ) -> TimeInterval
}
