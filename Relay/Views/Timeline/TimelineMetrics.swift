//
//  TimelineMetrics.swift
//  Relay
//
//  Shared layout constants for the vertical Day-view timeline. Kept in a
//  module-internal namespace so `DayTimelineView`, `ForecastOverlayView`, and
//  any future overlays compute `y` offsets from the same numbers (ADR-002 —
//  half-hour positional rendering on the unchanged hour grid).
//

import Foundation
import CoreGraphics

enum TimelineMetrics {
    /// Pixel height of one hour band in the scroll view (matches RELAY-4).
    static let hourRowHeight: CGFloat = 64

    /// Width of the left rail that holds hour labels and feed markers.
    static let gutterWidth: CGFloat = 48

    /// Total scroll content height — 24 hours of bands.
    static let dayHeight: CGFloat = hourRowHeight * 24

    /// Half-hour height. Forecast blocks and tap-cells are positioned in
    /// multiples of this (`y = (secondsFromStartOfDay / 1800) * halfHourHeight`).
    static let halfHourHeight: CGFloat = hourRowHeight / 2

    /// Y-offset for `date` measured from `dayStart`. Shared so overlay
    /// rectangles, the now-line, and SessionBlockButton all align.
    static func yOffset(for date: Date, dayStart: Date) -> CGFloat {
        let seconds = max(0, date.timeIntervalSince(dayStart))
        return CGFloat(seconds) / 3_600 * hourRowHeight
    }
}
