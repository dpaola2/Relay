//
//  Clock.swift
//  Relay
//
//  Time-injection seam so view models can be tested with a `FakeClock`.
//

import Foundation

protocol Clock: Sendable {
    var now: Date { get }
}

struct SystemClock: Clock {
    var now: Date { Date() }
}
