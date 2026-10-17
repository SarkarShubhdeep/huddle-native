import SwiftUI

/// "What's the plan today?" One sheet posts the plan to Huddle and clocks you
/// in with it linked to the new shift. The rich editor arrives in Step 8;
/// until then the plan is plain text (markdown is kept as typed).
struct PlanSheet: View {
    let teamName: String
    /// Posts the plan and starts the day; returns whether it worked.
    var start: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(NowModel.self) private var now
    @State private var text = ""
    @State private var isStarting = false
    @FocusState private var focused: Bool

    private var canStart: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStarting }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("What’s the plan today?")
                        .font(.title.bold())
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(teamName) asks for one. It’s posted to Huddle and linked to this shift.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                Hairline()
                ComposerField(text: $text, placeholder: "A few lines on what you’ll work on…")
                    .focused($focused)
                if let error = now.actionError {
                    InlineError(message: error)
                }
                Spacer(minLength: 0)
                Text("Start day posts this plan and clocks you in.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.l)
            .background(Palette.canvas)
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submit) {
                        if isStarting { ProgressView() } else { Text("Start day") }
                    }
                    .buttonStyle(HNButtonStyle(role: .primary, size: .small))
                    .disabled(!canStart)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isStarting)
        .onAppear { focused = true; now.actionError = nil }
    }

    private func submit() {
        guard canStart else { return }
        isStarting = true
        Task {
            if await start(text) { dismiss() }
            isStarting = false
        }
    }
}

/// A multi-line text area on the canvas, with a placeholder. Stands in for
/// the rich composer until Step 8.
struct ComposerField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .foregroundStyle(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 140)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(Palette.textSecondary.opacity(0.6))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(placeholder)
    }
}
