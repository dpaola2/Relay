//
//  TotalsView.swift
//  Relay
//
//  The Totals tab — per-person cumulative sleep over 24h, 48h, and 72h.
//  Big numbers, minimal decoration (TOT-002). Zero sessions render as
//  "0h 0m" rather than an empty / placeholder state (TOT-empty).
//
//  Composition keeps each subview ≤50 lines per Sandi Metz's view-body rule.
//

import SwiftUI
import SwiftData

struct TotalsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: TotalsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TotalsContent(viewModel: viewModel)
            } else {
                Color.clear
            }
        }
        .task {
            if viewModel == nil {
                let store = SwiftDataSleepSessionStore(context: modelContext)
                let vm = TotalsViewModel(store: store, clock: SystemClock())
                vm.refresh()
                viewModel = vm
            }
        }
    }
}

private struct TotalsContent: View {
    let viewModel: TotalsViewModel

    private static let windows: [(label: String, seconds: TimeInterval)] = [
        ("Last 24h", 24 * 3_600),
        ("Last 48h", 48 * 3_600),
        ("Last 72h", 72 * 3_600)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Person.allCases) { person in
                    PersonTotalsCard(person: person, viewModel: viewModel, windows: Self.windows)
                }
            }
            .padding(20)
        }
    }
}

private struct PersonTotalsCard: View {
    let person: Person
    let viewModel: TotalsViewModel
    let windows: [(label: String, seconds: TimeInterval)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(person.displayName)
                    .font(.title2.weight(.semibold))
                Spacer()
                SleepDebtBadge(person: person, viewModel: viewModel)
            }
            ForEach(windows, id: \.label) { window in
                TotalsRow(
                    label: window.label,
                    interval: viewModel.total(for: person, over: window.seconds)
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TotalsRow: View {
    let label: String
    let interval: TimeInterval

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(format(interval))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }
}
