//
//  NamesScreen.swift
//  Relay
//
//  RELAY-10 — Onboarding screen 3. Two name fields. `Done` stays disabled
//  until both are non-empty (whitespace-only counts as empty). The 30-char
//  cap is enforced by the binding — paste of a longer string truncates
//  rather than rejecting, so the field doesn't visibly reject input.
//

import SwiftUI

struct NamesScreen: View {
    @Binding var draftA: String
    @Binding var draftB: String
    let onDone: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field { case a, b }

    /// Same length cap used by `SettingsView.NamesSection`. Kept here as a
    /// local constant so the two surfaces are consistent.
    private static let maxLength = 30

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Two parents on this phone.")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(Color.relayCream)
                        .padding(.top, 80)

                    Text("What are your names?")
                        .font(.title3)
                        .foregroundStyle(Color.relaySoftCream)

                    VStack(spacing: 12) {
                        nameField(placeholder: "Person A", text: bindingFor($draftA), focus: .a)
                        nameField(placeholder: "Person B", text: bindingFor($draftB), focus: .b)
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            OnboardingPrimaryButton(
                title: "Done",
                action: onDone,
                isEnabled: isReady
            )
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focusedField = .a }
    }

    private var isReady: Bool {
        !draftA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !draftB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func nameField(placeholder: String, text: Binding<String>, focus: Field) -> some View {
        TextField(placeholder, text: text)
            .focused($focusedField, equals: focus)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(focus == .a ? .next : .done)
            .onSubmit {
                if focus == .a {
                    focusedField = .b
                } else if isReady {
                    onDone()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.relayCream.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Color.relayCream)
    }

    private func bindingFor(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { source.wrappedValue = String($0.prefix(Self.maxLength)) }
        )
    }
}
