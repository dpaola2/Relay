//
//  DayTimelineView.swift
//  Relay
//
//  RELAY-4 — the Timeline tab. Vertical Day view (Huckleberry-style): hour
//  labels in a left gutter, two lanes (Dave / Bethany), session blocks placed
//  by `startedAt` and sized by duration. Swipe or chevron to navigate days
//  within the last 7 days (ADR-003). Tap a block → existing Edit sheet.
//
//  RELAY-5 (M7) — extends the lane area forward in time: dashed-bordered
//  Forecast blocks below the now-line, half-hour tap cells that cycle the
//  assignment, ▷ feed markers on the left rail, and a `ScrollViewReader`
//  that pins the now-line to the centre of the viewport on appear (OQ-8).
//
//  Composition keeps each subview ≤ ~50 lines per Sandi Metz's view-body rule.
//

import SwiftUI
import SwiftData

struct DayTimelineView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var timelineVM: TimelineViewModel?
    @State private var editVM: EditViewModel?
    @State private var forecastVM: ForecastViewModel?
    @State private var forecastStore: (any ProposedShiftStore)?
    @State private var feedCadence = FeedCadenceSettings()
    @State private var firstRunFlag = ForecastFirstRunFlag()
    @State private var selectedDay: Date = Date.startOfToday()
    @State private var showingSettings = false
    @State private var showingWhy = false
    @State private var showingAddPast = false

    var body: some View {
        NavigationStack {
            Group {
                if let timelineVM, let editVM, let forecastVM, let forecastStore {
                    DayTimelineContent(
                        timelineVM: timelineVM,
                        editVM: editVM,
                        forecastVM: forecastVM,
                        forecastStore: forecastStore,
                        feedCadence: feedCadence,
                        firstRunFlag: firstRunFlag,
                        selectedDay: $selectedDay,
                        showingSettings: $showingSettings,
                        showingWhy: $showingWhy,
                        showingAddPast: $showingAddPast
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
            forecastVM?.refresh(forPlanDay: selectedDay)
        }
    }

    private func bootstrap() async {
        if timelineVM == nil {
            let sessionStore = SwiftDataSleepSessionStore(context: modelContext)
            let proposedStore = SwiftDataProposedShiftStore(context: modelContext)
            let timeline = TimelineViewModel(store: sessionStore, clock: SystemClock())
            let forecast = ForecastViewModel(
                engine: ForecastEngine(),
                store: proposedStore,
                deficitProvider: timeline,
                clock: SystemClock(),
                calendar: .current,
                firstRunFlag: firstRunFlag
            )
            timelineVM = timeline
            editVM = EditViewModel(store: sessionStore, clock: SystemClock())
            forecastStore = proposedStore
            forecastVM = forecast
        }
        timelineVM?.refresh()
        editVM?.refresh()
        selectedDay = timelineVM?.today ?? Date.startOfToday()
        forecastVM?.refresh(forPlanDay: selectedDay)
        forecastVM?.beginObserving(planDay: selectedDay)
    }
}

// MARK: - Content (header + body)

private struct DayTimelineContent: View {
    let timelineVM: TimelineViewModel
    let editVM: EditViewModel
    let forecastVM: ForecastViewModel
    let forecastStore: any ProposedShiftStore
    let feedCadence: FeedCadenceSettings
    let firstRunFlag: ForecastFirstRunFlag
    @Binding var selectedDay: Date
    @Binding var showingSettings: Bool
    @Binding var showingWhy: Bool
    @Binding var showingAddPast: Bool

    var body: some View {
        let isToday = Calendar.current.isDate(selectedDay, inSameDayAs: timelineVM.today)
        let blocks = forecastVM.renderableBlocks(forPlanDay: selectedDay)
        let showFirstRun = isToday
            && !blocks.isEmpty
            && ForecastFirstRunCard.shouldRender(flag: firstRunFlag)

        VStack(spacing: 0) {
            if showFirstRun {
                ForecastFirstRunCard(onDismiss: {
                    forecastVM.dismissFirstRunCard()
                })
            }
            DayBody(
                slices: timelineVM.slices(for: selectedDay),
                color: timelineVM.color(for:),
                editVM: editVM,
                forecastVM: forecastVM,
                forecastStore: forecastStore,
                feedCadence: feedCadence,
                blocks: blocks,
                isToday: isToday,
                selectedDay: selectedDay,
                onAddPast: { showingAddPast = true }
            )
        }
        .gesture(swipeGesture)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.relayInk, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(Color.relayTerracotta)
        .toolbar { toolbarContent(blocks: blocks, isToday: isToday) }
        .sheet(isPresented: $showingSettings) {
            FeedCadenceSettingsSheet(settings: feedCadence)
        }
        .sheet(isPresented: $showingWhy) {
            WhyThisSplitSheet(
                deficitLine: WhyThisSplitSheet.deficitLine(
                    daveDeficit48h: deficit48h(for: .dave),
                    bethanyDeficit48h: deficit48h(for: .bethany)
                ),
                onAdjust: { showingWhy = false },
                onDismiss: { showingWhy = false }
            )
        }
        .sheet(isPresented: $showingAddPast) {
            AddPastSleepSheet()
        }
        .onChange(of: selectedDay) { _, newDay in
            forecastVM.refresh(forPlanDay: newDay)
            forecastVM.beginObserving(planDay: newDay)
        }
    }

    /// 48h deficit in seconds for `person`, derived from the cached
    /// `TimelineViewModel.sessions` (which already covers the trailing 7 days
    /// per RELAY-4). Mirrors the 24h overlap math from
    /// `TimelineViewModel+DeficitProviding.swift` but widens the window.
    private func deficit48h(for person: Person) -> TimeInterval {
        let now = Date()
        let window: TimeInterval = 48 * 3_600
        let windowStart = now.addingTimeInterval(-window)
        var actual: TimeInterval = 0
        for session in timelineVM.sessions where session.who == person {
            let rawEnd = session.endedAt ?? now
            let lower = max(session.startedAt, windowStart)
            let upper = min(rawEnd, now)
            guard lower < upper else { continue }
            actual += upper.timeIntervalSince(lower)
        }
        let target: TimeInterval = 8 * 3_600 * 2  // 8h × 2 days
        return max(0, target - actual)
    }

    @ToolbarContentBuilder
    private func toolbarContent(
        blocks: [ForecastViewModel.RenderableBlock],
        isToday: Bool
    ) -> some ToolbarContent {
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

        // Visual order on screen, right-to-left: chevron → gear → ⓘ → re-propose.
        // SwiftUI renders trailing items in source order so we declare the
        // chevron FIRST and the conditional re-propose LAST.
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                selectedDay = nextDay(after: selectedDay, clampedTo: timelineVM.today)
            } label: {
                Image(systemName: "chevron.right")
                    .accessibilityLabel("Next day")
            }
            .disabled(Calendar.current.isDate(selectedDay, inSameDayAs: timelineVM.today))
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gear")
                    .accessibilityLabel("Feed cadence settings")
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingWhy = true
            } label: {
                Image(systemName: "info.circle")
                    .accessibilityLabel("Why this split")
            }
        }

        // ADJ-006 — re-propose is visible ONLY when at least one
        // ProposedShift for the selected day is manually overridden. Tapping
        // clears all override flags for the day and re-runs the engine.
        if isToday && blocks.contains(where: { $0.manuallyOverridden }) {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    forecastVM.resetOverrides(forPlanDay: selectedDay)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .accessibilityLabel("Re-propose tonight's split")
                }
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

/// Sentinel scroll target for the now-line. `ScrollViewReader.scrollTo(...)` on
/// appear pins this anchor to the centre of the viewport (UI-006 / OQ-8).
private let nowAnchorID = "now-line"

private struct DayBody: View {
    let slices: TimelineViewModel.DaySlices
    let color: (Person) -> Color
    let editVM: EditViewModel
    let forecastVM: ForecastViewModel
    let forecastStore: any ProposedShiftStore
    let feedCadence: FeedCadenceSettings
    let blocks: [ForecastViewModel.RenderableBlock]
    let isToday: Bool
    let selectedDay: Date
    let onAddPast: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    HourGutter(
                        feedCadence: feedCadence,
                        dayStart: slices.day,
                        isToday: isToday
                    )
                    LaneArea(
                        slices: slices,
                        color: color,
                        editVM: editVM,
                        forecastVM: forecastVM,
                        forecastStore: forecastStore,
                        blocks: blocks,
                        isToday: isToday,
                        selectedDay: selectedDay,
                        onAddPast: onAddPast
                    )
                }
                .frame(height: TimelineMetrics.dayHeight)
            }
            .background(Color.relayInk)
            .onAppear {
                guard isToday else { return }
                // Defer one runloop tick so layout completes before we scroll.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(nowAnchorID, anchor: .center)
                    }
                }
            }
        }
    }
}

