//
//  ProposedShiftStore.swift
//  Relay
//
//  The protocol view models depend on to read and mutate the Forecast plan.
//  Mirrors `SleepSessionStore`: `nonisolated`, `Sendable`, with an in-memory
//  test double in `RelayTests/Mocks/InMemoryProposedShiftStore.swift` and a
//  SwiftData concrete in `SwiftDataProposedShiftStore.swift`.
//
//  Identity for `upsert(...)` is the composite `(planDay, startedAt)`; calling
//  twice with the same composite key updates in place — no duplicates.
//
//  `cycle(...)` keeps tap semantics OFF the view: it advances a cell through
//  the 4-state rotation Dave → Bethany → unassigned → engine-proposal and
//  manages the `manuallyOverridden` flag per ADJ-002 / ADJ-003 (returning to
//  the current engine proposal clears the override).
//
//  Architecture §6.6.
//

import Foundation

extension Notification.Name {
    /// Posted after any successful `ProposedShiftStore` write (`upsert`,
    /// `cycle`, `delete`, `prune`). `ForecastViewModel` observes this to
    /// re-read its cached projections so cross-tab and DEBUG-seed mutations
    /// are reflected without view teardown. Mirrors `.sleepSessionsDidChange`.
    static let proposedShiftsDidChange = Notification.Name("relay.proposedShiftsDidChange")
}

protocol ProposedShiftStore: AnyObject, Sendable {
    // Reads
    func shifts(forPlanDay planDay: Date) throws -> [ProposedShift]

    // Writes — idempotent on (planDay, startedAt) composite key.
    func upsert(
        planDay: Date,
        startedAt: Date,
        who: Person,
        manuallyOverridden: Bool
    ) throws -> ProposedShift

    /// 4-state cycle helper (ADJ-001). Returns the new state, or `nil` when
    /// the cell ends up unassigned.
    ///
    /// Order: `Dave → Bethany → unassigned → engine-proposal → Dave → …`
    ///
    /// Override flag (ADJ-002 / ADJ-003): re-cycling to `currentEngineProposal`
    /// clears the flag; any other transition sets it.
    func cycle(
        planDay: Date,
        startedAt: Date,
        currentEngineProposal: Person?
    ) throws -> ProposedShift?

    func delete(_ shift: ProposedShift) throws

    /// Deletes rows with `planDay < cutoffPlanDay`. Strict `<` semantics —
    /// rows whose `planDay` equals the cutoff remain. Matches the 7-day
    /// retention policy in ADR-003 (callers compute cutoff as `today − 6 days`).
    func prune(olderThan cutoffPlanDay: Date) throws
}
