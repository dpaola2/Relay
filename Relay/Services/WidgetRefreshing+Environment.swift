//
//  WidgetRefreshing+Environment.swift
//  Relay
//
//  RELAY-9 — SwiftUI environment seam so views that construct a
//  `SwiftDataSleepSessionStore` can pull the production widget
//  refresher without each call site importing WidgetKit. Mirrors
//  the existing `SleepSessionStore+Environment.swift` shape.
//

import SwiftUI

private struct WidgetRefresherKey: EnvironmentKey {
    static let defaultValue: any WidgetRefreshing = NoopWidgetRefresher()
}

extension EnvironmentValues {
    var widgetRefresher: any WidgetRefreshing {
        get { self[WidgetRefresherKey.self] }
        set { self[WidgetRefresherKey.self] = newValue }
    }
}
