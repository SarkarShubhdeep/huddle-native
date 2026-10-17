import HuddleKit
import Observation
import SwiftUI

/// The people and tickets `@` can mention in one team. Reuses the Tickets
/// tab's caches, so it's ready at once.
@MainActor
@Observable
final class MentionDirectory {
    let members: Resource<[TeamMember]>
    let tickets: Resource<[Ticket]>

    init(api: APIClient, teamId: String, snapshots: any SnapshotStore) {
        let teams = TeamService(api)
        let service = TicketService(api)
        members = Resource(cacheKey: "members.\(teamId)", store: snapshots) { try await teams.members(teamId: teamId) }
        tickets = Resource(cacheKey: "tickets.\(teamId)", store: snapshots) { try await service.list(teamId: teamId) }
    }

    func load() async {
        async let a: Void = members.load()
        async let b: Void = tickets.load()
        _ = await (a, b)
    }

    func people(matching query: String, excluding me: String?) -> [TeamMember] {
        let q = query.lowercased()
        return (members.value ?? [])
            .filter { $0.id != me && (q.isEmpty || $0.displayName.lowercased().contains(q) || ($0.username?.lowercased().contains(q) ?? false)) }
            .prefix(4).map { $0 }
    }

    func tickets(matching query: String) -> [Ticket] {
        let open = (tickets.value ?? []).filter { $0.status != "closed" }
        let matches = query.isEmpty ? open : open.filter { TicketQuery.match(query, in: $0.title) != nil }
        return Array(matches.prefix(3))
    }
}

/// Rich text, an `@` popover for people and tickets, and the formatting
/// toolbar. Plan, wrap-up and Huddle posts all use it.
struct Composer: View {
    let controller: RichEditorController
    let directory: MentionDirectory?
    var placeholder = "Write something…"
    var autofocus = true

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: Spacing.m) {
            RichTextEditor(controller: controller, placeholder: placeholder, autofocus: autofocus)
                .overlay(alignment: .topLeading) {
                    if controller.isEmpty {
                        Text(placeholder)
                            .font(.body)
                            .foregroundStyle(Palette.textSecondary.opacity(0.6))
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxHeight: .infinity)
            if let query = controller.mentionQuery, let directory {
                MentionSuggestions(query: query, directory: directory, me: app.userId) { run in
                    controller.insertMention(run)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            ComposerToolbar(active: controller.active) { controller.apply($0) }
        }
        .springAnimation(value: controller.mentionQuery == nil)
        .task { await directory?.load() }
    }
}

/// People, then tickets, matching what's typed after `@`.
private struct MentionSuggestions: View {
    let query: String
    let directory: MentionDirectory
    let me: String?
    var pick: (RichRun) -> Void

    var body: some View {
        let people = directory.people(matching: query, excluding: me)
        let tickets = directory.tickets(matching: query)
        VStack(alignment: .leading, spacing: 0) {
            if !people.isEmpty {
                header("People")
                ForEach(people) { member in
                    Button {
                        let first = member.displayName.split(separator: " ").first.map(String.init) ?? member.displayName
                        pick(RichRun("@\(first)", mention: .person(userId: member.id)))
                    } label: {
                        HStack(spacing: 10) {
                            Avatar(initials: TicketsModel.initials(member.displayName), size: 30, isMe: true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(member.displayName).fontWeight(.semibold)
                                if let handle = member.username {
                                    Text("@\(handle)").font(.footnote).foregroundStyle(Palette.textSecondary)
                                }
                            }
                            Spacer()
                        }
                        .row()
                    }
                    .buttonStyle(.plain)
                }
            }
            if !tickets.isEmpty {
                if !people.isEmpty { Hairline() }
                header("Tickets")
                ForEach(tickets) { ticket in
                    Button {
                        pick(RichRun(ticket.title, mention: .ticket(ticketId: ticket.id)))
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(TicketStatus(raw: ticket.status).color).frame(width: 9, height: 9)
                                .frame(width: 30, height: 30)
                                .background(Palette.fill, in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(ticket.title).fontWeight(.semibold).lineLimit(1)
                                Text(TicketStatus(raw: ticket.status).label).font(.footnote).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer()
                        }
                        .row()
                    }
                    .buttonStyle(.plain)
                }
            }
            if people.isEmpty && tickets.isEmpty {
                Text(query.isEmpty ? "Loading…" : "No one or nothing matches “\(query)”.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(Spacing.l)
            }
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(.vertical, Spacing.xs)
        .controlGlass(in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mention suggestions")
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    func row() -> some View {
        padding(.horizontal, Spacing.l)
            .padding(.vertical, 7)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
