import HuddleKit
import SwiftUI

/// The Tickets tab: the team's tickets edge to edge, narrowed by dropdown
/// pills, each with a play/pause button for its timer.
struct TicketsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(NowModel.self) private var now

    @State private var model: TicketsModel?
    @State private var showSearch = false
    @State private var showNew = false
    @State private var offClockTicket: Ticket?
    @State private var planTicket: Ticket?
    @State private var statusError: String?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.canvas)
        .task(id: app.team?.id) {
            guard let api = app.api, let teamId = app.team?.id else { return }
            let model = TicketsModel(api: api, teamId: teamId, snapshots: app.snapshotStore)
            self.model = model
            await model.load()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Search tickets", systemImage: "magnifyingglass") { showSearch = true }
                Button("New ticket", systemImage: "plus") { showNew = true }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.lime)
                    .foregroundStyle(Palette.onLime)
            }
        }
        .navigationDestination(isPresented: $showSearch) {
            if let model {
                TicketSearchScreen(model: model, onToggleTimer: toggleTimer)
            }
        }
        .sheet(isPresented: $showNew) {
            if let model {
                NewTicketSheet(model: model)
            }
        }
        .sheet(item: $offClockTicket) { ticket in
            StartTimerSheet(ticket: ticket, teamName: app.team?.name ?? "") {
                if app.team?.requiresPlan == true {
                    offClockTicket = nil
                    planTicket = ticket
                    return false
                }
                guard let teamId = app.team?.id else { return false }
                return await now.startDay(teamId: teamId, plan: nil, ticketId: ticket.id)
            }
        }
        .sheet(item: $planTicket) { ticket in
            PlanSheet(teamName: app.team?.name ?? "Your team", initialText: "Working on \(ticket.title).") { plan in
                guard let teamId = app.team?.id else { return false }
                return await now.startDay(teamId: teamId, plan: plan, ticketId: ticket.id)
            }
        }
    }

    // MARK: List

    @ViewBuilder private func content(_ model: TicketsModel) -> some View {
        let me = app.userId ?? ""
        let seconds = now.secondsToday()
        let all = model.tickets.value ?? []
        let visible = model.query.apply(to: all, me: me, secondsToday: seconds)

        List {
            Group {
                TicketPills(model: model)
                    .padding(.bottom, Spacing.xs)
                if model.tickets.error != nil, model.tickets.value != nil {
                    RefreshBanner(message: "Couldn’t refresh tickets.") { Task { await model.refresh() } }
                        .padding(.horizontal, Spacing.margin)
                }
                if let message = now.actionError ?? statusError {
                    InlineError(message: message).padding(.horizontal, Spacing.margin)
                }
                if model.tickets.value != nil {
                    Text(summary(visible.count, model.query))
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.margin + Spacing.xs)
                        .padding(.vertical, Spacing.s)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.canvas)

            ForEach(visible) { ticket in
                let isRunning = now.runningTicketId == ticket.id
                Group {
                    if isRunning {
                        // Only the running row ticks.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            row(ticket, in: model, isRunning: true, at: context.date)
                        }
                    } else {
                        row(ticket, in: model, isRunning: false, at: .now)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(isRunning ? Palette.limeSoft : Palette.canvas)
                .alignmentGuide(.listRowSeparatorLeading) { _ in 42 }
                .swipeActions(edge: .trailing) {
                    if ticket.status != TicketStatus.closed.rawValue {
                        Button("Done", systemImage: "checkmark") { setStatus(.closed, ticket, in: model) }
                            .tint(Palette.done)
                    }
                    if ticket.status != TicketStatus.inProgress.rawValue {
                        Button("In progress", systemImage: "arrow.forward") { setStatus(.inProgress, ticket, in: model) }
                            .tint(Palette.limeText)
                    }
                }
                .swipeActions(edge: .leading) {
                    Button(isRunning ? "Pause" : "Start", systemImage: isRunning ? "pause.fill" : "play.fill") { toggleTimer(ticket) }
                        .tint(isRunning ? Palette.textSecondary : Palette.limeText)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .refreshable { await model.refresh() }
        .overlay {
            if model.tickets.value == nil, model.tickets.error != nil {
                StatusView.unreachable(
                    host: app.session.session?.endpoint.baseURL.host() ?? "The server",
                    onRetry: { Task { await model.refresh() } },
                    onChangeServer: { app.signOut() }
                )
            } else if model.tickets.value == nil {
                ProgressView()
            } else if visible.isEmpty {
                emptyState(model, hasTickets: !all.isEmpty)
            }
        }
    }

    @ViewBuilder private func emptyState(_ model: TicketsModel, hasTickets: Bool) -> some View {
        if hasTickets {
            StatusView(systemImage: "line.3.horizontal.decrease", title: "No tickets match",
                       message: "Nothing fits these filters.",
                       primary: .init(title: "Clear filters") { clearFilters(model) })
        } else {
            StatusView(systemImage: "list.bullet", title: "No tickets yet",
                       message: "Create one to start tracking time against it.", tone: .working,
                       primary: .init(title: "New ticket") { showNew = true })
        }
    }

    private func row(_ ticket: Ticket, in model: TicketsModel, isRunning: Bool, at date: Date) -> some View {
        TicketRow(
            title: ticket.title,
            status: TicketStatus(raw: ticket.status),
            priority: TicketPriority(raw: ticket.priority).title,
            assigneeInitials: ticket.assignedTo.prefix(3).map(model.initials(of:)),
            timeText: timeText(ticket, isRunning: isRunning, at: date),
            isRunning: isRunning,
            onToggleTimer: { toggleTimer(ticket) }
        )
    }

    // MARK: Actions

    /// Play/pause on a ticket: pause it if it's running; start it on shift;
    /// off the clock, offer to start the day and the timer together.
    private func toggleTimer(_ ticket: Ticket) {
        statusError = nil
        if now.runningTicketId == ticket.id {
            Task { await now.pauseTimer() }
        } else if now.active != nil {
            Task { await now.startTimer(ticketId: ticket.id) }
        } else {
            offClockTicket = ticket
        }
    }

    private func setStatus(_ status: TicketStatus, _ ticket: Ticket, in model: TicketsModel) {
        statusError = nil
        Task {
            do { try await model.setStatus(status, of: ticket) } catch {
                statusError = APIError.from(error).localizedDescription
            }
        }
    }

    private func clearFilters(_ model: TicketsModel) {
        model.query.status = .all
        model.query.assignee = .anyone
        model.query.priorities = []
    }

    // MARK: Text

    private func timeText(_ ticket: Ticket, isRunning: Bool, at date: Date) -> String {
        let total = now.secondsToday(at: date)[ticket.id] ?? 0
        if isRunning, let running = now.data.value?.running {
            return "Now \(ShiftClockFormat.clock(running.seconds(at: date))) · today \(hoursMinutes(total))"
        }
        return total > 0 ? "Today \(hoursMinutes(total))" : "No time today"
    }

    private func hoursMinutes(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    private func summary(_ count: Int, _ query: TicketQuery) -> String {
        let order = query.ascending ? query.sort.ascendingTitle : query.sort.descendingTitle
        return "\(count) \(count == 1 ? "ticket" : "tickets") · \(query.sort.title), \(order.lowercased())"
    }
}

/// The dropdown pills over the list: filters count, status, assignee, priority, sort.
private struct TicketPills: View {
    @Bindable var model: TicketsModel
    @Environment(AppModel.self) private var app

    var body: some View {
        PillBar {
            Menu {
                Button("Clear filters", systemImage: "xmark.circle") {
                    model.query.status = .all
                    model.query.assignee = .anyone
                    model.query.priorities = []
                }
                .disabled(model.query.activeFilterCount == 0)
            } label: {
                FilterCountPill(activeCount: model.query.activeFilterCount)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("Filters, \(model.query.activeFilterCount) active")

            FilterPill(title: statusTitle, isActive: model.query.status != .all) {
                Picker("Status", selection: $model.query.status) {
                    Text("Open").tag(TicketQuery.StatusFilter.open)
                    Text("All statuses").tag(TicketQuery.StatusFilter.all)
                    Divider()
                    ForEach(TicketStatus.allCases, id: \.self) { status in
                        Text(status.label).tag(TicketQuery.StatusFilter.only(status.rawValue))
                    }
                }
            }

            FilterPill(title: assigneeTitle, isActive: model.query.assignee != .anyone) {
                Picker("Assignee", selection: $model.query.assignee) {
                    Text("Me").tag(TicketQuery.AssigneeFilter.me)
                    Text("Anyone").tag(TicketQuery.AssigneeFilter.anyone)
                    let others = (model.members.value ?? []).filter { $0.id != app.userId }
                    if !others.isEmpty {
                        Divider()
                        ForEach(others) { member in
                            Text(member.displayName).tag(TicketQuery.AssigneeFilter.user(member.id))
                        }
                    }
                }
            }

            MultiSelectPill(title: "Priority", options: TicketPriority.allCases.reversed(),
                            label: \.title, selection: $model.query.priorities)

            SortPill(options: TicketQuery.Sort.allCases.map {
                SortOption(key: $0, title: $0.title, descending: $0.descendingTitle, ascending: $0.ascendingTitle)
            }, key: $model.query.sort, ascending: $model.query.ascending)
        }
    }

    private var statusTitle: String {
        switch model.query.status {
        case .open: "Open"
        case .all: "Status"
        case let .only(raw): TicketStatus(raw: raw).label
        }
    }

    private var assigneeTitle: String {
        switch model.query.assignee {
        case .me: "Assignee: Me"
        case .anyone: "Assignee"
        case let .user(id): "Assignee: \(model.name(of: id).split(separator: " ").first.map(String.init) ?? "")"
        }
    }
}
