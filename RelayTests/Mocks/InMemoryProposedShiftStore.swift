//
//  InMemoryProposedShiftStore.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M3 support; used by M5 tests)
//
//  Test double for `ProposedShiftStore` that backs storage with an in-memory
//  array instead of SwiftData. Mirrors the `InMemorySleepSessionStore`
//  pattern. Per ADR-002 + CLAUDE.md §"Engineering Methodology" item 6, mocks
//  conforming to app protocols across actor boundaries use `@unchecked
//  Sendable`.
//
//  Behavior is intended to mirror `SwiftDataProposedShiftStore` bit-for-bit
//  (idempotent upsert on `(planDay, startedAt)`, cycle semantics including
//  override-clear-on-return-to-proposal, prune by `planDay < cutoffPlanDay`,
//  notification post on every write).
//
//  This file is a TEST SUPPORT file, not implementation. If `ProposedShiftStore`
//  or `ProposedShift` is not yet defined in the app target, this file will fail
//  to compile — that is the expected TDD red phase.
//

import Foundation
@testable import Relay

/// In-memory fake `ProposedShiftStore`. Single-test access; no synchronization.
final class InMemoryProposedShiftStore: ProposedShiftStore, @unchecked Sendable {
    private var rows: [ProposedShift] = []

    // Test spy counters.
    private(set) var upsertCallCount = 0
    private(set) var cycleCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var pruneCallCount = 0
    private(set) var shiftsCallCount = 0

    init(seed: [ProposedShift] = []) {
        self.rows = seed
    }

    // MARK: - Reads

    func shifts(forPlanDay planDay: Date) throws -> [ProposedShift] {
        shiftsCallCount += 1
        return rows
            .filter { $0.planDay == planDay }
            .sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: - Writes

    func upsert(
        planDay: Date,
        startedAt: Date,
        who: Person,
        manuallyOverridden: Bool
    ) throws -> ProposedShift {
        upsertCallCount += 1

        if let idx = rows.firstIndex(where: {
            $0.planDay == planDay && $0.startedAt == startedAt
        }) {
            rows[idx].who = who
            rows[idx].manuallyOverridden = manuallyOverridden
            rows[idx].updatedAt = .now
            NotificationCenter.default.post(name: .proposedShiftsDidChange, object: nil)
            return rows[idx]
        }

        let shift = ProposedShift(
            planDay: planDay,
            who: who,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            manuallyOverridden: manuallyOverridden
        )
        rows.append(shift)
        NotificationCenter.default.post(name: .proposedShiftsDidChange, object: nil)
        return shift
    }

    func cycle(
        planDay: Date,
        startedAt: Date,
        currentEngineProposal: Person?
    ) throws -> ProposedShift? {
        cycleCallCount += 1
        let existing = rows.first {
            $0.planDay == planDay && $0.startedAt == startedAt
        }

        // Current state: who the cell is assigned to right now.
        let currentWho: Person? = existing?.who

        // Cycle order: Dave → Bethany → unassigned → engine-proposal → Dave → ...
        let next: Person?
        switch currentWho {
        case .dave:
            next = .bethany
        case .bethany:
            next = nil
        case nil:
            next = currentEngineProposal
        }

        // Determine the new override flag.
        let newOverridden: Bool
        if let next, next == currentEngineProposal {
            // Returning to the engine's proposed assignment clears the flag.
            newOverridden = false
        } else if next == nil {
            // Unassigned is still an "override" intent (user chose to clear).
            newOverridden = true
        } else {
            newOverridden = true
        }

        if let next {
            let result = try upsert(
                planDay: planDay,
                startedAt: startedAt,
                who: next,
                manuallyOverridden: newOverridden
            )
            // upsert already posted the notification.
            // Decrement upsertCallCount so cycle test isn't double-counted.
            upsertCallCount -= 1
            return result
        } else {
            // Unassigned: delete the row if any. Mark intent by posting change.
            if let existing {
                rows.removeAll { $0.id == existing.id }
            }
            NotificationCenter.default.post(name: .proposedShiftsDidChange, object: nil)
            return nil
        }
    }

    func delete(_ shift: ProposedShift) throws {
        deleteCallCount += 1
        rows.removeAll { $0.id == shift.id }
        NotificationCenter.default.post(name: .proposedShiftsDidChange, object: nil)
    }

    func prune(olderThan cutoffPlanDay: Date) throws {
        pruneCallCount += 1
        rows.removeAll { $0.planDay < cutoffPlanDay }
        NotificationCenter.default.post(name: .proposedShiftsDidChange, object: nil)
    }

    // MARK: - Test-only helpers

    /// Direct read of underlying rows. Not part of the protocol.
    var allRowsForTesting: [ProposedShift] { rows }

    /// Reset spy counters between assertions in the same test.
    func resetCallCounts() {
        upsertCallCount = 0
        cycleCallCount = 0
        deleteCallCount = 0
        pruneCallCount = 0
        shiftsCallCount = 0
    }
}
