//
//  SleepSessionStore+Environment.swift
//  Relay
//
//  SwiftUI environment seam so views can pull the store via
//  `@Environment(\.sleepSessionStore)` (Arch §3.2).
//

import SwiftUI

private struct SleepSessionStoreKey: EnvironmentKey {
    static let defaultValue: (any SleepSessionStore)? = nil
}

extension EnvironmentValues {
    var sleepSessionStore: (any SleepSessionStore)? {
        get { self[SleepSessionStoreKey.self] }
        set { self[SleepSessionStoreKey.self] = newValue }
    }
}
