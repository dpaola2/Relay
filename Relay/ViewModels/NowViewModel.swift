//
//  NowViewModel.swift
//  Relay
//
//  The Now-screen logging state machine (Arch §3.5). Per-person concurrency
//  per ADR-001:
//    - tapPersonX with that person already open        → no-op (Q5 guard)
//    - tapPersonX with the OTHER person open           → opens this person too
//    - tapOnDuty with no open sessions                 → no-op (PRD NOW-006)
//    - tapOnDuty with one or both open                 → closes ALL at clock.now
//
//  Per ADR-002 / CLAUDE.md §"Engineering Methodology" item 6 this is
//  `@Observable nonisolated final class` so test mocks can drive it across
//  actor boundaries without inheriting `SWIFT_DEFAULT_ACTOR_ISOLATION`.
//

import Foundation
import Observation

@Observable
nonisolated final class NowViewModel {
    private let store: any SleepSessionStore
    private let clock: any Clock

    /// Currently-open sessions (zero, one, or two). Driven by `refresh()`.
    /// Views call `refresh()` on appear and after intents to keep this in
    /// sync with the store. The view model deliberately does NOT auto-refresh
    /// inside the intent methods — the test suite verifies the explicit
    /// `refresh()` contract.
    var activeSessions: [SleepSession] = []

    init(store: any SleepSessionStore, clock: any Clock = SystemClock()) {
        self.store = store
        self.clock = clock
    }

    // MARK: - Intents

    /// Start an open session for person A. No-op if person A already has one
    /// open (ADR-001 Q5 idempotency guard).
    func tapPersonA() throws {
        try startIfIdle(for: .personA)
    }

    /// Start an open session for person B. No-op if person B already has one
    /// open. If person A is open, their session stays open (ADR-001 Q6 —
    /// per-person concurrency).
    func tapPersonB() throws {
        try startIfIdle(for: .personB)
    }

    /// "On duty" — closes ALL open sessions at the current clock instant.
    /// No-op when no sessions are open (PRD NOW-006).
    func tapOnDuty() throws {
        let open = try store.allOpenSessions()
        guard !open.isEmpty else { return }
        let endMoment = clock.now
        for session in open {
            try store.endSession(session, at: endMoment)
        }
    }

    // MARK: - Refresh

    /// Re-read the currently-open sessions from the store. Called by views
    /// on appear and after each intent. Also covers the "app killed while
    /// open" edge case (PRD §8) by re-surfacing prior-launch open sessions
    /// on the first refresh after launch.
    func refresh() {
        activeSessions = (try? store.allOpenSessions()) ?? []
    }

    // MARK: - Private

    private func startIfIdle(for person: Person) throws {
        if try store.openSession(for: person) != nil { return }
        _ = try store.startSession(for: person, at: clock.now)
    }
}
