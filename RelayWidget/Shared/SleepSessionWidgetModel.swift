//
//  SleepSessionWidgetModel.swift
//  RelayWidget
//
//  RELAY-9 — MIRROR FILE.
//
//  This is a widget-target copy of the @Model class + the Person enum from
//  the main app. The widget extension is a separate Swift module (it can't
//  `import Relay`), so the types are duplicated source-level. SwiftData
//  matches entities across modules by entity name + property names, so two
//  modules each defining `SleepSession` with the same schema read/write
//  the same SQLite table fine.
//
//  Canonical sources:
//      Relay/Models/SleepSession.swift
//      Relay/Models/Person.swift
//
//  If you change the schema (add a property, change a type), update BOTH
//  files in the same commit. A schema mismatch will cause SwiftData
//  migration failures on launch.
//

import Foundation
import SwiftData

@Model
final class SleepSession {
    var id: UUID
    var whoRaw: String
    var startedAt: Date
    var endedAt: Date?
    var note: String?
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

    var who: Person {
        get { Person(rawValue: whoRaw) ?? .personA }
        set { whoRaw = newValue.rawValue }
    }

    var isOpen: Bool { endedAt == nil }
}

enum Person: String, CaseIterable, Sendable {
    case personA
    case personB

    /// Same defensive-decoder contract as the main-app copy. The widget
    /// extension runs in its own process and can read a row before
    /// `PersonEnumMigrator` has rewritten it, so accept both schemas.
    init?(rawValue: String) {
        switch rawValue {
        case "personA", "dave": self = .personA
        case "personB", "bethany": self = .personB
        default: return nil
        }
    }

    /// Last-resort placeholder for paths that don't yet have a real name
    /// (gallery preview before any name is read; accessibility labels in
    /// the `placeholder(in:)` snapshot). Real names ship in the entry —
    /// see `SleepDebtTimelineEntry.nameA` / `.nameB`.
    var placeholderName: String {
        switch self {
        case .personA: return "Person A"
        case .personB: return "Person B"
        }
    }
}