// MARK: - Hour gutter + feed markers

private struct HourGutter: View {
    let feedCadence: FeedCadenceSettings
    let dayStart: Date
    let isToday: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
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
            ForEach(feedMarkerDates, id: \.self) { markerDate in
                FeedMarker(dayStart: dayStart, markerDate: markerDate)
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

    /// Marker times for the visible calendar day. Projects forward AND backward
    /// from `FeedCadenceSettings.anchorAt` at the configured cadence (FED-004),
    /// then clips to `[dayStart, dayStart+24h)`.
    private var feedMarkerDates: [Date] {
        let anchor = feedCadence.anchorAt
        let cadence = feedCadence.hours * 3_600
        guard cadence > 0 else { return [] }
        let dayEnd = dayStart.addingTimeInterval(24 * 3_600)

        // Find the first marker on/after dayStart by stepping from anchor.
        let stepsToDayStart = (dayStart.timeIntervalSince(anchor) / cadence).rounded(.up)
        var current = anchor.addingTimeInterval(stepsToDayStart * cadence)
        var markers: [Date] = []
        while current < dayEnd {
            if current >= dayStart {
                markers.append(current)
            }
            current = current.addingTimeInterval(cadence)
        }
        return markers
    }
}

private struct FeedMarker: View {
    let dayStart: Date
    let markerDate: Date

