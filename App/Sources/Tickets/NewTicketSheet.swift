import HuddleKit
import SwiftUI

/// A new ticket: title, details, priority, assignees, GitHub link, and an
/// option to start its timer right away.
struct NewTicketSheet: View {
    let model: TicketsModel

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Environment(NowModel.self) private var now

    @State private var title = ""
    @State private var details = ""
    @State private var priority: TicketPriority = .none
    @State private var assignees: Set<String> = []
    @State private var github = ""
    @State private var startTimer = true
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var titleFocused: Bool

    private var onShift: Bool { now.active != nil }
    private var githubIsValid: Bool {
        let link = github.trimmingCharacters(in: .whitespaces)
        return link.isEmpty || (link.lowercased().hasPrefix("https://") && URL(string: link)?.host() != nil)
    }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && githubIsValid && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    EdgeToEdgeList(separatorInset: Spacing.xl) {
                        TextField("Title", text: $title, axis: .vertical)
                            .font(.title3.weight(.semibold))
                            .focused($titleFocused)
                            .submitLabel(.next)
                            .padding(.vertical, 14)
                            .padding(.horizontal, Spacing.xl)
                        TextField("Add details (optional)", text: $details, axis: .vertical)
                            .lineLimit(3...8)
                            .padding(.vertical, 14)
                            .padding(.horizontal, Spacing.xl)
                    }

                    VStack(alignment: .leading, spacing: Spacing.s) {
                        Text("Priority")
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(.horizontal, Spacing.xl)
                        Picker("Priority", selection: $priority) {
                            ForEach(TicketPriority.allCases) { Text($0.shortTitle).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, Spacing.margin)
                    }

                    EdgeToEdgeList(separatorInset: Spacing.xl) {
                        NavigationLink {
                            AssigneePicker(model: model, selection: $assignees)
                        } label: {
                            row("Assignees") {
                                Text(assigneeSummary).foregroundStyle(Palette.textSecondary)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        row("GitHub link") {
                            TextField("Optional", text: $github)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(githubIsValid ? Palette.textSecondary : Palette.destructive)
                        }
                        Toggle(isOn: $startTimer) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Start timer now")
                                if !onShift {
                                    Text("Start your day first").font(.footnote).foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                        .tint(Palette.limeText)
                        .disabled(!onShift)
                        .padding(.vertical, 10)
                        .padding(.horizontal, Spacing.xl)
                    }

                    if !githubIsValid {
                        InlineError(message: "GitHub links must start with https://").padding(.horizontal, Spacing.margin)
                    }
                    if let error {
                        InlineError(message: error).padding(.horizontal, Spacing.margin)
                    }
                    Text(assignees.isEmpty ? "It’s assigned to you." : "The assignees get a notification.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.xl)
                }
                .padding(.vertical, Spacing.l)
            }
            .background(Palette.canvas)
            .navigationTitle("New ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add ticket", systemImage: "checkmark", action: save)
                        .buttonStyle(.glassProminent)
                        .tint(Palette.lime)
                        .foregroundStyle(Palette.onLime)
                        .disabled(!canSave)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onAppear { titleFocused = true }
    }

    private func row<Trailing: View>(_ label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: Spacing.m) {
            Text(label).foregroundStyle(Palette.textPrimary)
            Spacer(minLength: Spacing.s)
            trailing()
        }
        .frame(minHeight: 44)
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.xl)
        .contentShape(Rectangle())
    }

    private var assigneeSummary: String {
        if assignees.isEmpty { return "Me" }
        let names = assignees.map { $0 == app.userId ? "Me" : model.name(of: $0) }.sorted()
        return names.count <= 2 ? names.joined(separator: ", ") : "\(names.count) people"
    }

    private func save() {
        guard canSave, let teamId = app.team?.id else { return }
        isSaving = true
        error = nil
        let link = github.trimmingCharacters(in: .whitespaces)
        let note = details.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let ticket = try await model.create(.init(
                    teamId: teamId,
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: note.isEmpty ? nil : note,
                    github: link.isEmpty ? nil : link,
                    priority: priority == .none ? nil : priority.rawValue,
                    assignedToUserIds: assignees.isEmpty ? nil : Array(assignees)
                ))
                if startTimer, onShift {
                    _ = await now.startTimer(ticketId: ticket.id)
                }
                dismiss()
            } catch {
                self.error = APIError.from(error).localizedDescription
            }
            isSaving = false
        }
    }
}

/// Pick who a new ticket is assigned to. Nobody picked means you.
private struct AssigneePicker: View {
    let model: TicketsModel
    @Binding var selection: Set<String>
    @Environment(AppModel.self) private var app

    var body: some View {
        List(model.members.value ?? []) { member in
            Button {
                if selection.contains(member.id) { selection.remove(member.id) } else { selection.insert(member.id) }
            } label: {
                HStack(spacing: Spacing.m) {
                    Avatar(initials: TicketsModel.initials(member.displayName), size: 32, isMe: member.id == app.userId)
                    Text(member.id == app.userId ? "\(member.displayName) (you)" : member.displayName)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    if selection.contains(member.id) {
                        Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Palette.limeText)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection.contains(member.id) ? .isSelected : [])
            .listRowBackground(Palette.canvas)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("Assignees")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.members.value == nil { ProgressView() }
        }
    }
}
