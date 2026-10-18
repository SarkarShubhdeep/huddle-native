import HuddleKit
import SwiftUI

/// Behind the avatar: who you are, which server and team, sign out, and
/// diagnostics for when something seems slow or stuck.
struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(ReleaseNotesStore.self) private var notes
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Spacing.l) {
                        Avatar(initials: app.me?.initials ?? "", size: 56, isMe: true)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(app.me?.displayName ?? "You").font(.title3.bold())
                            if let username = app.me?.username {
                                Text("@\(username)").font(.subheadline).foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                }

                Section("Workspace") {
                    LabeledContent("Team", value: app.team?.name ?? "–")
                    if let endpoint = app.session.session?.endpoint {
                        LabeledContent("Server") {
                            Text(serverText(endpoint)).font(.subheadline.monospaced()).textSelection(.enabled)
                        }
                    }
                    if let expires = app.session.session?.expiresAt {
                        LabeledContent("Signed in until", value: expires.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                Section {
                    NavigationLink { ReleaseNotesList() } label: {
                        HStack {
                            Label("What’s new", systemImage: "sparkles")
                            Spacer()
                            if !notes.unread.isEmpty {
                                Text("\(notes.unread.count)")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Palette.onLime)
                                    .padding(.horizontal, 7)
                                    .frame(minHeight: 20)
                                    .background(Palette.lime, in: Capsule())
                                    .accessibilityLabel("\(notes.unread.count) new")
                            }
                        }
                    }
                    NavigationLink("Diagnostics") { DiagnosticsView() }
                    LabeledContent("Version", value: version)
                }

                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("To use a different server, sign out and pick it on the first screen.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .confirmationDialog("Sign out of Huddle?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    dismiss()
                    app.signOut()
                }
            } message: {
                Text("A running shift keeps going on the server. You can sign back in any time.")
            }
        }
        .tint(Palette.limeText)
    }

    private func serverText(_ endpoint: ServerEndpoint) -> String {
        let url = endpoint.baseURL
        return [url.host(), url.port.map(String.init)].compactMap { $0 }.joined(separator: ":")
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// The last requests to the server: which call, how long, and how it ended.
struct DiagnosticsView: View {
    @Environment(AppModel.self) private var app
    @State private var entries: [RequestLog.Entry] = []
    @State private var probe: ServerProbe.Outcome?

    var body: some View {
        List {
            Section {
                if let endpoint = app.session.session?.endpoint {
                    Button("Test connection") {
                        probe = nil
                        Task {
                            probe = await ServerProbe(transport: LoggingTransport(URLSessionTransport(), log: app.requestLog)).check(endpoint)
                            entries = app.requestLog.entries
                        }
                    }
                    if let probe { ConnectionStatus.done(probe).view(endpoint: endpoint) }
                }
            } footer: {
                Text("Requests time out after 10 s, and pull to refresh always stops within 6 s.")
            }

            Section("Recent requests") {
                if entries.isEmpty {
                    Text("No requests yet.").foregroundStyle(Palette.textSecondary)
                }
                ForEach(entries) { entry in
                    HStack(spacing: Spacing.m) {
                        Circle().fill(entry.succeeded ? Palette.done : Palette.destructive).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name).font(.subheadline.monospaced())
                            Text(detail(entry)).font(.caption).foregroundStyle(Palette.textSecondary)
                        }
                        Spacer()
                        Text("\(entry.milliseconds) ms").font(.subheadline).monospacedDigit()
                            .foregroundStyle(entry.milliseconds > 2000 ? Palette.breakText : Palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("Diagnostics")
        .refreshable { entries = app.requestLog.entries }
        .onAppear { entries = app.requestLog.entries }
    }

    private func detail(_ entry: RequestLog.Entry) -> String {
        let time = entry.startedAt.formatted(date: .omitted, time: .standard)
        if let status = entry.status { return "\(time) · HTTP \(status)" }
        return "\(time) · \(entry.failure ?? "No response")"
    }
}
