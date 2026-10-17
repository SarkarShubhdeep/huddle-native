import HuddleKit
import SwiftUI

/// The Inbox tab: notifications newest first, unread ones marked. Swipe to
/// mark read or delete; tap to mark read and go where it points.
struct InboxScreen: View {
    @Environment(InboxModel.self) private var model
    @Environment(AppModel.self) private var app
    var open: (NotificationRoute) -> Void = { _ in }

    var body: some View {
        List {
            if model.inbox.error != nil, model.inbox.value != nil {
                RefreshBanner(message: "Couldn’t refresh notifications.") { Task { await model.refresh() } }
                    .padding(.horizontal, Spacing.margin)
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
            }
            if let error = model.error {
                InlineError(message: error)
                    .padding(.horizontal, Spacing.margin)
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Palette.canvas)
            }
            ForEach(model.notifications) { notification in
                Button {
                    Task { await model.markRead(notification) }
                    open(NotificationRoute(notification))
                } label: {
                    NotificationRow(notification: notification)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.canvas)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 64 }
                .swipeActions(edge: .leading) {
                    if !notification.read {
                        Button("Mark read", systemImage: "envelope.open") { Task { await model.markRead(notification) } }
                            .tint(Palette.limeText)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete", systemImage: "trash", role: .destructive) { Task { await model.delete([notification]) } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .refreshable { await model.refresh() }
        .overlay {
            if model.inbox.value == nil, model.inbox.error != nil {
                StatusView.unreachable(host: app.session.session?.endpoint.baseURL.host() ?? "The server",
                                       onRetry: { Task { await model.refresh() } },
                                       onChangeServer: { app.signOut() })
            } else if model.inbox.value == nil {
                ProgressView()
            } else if model.notifications.isEmpty {
                StatusView(systemImage: "bell", title: "You’re all caught up",
                           message: "Clock reminders, mentions and ticket updates show up here.", tone: .done)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Mark all read", systemImage: "envelope.open") { Task { await model.markAllRead() } }
                        .disabled(model.unreadCount == 0)
                    Button("Delete read", systemImage: "trash", role: .destructive) {
                        Task { await model.delete(model.notifications.filter(\.read)) }
                    }
                    .disabled(!model.notifications.contains(where: \.read))
                }
            }
        }
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(notification.read ? Palette.textSecondary : Palette.limeText)
                .frame(width: 32, height: 32)
                .background(notification.read ? Palette.fill : Palette.limeSoft, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(kind)
                        .font(.subheadline.weight(notification.read ? .regular : .semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text(notification.createdAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let body = notification.body {
                    Text(body)
                        .font(.body.weight(notification.read ? .regular : .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                }
            }
            if !notification.read {
                Circle().fill(Palette.limeText).frame(width: 8, height: 8).padding(.top, 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Spacing.m)
        .padding(.horizontal, Spacing.xl)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(notification.read ? "" : "Unread")
    }

    /// What it's about; the server's title is always just "Huddle".
    private var kind: String {
        let type = notification.type ?? ""
        if type.hasPrefix("clock") { return "Clock" }
        if type.hasPrefix("shift") { return "Shift reminder" }
        if type.hasPrefix("ticket") { return "Ticket" }
        if type.contains("mention") { return "Mention" }
        if type.hasPrefix("timesheet") { return "Timesheet" }
        if type.hasPrefix("huddle") { return "Huddle" }
        return notification.title ?? "Huddle"
    }

    private var icon: String {
        let type = notification.type ?? ""
        if type.hasPrefix("clock") || type.hasPrefix("shift") { return "clock" }
        if type.hasPrefix("ticket") { return "list.bullet" }
        if type.hasPrefix("huddle") || type.contains("mention") { return "bubble.left" }
        if type.hasPrefix("timesheet") { return "chart.bar" }
        return "bell"
    }
}
