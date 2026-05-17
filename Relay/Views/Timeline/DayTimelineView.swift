//
//  DayTimelineView.swift
//  Relay
//
//  RELAY-4 — the Timeline tab. Vertical Day view (Huckleberry-style): hour
//  labels in a left gutter, two lanes (Dave / Bethany), session blocks placed
//  by `startedAt` and sized by duration. Swipe or chevron to navigate days
//  within the last 7 days (ADR-003). Tap a block → existing Edit sheet.
//
//  Composition keeps each subview ≤ ~50 lines per Sandi Metz's view-body rule.
//

import SwiftUI
import SwiftData

struct DayTimelineView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var timelineVM: TimelineViewModel?
    @State private var editVM: EditViewModel?
    @State private var selectedDay: Date = Date.startOfToday()

    var body: some View {
        NavigationStack {
            Group {
                if let timelineVM, let editVM {
                    DayTimelineContent(
                        timelineVM: timelineVM,
                        editVM: editVM,
                        selectedDay: $selectedDay
                    )
                } else {
                    Color.relayInk
                }
            }
            .background(Color.relayInk.ignoresSafeArea())
        }
        .task {
            if timelineVM == nil {
                let store = SwiftDataSleepSessionStore(context: modelContext)
                timelineVM = TimelineViewModel(store: store, clock: SystemClock())
                editVM = EditViewModel(store: store, clock: SystemClock())
            }
            timelineVM?.refresh()
            editVM?.refresh()
            selectedDay = timelineVM?.today ?? Date.startOfToday()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sleepSessionsDidChange)) { _ in
            timelineVM?.refresh()
            editVM?.refresh()
        }
    }
}

// MARK: - Content (header + body)

private struct DayTimelineContent: View {
    let timelineVM: TimelineViewModel
    let editVM: EditViewModel
    @Binding var selectedDay: Date

    var body: some View {
        DayBody(
            slices: timelineVM.slices(for: selectedDay),
            color: timelineVM.color(for:),
            editVM: editVM,
            isToday: Calendar.current.isDate(selectedDay, inSameDayAs: timelineVM.today)
        )
        .gesture(swipeGesture)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.relayInk, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(Color.relayTerracotta)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    selectedDay = previousDay(before: selectedDay, clampedTo: timelineVM.earliestSelectableDay)
                } label: {
                    Image(systemName: "chevron.left")
                        .accessibilityLabel("Previous day")
                }
                .disabled(Calendar.current.isDate(selectedDay, inSameDayAs: timelineVM.earliestSelectableDay))
            }

            ToolbarItem(placement: .principal) {
                Text(selectedDay, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.headline)
                    .foregroundStyle(Color.relayCream)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    selectedDay = nextDay(after: selectedDay, clampedTo: timelineVM.today)
                } label: {
                    Image(systemName: "chevron.right")
                        .accessibilityLabel("Next day")
                }
                .disabled(Calendar.current.isDate(selectedDay, inSameDayAs: timelineVM.today))
            }
        }
    }

    /// Horizontal swipe → step day. Threshold 50pt keeps it from firing on
    /// vertical scroll attempts. Left swipe = forward, right swipe = back.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 50 else { return }
                if dx < 0 {
                    selectedDay = nextDay(after: selectedDay, clampedTo: timelineVM.today)
                } else {
                    selectedDay = previousDay(before: selectedDay, clampedTo: timelineVM.earliestSelectableDay)
                }
            }
    }
}

// MARK: - Day body (hour grid + lanes + blocks + now-line)

private let hourRowHeight: CGFloat = 64
private let gutterWidth: CGFloat = 48
private let dayHeight: CGFloat = hourRowHeight * 24

private struct DayBody: View {
    let slices: TimelineViewModel.DaySlices
    let color: (Person) -> Color
    let editVM: EditViewModel
    let isToday: Bool

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                HourGutter()
                LaneArea(slices: slices, color: color, editVM: editVM, isToday: isToday)
            }
            .frame(height: dayHeight)
        }
        .background(Color.relayInk)
    }
}

private struct HourGutter: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack {
                    Spacer()
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.relaySoftCream.opacity(0.7))
                        .padding(.trailing, 6)
                }
                .frame(height: hourRowHeight, alignment: .top)
            }
        }
        .frame(width: gutterWidth)
    }

    /// Compact hour-of-day label, e.g. `12a`, `1a`, `12p`, `5p`.
    private func hourLabel(_ hour: Int) -> String {
        let suffix = hour < 12 ? "a" : "p"
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(h12)\(suffix)"
    }
}

