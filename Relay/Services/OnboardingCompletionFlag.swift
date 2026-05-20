//
//  OnboardingCompletionFlag.swift
//  Relay
//
//  RELAY-10 — Latch over App-Group UserDefaults that records whether the
//  three-screen first-run onboarding has been shown. `@Observable` so the
//  app shell can present `.fullScreenCover` based on its current value and
//  dismiss it instantly once the user taps Done on the Names screen.
//
//  One-way under normal use. There is no public "reset" surface — wiping
//  data through the QA Settings button does not affect onboarding state,
//  and that's deliberate: a parent who already named themselves and then
//  resets sample data shouldn't be greeted by Welcome again.
//

import Foundation
import Observation

@Observable
nonisolated final class OnboardingCompletionFlag: @unchecked Sendable {

    static let key = "relay.onboarding.completed"

    private let defaults: UserDefaults

    private(set) var isCompleted: Bool

    init(defaults: UserDefaults = .relayAppGroup) {
        self.defaults = defaults
        self.isCompleted = defaults.bool(forKey: Self.key)
    }

    func markCompleted() {
        isCompleted = true
        defaults.set(true, forKey: Self.key)
    }
}
