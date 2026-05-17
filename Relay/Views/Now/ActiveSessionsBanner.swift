//
//  ActiveSessionsBanner.swift
//  Relay
//
//  Shows the currently-open sleep session(s) with live-ticking elapsed time.
//  Supports zero / one / two simultaneous active sessions (ADR-001 / NOW-007).
//
//  Live-ticks via `TimelineView(.periodic(from: .now, by: 1))` so the elapsed
//  display refreshes once per second without the parent view re-rendering.
//

import SwiftUI

struct ActiveSessionsBanner: View {
    let sessions: [SleepSession]

    var body: some View {
        if sessions.isEmpty {
            EmptyActiveSessionsRow()
        } else {
            VStack(spacing: 8) {
                SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 8) {
                        ForEach(sessions, id: \.id) { session in
                            ActiveSessionRow(session: session, asOf: context.date)
                        }
                    }
                }
            }
        }
    }
}

private struct ActiveSessionRow: View {
    let session: SleepSession
    let asOf: Date

    var body: some View {
        HStack {
            Text("\(session.who.displayName) sleeping")
                .font(.headline)
            Spacer()
            Text(elapsedString(from: session.duration(asOf: asOf)))
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }

    private func elapsedString(from interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

private struct EmptyActiveSessionsRow: View {
    var body: some View {
        Text("No one sleeping")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
}