    var body: some View {
        let y = TimelineMetrics.yOffset(for: markerDate, dayStart: dayStart)
        HStack(spacing: 2) {
            Image(systemName: "play.fill")
                .resizable()
                .frame(width: 6, height: 6)
                .foregroundStyle(Color.relaySoftCream.opacity(0.55))
            Text("feed")
                .font(.system(size: 8))
                .foregroundStyle(Color.relaySoftCream.opacity(0.55))
        }
        .padding(.leading, 2)
        .frame(height: TimelineMetrics.halfHourHeight, alignment: .center)
        .offset(y: y - TimelineMetrics.halfHourHeight / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Lane area

private struct LaneArea: View {
    let slices: TimelineViewModel.DaySlices
    let color: (Person) -> Color
    let editVM: EditViewModel
    let forecastVM: ForecastViewModel
    let forecastStore: any ProposedShiftStore
    let blocks: [ForecastViewModel.RenderableBlock]
    let isToday: Bool
    let selectedDay: Date
    let onAddPast: () -> Void

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
                    if !blocks.isEmpty {
                        ForecastOverlayView(
                            blocks: blocks,
                            planDay: slices.day,
                            now: Date(),
                            laneWidth: laneWidth,
                            color: color,
                            onCycle: { startedAt, engineProposal in
                                _ = try? forecastStore.cycle(
                                    planDay: slices.day,
                                    startedAt: startedAt,
                                    currentEngineProposal: engineProposal
                                )
                            }
                        )
                    } else {
                        ForecastEmptyState(onAddPast: onAddPast)
                            .frame(width: geo.size.width)
                            .position(x: geo.size.width / 2, y: TimelineMetrics.dayHeight / 2)
                    }
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
