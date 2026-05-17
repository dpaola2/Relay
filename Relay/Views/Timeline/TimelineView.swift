//
//  TimelineView.swift
//  Relay
//
//  The Timeline tab — a horizontally-scrolling 72h band relative to
//  `clock.now`. Each `SleepSession` renders as a colored block (one color
//  per person), with day/night shading behind the blocks for orientation.
//  Open sessions extend to `clock.now` (TML-005).
//
//  Composition keeps each subview ≤50 lines per Sandi Metz's view-body rule.
//

import SwiftUI
import SwiftData

struct TimelineView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: TimelineViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TimelineContent(viewModel: viewModel)
            } else {
                Color.clear
            }
        }
        .task {
            if viewModel == nil {
                let store = SwiftDataSleepSessionStore(context: modelContext)
                viewModel = TimelineViewModel(store: store, clock: SystemClock())
            }
            viewModel?.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepSessionsDidChange)) { _ in
            viewModel?.refresh()
        }
    }
}

private struct TimelineContent: View {
    let viewModel: TimelineViewModel

    /// Visual scale: 60 points per hour gives a 72h band 4,320 points wide —
    /// readable on iPhone and horizontally-scrollable.
    private let pointsPerHour: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 72 hours")
                .font(.headline)
                .padding(.horizontal, 20)
            ScrollView(.horizontal, showsIndicators: false) {
                TimelineBand(
                    viewModel: viewModel,
                    pointsPerHour: pointsPerHour
                )
                .frame(height: 200)
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 16)
    }
}

private struct TimelineBand: View {
    let viewModel: TimelineViewModel
    let pointsPerHour: CGFloat

    private var totalWidth: CGFloat { 72 * pointsPerHour }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background — day color
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.10))
            // Night-shading bands
            ForEach(Array(viewModel.nightBands.enumerated()), id: \.offset) { _, band in
                NightBandView(
                    band: band,
                    windowStart: viewModel.windowStart,
                    pointsPerHour: pointsPerHour
                )
            }
            // Session blocks
            ForEach(viewModel.sessions, id: \.id) { session in
                SessionBlockView(
                    session: session,
                    color: viewModel.color(for: session.who),
                    windowStart: viewModel.windowStart,
                    effectiveEnd: viewModel.effectiveEnd(of: session),
                    pointsPerHour: pointsPerHour
                )
            }
        }
        .frame(width: totalWidth, height: 180)
    }
}

private struct NightBandView: View {
    let band: TimelineViewModel.NightBand
    let windowStart: Date
    let pointsPerHour: CGFloat

    var body: some View {
        let offset = CGFloat(band.start.timeIntervalSince(windowStart)) / 3_600 * pointsPerHour
        let width = CGFloat(band.end.timeIntervalSince(band.start)) / 3_600 * pointsPerHour
        return RoundedRectangle(cornerRadius: 6)
            .fill(Color.black.opacity(0.30))
            .frame(width: max(0, width), height: 180)
            .offset(x: offset)
    }
}

private struct SessionBlockView: View {
    let session: SleepSession
    let color: Color
    let windowStart: Date
    let effectiveEnd: Date
    let pointsPerHour: CGFloat

    var body: some View {
        let startOffset = max(0, session.startedAt.timeIntervalSince(windowStart))
        let endOffset = max(startOffset, effectiveEnd.timeIntervalSince(windowStart))
        let x = CGFloat(startOffset) / 3_600 * pointsPerHour
        let width = CGFloat(endOffset - startOffset) / 3_600 * pointsPerHour
        let y: CGFloat = session.who == .dave ? 24 : 100
        return RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(width: max(2, width), height: 64)
            .offset(x: x, y: y)
            .accessibilityLabel(Text("\(session.who.displayName) sleeping"))
    }
}