private struct LaneArea: View {
    let slices: TimelineViewModel.DaySlices
    let color: (Person) -> Color
    let editVM: EditViewModel
    let isToday: Bool

    var body: some View {
        GeometryReader { geo in
            let laneWidth = geo.size.width / 2
            ZStack(alignment: .topLeading) {
                LaneGrid(laneWidth: laneWidth)
                LaneSlices(
                    lane: slices.dave,
                    dayStart: slices.day,
                    color: color(.dave),
                    laneIndex: 0,
                    laneWidth: laneWidth,
                    editVM: editVM
                )
                LaneSlices(
                    lane: slices.bethany,
                    dayStart: slices.day,
                    color: color(.bethany),
                    laneIndex: 1,
                    laneWidth: laneWidth,
                    editVM: editVM
                )
                if isToday {
                    NowLine(dayStart: slices.day, totalWidth: geo.size.width)
                }
            }
        }
    }
}

/// Background grid: per-hour faint horizontal rules + a single vertical divider
/// between the two lanes. Drawn separately so blocks render on top cleanly.
private struct LaneGrid: View {
    let laneWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.relayCream.opacity(0.05))
                        .frame(height: 0.5)
                    Spacer().frame(height: hourRowHeight - 0.5)
                }
            }
            Rectangle()
                .fill(Color.relaySoftCream.opacity(0.15))
                .frame(width: 0.5, height: dayHeight)
                .offset(x: laneWidth)
        }
    }
}

private struct LaneSlices: View {
    let lane: [TimelineViewModel.DaySlice]
    let dayStart: Date
    let color: Color
    let laneIndex: Int   // 0 = left, 1 = right
    let laneWidth: CGFloat
    let editVM: EditViewModel

    var body: some View {
        ForEach(lane) { slice in
            SessionBlockButton(
                slice: slice,
                color: color,
                xOffset: CGFloat(laneIndex) * laneWidth,
                width: laneWidth,
                dayStart: dayStart,
                editVM: editVM
            )
        }
    }
}

private struct SessionBlockButton: View {
    let slice: TimelineViewModel.DaySlice
    let color: Color
    let xOffset: CGFloat
    let width: CGFloat
    let dayStart: Date
    let editVM: EditViewModel

    var body: some View {
        let y = yOffset(for: slice.visibleStart, in: dayStart)
        let h = max(6, yOffset(for: slice.visibleEnd, in: dayStart) - y)

        NavigationLink {
            EditSessionView(session: slice.session, viewModel: editVM)
        } label: {
            blockLabel(height: h)
        }
        .buttonStyle(.plain)
        .frame(width: width - 8, height: h, alignment: .topLeading)
        .offset(x: xOffset + 4, y: y)
    }

    private func blockLabel(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color.opacity(slice.isOpen ? 0.7 : 0.9))
            .overlay(alignment: .topLeading) {
                if height > 18 {
                    Text(durationLabel(slice.fullDuration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.relayInk)
                        .padding(.horizontal, 6)
                        .padding(.top, 4)
                }
            }
            .accessibilityLabel(Text("\(slice.who.displayName) sleeping \(durationLabel(slice.fullDuration))"))
    }

    private func yOffset(for date: Date, in dayStart: Date) -> CGFloat {
        let seconds = max(0, date.timeIntervalSince(dayStart))
        return CGFloat(seconds) / 3_600 * hourRowHeight
    }

    private func durationLabel(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }
}

private struct NowLine: View {
    let dayStart: Date
    let totalWidth: CGFloat

    var body: some View {
        // Repaint once per minute so the now-line tracks wall-clock time
        // without us writing a Timer. Qualify SwiftUI.TimelineView to dodge
        // the in-module type-name shadow CLAUDE.md flags.
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let seconds = max(0, context.date.timeIntervalSince(dayStart))
            let y = CGFloat(seconds) / 3_600 * hourRowHeight
            Rectangle()
                .fill(Color.relayTerracotta)
                .frame(width: totalWidth, height: 1.5)
                .offset(y: y)
        }
    }
}

// MARK: - Day-step helpers (file-scope so multiple views share them)

private func nextDay(after day: Date, clampedTo latest: Date) -> Date {
    let next = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
    return min(next, latest)
}

private func previousDay(before day: Date, clampedTo earliest: Date) -> Date {
    let prev = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
    return max(prev, earliest)
}

private extension Date {
    static func startOfToday() -> Date {
        Calendar.current.startOfDay(for: Date())
    }
}
