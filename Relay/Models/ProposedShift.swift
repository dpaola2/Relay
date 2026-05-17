//
//  ProposedShift.swift
//  Relay
//
//  An engine-proposed (or user-overridden) sleep block for a planned night.
//  One row per half-hour cell — see Architecture §1.2 (ADR-001) for the
//  per-cell-vs-variable-length-block decision and its rationale. Per-cell
//  storage makes override semantics trivial (each tap toggles one row).
//
//  Class invariant: `endedAt - startedAt == 1800` seconds (30 minutes) for
//  every row. Tests pin this.
//

import Foundation
import SwiftData

@Model
final class ProposedShift {
    // Identity
    var id: UUID

    // Day bucket — start-of-day anchor for the night this row plans. Lets us
    // scope queries cheaply and prune by age.
    var planDay: Date

    // Domain — half-hour cell. `endedAt` is always `startedAt + 30 min`.
    var whoRaw: String
    var startedAt: Date
    var endedAt: Date

    // True iff the user tapped this cell to change its assignment.
    // Engine re-runs MUST NOT clobber rows where this is true.
    var manuallyOverridden: Bool

    // Bookkeeping
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        planDay: Date,
        who: Person,
        startedAt: Date,
        endedAt: Date,
        manuallyOverridden: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.planDay = planDay
        self.whoRaw = who.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.manuallyOverridden = manuallyOverridden
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Defensive fallback when storage is corrupt — mirrors `SleepSession.who`.
    var who: Person {
        get { Person(rawValue: whoRaw) ?? .dave }
        set { whoRaw = newValue.rawValue }
    }
}
