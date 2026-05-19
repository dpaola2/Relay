//
//  DayTimelineView.swift
//  Relay
//
//  RELAY-4 — the Timeline tab. Vertical Day view (Huckleberry-style): hour
//  labels in a left gutter, two lanes (Dave / Bethany), session blocks placed
//  by `startedAt` and sized by duration. Swipe or chevron to navigate days
//  within the last 7 days (ADR-003). Tap a block → existing Edit sheet.
//
//  RELAY-8 — Forecast is gone; the Day view is the lanes, the now-line, and
//  the chevrons. A pinned legend (`LaneHeader`) sits between the toolbar and
//  the grid so the color → person mapping is always visible.
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
        .task { await bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: .sleepSessionsDidChange)) { _ in
            timelineVM?.refresh()
            editVM?.refresh()
        }
    }

    private func bootstrap() async {
        if timelineVM == nil {
            let sessionStore = SwiftDataSleepSessionStore(context: modelContext)
            timelineVM = TimelineViewModel(store: sessionStore, clock: SystemClock())
            editVM = EditViewModel(store: sessionStore, clock: SystemClock())
        }
        timelineVM?.refresh()
        editVM?.refresh()
        selectedDay = timelineVM?.today ?? Date.startOfToday()
    }
}

// MARK: - Content (header + body)

private struct DayTimelineContent: View {
    let timelineVM: TimelineViewModel
    let editVM: EditViewModel
    @Binding var selectedDay: Date

    var body: some View {
        VStack(spacing: 0) {
            LaneHeader(color: timelineVM.color(for:))
            DayBody(
                slices: timelineVM.slices(for: selectedDay),
                color: timelineVM.color(for:),
                editVM: editVM,
                isToday: Calendar.current.isDate(selectedDay, inSameDayAs: timelineVM.today)
            )
        }
        .simultaneousGesture(swipeGesture)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.relayInk, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(Color.relayTerracotta)
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                stepDay(.backward)
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
                stepDay(.forward)
            } label: {
                Image(systemName: "chevron.right")
                    .accessibilityLabel("Next day")
            }
            .disabled(Calendar.current.isDate(selectedDay, inSameDayAs: timelineVM.today))
        }
    }

    /// Horizontal swipe → step day. Uses `.simultaneousGesture` so the
    /// `ScrollView`'s vertical drag still wins for vertical motion, and the
    /// `DayTimelineSwipe.direction(...)` helper rejects vertical-dominant
    /// translations so a diagonal scroll doesn't get hijacked.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard let direction = DayTimelineSwipe.direction(translation: value.translation) else {
                    return
                }
                withAnimation(.easeOut(duration: 0.18)) {
                    stepDay(direction)
                }
            }
    }

    private func stepDay(_ direction: DayTimelineSwipe.Direction) {
        switch direction {
        case .forward:
            selectedDay = nextDay(after: selectedDay, clampedTo: timelineVM.today)
        case .backward:
            selectedDay = previousDay(before: selectedDay, clampedTo: timelineVM.earliestSelectableDay)
        }
    }
}

// MARK: - Lane header (color legend)

/// Always-visible mapping between lane color and person. Sits above the hour
/// grid so a half-conscious operator at 3am can tell at a glance which lane is
/// whose without leaving the Day view.
struct LaneHeader: View {
    let color: (Person) -> Color

    struct Entry: Equatable {
        let person: Person
        let label: String
        let color: Color
        let accessibilityLabel: String
    }

    /// Pure data seam — unit tests assert on this instead of rendering SwiftUI.
    static func entries(color: (Person) -> Color) -> [Entry] {
        Person.allCases
            .sorted { $0.laneOrder < $1.laneOrder }
            .map { person in
                Entry(
                    person: person,
                    label: person.displayName,
                    color: color(person),
                    accessibilityLabel: "\(person.displayName)'s lane, \(person.colorName)"
                )
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Gutter spacer so the lane columns line up with the hour grid below.
            Color.clear.frame(width: TimelineMetrics.gutterWidth)
            ForEach(Self.entries(color: color), id: \.person) { entry in
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.color)
                        .frame(width: 8, height: 8)
                    Text(entry.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.relayCream)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.accessibilityLabel)
            }
        }
        .frame(height: 24)
        .background(Color.relayInk)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.relaySoftCream.opacity(0.15))
                .frame(height: 0.5)
        }
    }
}

