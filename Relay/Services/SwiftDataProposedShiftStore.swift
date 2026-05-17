//
//  SwiftDataProposedShiftStore.swift
//  Relay
//
//  Concrete `ProposedShiftStore` backed by a SwiftData `ModelContext`. Declared
//  `nonisolated` so it does not pick up the app target's implicit MainActor
//  isolation (ADR-002).
//
//  Behavior mirrors `InMemoryProposedShiftStore` (the test double) bit-for-bit:
//  - `upsert(...)` is idempotent on `(planDay, startedAt)`.
//  - `cycle(...)` advances Dave → Bethany → unassigned → engine-proposal and
//    manages the `manuallyOverridden` flag (ADJ-002 / ADJ-003).
//  - `prune(...)` deletes rows with `planDay < cutoffPlanDay`.
//  - `.proposedShiftsDidChange` is posted after every write — including
//    `prune` calls that remove zero rows (callers may use the notification
//    as a generic refresh signal).
//

import Foundation
import SwiftData

/// `@unchecked Sendable` because `ModelContext` is not `Sendable`-conforming.
/// Used from a single context at a time in v1 (app thread or test thread), so
/// the unchecked promise holds. Revisit when SwiftData ships `Sendable`
/// `ModelContext` support (CLAUDE.md §"Engineering Methodology" item 6).
nonisolated final class SwiftDataProposedShiftStore: ProposedShiftStore, @unchecked Sendable {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    private func notifyDidChange() {
        NotificationCenter.default.post(name: .proposedShiftsDidChange, object: nil)
    }

    // MARK: - Reads

    func shifts(forPlanDay planDay: Date) throws -> [ProposedShift] {
        let descriptor = FetchDescriptor<ProposedShift>(
            predicate: #Predicate { $0.planDay == planDay },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Writes

    func upsert(
        planDay: Date,
        startedAt: Date,
        who: Person,
        manuallyOverridden: Bool
    ) throws -> ProposedShift {
        if let existing = try fetch(planDay: planDay, startedAt: startedAt) {
            existing.who = who
            existing.manuallyOverridden = manuallyOverridden
            existing.updatedAt = .now
            try context.save()
            notifyDidChange()
            return existing
        }

        let shift = ProposedShift(
            planDay: planDay,
            who: who,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            manuallyOverridden: manuallyOverridden
        )
        context.insert(shift)
        try context.save()
        notifyDidChange()
        return shift
    }

    func cycle(
        planDay: Date,
        startedAt: Date,
        currentEngineProposal: Person?
    ) throws -> ProposedShift? {
        let existing = try fetch(planDay: planDay, startedAt: startedAt)
        let currentWho: Person? = existing?.who

        // Cycle order: Dave → Bethany → unassigned → engine-proposal → Dave → …
        let next: Person?
        switch currentWho {
        case .dave:
            next = .bethany
        case .bethany:
            next = nil
        case nil:
            next = currentEngineProposal
        }

        if let next {
            // Override flag: returning to the engine's proposed assignment
            // clears the flag (ADJ-003); any other transition sets it.
            let newOverridden = (next != currentEngineProposal)
            return try upsert(
                planDay: planDay,
                startedAt: startedAt,
                who: next,
                manuallyOverridden: newOverridden
            )
            // upsert already posted .proposedShiftsDidChange.
        }

        // Unassigned: delete the underlying row if any. Always post the
        // change notification — the cycle itself is the write.
        if let existing {
            context.delete(existing)
            try context.save()
        }
        notifyDidChange()
        return nil
    }

    func delete(_ shift: ProposedShift) throws {
        context.delete(shift)
        try context.save()
        notifyDidChange()
    }

    func prune(olderThan cutoffPlanDay: Date) throws {
        let descriptor = FetchDescriptor<ProposedShift>(
            predicate: #Predicate { $0.planDay < cutoffPlanDay }
        )
        let stale = try context.fetch(descriptor)
        for row in stale {
            context.delete(row)
        }
        if !stale.isEmpty {
            try context.save()
        }
        notifyDidChange()
    }

    // MARK: - Private

    private func fetch(planDay: Date, startedAt: Date) throws -> ProposedShift? {
        let descriptor = FetchDescriptor<ProposedShift>(
            predicate: #Predicate { $0.planDay == planDay && $0.startedAt == startedAt }
        )
        return try context.fetch(descriptor).first
    }
}
