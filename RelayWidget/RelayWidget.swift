//
//  RelayWidget.swift
//  RelayWidget
//
//  RELAY-9 — Sleep-debt home-screen widget. systemSmall only.
//
//  Reads the shared SwiftData store via the App Group container,
//  computes per-person 24h sleep balance, and emits 12 timeline
//  entries spaced 5 minutes apart so the displayed numbers
//  refresh every 5 min for the next hour without burning the
//  iOS reload budget. After the hour, iOS calls back into
//  `getTimeline` and we re-read the store.
//
//  The app pushes an explicit reload on every store commit via
//  `WidgetCenterRefresher`, so a logged session is reflected
//  near-immediately regardless of where we sit in the timeline.
//

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - TimelineEntry

struct SleepDebtTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: SleepDebtSnapshot
}

// MARK: - TimelineProvider

struct SleepDebtTimelineProvider: TimelineProvider {

    static let displayInterval: TimeInterval = 5 * 60      // 5 min
    static let entriesPerTimeline = 12                     // covers 1h
    static let reloadAfter: TimeInterval = 60 * 60         // 1h

    func placeholder(in context: Context) -> SleepDebtTimelineEntry {
        SleepDebtTimelineEntry(
            date: .now,
            snapshot: SleepDebtSnapshot(date: .now, daveBalance: nil, bethanyBalance: nil)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepDebtTimelineEntry) -> Void) {
        let sessions = fetchRecentSessions(now: .now)
        let snap = SleepDebtSnapshotComputer.snapshot(sessions: sessions, at: .now)
        completion(SleepDebtTimelineEntry(date: .now, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepDebtTimelineEntry>) -> Void) {
        let now = Date()
        let sessions = fetchRecentSessions(now: now)
        let entries = (0..<Self.entriesPerTimeline).map { index in
            let entryDate = now.addingTimeInterval(Double(index) * Self.displayInterval)
            let snap = SleepDebtSnapshotComputer.snapshot(sessions: sessions, at: entryDate)
            return SleepDebtTimelineEntry(date: entryDate, snapshot: snap)
        }
        let reloadAt = now.addingTimeInterval(Self.reloadAfter)
        completion(Timeline(entries: entries, policy: .after(reloadAt)))
    }

    // MARK: - SwiftData read

    private func fetchRecentSessions(now: Date) -> [SleepSession] {
        guard let storeURL = WidgetAppGroup.storeURL else { return [] }
        do {
            let schema = Schema([SleepSession.self])
            let config = ModelConfiguration(schema: schema, url: storeURL, allowsSave: false)
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<SleepSession>()
            let all = try context.fetch(descriptor)
            let scanLower = now.addingTimeInterval(-SleepDebtSnapshotComputer.scanWindow)
            return all.filter { row in
                let endOrOpen = row.endedAt ?? .distantFuture
                return row.startedAt <= now && endOrOpen >= scanLower
            }
        } catch {
            return []
        }
    }
}

// MARK: - Entry View

struct SleepDebtEntryView: View {
    let entry: SleepDebtTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PersonDebtRow(
                person: .dave,
                balance: entry.snapshot.daveBalance,
                laneColor: .relayTerracotta
            )
            PersonDebtRow(
                person: .bethany,
                balance: entry.snapshot.bethanyBalance,
                laneColor: .relaySoftPeach
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "relay://totals"))
    }
}

private struct PersonDebtRow: View {
    let person: Person
    let balance: TimeInterval?
    let laneColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(laneColor)
                    .frame(width: 8, height: 8)
                Text(person.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.relayInk.opacity(0.7))
            }
            Text(displayString)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.relayInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(person.displayName) sleep debt \(displayString)"))
    }

    private var displayString: String {
        guard let balance else { return SleepDebtFormatter.noDataPlaceholder }
        return SleepDebtFormatter.format(balance: balance)
    }
}

// MARK: - Widget

struct RelayWidget: Widget {
    /// Keep this string in sync with `WidgetCenterRefresher.sleepDebtWidgetKind`
    /// in the app target — a mismatch silently no-ops the on-write reload.
    let kind: String = "RelaySleepDebtWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepDebtTimelineProvider()) { entry in
            SleepDebtEntryView(entry: entry)
                .containerBackground(Color.relayCream, for: .widget)
        }
        .configurationDisplayName("Sleep Debt")
        .description("How much sleep Dave and Bethany are short of an 8h/24h target.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    RelayWidget()
} timeline: {
    SleepDebtTimelineEntry(
        date: .now,
        snapshot: SleepDebtSnapshot(date: .now, daveBalance: -3 * 3600 - 12 * 60, bethanyBalance: -1 * 3600 - 45 * 60)
    )
    SleepDebtTimelineEntry(
        date: .now,
        snapshot: SleepDebtSnapshot(date: .now, daveBalance: nil, bethanyBalance: nil)
    )
    SleepDebtTimelineEntry(
        date: .now,
        snapshot: SleepDebtSnapshot(date: .now, daveBalance: 0, bethanyBalance: 1800)
    )
}
