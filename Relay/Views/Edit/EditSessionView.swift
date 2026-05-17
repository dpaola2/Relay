//
//  EditSessionView.swift
//  Relay
//
//  The per-session edit form. Reachable by tapping a row on `EditView`
//  (EDT-003). Adjusts `startedAt` / `endedAt` / `who` and persists through
//  `EditViewModel.save` (EDT-004 / EDT-006). Inline error when the form
//  would set `endedAt < startedAt` (PRD §8).
//

import SwiftUI

struct EditSessionView: View {
    let session: SleepSession
    let viewModel: EditViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var endedAtEnabled: Bool
    @State private var who: Person
    @State private var errorMessage: String?

    init(session: SleepSession, viewModel: EditViewModel) {
        self.session = session
        self.viewModel = viewModel
        _startedAt = State(initialValue: session.startedAt)
        _endedAt = State(initialValue: session.endedAt ?? .now)
        _endedAtEnabled = State(initialValue: session.endedAt != nil)
        _who = State(initialValue: session.who)
    }

    var body: some View {
        Form {
            Section("Who") {
                Picker("Person", selection: $who) {
                    ForEach(Person.allCases) { person in
                        Text(person.displayName).tag(person)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Times") {
                DatePicker("Started at", selection: $startedAt)
                Toggle("Has end time", isOn: $endedAtEnabled)
                if endedAtEnabled {
                    DatePicker("Ended at", selection: $endedAt, in: startedAt...)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Edit session")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { commit() }
            }
        }
    }

    private func commit() {
        let proposedEnd: Date? = endedAtEnabled ? endedAt : session.endedAt
        do {
            try viewModel.save(
                session: session,
                startedAt: startedAt,
                endedAt: proposedEnd,
                who: who
            )
            viewModel.refresh()
            dismiss()
        } catch {
            errorMessage = "End time must be after start time."
        }
    }
}
