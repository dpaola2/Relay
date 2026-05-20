//
//  UserDefaults+AppGroup.swift
//  Relay
//
//  RELAY-10 — Shared UserDefaults suite scoped to the App Group container
//  registered in RELAY-9. Both the app target and (via the literal suite
//  name in `WidgetAppGroup`) the widget extension read/write the same
//  preferences here: names, onboarding completion flag, migration sentinels.
//

import Foundation

extension UserDefaults {
    /// The single shared suite used by every cross-target preference in Relay.
    /// Force-unwrapped because the App Group entitlement is required for the
    /// app to function at all — a missing entitlement is a build configuration
    /// bug, not a runtime fallback case.
    ///
    /// `nonisolated(unsafe)` opts out of the app target's implicit MainActor
    /// isolation (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`); `UserDefaults`
    /// itself is already thread-safe, so the access is safe and we need to be
    /// callable from `nonisolated` setters in `PersonNameSettings` and
    /// `OnboardingCompletionFlag`.
    nonisolated(unsafe) static let relayAppGroup: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: AppGroupContainer.identifier) else {
            fatalError("App Group UserDefaults unavailable: check entitlement configuration for \(AppGroupContainer.identifier)")
        }
        return defaults
    }()
}
