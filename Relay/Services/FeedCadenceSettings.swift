//
//  FeedCadenceSettings.swift
//  Relay
//
//  `UserDefaults` wrapper for the user-configurable feed cadence. Two scalars:
//  the cadence (hours, Double) and the projection anchor (Date, quarter-hour).
//
//  No `@Model`, no SwiftData. The feature is render-only — feed markers project
//  forward and backward from the anchor at the configured cadence (FED-004 /
//  FED-005). The PRD: "we don't log feeds — Huckleberry does that."
//
//  Declared `nonisolated final class` so it does not inherit the app target's
//  implicit MainActor isolation (CLAUDE.md §"Actor isolation in tests") and can
//  be handed to a `nonisolated` view-model in M5.
//
//  See architecture proposal §6.7.
//

import Foundation

nonisolated final class FeedCadenceSettings: Sendable {
    static let defaultHours: Double = 2.0
    static let minHours: Double = 1.0
    static let maxHours: Double = 4.0
    static let stepHours: Double = 0.5

    private let defaults: UserDefaults
    private let hoursKey = "relay.forecast.feedCadenceHours"
    private let anchorKey = "relay.forecast.feedCadenceAnchorAt"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Cadence in hours. Reads return a value clamped to `[minHours, maxHours]`
    /// and snapped to `stepHours` — even if a corrupt or out-of-range value is
    /// persisted. Writes clamp + snap before persisting. Writing for the first
    /// time also establishes the projection anchor if it is not yet set
    /// (FED-003).
    var hours: Double {
        get {
            guard defaults.object(forKey: hoursKey) != nil else {
                return Self.defaultHours
            }
            return Self.normalize(defaults.double(forKey: hoursKey))
        }
        set {
            let normalized = Self.normalize(newValue)
            defaults.set(normalized, forKey: hoursKey)
            establishAnchorIfNeeded()
        }
    }

    /// Projection anchor for feed markers. Quarter-hour boundary, seconds zero.
    /// Returns the persisted anchor; if none is persisted, persists and returns
    /// `Date.now` rounded down to the nearest quarter-hour (FED-003). Stable
    /// across reads.
    var anchorAt: Date {
        if let stored = defaults.object(forKey: anchorKey) as? Date {
            return stored
        }
        let anchor = Self.quarterHour(from: Date())
        defaults.set(anchor, forKey: anchorKey)
        return anchor
    }

    // MARK: - Helpers

    private func establishAnchorIfNeeded() {
        guard defaults.object(forKey: anchorKey) == nil else { return }
        defaults.set(Self.quarterHour(from: Date()), forKey: anchorKey)
    }

    private static func normalize(_ value: Double) -> Double {
        let snapped = (value / stepHours).rounded() * stepHours
        return min(max(snapped, minHours), maxHours)
    }

    private static func quarterHour(from date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard let minute = components.minute else { return date }
        let flooredMinute = (minute / 15) * 15
        var rounded = components
        rounded.minute = flooredMinute
        rounded.second = 0
        return calendar.date(from: rounded) ?? date
    }
}
