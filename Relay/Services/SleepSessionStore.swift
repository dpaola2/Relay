//
//  SleepSessionStore.swift
//  Relay
//
//  The protocol view models depend on, plus the error type the store throws
//  when validation fails. Implementations are `nonisolated` so test mocks can
//  conform across actor boundaries without inheriting the app target's
//  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (ADR-002).
//

import Foundation

enum SleepSessionStoreError: Error, Equatable {
    /// Thrown when an update or insert would set `endedAt < startedAt`.
    case endBeforeStart
}

protocol SleepSessionStore: AnyObject, Sendable {
    // Reads
    func sessions(in range: ClosedRange<Date>) throws -> [SleepSession]
    func openSession(for who: Person) throws -> SleepSession?
    func allOpenSessions() throws -> [SleepSession]

    // Writes
    func startSession(for who: Person, at startedAt: Date) throws -> SleepSession
    func endSession(_ session: SleepSession, at endedAt: Date) throws
    func update(
        _ session: SleepSession,
        startedAt: Date?,
        endedAt: Date??,
        who: Person?,
        note: String??
    ) throws
    func delete(_ session: SleepSession) throws
}
