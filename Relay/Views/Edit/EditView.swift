//
//  EditView.swift
//  Relay
//
//  The Edit tab — a list of `SleepSession` rows in the last 7 days (ADR-003).
//  Each row exposes who / start / end-or-ongoing / duration (EDT-002); tap
//  navigates to the per-session edit form (EDT-003). Swipe-to-delete covers
//  EDT-005 (Should).
//
//  Composition keeps each subview ≤50 lines per Sandi Metz's view-body rule.
//

import SwiftUI
import SwiftData

struct EditView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: EditViewModel?

    var body: some View {
        Group {
            if let viewModel {
                EditContent(viewModel: viewModel)
            } else {
                Color.clear
            }
        }
        .task {
            if viewModel == nil {
                let store = SwiftDataSleepSessionStore(context: modelContext)
                let vm = EditViewModel(store: store, clock: SystemClock())
                vm.refresh()
                viewModel = vm
            }
        }
    }
}

private struct EditContent: View {
    let viewModel: EditViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.sessions.isEmpty {
                    EditEmptyState()
                } else {
                    EditSessionList(viewModel: viewModel)
                }
            }
            .navigationTitle("Last 7 days")
        }
    }
}

private struct EditEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("No sessions in the last 7 days")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EditSessionList: View {
    let viewModel: EditViewModel

    var body: some View {
        List {
            ForEach(viewModel.sessions, id: \.id) { session in
                NavigationLink {
                    EditSessionView(session: session, viewModel: viewModel)
                } label: {
                    EditSessionRow(session: session)
                }
            }
            .onDelete(perform: delete)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let session = viewModel.sessions[index]
            try? viewModel.delete(session)
        }
        viewModel.refresh()
    }
}

private struct EditSessionRow: View {
    let session: SleepSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.who.displayName)
                .font(.headline)
            HStack(spacing: 4) {
                Text(session.startedAt, style: .date)
                Text(session.startedAt, style: .time)
                Text("→")
                if let endedAt = session.endedAt {
                    Text(endedAt, style: .time)
                } else {
                    Text("ongoing").italic()
                }
                Spacer()
                Text(durationString(session.duration(asOf: .now)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }
}
