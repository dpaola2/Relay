//
//  WidgetRefreshing.swift
//  Relay
//
//  RELAY-9 — Seam between the SwiftData write path and the WidgetKit
//  reload call. The store depends on this protocol so tests can assert
//  "refresh fires on every commit" without importing WidgetKit, and so
//  the app can swap in the real `WidgetCenter` adapter at composition
//  time.
//
//  `nonisolated` mirrors the rest of the service layer (ADR-002) so the
//  protocol slots into `SwiftDataSleepSessionStore` without dragging in
//  the app target's implicit MainActor isolation.
//

import Foundation

protocol WidgetRefreshing: Sendable {
    /// Ask the system to rebuild the widget's timeline. Called from the
    /// store after every successful commit (start / end / update / delete).
    /// Implementations must be cheap and safe to call repeatedly — iOS
    /// rate-limits widget reloads on its own.
    func refresh()
}

/// Default refresher for tests, previews, and any composition where no
/// widget is actually installed. A no-op so call sites don't need
/// `Optional<WidgetRefreshing>` plumbing.
struct NoopWidgetRefresher: WidgetRefreshing {
    func refresh() {}
}
