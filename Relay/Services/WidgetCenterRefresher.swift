//
//  WidgetCenterRefresher.swift
//  Relay
//
//  RELAY-9 — Production `WidgetRefreshing` impl that asks WidgetKit
//  to rebuild the sleep-debt widget's timeline after every store
//  commit. Lives in the app target only because WidgetKit is imported
//  here; tests use `NoopWidgetRefresher` from `WidgetRefreshing.swift`.
//

import Foundation
import WidgetKit

struct WidgetCenterRefresher: WidgetRefreshing {

    /// Kind matches the `Widget` declaration in RelayWidgetExtension.
    /// Keep these in sync — a mismatch silently no-ops.
    static let sleepDebtWidgetKind = "RelaySleepDebtWidget"

    func refresh() {
        WidgetCenter.shared.reloadTimelines(ofKind: Self.sleepDebtWidgetKind)
    }
}
