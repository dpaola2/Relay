//
//  FakeClock.swift
//  RelayTests
//
//  Stage 4 — Test Generation (Milestone M2 support; used by M3, M4, M5, M6 tests)
//
//  Pinnable clock for time-dependent view models. The Now / Timeline / Totals /
//  Edit view models all depend on `Clock` for `.now` so that tests can pin time
//  deterministically.
//
//  Per ADR-002, mocks crossing actor boundaries use `@unchecked Sendable`.
//

import Foundation
@testable import Relay

/// Deterministic `Clock` for tests. Mutate `currentDate` between assertions to
/// simulate time passing.
final class FakeClock: Clock, @unchecked Sendable {
    var currentDate: Date

    init(_ initial: Date = Date(timeIntervalSince1970: 1_780_000_000)) {
        self.currentDate = initial
    }

    var now: Date { currentDate }

    /// Convenience — advance the clock by a duration in seconds.
    func advance(by seconds: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(seconds)
    }
}
