//
//  ForecastViewModel.swift
//  Relay
//
//  The integration nexus for the Forecast feature. Marshals between
//  `ForecastEngine` (pure value-in/value-out) and `ProposedShiftStore`
//  (SwiftData persistence), owns the same-`who` run-length collapse used
//  for rendering, and manages the notification-subscription lifecycle so
//  cross-tab + DEBUG-seed mutations refresh the plan without view teardown.
//
//  Per ADR-002 / CLAUDE.md §"Engineering Methodology" item 6 this is
//  `@Observable nonisolated final class` so test mocks can drive it across
//  actor boundaries without inheriting `SWIFT_DEFAULT_ACTOR_ISOLATION`.
//
//  Architecture §6.1 (engine boundary), §1.2 (same-who collapse).
//

import Foundation
import Observation

@Observable
nonisolated final class ForecastViewModel {

    // MARK: - Public render type

    /// A run of consecutive same-`who` half-hour cells collapsed into a
    /// single rectangle for rendering. `startedAt` is the run's first cell's
    /// start; `endedAt` is the last cell's end. Architecture §1.2.
    struct RenderableBlock: Equatable, Identifiable {
        let who: Person
        let startedAt: Date
        let endedAt: Date
        var manuallyOverridden: Bool

        var id: String {
            "\(who.rawValue)-\(startedAt.timeIntervalSince1970)"
        }
    }

    // MARK: - Dependencies

    private let engine: ForecastEngine
    private let store: any ProposedShiftStore
    private let deficitProvider: any DeficitProviding
    private let clock: any Clock
    private let calendar: Calendar
    private let firstRunFlag: ForecastFirstRunFlag

    /// Standard 24h target — engine clamps deficit at 0 so this only affects
    /// the proportional split, not whether a proposal is generated.
    private let targetHoursPer24h: Double = 8.0

    /// Re-entrancy guard. `refresh(...)` mutates the store via `upsert(...)`
    /// and `delete(...)`, both of which post `.proposedShiftsDidChange`. Without
    /// this flag, the observer would recursively call `refresh(...)` from
    /// inside `refresh(...)` and spin.
    private var isRefreshing: Bool = false

    /// Active observer tokens, if `beginObserving(...)` has been called.
    /// Stored as NSObjects so `endObserving()` can remove them precisely.
    private var observers: [NSObjectProtocol] = []

    /// The planDay the active observers are scoped to. nil when not observing.
    private var observedPlanDay: Date?

    // MARK: - Init

    init(
        engine: ForecastEngine,
        store: any ProposedShiftStore,
        deficitProvider: any DeficitProviding,
        clock: any Clock,
        calendar: Calendar,
        firstRunFlag: ForecastFirstRunFlag
    ) {
        self.engine = engine
        self.store = store
        self.deficitProvider = deficitProvider
        self.clock = clock
        self.calendar = calendar
        self.firstRunFlag = firstRunFlag
    }

    deinit {
        // Defensive cleanup if the owner forgot to call `endObserving()`.
        for token in observers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Refresh (engine ↔ store marshaling)

    /// Re-runs the engine for `planDay` and reconciles the store:
    ///   1. Read existing `ProposedShift`s for `planDay` from the store.
    ///   2. Gather per-person 24h deficits from `deficitProvider`.
    ///   3. Ask the engine to propose half-hour cells (engine skips cells
    ///      aligned with overridden rows — ENG-011).
    ///   4. Upsert each proposed cell (`manuallyOverridden: false`).
    ///   5. Delete pre-existing non-overridden rows the engine no longer
    ///      proposes (stale-row reclamation).
    ///   6. Overridden rows are preserved byte-identical — never read, never
    ///      written, never deleted by this method.
    ///
    /// Idempotent: a second call with unchanged inputs upserts the same
    /// (planDay, startedAt) keys, which the store treats as in-place updates,
    /// so no duplicate rows accrue.
    func refresh(forPlanDay planDay: Date) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let existing = (try? store.shifts(forPlanDay: planDay)) ?? []
        let now = clock.now
        let deficits: [Person: TimeInterval] = [
            .dave: deficitProvider.deficit24h(
                for: .dave,
                targetHoursPer24h: targetHoursPer24h,
                asOf: now
            ),
            .bethany: deficitProvider.deficit24h(
                for: .bethany,
                targetHoursPer24h: targetHoursPer24h,
                asOf: now
            )
        ]

        let inputs = ForecastEngine.Inputs(
            planDay: planDay,
            now: now,
            calendar: calendar,
            deficits: deficits,
            targetHoursPer24h: targetHoursPer24h,
            planningWindow: ForecastEngine.PlanningWindow(startHour: 22, endHour: 6),
            existingShifts: existing
        )
        let proposed = engine.propose(inputs)

        // Step 4: write engine output (skips overridden positions because the
        // engine omits them from the returned array per ENG-011).
        let proposedStarts: Set<Date> = Set(proposed.map(\.startedAt))
        for cell in proposed {
            _ = try? store.upsert(
                planDay: planDay,
                startedAt: cell.startedAt,
                who: cell.who,
                manuallyOverridden: false
            )
        }

        // Step 5: reclaim stale non-overridden rows the engine no longer
        // proposes. Overridden rows are skipped — ENG-011 preservation.
        for row in existing where !row.manuallyOverridden
            && !proposedStarts.contains(row.startedAt) {
            try? store.delete(row)
        }
    }

    // MARK: - Renderable blocks (same-who run collapse)

    /// Reads all `ProposedShift`s for `planDay` (sorted by `startedAt`) and
    /// collapses consecutive same-`who` half-hour rows into single rectangles.
    /// A gap (missing half-hour cell) or a `who` change breaks the run.
    /// Architecture §1.2 — pure logic, no SwiftData mutation.
    func renderableBlocks(forPlanDay planDay: Date) -> [RenderableBlock] {
        let rows = (try? store.shifts(forPlanDay: planDay)) ?? []
        guard !rows.isEmpty else { return [] }

        var blocks: [RenderableBlock] = []
        var runStart: Date = rows[0].startedAt
        var runEnd: Date = rows[0].endedAt
        var runWho: Person = rows[0].who
        var runOverridden: Bool = rows[0].manuallyOverridden

        for row in rows.dropFirst() {
            let contiguous = row.startedAt == runEnd
            if contiguous && row.who == runWho {
                runEnd = row.endedAt
                // Any overridden cell in the run flags the whole rectangle.
                runOverridden = runOverridden || row.manuallyOverridden
                continue
            }
            blocks.append(RenderableBlock(
                who: runWho,
                startedAt: runStart,
                endedAt: runEnd,
                manuallyOverridden: runOverridden
            ))
            runStart = row.startedAt
            runEnd = row.endedAt
            runWho = row.who
            runOverridden = row.manuallyOverridden
        }
        blocks.append(RenderableBlock(
            who: runWho,
            startedAt: runStart,
            endedAt: runEnd,
            manuallyOverridden: runOverridden
        ))
        return blocks
    }

    // MARK: - Notification-driven refresh

    /// Subscribes to `.sleepSessionsDidChange` and `.proposedShiftsDidChange`.
    /// Each posted notification triggers `refresh(forPlanDay:)` against the
    /// supplied planDay. Call `endObserving()` before deinit (or the deinit
    /// fallback will clean up). Idempotent: calling twice replaces the
    /// existing subscription.
    func beginObserving(planDay: Date) {
        endObserving()
        observedPlanDay = planDay
        let center = NotificationCenter.default
        let handler: (Notification) -> Void = { [weak self] _ in
            guard let self else { return }
            guard let day = self.observedPlanDay else { return }
            self.refresh(forPlanDay: day)
        }
        observers.append(center.addObserver(
            forName: .sleepSessionsDidChange,
            object: nil,
            queue: nil,
            using: handler
        ))
        observers.append(center.addObserver(
            forName: .proposedShiftsDidChange,
            object: nil,
            queue: nil,
            using: handler
        ))
    }

    /// Tears down active observers. Safe to call without a prior
    /// `beginObserving(...)` (no-op).
    func endObserving() {
        let center = NotificationCenter.default
        for token in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
        observedPlanDay = nil
    }

    // MARK: - Derived state for the first-run philosophy card

    /// Whether the one-time first-run philosophy card should be visible.
    /// `false` once the user dismisses it (PHL-005 / PHL-006).
    var shouldShowFirstRunCard: Bool {
        !firstRunFlag.dismissed
    }

    /// Marks the card dismissed. Idempotent — the flag is a one-way latch.
    func dismissFirstRunCard() {
        firstRunFlag.dismissed = true
    }
}
