//
//  Person.swift
//  Relay
//
//  The two people who can have sleep sessions logged. Cases are
//  household-anonymous (`personA` / `personB`) so any two-parent pair can
//  use the app; display strings come from `PersonNameSettings` via the
//  `displayName(_:)` extension.
//

import Foundation

/// String-backed so SwiftData stores the value as a plain String, sidestepping
/// enum-migration friction (Arch §1.1 + §8.1). Cases are anonymous so the
/// same schema works for any household — see `PersonNameSettings`.
enum Person: String, CaseIterable, Identifiable, Sendable {
    case personA
    case personB

    /// Defensive decoder. Accepts both the canonical raw values and the
    /// legacy `"dave"` / `"bethany"` strings that pre-v1.6 stores persisted.
    /// `PersonEnumMigrator` rewrites legacy rows on launch, but the widget
    /// extension can read a row in flight; the fallback closes that race.
    ///
    /// Remove the legacy branch in v1.7 once enough time has passed that any
    /// unmigrated row would have been touched by a launch.
    init?(rawValue: String) {
        switch rawValue {
        case "personA", "dave": self = .personA
        case "personB", "bethany": self = .personB
        default: return nil
        }
    }

    var id: String { rawValue }
}
