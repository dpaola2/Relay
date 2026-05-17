//
//  AddPastSleepSheet.swift
//  Relay
//
//  Modal sheet behind the Edit-tab `+` toolbar button (RELAY-2 / M2).
//  Hosts `AddPastSleepViewModel` and renders a `Form`-based UI mirroring
//  `EditSessionView`'s structural template — `Section("Who")` segmented
//  `Picker`, `Section("Times")` two `DatePicker`s, a live `Duration` readout
//  plus inline `VAL-004` helper copy, and an optional `Section("Note")`
//  `TextField`.
//
//  Save / Cancel sit in the navigation bar as `.confirmationAction` /
//  `.cancellationAction` toolbar items. Save calls `vm.save()` and dismisses;
//  Cancel just dismisses. No confirmation prompt — taps are reversible via
//  the Edit list (CLAUDE.md §"UX for the half-asleep operator").
//
//  Construction mirrors `EditView`: a `SwiftDataSleepSessionStore` is built
//  inline from the environment's `modelContext`, and a fresh `SystemClock` is
//  injected. No `EnvironmentValues` seam is introduced (architecture §10
//  "Files NOT Touched").
//

import SwiftUI
import SwiftData

struct AddPastSleepSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: AddPastSleepViewModel?
    @State private var saveErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    AddPastSleepForm(
                        viewModel: viewModel,
                        saveErrorMessage: saveErrorMessage
                    )
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Add Past Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
        }
        .task {
            if viewModel == nil {
                let store = SwiftDataSleepSessionStore(context: modelContext)
                viewModel = AddPastSleepViewModel(store: store, clock: SystemClock())
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { commit() }
                .disabled(viewModel?.isSaveEnabled != true)
        }
    }

    private func commit() {
        guard let viewModel else { return }
        do {
            try viewModel.save()
            dismiss()
        } catch {
            saveErrorMessage = "Couldn't save — try again."
        }
    }
}

private struct AddPastSleepForm: View {
    @Bindable var viewModel: AddPastSleepViewModel
    let saveErrorMessage: String?

    var body: some View {
        Form {
            WhoSection(who: $viewModel.who)
            TimesSection(
                startedAt: $viewModel.startedAt,
                endedAt: $viewModel.endedAt
            )
            DurationSection(
                duration: viewModel.duration,
                validationMessage: viewModel.validationMessage
            )
            NoteSection(note: $viewModel.note)
            if let saveErrorMessage {
                Section {
                    Text(saveErrorMessage).foregroundStyle(Color.relayDeepTerracotta)
                }
            }
        }
    }
}

private struct WhoSection: View {
    @Binding var who: Person

    var body: some View {
        Section("Who") {
            Picker("Person", selection: $who) {
                ForEach(Person.allCases) { person in
                    Text(person.displayName).tag(person)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct TimesSection: View {
    @Binding var startedAt: Date
    @Binding var endedAt: Date

    var body: some View {
        Section("Times") {
            DatePicker("Fell asleep", selection: $startedAt)
            DatePicker("Woke up", selection: $endedAt)
        }
    }
}

private struct DurationSection: View {
    let duration: TimeInterval
    let validationMessage: String?

    var body: some View {
        Section {
            HStack {
                Text("Duration")
                Spacer()
                Text(durationString)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let validationMessage {
                // Validation copy uses `.relayDeepTerracotta` per RELAY-3 —
                // the palette has no red, so deep terracotta carries the
                // alarm/error signal. Bumped to `.footnote.weight(.medium)`
                // for half-asleep-operator contrast at 3 AM (RELAY-2 / M4).
                Text(validationMessage)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.relayDeepTerracotta)
            }
        }
    }

    private var durationString: String {
        guard duration > 0 else { return "0h 0m" }
        let total = Int(duration)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        return "\(hours)h \(minutes)m"
    }
}

private struct NoteSection: View {
    @Binding var note: String

    var body: some View {
        Section("Note") {
            TextField("Optional", text: $note, axis: .vertical)
                .lineLimit(1...3)
        }
    }
}
