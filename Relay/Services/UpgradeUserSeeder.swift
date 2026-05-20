//
//  UpgradeUserSeeder.swift
//  Relay
//
//  RELAY-10 — On upgrade installs (where v1.5 left SwiftData rows for
//  Dave & Bethany on disk and the user has never configured names), seed
//  the canonical names + mark onboarding complete so the upgrading user
//  doesn't see a Welcome screen. Fresh installs leave both flags untouched
//  so onboarding presents normally.
//
//  Decision signal: "is this an upgrade?" = there is at least one existing
//  `SleepSession` row AND both names are empty. We don't depend on the
//  `PersonEnumMigrator` sentinel because that flag flips on fresh installs
//  too (after a no-op scan).
//

import Foundation

enum UpgradeUserSeeder {

    /// Default names seeded on upgrade. These match the only two households
    /// in production today (Dave + Bethany). New installs land on onboarding
    /// and pick their own names.
    static let defaultNameA = "Dave"
    static let defaultNameB = "Bethany"

    /// Seed the names + completion flag iff this looks like an upgrade
    /// install. Returns `true` when it actually seeded.
    @discardableResult
    static func seedIfNeeded(
        hasExistingSessions: Bool,
        settings: PersonNameSettings,
        completion: OnboardingCompletionFlag
    ) -> Bool {
        guard hasExistingSessions else { return false }
        guard settings.nameA.isEmpty, settings.nameB.isEmpty else { return false }
        settings.nameA = defaultNameA
        settings.nameB = defaultNameB
        completion.markCompleted()
        return true
    }
}
