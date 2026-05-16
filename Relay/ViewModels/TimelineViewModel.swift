//
//  TimelineViewModel.swift
//  Relay
//
//  The Timeline-screen view model (Arch §3.3 / gameplan M4). Exposes a 72h
//  window relative to `clock.now`, the sessions that overlap it, a stable
//  per-person color identity, an "effective end" derivation so open sessions
//  render extending to `clock.now`, and the day/night shading bands the view
//  paints behind the session blocks.
//
//  Per ADR-002 / CLAUDE.md §"Engineering Methodology" item 6 this is
//  `@Observable nonisolated final class` so test mocks can drive it across
//  actor boundaries without inheriting `SWIFT_DEFAULT_ACTOR_ISOLATION`.
//

import Foundation
import Observation
import SwiftUI

@Observable
nonisolated final class TimelineViewModel {
    /// A day/night shading band — a closed interval in absolute time. The view
    /// paints these as the timeline background; the view model derives them so
    /// the math is testable without a SwiftUI view tree.
    struct NightBand: Equatable, Sendable {
        let start: Date
        let end: Date
    }

    private let store: any SleepSessionStore
    private let clock: any Clock
    private let calendar: Calendar

    /// Sessions overlapping the 72h window, sorted oldest-first. Driven by
    /// `refresh()`.
    var sessions: [SleepSession] = []

    init(
        store: any SleepSessionStore,
        clock: any Clock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.store = store
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: - Window

    var windowEnd: Date { clock.now }
    var windowStart: Date { windowEnd.addingTimeInterval(-72 * 3_600) }

    // MARK: - Refresh

    /// Re-read sessions overlapping the 72h window from the store. Called by
    /// the view on appear.
    func refresh() {
        let range = windowStart...windowEnd
        sessions = (try? store.sessions(in: range)) ?? []
    }

    // MARK: - Derivations

    /// For rendering — closed sessions return their `endedAt`, open sessions
    /// return `clock.now` (TML-005).
    func effectiveEnd(of session: SleepSession) -> Date {
        session.endedAt ?? clock.now
    }

    /// Stable, distinct color per person (TML-002). Hue values chosen for dark
    /// mode contrast; the view binds to these directly.
    func color(for person: Person) -> Color {
        switch person {
        case .dave: return Color(red: 0.40, green: 0.65, blue: 1.00)
        case .bethany: return Color(red: 1.00, green: 0.55, blue: 0.75)
        }
    }

    /// Night-shading bands across the 72h window (TML-003). Each band runs
    /// from 22:00 to 06:00 local time on each day the window touches, clipped
    /// to `[windowStart, windowEnd]`.
    var nightBands: [NightBand] {
        var bands: [NightBand] = []
        let start = windowStart
        let end = windowEnd

        // Walk back to the start-of-day containing windowStart, then step
        // forward day-by-day generating a (22:00 prev-day → 06:00 this-day)
        // band for each calendar day in the window.
        guard let firstDay = calendar.dateInterval(of: .day, for: start)?.start else {
            return []
        }
        var dayCursor = firstDay
        let oneDay: TimeInterval = 24 * 3_600
        // Add one extra day of slack on either side so a band that begins the
        // previous evening can still be emitted for the first day in window.
        let stopAt = end.addingTimeInterval(oneDay)
        while dayCursor <= stopAt {
            if let band = nightBand(forDayStartingAt: dayCursor, clippedTo: start...end) {
                bands.append(band)
            }
            dayCursor = dayCursor.addingTimeInterval(oneDay)
        }
        return bands
    }

    // MARK: - Private

    /// Builds the band for the night that begins at 22:00 of the calendar day
    /// previous to `dayStart` and ends at 06:00 of `dayStart`. Returns nil if
    /// the band doesn't intersect the window.
    private func nightBand(
        forDayStartingAt dayStart: Date,
        clippedTo window: ClosedRange<Date>
    ) -> NightBand? {
        let nightStart = dayStart.addingTimeInterval(-2 * 3_600)   // previous day 22:00
        let nightEnd = dayStart.addingTimeInterval(6 * 3_600)      // this day 06:00
        let clippedStart = max(nightStart, window.lowerBound)
        let clippedEnd = min(nightEnd, window.upperBound)
        guard clippedStart < clippedEnd else { return nil }
        return NightBand(start: clippedStart, end: clippedEnd)
    }
}