private extension Person {
    /// Stable left-to-right placement in the Day-view lanes. Lower = leftmost.
    var laneOrder: Int {
        switch self {
        case .dave: return 0
        case .bethany: return 1
        }
    }

    /// Human-readable color name used in the legend's accessibility label.
    /// Kept in sync with the palette tokens in `Color+Palette.swift`.
    var colorName: String {
        switch self {
        case .dave: return "terracotta"
        case .bethany: return "peach"
        }
    }
}

// MARK: - Swipe direction helper (pure function, unit-tested)

/// Decision logic for the Day-view horizontal swipe. Extracted so
/// `DayTimelineSwipeTests` can verify it without standing up SwiftUI gestures.
enum DayTimelineSwipe {
    enum Direction: Equatable {
        case forward   // left swipe = next day
        case backward  // right swipe = previous day
    }

    /// Minimum horizontal travel before we commit to a day step. Mirrors
    /// `DragGesture(minimumDistance:)` but used here as the *commit* threshold,
    /// not the *start* threshold — the gesture starts at 30, but we only step
    /// once the user has clearly committed to horizontal motion.
    static let horizontalThreshold: CGFloat = 30

    /// Horizontal motion must dominate vertical by at least this factor or we
    /// treat the drag as a (possibly diagonal) vertical scroll attempt and
    /// ignore it. 1.5 is enough to disambiguate without being twitchy.
    static let horizontalDominanceFactor: CGFloat = 1.5

    /// Returns `.forward` for left swipes, `.backward` for right swipes, and
    /// `nil` if the translation is below threshold or vertically dominant.
    static func direction(translation: CGSize) -> Direction? {
        let dx = translation.width
        let dy = translation.height
        guard abs(dx) >= horizontalThreshold else { return nil }
        guard abs(dx) > abs(dy) * horizontalDominanceFactor else { return nil }
        return dx < 0 ? .forward : .backward
    }
}

// MARK: - Day body (hour grid + lanes + blocks + now-line)

/// Sentinel scroll target for the now-line. `ScrollViewReader.scrollTo(...)` on
/// appear pins this anchor to the centre of the viewport (UI-006 / OQ-8).
private let nowAnchorID = "now-line"

private struct DayBody: View {
    let slices: TimelineViewModel.DaySlices
    let color: (Person) -> Color
    let editVM: EditViewModel
    let isToday: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    HourGutter()
                    LaneArea(
                        slices: slices,
                        color: color,
                        editVM: editVM,
                        isToday: isToday
                    )
                }
                .frame(height: TimelineMetrics.dayHeight)
            }
            .background(Color.relayInk)
            .onAppear {
                guard isToday else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(nowAnchorID, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Hour gutter

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
                .frame(height: TimelineMetrics.hourRowHeight, alignment: .top)
            }
        }
        .frame(width: TimelineMetrics.gutterWidth)
    }

    /// Compact hour-of-day label, e.g. `12a`, `1a`, `12p`, `5p`.
    private func hourLabel(_ hour: Int) -> String {
        let suffix = hour < 12 ? "a" : "p"
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(h12)\(suffix)"
    }
}

// MARK: - Lane area

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
                    Spacer().frame(height: TimelineMetrics.hourRowHeight - 0.5)
                }
            }
            Rectangle()
                .fill(Color.relaySoftCream.opacity(0.15))
                .frame(width: 0.5, height: TimelineMetrics.dayHeight)
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
        let y = TimelineMetrics.yOffset(for: slice.visibleStart, dayStart: dayStart)
        let h = max(6, TimelineMetrics.yOffset(for: slice.visibleEnd, dayStart: dayStart) - y)

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
            let y = TimelineMetrics.yOffset(for: context.date, dayStart: dayStart)
            Rectangle()
                .fill(Color.relayTerracotta)
                .frame(width: totalWidth, height: 1.5)
                .offset(y: y)
                .id(nowAnchorID)
                .accessibilityHidden(true)
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
