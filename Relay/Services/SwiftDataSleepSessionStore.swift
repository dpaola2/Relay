//
//  SwiftDataSleepSessionStore.swift
//  Relay
//
//  Concrete `SleepSessionStore` backed by a SwiftData `ModelContext`. Declared
//  `nonisolated` so it does not pick up the app target's implicit MainActor
//  isolation (ADR-002).
//

import Foundation
import SwiftData

extension Notification.Name {
    /// Posted after any successful write (`save` or `delete`). View models
    /// observe this to re-read their cached projections so seed/wipe and
    /// cross-tab mutations are reflected without a tab teardown.
    static let sleepSessionsDidChange = Notification.Name("relay.sleepSessionsDidChange")
}

/// `@unchecked Sendable` because `ModelContext` is not yet `Sendable`-conforming.
/// Used from a single context at a time in v1 (app thread or test thread), so the
/// unchecked promise holds. Revisit when SwiftData ships proper Sendable support.
nonisolated final class SwiftDataSleepSessionStore: SleepSessionStore, @unchecked Sendable {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    private func notifyDidChange() {
        NotificationCenter.default.post(name: .sleepSessionsDidChange, object: nil)
    }

    // MARK: - Reads

    func sessions(in range: ClosedRange<Date>) throws -> [SleepSession] {
        let lower = range.lowerBound
        let upper = range.upperBound
        let descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        return all.filter { row in
            let endOrOpen = row.endedAt ?? .distantFuture
            return row.startedAt <= upper && endOrOpen >= lower
        }
    }

    func openSession(for who: Person) throws -> SleepSession? {
        let raw = who.rawValue
        let descriptor = FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.whoRaw == raw && $0.endedAt == nil }
        )
        return try context.fetch(descriptor).first
    }

    func allOpenSessions() throws -> [SleepSession] {
        let descriptor = FetchDescriptor<SleepSession>(
            predicate: #Predicate { $0.endedAt == nil }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Writes

    func startSession(for who: Person, at startedAt: Date) throws -> SleepSession {
        let session = SleepSession(who: who, startedAt: startedAt)
        context.insert(session)
        try context.save()
        notifyDidChange()
        return session
    }

    func endSession(_ session: SleepSession, at endedAt: Date) throws {
        if endedAt < session.startedAt {
            throw SleepSessionStoreError.endBeforeStart
        }
        session.endedAt = endedAt
        session.updatedAt = endedAt
        try context.save()
        notifyDidChange()
    }

    func update(
        _ session: SleepSession,
        startedAt: Date?,
        endedAt: Date??,
        who: Person?,
        note: String??
    ) throws {
        let proposedStart = startedAt ?? session.startedAt
        let proposedEnd: Date?
        if let outer = endedAt {
            proposedEnd = outer
        } else {
            proposedEnd = session.endedAt
        }

        if let end = proposedEnd, end < proposedStart {
            throw SleepSessionStoreError.endBeforeStart
        }

        session.startedAt = proposedStart
        session.endedAt = proposedEnd
        if let who { session.who = who }
        if let outer = note { session.note = outer }
        session.updatedAt = .now
        try context.save()
        notifyDidChange()
    }

    func delete(_ session: SleepSession) throws {
        context.delete(session)
        try context.save()
        notifyDidChange()
    }
}
