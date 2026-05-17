//
//  ForecastOverlayView.swift
//  Relay
//
//  Half-hour positional renderer for the Forecast plan. Lives inside the
//  lane `ZStack` in `DayTimelineView` (today only — EDG-013) and draws:
//
//  1. Dashed-bordered rectangles for each `ForecastViewModel.RenderableBlock`
//     (lane-colored fill at low opacity per OQ-7 + UI-007).
//  2. A future-only grid of half-hour tap cells (Color.clear) that route
//     taps through `ProposedShiftStore.cycle(...)` (ADJ-001 / ADJ-002 /
//     ADJ-003). Cells above the now-line render NO tap surface so past taps
//     fall through to the existing `SessionBlockButton` NavigationLink.
//
//  Architecture §6.2 — keep RELAY-4's hour grid untouched and project blocks
//  via `y = (secondsFromStartOfDay / 1800) * halfHourHeight`.
//

import SwiftUI

struct ForecastOverlayView: View {
    let blocks: [ForecastViewModel.RenderableBlock]
    let planDay: Date
    let now: Date
    let laneWidth: CGFloat
    let color: (Person) -> Color
    let onCycle: (_ startedAt: Date, _ currentEngineProposal: Person?) -> Void

    /// Half-hour cells (`planDay 00:00 → planDay+1 00:00`, 48 entries) that
    /// start strictly after `now` are the tap targets. Past cells are
    /// untouchable so the existing `SessionBlockButton` NavigationLink
    /// behaviour (EDG-006) is preserved.
    private var futureCellStarts: [Date] {
        var starts: [Date] = []
        starts.reserveCapacity(48)
        for index in 0..<48 {
            let started = planDay.addingTimeInterval(Double(index) * 1_800)
            if started > now {
                starts.append(started)
            }
        }
        return starts
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(blocks) { block in
                BlockRectangle(
                    block: block,
                    planDay: planDay,
                    laneWidth: laneWidth,
                    color: color(block.who)
                )
            }
            ForEach(futureCellStarts, id: \.self) { started in
                TapCell(
                    startedAt: started,
                    planDay: planDay,
                    laneWidth: laneWidth,
                    blocks: blocks,
                    onCycle: onCycle
                )
            }
        }
    }
}

// MARK: - Block rectangle (dashed border, low-opacity lane fill)

private struct BlockRectangle: View {
    let block: ForecastViewModel.RenderableBlock
    let planDay: Date
    let laneWidth: CGFloat
    let color: Color

    var body: some View {
        let y = TimelineMetrics.yOffset(for: block.startedAt, dayStart: planDay)
        let bottom = TimelineMetrics.yOffset(for: block.endedAt, dayStart: planDay)
        let height = max(6, bottom - y)
        let xOffset = block.who == .dave ? 0 : laneWidth

        RoundedRectangle(cornerRadius: 8)
            .fill(color.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        color.opacity(0.95),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
            )
            .frame(width: laneWidth - 8, height: height)
            .offset(x: xOffset + 4, y: y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Tap cell (invisible, future-only, cycles assignment)

private struct TapCell: View {
    let startedAt: Date
    let planDay: Date
    let laneWidth: CGFloat
    let blocks: [ForecastViewModel.RenderableBlock]
    let onCycle: (_ startedAt: Date, _ currentEngineProposal: Person?) -> Void

    var body: some View {
        let y = TimelineMetrics.yOffset(for: startedAt, dayStart: planDay)
        HStack(spacing: 0) {
            laneButton(for: .dave, laneWidth: laneWidth)
            laneButton(for: .bethany, laneWidth: laneWidth)
        }
        .frame(height: TimelineMetrics.halfHourHeight)
        .offset(y: y)
    }

    private func laneButton(for who: Person, laneWidth: CGFloat) -> some View {
        Button {
            onCycle(startedAt, engineProposal(at: startedAt))
        } label: {
            Color.clear
                .frame(width: laneWidth, height: TimelineMetrics.halfHourHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(
            "Cycle shift assignment at \(timeLabel) (\(who.displayName) lane)"
        ))
    }

    /// The current engine proposal for `startedAt` — derived from the
    /// pre-collapsed render blocks. If a non-overridden block covers
    /// `startedAt`, the engine proposal there is that block's `who`; otherwise
    /// nil. The store uses this to decide whether the next cycle step lands
    /// back on the engine assignment (which clears the override flag) or
    /// stays unassigned (no engine proposal exists for this cell).
    private func engineProposal(at startedAt: Date) -> Person? {
        for block in blocks where !block.manuallyOverridden {
            if startedAt >= block.startedAt && startedAt < block.endedAt {
                return block.who
            }
        }
        return nil
    }

    private var timeLabel: String {
        startedAt.formatted(date: .omitted, time: .shortened)
    }
}
