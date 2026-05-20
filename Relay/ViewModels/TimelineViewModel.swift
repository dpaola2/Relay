//
//  TimelineViewModel.swift
//  Relay
//
//  Backs the vertical Day-view Timeline (RELAY-4). Caches sessions across a
//  7-day window so the view can slice them per displayed calendar day without
//  re-hitting the store on every swipe.
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

    /// One render-ready slice of a `SleepSession` clipped to a single calendar
    /// day's [00:00, 24:00) window. A session that spans midnight produces TWO
    /// slices (one per day) that share the same `sessionID` but get distinct
    /// `id`s so SwiftUI ForEach treats them as separate rows.
    struct DaySlice: Identifiable {
        let id: String
        let sessionID: UUID
        let session: SleepSession
        let who: Person
        let visibleStart: Date
        let visibleEnd: Date
        /// Full duration of the underlying session (not the slice). Each slice
        /// reports the whole session's length so a spanning session reads as
        /// "5h" on both sides of midnight, not "2h" + "3h".
        let fullDuration: TimeInterval
        let isOpen: Bool
    }

    /// Per-person lanes for one calendar day, in chronological order. Keyed
    /// by `Person.personA` / `.personB`; the per-person display name is
    /// supplied by `PersonNameSettings` at the view layer.
    struct DaySlices {
        let day: Date
        let personA: [DaySlice]
        let personB: [DaySlice]
    }

    private let store: any SleepSessionStore
    private let clock: any Clock
    private let calendar: Calendar

    /// Cached sessions overlapping the last-7-days window (plus a 1-day forward
    /// buffer so open sessions and edge clipping behave consistently). The view
    /// observes this property — mutating it on `refresh()` triggers redraws.
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

    // MARK: - Navigation bounds

    /// Start-of-day of the clock's current moment, in `calendar`'s time zone.
    /// Day navigation is anchored here.
    var today: Date {
        calendar.dateInterval(of: .day, for: clock.now)?.start ?? clock.now
    }

    /// Earliest day the user may navigate to — mirrors ADR-003's 7-day Edit
    /// window. `today - 6 days` so the inclusive [earliest, today] range
    /// contains exactly 7 calendar days.
    var earliestSelectableDay: Date {
        calendar.date(byAdding: .day, value: -6, to: today) ?? today
    }

    // MARK: - Refresh

    /// Re-read the 7-day window into `sessions`. Called by the view on appear
    /// and on the cross-tab `.sleepSessionsDidChange` notification.
    func refresh() {
        let lower = calendar.date(byAdding: .day, value: -7, to: clock.now) ?? clock.now
        let upper = calendar.date(byAdding: .day, value: 1, to: clock.now) ?? clock.now
        sessions = (try? store.sessions(in: lower...upper)) ?? []
    }

    // MARK: - Per-day slicing

    /// Per-person session slices for the calendar day containing `day`. Slices
    /// are clipped to `[dayStart, dayEnd)`; open sessions clip to
    /// `min(clock.now, dayEnd)` so a still-running session on a past day stops
    /// at that day's midnight rather than bleeding forward.
    func slices(for day: Date) -> DaySlices {
        guard let interval = calendar.dateInterval(of: .day, for: day) else {
            return DaySlices(day: day, personA: [], personB: [])
        }
        let dayStart = interval.start
        let dayEnd = interval.end
        let dayKey = Int(dayStart.timeIntervalSince1970)

        var personA: [DaySlice] = []
        var personB: [DaySlice] = []

        for session in sessions {
            let rawEnd = session.endedAt ?? clock.now
            let visibleStart = max(session.startedAt, dayStart)
            let visibleEnd = min(rawEnd, dayEnd)
            guard visibleStart < visibleEnd else { continue }

            let slice = DaySlice(
                id: "\(session.id.uuidString)-\(dayKey)",
                sessionID: session.id,
                session: session,
                who: session.who,
                visibleStart: visibleStart,
                visibleEnd: visibleEnd,
                fullDuration: session.duration(asOf: clock.now),
                isOpen: session.isOpen
            )
            switch session.who {
            case .personA: personA.append(slice)
            case .personB: personB.append(slice)
            }
        }

        personA.sort { $0.visibleStart < $1.visibleStart }
        personB.sort { $0.visibleStart < $1.visibleStart }
        return DaySlices(day: dayStart, personA: personA, personB: personB)
    }

    /// The current moment if it falls inside `day`'s calendar window. Used by
    /// the view to draw a "now" indicator line — nil suppresses the line.
    func nowAnchor(in day: Date) -> Date? {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return nil }
        return interval.contains(clock.now) ? clock.now : nil
    }

    // MARK: - Color identity

    /// Stable per-person color sourced from the Relay palette. Kept on the VM
    /// so the view doesn't reach into palette tokens directly.
    func color(for person: Person) -> Color {
        switch person {
        case .personA: return .relayTerracotta
        case .personB: return .relaySoftPeach
        }
    }
}
