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
//  RELAY-10 — entries now carry the per-person display names so the
//  widget renders the household's actual names instead of "Dave" /
//  "Bethany." Names are read from the App Group `UserDefaults` suite
//  written by `PersonNameSettings` in the app target. Empty values fall
//  back to "Person A" / "Person B" for the pre-onboarding window.
//

import WidgetKit
import SwiftUI
import SwiftData

// MARK: - TimelineEntry

struct SleepDebtTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: SleepDebtSnapshot
    let nameA: String
    let nameB: String
}

// MARK: - TimelineProvider

struct SleepDebtTimelineProvider: TimelineProvider {

    static let displayInterval: TimeInterval = 5 * 60      // 5 min
    static let entriesPerTimeline = 12                     // covers 1h
    static let reloadAfter: TimeInterval = 60 * 60         // 1h

    /// UserDefaults keys shared with `PersonNameSettings.Keys` in the app
    /// target. Duplicated here because the widget extension can't import
    /// app-target code; treat both sides as the authoritative spec.
    private static let nameAKey = "relay.person.nameA"
    private static let nameBKey = "relay.person.nameB"

    func placeholder(in context: Context) -> SleepDebtTimelineEntry {
        let (nameA, nameB) = Self.resolvedNames()
        return SleepDebtTimelineEntry(
            date: .now,
            snapshot: SleepDebtSnapshot(date: .now, personABalance: nil, personBBalance: nil),
            nameA: nameA,
            nameB: nameB
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepDebtTimelineEntry) -> Void) {
        let sessions = fetchRecentSessions(now: .now)
        let snap = SleepDebtSnapshotComputer.snapshot(sessions: sessions, at: .now)
        let (nameA, nameB) = Self.resolvedNames()
        completion(SleepDebtTimelineEntry(date: .now, snapshot: snap, nameA: nameA, nameB: nameB))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepDebtTimelineEntry>) -> Void) {
        let now = Date()
        let sessions = fetchRecentSessions(now: now)
        let (nameA, nameB) = Self.resolvedNames()
        let entries = (0..<Self.entriesPerTimeline).map { index in
            let entryDate = now.addingTimeInterval(Double(index) * Self.displayInterval)
            let snap = SleepDebtSnapshotComputer.snapshot(sessions: sessions, at: entryDate)
            return SleepDebtTimelineEntry(date: entryDate, snapshot: snap, nameA: nameA, nameB: nameB)
        }
        let reloadAt = now.addingTimeInterval(Self.reloadAfter)
        completion(Timeline(entries: entries, policy: .after(reloadAt)))
    }

    /// Resolve the configured names from the App Group suite. Empty stored
    /// values fall through to `"Person A"` / `"Person B"` so a widget added
    /// before onboarding completes still renders something legible.
    private static func resolvedNames() -> (nameA: String, nameB: String) {
        let defaults = UserDefaults(suiteName: WidgetAppGroup.identifier)
        let storedA = defaults?.string(forKey: nameAKey) ?? ""
        let storedB = defaults?.string(forKey: nameBKey) ?? ""
        return (
            storedA.isEmpty ? "Person A" : storedA,
            storedB.isEmpty ? "Person B" : storedB
        )
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
                name: entry.nameA,
                balance: entry.snapshot.personABalance,
                laneColor: .relayTerracotta
            )
            PersonDebtRow(
                name: entry.nameB,
                balance: entry.snapshot.personBBalance,
                laneColor: .relaySoftPeach
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "relay://totals"))
    }
}

private struct PersonDebtRow: View {
    let name: String
    let balance: TimeInterval?
    let laneColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(laneColor)
                    .frame(width: 8, height: 8)
                Text(name)
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
        .accessibilityLabel(Text("\(name) sleep debt \(displayString)"))
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
        .description("How much sleep each parent is short of an 8h/24h target.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Preview

/// Gallery preview names. Generic real-sounding names communicate
/// "this is what it'll look like for your household" without
/// presenting "Person A" placeholders that look broken in the gallery.
private let galleryNameA = "Casey"
private let galleryNameB = "Avery"

#Preview(as: .systemSmall) {
    RelayWidget()
} timeline: {
    SleepDebtTimelineEntry(
        date: .now,
        snapshot: SleepDebtSnapshot(date: .now, personABalance: -3 * 3600 - 12 * 60, personBBalance: -1 * 3600 - 45 * 60),
        nameA: galleryNameA,
        nameB: galleryNameB
    )
    SleepDebtTimelineEntry(
        date: .now,
        snapshot: SleepDebtSnapshot(date: .now, personABalance: nil, personBBalance: nil),
        nameA: galleryNameA,
        nameB: galleryNameB
    )
    SleepDebtTimelineEntry(
        date: .now,
        snapshot: SleepDebtSnapshot(date: .now, personABalance: 0, personBBalance: 1800),
        nameA: galleryNameA,
        nameB: galleryNameB
    )
}
