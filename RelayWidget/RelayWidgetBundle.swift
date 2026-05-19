//
//  RelayWidgetBundle.swift
//  RelayWidget
//
//  RELAY-9 — entry point for the widget extension. v1.5 ships only
//  the sleep-debt widget; no control widgets, no live activities.
//

import WidgetKit
import SwiftUI

@main
struct RelayWidgetBundle: WidgetBundle {
    var body: some Widget {
        RelayWidget()
    }
}
