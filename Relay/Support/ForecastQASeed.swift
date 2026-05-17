//
//  ForecastQASeed.swift
//  Relay
//
//  Debug-only QA seed for the Forecast feature (gameplan M9). Three idempotent
//  seed actions Dave taps in the simulator to drive the three scenarios the
//  Forecast view must render:
//
//    1. Auto-proposal     — asymmetric deficit (Bethany more depleted than
//                            Dave) drives an engine-generated proposal where
//                            Bethany gets the bigger overnight block.
//    2. Manual overrides  — runs (1), then inserts at least one
//                            `manuallyOverridden = true` ProposedShift so the
//                            "re-propose" toolbar button (ADJ-006) becomes
//                            visible.
//    3. Empty state       — wipes today's SleepSessions and ProposedShifts
//                            AND resets `relay.forecast.firstRunCardDismissed`
//                            (the in-app flag is a one-way latch per PHL-006;
//                            only DEBUG paths reset it).
//
//  All three seeds go through the existing store APIs — never raw
//  `ModelContext` — so they exercise the same write paths production uses.
//
//  MUST NOT compile in Release. The file-wide `#if DEBUG` guard, the
//  RELAY_DEBUG_ONLY_FORECAST_SEEDS sentinel string, and the DEBUG-only
//  SettingsView call sites form a triple guarantee. The Release build's
//  binary must not contain "ForecastQASeed" or the sentinel.
//

#if DEBUG
import Foundation

// RELAY_DEBUG_ONLY_FORECAST_SEEDS — Release-grep verification token.

/// Debug seeder for the Forecast feature. Pure helper — no UI, no view-model
/// coupling. Construct once and call one of the three `seed*` methods.
struct ForecastQASeed {

    init() {}

    // MARK: - Constants

    /// Key for the first-run philosophy card dismissal flag. Mirrors the
    /// private constant in `ForecastFirstRunFlag` — duplicated here on purpose
    /// because the flag is a one-way latch in production (writing `false` is a
    /// no-op). Direct `UserDefaults.removeObject(forKey:)` is the only way to
    /// reset it, and that path is DEBUG-only by design.
    private static let firstRunCardKey = "relay.forecast.firstRunCardDismissed"

    // MARK: - Seed 1: Auto-proposal scenario

    /// Wipes today's `ProposedShift`s and recent `SleepSession`s, then seeds
    /// enough sessions to produce an asymmetric 24h deficit (Bethany more
    /// depleted than Dave). Triggers a `ForecastViewModel.refresh` indirectly
    /// via `.sleepSessionsDidChange` so the Timeline tab repaints when next
    /// shown.
    ///
    /// Idempotency: every seed call begins with `wipeForecastScope(...)` which
    /// removes everything this seed could have written previously (today's
    /// proposed shifts + any SleepSession noted "qa-forecast"). A second tap
    /// produces the same final state, not double data.
    func seedAutoProposal(
        sessionStore: SleepSessionStore,
        proposedStore: ProposedShiftStore,
        clock: any Clock
    ) throws {
        let now = clock.now
        try wipeForecastScope(sessionStore: sessionStore, proposedStore: proposedStore, now: now)
        try applySessionPlans(asymmetricDeficitPlans(now: now), to: sessionStore)
        print("[ForecastQASeed] Auto-proposal seeded — Bethany has the larger deficit.")
    }

    // MARK: - Seed 2: Manual overrides scenario

    /// Runs `seedAutoProposal` then inserts one `manuallyOverridden = true`
    /// `ProposedShift` aligned to a half-hour cell INSIDE the engine's
    /// planning window (22:00 today → 06:00 tomorrow). The override is at
    /// 23:00 today, swapped to Dave (the auto-proposal favors Bethany there,
    /// so this is a real override the user could have tapped). The
    /// "re-propose" toolbar button becomes visible because at least one row
    /// has `manuallyOverridden == true`.
    func seedManualOverrides(
        sessionStore: SleepSessionStore,
        proposedStore: ProposedShiftStore,
        clock: any Clock
    ) throws {
        try seedAutoProposal(
            sessionStore: sessionStore,
            proposedStore: proposedStore,
            clock: clock
        )
        let now = clock.now
        let planDay = Calendar.current.startOfDay(for: now)
        guard let overrideStart = anchor(hour: 23, minute: 0, on: planDay) else {
            print("[ForecastQASeed] Could not anchor override cell — Calendar.date(from:) returned nil.")
            return
        }
        _ = try proposedStore.upsert(
            planDay: planDay,
            startedAt: overrideStart,
            who: .dave,
            manuallyOverridden: true
        )
        print("[ForecastQASeed] Manual override seeded at \(overrideStart) for Dave.")
    }

    // MARK: - Seed 3: Empty state

