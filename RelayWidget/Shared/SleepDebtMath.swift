//
//  SleepDebtMath.swift
//  RelayWidget
//
//  RELAY-9 — MIRROR FILE for the pure debt math + formatter + App Group ID.
//
//  Canonical sources:
//      Relay/Support/SleepDebtFormatter.swift
//      Relay/Services/SleepDebtSnapshotComputer.swift
//      Relay/Services/AppGroupContainer.swift (identifier + storeFilename only)
//
//  Pure value types. If the canonical versions change shape, update here too.
//

import Foundation

// MARK: - App Group identifiers

enum WidgetAppGroup {
    static let identifier = "group.com.davepaola.relay"
    static let storeFilename = "default.store"

    static var storeURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appendingPathComponent(storeFilename)
    }
}

// MARK: - Formatter

enum SleepDebtFormatter {

    static let noDataPlaceholder = "—"

    static func format(balance seconds: TimeInterval) -> String {
        let absMinutes = Int(abs(seconds) / 60)
        if absMinutes == 0 { return "0" }
        let hours = absMinutes / 60
        let minutes = absMinutes % 60
        let prefix = seconds < 0 ? "\u{2212}" : "+"
        return "\(prefix)\(hours)h \(minutes)m"
    }
}

// MARK: - Snapshot

struct SleepDebtSnapshot: Sendable, Equatable {
    let date: Date
    let personABalance: TimeInterval?
    let personBBalance: TimeInterval?
}

enum SleepDebtSnapshotComputer {

    static let defaultTargetHoursPer24h: Double = 8.0
    static let defaultWindow: TimeInterval = 24 * 3_600
    static let scanWindow: TimeInterval = 72 * 3_600

    static func snapshot(
        sessions: [SleepSession],
        at now: Date,
        targetHoursPer24h: Double = defaultTargetHoursPer24h,
        window: TimeInterval = defaultWindow
    ) -> SleepDebtSnapshot {
        guard !sessions.isEmpty else {
            return SleepDebtSnapshot(date: now, personABalance: nil, personBBalance: nil)
        }
        return SleepDebtSnapshot(
            date: now,
            personABalance: balance(for: .personA, sessions: sessions, now: now,
                                 targetHoursPer24h: targetHoursPer24h, window: window),
            personBBalance: balance(for: .personB, sessions: sessions, now: now,
                                    targetHoursPer24h: targetHoursPer24h, window: window)
        )
    }

    private static func balance(
        for person: Person,
        sessions: [SleepSession],
        now: Date,
        targetHoursPer24h: Double,
        window: TimeInterval
    ) -> TimeInterval {
        let scaledTarget = (targetHoursPer24h * 3_600) * (window / (24 * 3_600))
        let windowStart = now.addingTimeInterval(-window)
        var actual: TimeInterval = 0
        for session in sessions where session.who == person {
            actual += overlap(session: session, with: windowStart...now)
        }
        return actual - scaledTarget
    }

    private static func overlap(
        session: SleepSession,
        with window: ClosedRange<Date>
    ) -> TimeInterval {
        let effectiveEnd = session.endedAt ?? window.upperBound
        let safeEnd = max(effectiveEnd, session.startedAt)
        let lower = max(session.startedAt, window.lowerBound)
        let upper = min(safeEnd, window.upperBound)
        guard lower < upper else { return 0 }
        return upper.timeIntervalSince(lower)
    }
}
