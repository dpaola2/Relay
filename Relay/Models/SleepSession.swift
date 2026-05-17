//
//  SleepSession.swift
//  Relay
//
//  The single `@Model` entity. Everything else in v1 is a query/view over this.
//

import Foundation
import SwiftData

@Model
final class SleepSession {
    // Identity
    var id: UUID

    // Domain — `whoRaw` is the persisted form; `who` is the typed bridge.
    var whoRaw: String
    var startedAt: Date
    var endedAt: Date?
    var note: String?

    // Bookkeeping
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        who: Person,
        startedAt: Date,
        endedAt: Date? = nil,
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.whoRaw = who.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Defensive fallback when storage is corrupt (Arch §1.3 + PRD §8).
    var who: Person {
        get { Person(rawValue: whoRaw) ?? .dave }
        set { whoRaw = newValue.rawValue }
    }

    var isOpen: Bool { endedAt == nil }

    /// Duration up to `referenceDate`. Open sessions count their elapsed-so-far
    /// portion (used by Totals/Timeline). A reference date before `startedAt`
    /// yields 0, not a negative interval (defensive against clock rewinds).
    func duration(asOf referenceDate: Date = .now) -> TimeInterval {
        let end = endedAt ?? referenceDate
        return max(0, end.timeIntervalSince(startedAt))
    }
}
