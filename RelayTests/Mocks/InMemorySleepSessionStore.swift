//
//  InMemorySleepSessionStore.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M2 support; used by M3, M4, M5, M6 tests)
//
//  Test double for `SleepSessionStore` that backs storage with an in-memory array
//  instead of SwiftData. Per ADR-002 + CLAUDE.md §"Engineering Methodology" item 6,
//  mocks conforming to app protocols across actor boundaries use `@unchecked Sendable`.
//
//  This file is a TEST SUPPORT file, not implementation. It deliberately implements
//  the contract Stage 5 will need to satisfy in `SwiftDataSleepSessionStore`. If
//  `SleepSessionStore` or `SleepSession` are not yet defined in the app target,
//  this file will fail to compile — that is the expected TDD red phase per ADR-002.
//

import Foundation
@testable import Relay

/// In-memory fake `SleepSessionStore`. Single-test access only; no synchronization.
final class InMemorySleepSessionStore: SleepSessionStore, @unchecked Sendable {
    private var rows: [SleepSession] = []

    // Hook test-side spies onto these counters/captures.
    private(set) var startCallCount = 0
    private(set) var endCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var deleteCallCount = 0

    init(seed: [SleepSession] = []) {
        self.rows = seed
    }

    // MARK: - Reads

    func sessions(in range: ClosedRange<Date>) throws -> [SleepSession] {
        rows.filter { row in
            let endOrOpen = row.endedAt ?? .distantFuture
            return row.startedAt <= range.upperBound && endOrOpen >= range.lowerBound
        }
    }

    func openSession(for who: Person) throws -> SleepSession? {
        rows.first { $0.who == who && $0.endedAt == nil }
    }

    func allOpenSessions() throws -> [SleepSession] {
        rows.filter { $0.endedAt == nil }
    }

    // MARK: - Writes

    func startSession(for who: Person, at startedAt: Date) throws -> SleepSession {
        startCallCount += 1
        let session = SleepSession(who: who, startedAt: startedAt, endedAt: nil)
        rows.append(session)
        return session
    }

    func endSession(_ session: SleepSession, at endedAt: Date) throws {
        endCallCount += 1
        guard let idx = rows.firstIndex(where: { $0.id == session.id }) else { return }
        rows[idx].endedAt = endedAt
        rows[idx].updatedAt = endedAt
    }

    func update(
        _ session: SleepSession,
        startedAt: Date?,
        endedAt: Date??,
        who: Person?,
        note: String??
    ) throws {
        updateCallCount += 1
        guard let idx = rows.firstIndex(where: { $0.id == session.id }) else { return }

        let proposedStart = startedAt ?? rows[idx].startedAt
        let proposedEnd: Date?
        if let outer = endedAt {
            // Caller wants to set endedAt (possibly to nil).
            proposedEnd = outer
        } else {
            // Caller wants "don't touch."
            proposedEnd = rows[idx].endedAt
        }

        // Validation: endedAt must not precede startedAt when both are set.
        if let end = proposedEnd, end < proposedStart {
            throw SleepSessionStoreError.endBeforeStart
        }

        rows[idx].startedAt = proposedStart
        rows[idx].endedAt = proposedEnd
        if let who { rows[idx].who = who }
        if let outer = note {
            rows[idx].note = outer
        }
        rows[idx].updatedAt = .now
    }

    func delete(_ session: SleepSession) throws {
        deleteCallCount += 1
        rows.removeAll { $0.id == session.id }
    }

    // MARK: - Test-only helpers

    /// Direct read of the underlying rows for assertions. Not part of the
    /// `SleepSessionStore` protocol.
    var allRowsForTesting: [SleepSession] { rows }
}
