//
//  PersonNameSettings+Environment.swift
//  Relay
//
//  RELAY-10 — SwiftUI environment seam so views can read the household's
//  configured display names without each call site holding a reference.
//  Mirrors `WidgetRefreshing+Environment.swift`.
//

import SwiftUI

private struct PersonNameSettingsKey: EnvironmentKey {
    /// Falls back to an in-memory `PersonNameSettings` so previews and any
    /// view rendered outside the live app graph still resolve a settings
    /// object. The fallback uses a private suite so it can't accidentally
    /// pollute the App Group store under test.
    static let defaultValue: PersonNameSettings = PersonNameSettings(
        defaults: UserDefaults(suiteName: "preview.PersonNameSettings.defaultValue") ?? .standard,
        widgetRefresher: NoopWidgetRefresher()
    )
}

extension EnvironmentValues {
    var personNameSettings: PersonNameSettings {
        get { self[PersonNameSettingsKey.self] }
        set { self[PersonNameSettingsKey.self] = newValue }
    }
}
