//
//  ProposedShiftStore+Environment.swift
//  Relay
//
//  SwiftUI environment seam so views can pull the store via
//  `@Environment(\.proposedShiftStore)`. Kept in its own file because
//  `EnvironmentKey` / `EnvironmentValues` live in SwiftUI, not Foundation
//  (CLAUDE.md §"Engineering Methodology" item 6 — keep SwiftUI environment
//  seams off Foundation-only service files).
//

import SwiftUI

private struct ProposedShiftStoreKey: EnvironmentKey {
    static let defaultValue: (any ProposedShiftStore)? = nil
}

extension EnvironmentValues {
    var proposedShiftStore: (any ProposedShiftStore)? {
        get { self[ProposedShiftStoreKey.self] }
        set { self[ProposedShiftStoreKey.self] = newValue }
    }
}