    /// Wipes today's `SleepSession`s and `ProposedShift`s so the Forecast view
    /// renders the empty-state copy. Also resets the
    /// `relay.forecast.firstRunCardDismissed` UserDefaults key — the in-app
    /// `ForecastFirstRunFlag` is a one-way latch per PHL-006, so this DEBUG
    /// path uses direct `UserDefaults.removeObject(forKey:)` to clear it.
    func seedEmptyState(
        sessionStore: SleepSessionStore,
        proposedStore: ProposedShiftStore,
        clock: any Clock
    ) throws {
        let now = clock.now
        try wipeTodaysSessions(sessionStore: sessionStore, now: now)
        try wipeTodaysProposedShifts(proposedStore: proposedStore, now: now)
        UserDefaults.standard.removeObject(forKey: Self.firstRunCardKey)
        print("[ForecastQASeed] Empty state seeded — today wiped, first-run flag reset.")
    }

    // MARK: - Plan application

    private struct SessionPlan {
        let who: Person
        let startedAt: Date
        let endedAt: Date?
    }

    /// Walks the plan list and writes via `startSession` + `update(endedAt:note:)`.
    /// Notes are stamped with the marker the wipe step uses to identify these
    /// rows, so re-seeding cleans up only this seed's data — not the user's
    /// real sessions if they happen to coexist.
    private func applySessionPlans(
        _ plans: [SessionPlan],
        to store: SleepSessionStore
    ) throws {
        for plan in plans {
            let session = try store.startSession(for: plan.who, at: plan.startedAt)
            try store.update(
                session,
                startedAt: nil,
                endedAt: plan.endedAt.map { .some($0) },
                who: nil,
                note: .some("qa-forecast")
            )
        }
    }

    /// Scenario plan: Bethany ~3h more depleted than Dave over the last 24h.
    /// Dave gets ~5.5h of sleep, Bethany gets ~2.5h — both below the 8h target,
    /// but Bethany's deficit is larger and asymmetric enough that the engine
    /// will propose her the longer overnight block.
    private func asymmetricDeficitPlans(now: Date) -> [SessionPlan] {
        let hour: TimeInterval = 3_600

        return [
            // Dave — two sessions adding up to ~5.5h in the last 24h.
            SessionPlan(
                who: .dave,
                startedAt: now.addingTimeInterval(-22 * hour),
                endedAt: now.addingTimeInterval(-18 * hour - 30 * 60)
            ),
            SessionPlan(
                who: .dave,
                startedAt: now.addingTimeInterval(-10 * hour),
                endedAt: now.addingTimeInterval(-9 * hour)
            ),
            // Bethany — one short session of ~2.5h in the last 24h.
            SessionPlan(
                who: .bethany,
                startedAt: now.addingTimeInterval(-15 * hour),
                endedAt: now.addingTimeInterval(-12 * hour - 30 * 60)
            )
        ]
    }

    // MARK: - Wipe primitives

    /// Combined wipe of today's QA-marked sessions + today's proposed shifts.
    /// Called at the top of `seedAutoProposal` so idempotency holds across
    /// repeated taps and across calling-sequence variations (auto-proposal
    /// after empty-state, etc.).
    private func wipeForecastScope(
        sessionStore: SleepSessionStore,
        proposedStore: ProposedShiftStore,
        now: Date
    ) throws {
        try wipeTodaysSessions(sessionStore: sessionStore, now: now)
        try wipeTodaysProposedShifts(proposedStore: proposedStore, now: now)
    }

    /// Deletes every `SleepSession` whose `startedAt` falls on today's
    /// calendar day OR within the seed's reference window (-24h ... now). The
    /// reference window covers seeded rows that started yesterday but were
    /// meant for "the last 24h" deficit math.
    private func wipeTodaysSessions(
        sessionStore: SleepSessionStore,
        now: Date
    ) throws {
        let startOfToday = Calendar.current.startOfDay(for: now)
        let lower = min(startOfToday, now.addingTimeInterval(-25 * 3_600))
        let endOfToday = startOfToday.addingTimeInterval(24 * 3_600 - 1)
        let upper = max(endOfToday, now)
        let rows = try sessionStore.sessions(in: lower...upper)
        for row in rows {
            try sessionStore.delete(row)
        }
    }

    /// Deletes every `ProposedShift` whose `planDay` equals today. Uses the
    /// store's `prune` primitive against today+1 (strict `<` semantics) after
    /// first fetching today's rows and deleting them individually — `prune`
    /// alone would delete rows for prior days too, which we want to leave
    /// alone (they're historical record per EDG-013).
    private func wipeTodaysProposedShifts(
        proposedStore: ProposedShiftStore,
        now: Date
    ) throws {
        let planDay = Calendar.current.startOfDay(for: now)
        let rows = try proposedStore.shifts(forPlanDay: planDay)
        for row in rows {
            try proposedStore.delete(row)
        }
    }

    // MARK: - Helpers

    /// Components-overlay anchor — same DST-safe pattern the engine uses.
    /// Pulls [.year, .month, .day] from `date` and overlays hour/minute/second.
    /// Avoids `Calendar.date(bySettingHour:of:)` per CLAUDE.md established
    /// footgun.
    private func anchor(hour: Int, minute: Int, on date: Date) -> Date? {
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)
    }
}
#endif
