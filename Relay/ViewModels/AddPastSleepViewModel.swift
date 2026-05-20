//
//  AddPastSleepViewModel.swift
//  Relay
//
//  Headless view model behind the "Add Past Sleep" sheet (RELAY-2 / M1).
//  Owns form state, defaults at sheet-open, validation, and the two-call save
//  path through the existing `SleepSessionStore` (ADR-001).
//
//  - DEF-002 / DEF-003: defaults to yesterday 11pm → today 7am in the injected
//                       calendar's zone, computed at init.
//  - DEF-001 (ADR-002): sticky `Who` derived at sheet-open from
//                       `store.sessions(in: last 24h)`, newest-first; `.personA`
//                       cold-start and on `throw`.
//  - VAL-001..VAL-005: a single `validationError` priority chain drives both
//                      Save enablement and the helper copy surfaced inline.
//  - STO-001..STO-005: `save()` uses `startSession(for:at:)` followed by
//                      `update(_:startedAt:endedAt:who:note:)` — matches the
//                      precedent in `Relay/Support/QASeed.swift`.
//
//  Per ADR-002 / CLAUDE.md §"Engineering Methodology" item 6 this is
//  `@Observable nonisolated final class` so test mocks (`@unchecked Sendable`)
//  conform across actor boundaries without inheriting the app target's
//  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
//

import Foundation
import Observation

@Observable
nonisolated final class AddPastSleepViewModel {
    private let store: any SleepSessionStore
    private let clock: any Clock
    private let calendar: Calendar

    // Form state — bound to the sheet's controls.
    var who: Person
    var startedAt: Date
    var endedAt: Date
    var note: String = ""

    init(
        store: any SleepSessionStore,
        clock: any Clock = SystemClock(),
        calendar: Calendar = .current
    ) {
        self.store = store
        self.clock = clock
        self.calendar = calendar
        let defaults = Self.defaults(now: clock.now, calendar: calendar)
        self.startedAt = defaults.startedAt
        self.endedAt = defaults.endedAt
        self.who = (try? Self.resolveDefaultWho(store: store, now: clock.now)) ?? .personA
    }

    // MARK: - Defaults (DEF-002, DEF-003, DEF-004)

    /// "Yesterday 11:00 PM → today 7:00 AM" in the supplied calendar's zone,
    /// computed from `now`. Pure — fully testable through `FakeClock`.
    ///
    /// Builds the date from `now`'s year/month/day components and overlays an
    /// explicit hour/minute, so the result is anchored to *today* regardless of
    /// where the time-of-day falls relative to `now`. Avoids the surprise where
    /// `Calendar.date(bySettingHour:of:)`'s default `.forward` search rolls to
    /// the next day when the requested hour is earlier than `now`'s hour.
    static func defaults(
        now: Date,
        calendar: Calendar
    ) -> (startedAt: Date, endedAt: Date) {
        let todayAt = { (hour: Int) -> Date in
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = hour
            comps.minute = 0
            comps.second = 0
            return calendar.date(from: comps) ?? now
        }
        let todaySevenAM = todayAt(7)
        let todayElevenPM = todayAt(23)
        let yesterdayElevenPM = calendar.date(
            byAdding: .day, value: -1, to: todayElevenPM
        ) ?? now
        return (yesterdayElevenPM, todaySevenAM)
    }

    /// DEF-001 sticky `Who`: pick the `who` of the most-recent session whose
    /// `startedAt` falls inside the trailing 24-hour window. Cold-start and
    /// throw paths both fall back to `.personA` (ADR-002).
    ///
    /// `store.sessions(in:)` uses overlap semantics (a session whose interval
    /// touches the range is returned), so we additionally clamp to `startedAt
    /// >= dayAgo` — the anchor is the start of the activity, not its tail.
    static func resolveDefaultWho(
        store: any SleepSessionStore,
        now: Date
    ) throws -> Person {
        let dayAgo = now.addingTimeInterval(-24 * 3_600)
        let recent = try store.sessions(in: dayAgo...now)
            .filter { $0.startedAt >= dayAgo }
        return recent.max(by: { $0.startedAt < $1.startedAt })?.who ?? .personA
    }

    // MARK: - Derived (UI-005, VAL-001..VAL-005)

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    /// Trailing 7-day cutoff — mirrors `EditViewModel.windowStart`.
    var windowStart: Date { clock.now.addingTimeInterval(-7 * 24 * 3_600) }

    /// Single source of truth for Save enablement and helper copy. Priority
    /// chain (VAL-001 > VAL-003 > VAL-002).
    var validationError: ValidationError? {
        if startedAt >= endedAt { return .endBeforeStart }
        if endedAt > clock.now { return .endInFuture }
        if startedAt < windowStart { return .startOutsideSevenDayWindow }
        return nil
    }

    var isSaveEnabled: Bool { validationError == nil }

    var validationMessage: String? { validationError?.helperCopy }

    // MARK: - Save (STO-001..STO-005)

    /// Persist a closed `SleepSession` via the two-call pattern. No-op when
    /// `validationError != nil` (defensive belt-and-suspenders — Save is
    /// disabled in the UI, but the VM does not assume that).
    ///
    /// Whitespace-only notes are normalized to `nil` so the persisted row
    /// matches a Now-captured session that was never tapped through the note
    /// field (STO-002 — schema-identical).
    func save() throws {
        guard validationError == nil else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = try store.startSession(for: who, at: startedAt)
        try store.update(
            session,
            startedAt: nil,
            endedAt: .some(endedAt),
            who: nil,
            note: trimmed.isEmpty ? nil : .some(trimmed)
        )
    }
}

extension AddPastSleepViewModel {
    enum ValidationError: Equatable {
        case endBeforeStart
        case endInFuture
        case startOutsideSevenDayWindow

        /// VAL-004 inline helper copy. Final wording is implementer's call
        /// per PRD Q5; these are the architectural defaults.
        var helperCopy: String {
            switch self {
            case .endBeforeStart:
                return "Fell asleep must be before woke up."
            case .endInFuture:
                return "Woke up can't be in the future."
            case .startOutsideSevenDayWindow:
                return "Sleep older than 7 days can't be added."
            }
        }
    }
}
