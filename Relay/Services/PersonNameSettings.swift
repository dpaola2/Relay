//
//  PersonNameSettings.swift
//  Relay
//
//  RELAY-10 — Configurable per-person display names. `@Observable` so views
//  re-render on change; `nonisolated` so it can be constructed and read
//  across the SwiftUI/MainActor boundary without inheriting the app target's
//  implicit MainActor isolation (ADR-002).
//
//  Persistence: App-Group `UserDefaults`. Widget extension reads the same
//  suite via its literal name (`WidgetAppGroup.identifier`) so a name change
//  in the app is visible the next time iOS reloads the widget's timeline.
//

import Foundation
import Observation

@Observable
nonisolated final class PersonNameSettings: @unchecked Sendable {

    /// UserDefaults keys — kept in one place so the widget side can read the
    /// same strings without re-deriving them.
    enum Keys {
        static let nameA = "relay.person.nameA"
        static let nameB = "relay.person.nameB"
    }

    private let defaults: UserDefaults
    private let widgetRefresher: any WidgetRefreshing

    var nameA: String {
        didSet {
            defaults.set(nameA, forKey: Keys.nameA)
            widgetRefresher.refresh()
        }
    }

    var nameB: String {
        didSet {
            defaults.set(nameB, forKey: Keys.nameB)
            widgetRefresher.refresh()
        }
    }

    init(
        defaults: UserDefaults = .relayAppGroup,
        widgetRefresher: any WidgetRefreshing = NoopWidgetRefresher()
    ) {
        self.defaults = defaults
        self.widgetRefresher = widgetRefresher
        self.nameA = defaults.string(forKey: Keys.nameA) ?? ""
        self.nameB = defaults.string(forKey: Keys.nameB) ?? ""
    }

    /// Resolve a `Person` to its display string. Empty stored names fall back
    /// to `"Person A"` / `"Person B"` so a widget added before onboarding
    /// completes still renders something legible.
    func displayName(for person: Person) -> String {
        switch person {
        case .personA: return nameA.isEmpty ? "Person A" : nameA
        case .personB: return nameB.isEmpty ? "Person B" : nameB
        }
    }
}
