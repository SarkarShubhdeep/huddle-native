import HuddleKit
import SwiftUI

/// The Huddle tab: the team's posts, newest first, edge to edge. Plans and
/// wrap-ups carry badges; Team / Mine narrows to your own posts.
struct HuddleScreen: View {
    enum Scope: String, CaseIterable { case team = "Team", mine = "Mine" }

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var feed: Resource<PostsPage>?
    @State private var directory: MentionDirectory?
    @State private var scope: Scope = .team
    @State private var showComposer = false

    var body: some View {
        List {
            Picker("Show", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.margin)
            .padding(.bottom, Spacing.s)
            .plainRow()

            if let feed, feed.error != nil, feed.value != nil {
                RefreshBanner(message: "Couldn’t refresh the feed.") { Task { await feed.refresh() } }
                    .padding(.horizontal, Spacing.margin)
                    .plainRow()
            }
            ForEach(posts) { post in
                PostRow(
                    authorName: post.userName ?? "Teammate",
                    authorInitials: post.userInitials ?? TicketsModel.initials(post.userName ?? "?"),
                    isMe: post.userId == app.userId,
                    meta: meta(post),
                    kind: post.kind,
                    markdown: endpoint.map { MediaURL.rebaseMarkdown(post.content.text, against: $0) } ?? post.content.text,
                    ticketTitle: post.ticketTitle,
                    imageURL: post.attachments.first(where: \.isImage).flatMap { image in
                        endpoint.flatMap { MediaURL.resolve(image.thumbnailUrl ?? image.url, against: $0) }
                    },
                    people: people,
                    likeCount: post.likes.count,
                    commentCount: post.commentCount
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.canvas)
                .alignmentGuide(.listRowSeparatorLeading) { _ in Spacing.xl }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .refreshable { await feed?.refresh() }
        .overlay { overlay }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New post", systemImage: "square.and.pencil") { showComposer = true }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.lime)
                    .foregroundStyle(Palette.onLime)
            }
        }
        .sheet(isPresented: $showComposer) {
            if let directory {
                NewPostSheet(directory: directory) { await feed?.refetch() }
            }
        }
        .task(id: app.team?.id) { await load() }
        // While the tab is on screen: refresh every 30 s.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await feed?.refresh()
            }
        }
    }

    @ViewBuilder private var overlay: some View {
        if let feed, feed.value == nil, feed.error != nil {
            StatusView.unreachable(host: endpoint?.baseURL.host() ?? "The server",
                                   onRetry: { Task { await feed.refresh() } },
                                   onChangeServer: { app.signOut() })
        } else if feed?.value == nil {
            ProgressView()
        } else if posts.isEmpty {
            StatusView(systemImage: "bubble.left", title: scope == .mine ? "You haven’t posted yet" : "No posts yet",
                       message: "Share a plan, an update or a question with your team.", tone: .working,
                       primary: .init(title: "New post") { showComposer = true })
        }
    }

    private var endpoint: ServerEndpoint? { app.session.session?.endpoint }

    private var posts: [HuddlePost] {
        let all = feed?.value?.posts ?? []
        return scope == .mine ? all.filter { $0.userId == app.userId } : all
    }

    private var people: [String: String] {
        RichMarkdown.mentionTokens((directory?.members.value ?? []).map { (id: $0.id, name: $0.displayName) })
    }

    private func load() async {
        guard let api = app.api, let teamId = app.team?.id else { return }
        let service = HuddleService(api)
        let resource = Resource<PostsPage>(cacheKey: "posts.\(teamId)", store: app.snapshotStore) {
            try await service.posts(teamId: teamId)
        }
        feed = resource
        directory = MentionDirectory(api: api, teamId: teamId, snapshots: app.snapshotStore)
        async let a: Void = resource.load()
        async let b: Void = directory!.load()
        _ = await (a, b)
    }

    /// "9:01 AM · shift 9:02 AM – now", "Yesterday · 5:40 PM", "Oct 12 · 3:10 PM".
    private func meta(_ post: HuddlePost) -> String {
        let calendar = Calendar.current
        let time = post.createdAt.formatted(date: .omitted, time: .shortened)
        var text: String
        if calendar.isDateInToday(post.createdAt) { text = time }
        else if calendar.isDateInYesterday(post.createdAt) { text = "Yesterday · \(time)" }
        else { text = "\(post.createdAt.formatted(.dateTime.month(.abbreviated).day())) · \(time)" }
        if let session = post.session {
            let start = session.startTime.formatted(date: .omitted, time: .shortened)
            text += " · shift \(start) – \(session.endTime?.formatted(date: .omitted, time: .shortened) ?? "now")"
        }
        if post.isEdited { text += " · edited" }
        return text
    }
}

private extension View {
    func plainRow() -> some View {
        listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
    }
}

/// A new Huddle post: the rich composer, posted to the current team.
struct NewPostSheet: View {
    let directory: MentionDirectory
    var posted: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var controller = RichEditorController()
    @State private var isPosting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Hairline()
                if let error { InlineError(message: error) }
                Composer(controller: controller, directory: directory, placeholder: "Share an update with your team…")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.s)
            .background(Palette.canvas)
            .navigationTitle("New post")
            .navigationSubtitle(app.team?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: post) {
                        if isPosting { ProgressView() } else { Text("Post") }
                    }
                    .buttonStyle(HNButtonStyle(role: .primary, size: .small))
                    .disabled(controller.isEmpty || isPosting)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isPosting || !controller.isEmpty)
    }

    private func post() {
        guard let api = app.api, let teamId = app.team?.id else { return }
        let content = controller.composed
        isPosting = true
        error = nil
        Task {
            do {
                _ = try await HuddleService(api).create(.init(
                    teamId: teamId,
                    content: .init(text: content.markdown, mentions: content.mentions),
                    ticketId: content.ticketId,
                    postDate: WorkDay().key(for: .now)
                ))
                await posted()
                dismiss()
            } catch {
                self.error = APIError.from(error).localizedDescription
            }
            isPosting = false
        }
    }
}
