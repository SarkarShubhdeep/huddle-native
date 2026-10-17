import HuddleKit
import SwiftUI

/// Search, on its own screen: this team, all your teams, or tickets assigned
/// to you, with the match highlighted and your recent searches.
struct TicketSearchScreen: View {
    let model: TicketsModel
    var onToggleTimer: (Ticket) -> Void

    enum Scope: Hashable { case team, allTeams, mine }

    @Environment(AppModel.self) private var app
    @Environment(NowModel.self) private var now
    @State private var query = ""
    @State private var scope: Scope = .team
    @State private var otherTeams: [String: [Ticket]] = [:]
    @State private var recent: [String] = UserDefaults.standard.stringArray(forKey: "tickets.recentSearches") ?? []
    @State private var isSearching = true

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                if !recent.isEmpty {
                    Section {
                        ForEach(recent, id: \.self) { term in
                            Button { query = term } label: {
                                Label(term, systemImage: "clock").foregroundStyle(Palette.textPrimary)
                            }
                            .listRowBackground(Palette.canvas)
                        }
                    } header: {
                        Text("Recent").font(.footnote.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                    }
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Palette.canvas)
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(results, id: \.ticket.id) { result in
                        resultRow(result)
                    }
                } header: {
                    Text(results.count == 1 ? "1 ticket" : "\(results.count) tickets")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tickets")
        .searchScopes($scope, activation: .onSearchPresentation) {
            Text(app.team?.name ?? "This team").tag(Scope.team)
            Text("All teams").tag(Scope.allTeams)
            Text("Assigned to me").tag(Scope.mine)
        }
        .onSubmit(of: .search) { remember(query) }
        .task(id: scope) {
            if scope == .allTeams { await loadOtherTeams() }
        }
    }

    // MARK: Results

    private struct Result {
        let ticket: Ticket
        let teamName: String
        let range: Range<String.Index>
    }

    private var results: [Result] {
        let me = app.userId ?? ""
        let here = (model.tickets.value ?? []).map { ($0, app.team?.name ?? "") }
        let pool: [(Ticket, String)]
        switch scope {
        case .team: pool = here
        case .mine: pool = here.filter { $0.0.assignedTo.contains(me) }
        case .allTeams:
            let names = Dictionary((app.teams?.value ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
            pool = here + otherTeams.flatMap { id, tickets in tickets.map { ($0, names[id] ?? "") } }
        }
        return pool.compactMap { ticket, team in
            TicketQuery.match(query, in: ticket.title).map { Result(ticket: ticket, teamName: team, range: $0) }
        }
    }

    private func resultRow(_ result: Result) -> some View {
        let status = TicketStatus(raw: result.ticket.status)
        let isRunning = now.runningTicketId == result.ticket.id
        return HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
            Circle().fill(status.color).frame(width: 10, height: 10).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(highlighted(result))
                    .font(.headline.weight(.regular))
                Text(meta(result))
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            // Timers only for this team's tickets; the others belong to another team's shift.
            if result.ticket.teamId == app.team?.id {
                Button(isRunning ? "Pause timer" : "Start timer", systemImage: isRunning ? "pause.fill" : "play.fill") {
                    remember(query)
                    onToggleTimer(result.ticket)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(HNIconButtonStyle(role: isRunning ? .primary : .secondary))
            }
        }
        .padding(.vertical, Spacing.xs)
        .listRowBackground(isRunning ? Palette.limeSoft : Palette.canvas)
    }

    private func highlighted(_ result: Result) -> AttributedString {
        let title = result.ticket.title
        var text = AttributedString(title)
        text.foregroundColor = Palette.textSecondary
        if let lower = AttributedString.Index(result.range.lowerBound, within: text),
           let upper = AttributedString.Index(result.range.upperBound, within: text) {
            text[lower..<upper].foregroundColor = Palette.textPrimary
            text[lower..<upper].font = .headline.weight(.bold)
        }
        return text
    }

    private func meta(_ result: Result) -> String {
        var parts = [TicketStatus(raw: result.ticket.status).label]
        let priority = TicketPriority(raw: result.ticket.priority)
        if priority != .none { parts.append(priority.title) }
        if !result.teamName.isEmpty { parts.append(result.teamName) }
        return parts.joined(separator: " · ")
    }

    // MARK: Helpers

    private func loadOtherTeams() async {
        guard let api = app.api else { return }
        let service = TicketService(api)
        let others = (app.teams?.value ?? []).filter { $0.id != app.team?.id && otherTeams[$0.id] == nil }
        await withTaskGroup(of: (String, [Ticket]?).self) { group in
            for team in others {
                group.addTask { (team.id, try? await service.list(teamId: team.id)) }
            }
            for await (id, tickets) in group {
                if let tickets { otherTeams[id] = tickets }
            }
        }
    }

    private func remember(_ term: String) {
        let term = term.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        recent = Array(([term] + recent.filter { $0.caseInsensitiveCompare(term) != .orderedSame }).prefix(5))
        UserDefaults.standard.set(recent, forKey: "tickets.recentSearches")
    }
}
