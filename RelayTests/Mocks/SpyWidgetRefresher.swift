//
//  SpyWidgetRefresher.swift
//  RelayTests
//
//  RELAY-9 — Sleep-debt widget. Spy that captures calls to
//  `WidgetRefreshing.refresh()` so the store's commit hook can be
//  asserted without importing WidgetKit in the test target.
//

import Foundation
@testable import Relay

final class SpyWidgetRefresher: WidgetRefreshing, @unchecked Sendable {
    private(set) var refreshCount = 0
    func refresh() { refreshCount += 1 }
}
